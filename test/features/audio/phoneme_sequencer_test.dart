// Pins the API of lib/features/audio/phoneme_sequencer.dart (PRD §8 Unit 13
// "Playback engine ... low-latency ... gapless sequential phoneme playback";
// Unit 6 "the app sounds out the word's phonemes ... highlighting each
// grapheme cluster ... using graphemePhonemeMap"; Unit 15 "the recorded
// human phoneme audio plays (grapheme's phonemeIds in order, gapless)".
// ticket audio-playback accept entries 2 and 5). This suite is authored
// before the implementation exists, so it is EXPECTED to fail to compile
// until phoneme_sequencer.dart is written with exactly the shapes exercised
// below.
//
// Pinned API surface this suite requires:
//   class PhonemeStarted {
//     int graphemeIndex; // index into WordToken.graphemePhonemeMap
//     String phonemeId;
//     PlaybackHandle handle;
//   }
//   class PhonemeAudioNotFoundException implements Exception { String phonemeId; }
//   class PhonemeSequencer {
//     PhonemeSequencer({required AudioService audioService, required Map<String, AudioRef> phonemeAudioRefs});
//     Stream<PhonemeStarted> playSequence(WordToken word, {AudioChannel channel = AudioChannel.help});
//   }
//
// Contract this suite locks in (builder-mechanical design choices made by
// this test suite, since the ticket leaves exact shapes to the builder and
// only pins behavior):
//  - playSequence walks word.graphemePhonemeMap strictly in order (index 0,
//    1, 2, ...). Each non-silent entry (phonemeId.isNotEmpty) resolves
//    through phonemeAudioRefs[phonemeId] and is played via
//    audioService.play(ref, channel: channel); a PhonemeStarted event is
//    emitted carrying the map index for grapheme-highlight sync (Unit 6).
//  - Entries with an empty phonemeId ('') are silent letters (e.g. the "e"
//    in "cake"): they are valid indices into graphemePhonemeMap but
//    contribute no audio -- skipped for playback and never produce a
//    PhonemeStarted event or an AudioService.play() call.
//  - Digraphs are one graphemePhonemeMap entry ("sh" for "ship") and
//    therefore one play() call / one PhonemeStarted event, never split.
//  - Gapless sequential intent (queue construction, not wall-clock): the
//    sequencer never inserts its own delay between phonemes. It awaits
//    audioService.completionOf(handle) for phoneme N before issuing
//    audioService.play() for phoneme N+1 -- the next play() is queued as
//    soon as the previous playback's completion resolves, observable
//    headlessly as "no extra Future.delayed/timer elapse needed between
//    completion and the next play() call", proxying gaplessness without
//    depending on wall-clock audio hardware.
//  - Low-latency intent (DEVICE proxy, ticket accept 5): the FIRST play()
//    call is issued synchronously, in the same event-loop turn as the
//    playSequence() call itself (before any fake-time elapses and before
//    any awaited Future settles) -- callers can rely on "instant" dispatch
//    to the audio engine. The <150ms wall-clock figure is owner-measured
//    on-device (A-6) and out of scope for a headless suite; that specific
//    acceptance item is `skip`-marked below with a [DEVICE] reason.
//  - A phonemeId with no entry in phonemeAudioRefs is a content/pack bug:
//    the returned stream emits a PhonemeAudioNotFoundException and closes
//    (no further phonemes are played after the failure).
//  - AudioService errors (e.g. AudioRefNotFoundException from a missing
//    shipped ref) propagate through the returned stream as stream errors.
//  - channel defaults to AudioChannel.help (Unit 6 Tier 1 sound-out is the
//    primary caller) but is fully overridable (e.g. Unit 15 Sound Garden
//    tap-to-hear may choose a different tag) and is forwarded verbatim to
//    every audioService.play() call in the sequence.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/audio/phoneme_sequencer.dart';

// ---------------------------------------------------------------------------
// Fixtures -- "ship" (digraph) and "cake" (silent-e), per the ticket.
// ---------------------------------------------------------------------------

WordToken _wordShip() => WordToken(
      text: 'ship',
      graphemePhonemeMap: const [
        (graphemes: 'sh', phonemeId: 'SH'),
        (graphemes: 'i', phonemeId: 'IH'),
        (graphemes: 'p', phonemeId: 'P'),
      ],
      pronunciationAudioRef: 'audio/words/ship.wav',
    );

WordToken _wordCake() => WordToken(
      text: 'cake',
      graphemePhonemeMap: const [
        (graphemes: 'c', phonemeId: 'K'),
        (graphemes: 'a', phonemeId: 'EY'),
        (graphemes: 'k', phonemeId: 'K'),
        (graphemes: 'e', phonemeId: ''), // silent e -- no audio
      ],
      pronunciationAudioRef: 'audio/words/cake.wav',
    );

const _shipPhonemeAudioRefs = {
  'SH': 'audio/phonemes/SH.wav',
  'IH': 'audio/phonemes/IH.wav',
  'P': 'audio/phonemes/P.wav',
};

const _cakePhonemeAudioRefs = {
  'K': 'audio/phonemes/K.wav',
  'EY': 'audio/phonemes/EY.wav',
};

/// Drives a PhonemeSequencer stream to completion by immediately
/// "completing" each phoneme's playback on the FakeAudioService as soon as
/// it starts -- models an idealized gapless engine advancing through the
/// whole sequence, and lets tests capture the emitted event order without
/// depending on any real timer.
Future<List<PhonemeStarted>> _drain(
  Stream<PhonemeStarted> stream,
  FakeAudioService fake,
) {
  final events = <PhonemeStarted>[];
  final completer = Completer<List<PhonemeStarted>>();
  late final StreamSubscription<PhonemeStarted> sub;
  sub = stream.listen(
    (event) {
      events.add(event);
      fake.completePlayback(event.handle);
    },
    onDone: () => completer.complete(events),
    onError: completer.completeError,
  );
  return completer.future.whenComplete(() => sub.cancel());
}

void main() {
  group('POSITIVE: gapless order for "ship" (digraph)', () {
    test('emits one PhonemeStarted per graphemePhonemeMap entry, in order', () async {
      final fake = FakeAudioService();
      final sequencer = PhonemeSequencer(audioService: fake, phonemeAudioRefs: _shipPhonemeAudioRefs);

      final events = await _drain(sequencer.playSequence(_wordShip()), fake);

      expect(events, hasLength(3));
      expect(events.map((e) => e.graphemeIndex).toList(), [0, 1, 2]);
      expect(events.map((e) => e.phonemeId).toList(), ['SH', 'IH', 'P']);
    });

    test('digraph "sh" is one play() call / one event, never split s-h', () async {
      final fake = FakeAudioService();
      final sequencer = PhonemeSequencer(audioService: fake, phonemeAudioRefs: _shipPhonemeAudioRefs);

      final events = await _drain(sequencer.playSequence(_wordShip()), fake);

      expect(events.first.graphemeIndex, 0);
      expect(events.first.phonemeId, 'SH');
      final playRefs = fake.callLog.whereType<PlayLogEntry>().map((e) => e.ref).toList();
      expect(playRefs, ['audio/phonemes/SH.wav', 'audio/phonemes/IH.wav', 'audio/phonemes/P.wav']);
    });

    test('play() calls are tagged with the sequence channel (default help)', () async {
      final fake = FakeAudioService();
      final sequencer = PhonemeSequencer(audioService: fake, phonemeAudioRefs: _shipPhonemeAudioRefs);

      await _drain(sequencer.playSequence(_wordShip()), fake);

      final channels = fake.callLog.whereType<PlayLogEntry>().map((e) => e.channel).toSet();
      expect(channels, {AudioChannel.help});
    });
  });

  group('POSITIVE: silent-e handling for "cake"', () {
    test('silent "e" entry is skipped for playback: only 3 phonemes play, not 4', () async {
      final fake = FakeAudioService();
      final sequencer = PhonemeSequencer(audioService: fake, phonemeAudioRefs: {..._cakePhonemeAudioRefs, 'K': 'audio/phonemes/K.wav'});

      final events = await _drain(sequencer.playSequence(_wordCake()), fake);

      expect(events, hasLength(3));
      expect(events.map((e) => e.graphemeIndex).toList(), [0, 1, 2]);
      expect(events.map((e) => e.phonemeId).toList(), ['K', 'EY', 'K']);
    });

    test('no PhonemeStarted and no play() call is issued for the silent-e index (3)', () async {
      final fake = FakeAudioService();
      final sequencer = PhonemeSequencer(audioService: fake, phonemeAudioRefs: {..._cakePhonemeAudioRefs, 'K': 'audio/phonemes/K.wav'});

      final events = await _drain(sequencer.playSequence(_wordCake()), fake);

      expect(events.any((e) => e.graphemeIndex == 3), isFalse);
      expect(fake.callLog.whereType<PlayLogEntry>(), hasLength(3));
    });
  });

  group('POSITIVE: gapless queue construction (not wall-clock)', () {
    test('next phoneme is queued as soon as the previous completes, no elapsed delay needed', () {
      fakeAsync((async) {
        final fake = FakeAudioService();
        final sequencer = PhonemeSequencer(audioService: fake, phonemeAudioRefs: _shipPhonemeAudioRefs);

        final events = <PhonemeStarted>[];
        sequencer.playSequence(_wordShip()).listen((event) {
          events.add(event);
          fake.completePlayback(event.handle);
        });

        // Flush microtasks only -- no fake time elapses. A sequencer that
        // inserted its own delay between phonemes would still be stuck on
        // event 1 here; a truly gapless queue drains the whole sequence.
        async.flushMicrotasks();

        expect(events.map((e) => e.graphemeIndex).toList(), [0, 1, 2]);
        expect(async.elapsed, Duration.zero);
      });
    });
  });

  group('POSITIVE / DEVICE-proxy: low-latency first dispatch (ticket accept 5)', () {
    test(
      'headless proxy: first play() is issued synchronously, same event-loop turn as trigger',
      () {
        fakeAsync((async) {
          final fake = FakeAudioService();
          final sequencer = PhonemeSequencer(audioService: fake, phonemeAudioRefs: _shipPhonemeAudioRefs);

          // Trigger playback and, without awaiting or elapsing any fake
          // time, assert the first play() has already reached the audio
          // service's call log -- proxying "instant" dispatch headlessly.
          sequencer.playSequence(_wordShip()).listen((_) {});

          expect(fake.callLog.whereType<PlayLogEntry>(), hasLength(1));
          expect(fake.callLog.first, isA<PlayLogEntry>());
          expect((fake.callLog.first as PlayLogEntry).ref, 'audio/phonemes/SH.wav');
          expect(async.elapsed, Duration.zero);
        });
      },
    );

    test(
      'phoneme sequence playback latency < 150ms from trigger on min-spec device (A-6)',
      () {
        // Body intentionally never runs -- see `skip` reason. Left as an
        // explicit placeholder so a future accidental un-skip fails loudly
        // instead of silently passing.
        fail('owner-measured in profile mode on min-spec hardware; not runnable headlessly.');
      },
      skip: '[DEVICE] ticket accept 5: owner-measured in profile mode against the '
          'just_audio-backed AudioService on min-spec hardware (A-6). The headless '
          'proxy above ("first play() same event-loop turn") is the compile-time '
          'stand-in for this suite; the wall-clock figure itself has no headless '
          'equivalent.',
    );
  });

  group('NEGATIVE: missing phoneme-audio lookup entry', () {
    test('a phonemeId absent from phonemeAudioRefs errors the stream and stops the sequence', () async {
      final fake = FakeAudioService();
      // 'IH' deliberately omitted.
      final sequencer = PhonemeSequencer(audioService: fake, phonemeAudioRefs: const {'SH': 'audio/phonemes/SH.wav'});

      final events = <PhonemeStarted>[];
      Object? capturedError;
      try {
        await for (final event in sequencer.playSequence(_wordShip())) {
          events.add(event);
          fake.completePlayback(event.handle);
        }
      } catch (e) {
        capturedError = e;
      }

      expect(capturedError, isA<PhonemeAudioNotFoundException>());
      expect((capturedError as PhonemeAudioNotFoundException).phonemeId, 'IH');
      // Only the first (resolvable) phoneme played before the failure.
      expect(events, hasLength(1));
      expect(events.single.phonemeId, 'SH');
    });

    test('an AudioService-level missing ref propagates through the sequencer as a stream error', () async {
      final fake = FakeAudioService(missingRefs: const {'audio/phonemes/SH.wav'});
      final sequencer = PhonemeSequencer(audioService: fake, phonemeAudioRefs: _shipPhonemeAudioRefs);

      await expectLater(
        sequencer.playSequence(_wordShip()),
        emitsError(isA<AudioRefNotFoundException>()),
      );
    });
  });

  group('EDGE: channel override and single/empty sequences', () {
    test('channel is forwarded verbatim when overridden (e.g. Sound Garden tap-to-hear)', () async {
      final fake = FakeAudioService();
      final sequencer = PhonemeSequencer(audioService: fake, phonemeAudioRefs: _shipPhonemeAudioRefs);

      await _drain(sequencer.playSequence(_wordShip(), channel: AudioChannel.narration), fake);

      final channels = fake.callLog.whereType<PlayLogEntry>().map((e) => e.channel).toSet();
      expect(channels, {AudioChannel.narration});
    });

    test('a single-phoneme word emits exactly one event and completes', () async {
      final word = WordToken(
        text: 'a',
        graphemePhonemeMap: const [(graphemes: 'a', phonemeId: 'AH')],
        pronunciationAudioRef: 'audio/words/a.wav',
      );
      final fake = FakeAudioService();
      final sequencer = PhonemeSequencer(audioService: fake, phonemeAudioRefs: const {'AH': 'audio/phonemes/AH.wav'});

      final events = await _drain(sequencer.playSequence(word), fake);

      expect(events, hasLength(1));
      expect(events.single.graphemeIndex, 0);
    });

    test('a word that is entirely silent letters emits no events and the stream simply closes', () async {
      final word = WordToken(
        text: 'xx',
        graphemePhonemeMap: const [
          (graphemes: 'x', phonemeId: ''),
          (graphemes: 'x', phonemeId: ''),
        ],
        pronunciationAudioRef: 'audio/words/xx.wav',
      );
      final fake = FakeAudioService();
      final sequencer = PhonemeSequencer(audioService: fake, phonemeAudioRefs: const {});

      final events = await _drain(sequencer.playSequence(word), fake);

      expect(events, isEmpty);
      expect(fake.callLog, isEmpty);
    });
  });
}

// Pins the API of lib/features/help/sound_out_sequence.dart (PRD §8 Unit 6
// "the app sounds out the word's phonemes ... highlighting each grapheme
// cluster in the word as its phoneme plays (using graphemePhonemeMap)";
// ticket stuck-word-scaffold accept entry 2). This suite is authored before
// the implementation exists, so it is EXPECTED to fail to compile until
// sound_out_sequence.dart is written with exactly the shape exercised
// below.
//
// Pinned API surface this suite requires:
//   class SoundOutSequence {
//     SoundOutSequence({required PhonemeSequencer phonemeSequencer});
//     Stream<HelpState> play(WordToken word, {AudioChannel channel = AudioChannel.help});
//   }
//
// Contract this suite locks in (builder-mechanical design choice, since the
// ticket pins the highlight *behavior* -- "matches graphemePhonemeMap
// exactly" -- not this wrapper's exact shape):
//  - `SoundOutSequence` is a thin adapter over `PhonemeSequencer`: it maps
//    each `PhonemeStarted { graphemeIndex, phonemeId, handle }` from
//    `PhonemeSequencer.playSequence` to a
//    `HelpState(currentHelpTier: HelpLevel.soundOut, highlightedGraphemeIndex: graphemeIndex)`.
//    It introduces no reordering, filtering, or batching of its own --
//    `PhonemeSequencer`'s pinned graphemePhonemeMap-order/digraph-as-one-
//    unit/silent-letter-skip guarantees (see phoneme_sequencer_test.dart)
//    are inherited verbatim, which is exactly what this suite checks from
//    the `HelpState` side of that same contract.
//  - The returned stream closes exactly when the underlying phoneme
//    sequence finishes (all phonemes played, or the word had none to
//    play), and propagates `PhonemeAudioNotFoundException` /
//    `AudioRefNotFoundException` as stream errors the same way
//    `PhonemeSequencer` does.
//  - `channel` defaults to `AudioChannel.help` (Tier 1 sound-out's tag) and
//    is forwarded verbatim to the underlying `PhonemeSequencer.playSequence`
//    call.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/audio/phoneme_sequencer.dart';
import 'package:learn_to_read/features/help/sound_out_sequence.dart';
import 'package:learn_to_read/features/listening/contracts/help_state.dart';

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

/// Drains a `SoundOutSequence.play` stream to completion, "completing"
/// each phoneme's fake playback as soon as it starts -- mirrors the
/// `_drain` helper in phoneme_sequencer_test.dart, one layer up.
Future<List<HelpState>> _drain(
  Stream<HelpState> stream,
  FakeAudioService fake,
) {
  final events = <HelpState>[];
  final completer = Completer<List<HelpState>>();
  late final StreamSubscription<HelpState> sub;
  sub = stream.listen(
    (event) {
      events.add(event);
      // The most recently-logged help-channel play is this event's clip.
      final handle = fake.callLog
          .whereType<PlayLogEntry>()
          .last // Orchestrator test-fix: the help-channel filter made the
          // channel-override test (narration-only) throw in _drain while its
          // own assertion forbids any help entry - mutually exclusive. The
          // file's missing-phoneme test already uses plain .last.

          .handle;
      fake.completePlayback(handle);
    },
    onDone: () => completer.complete(events),
    onError: completer.completeError,
  );
  return completer.future.whenComplete(() => sub.cancel());
}

void main() {
  group('POSITIVE: "ship" (digraph) highlight sequence matches graphemePhonemeMap', () {
    test('emits one HelpState per graphemePhonemeMap entry, in order, tier soundOut', () async {
      final fake = FakeAudioService();
      final sequence = SoundOutSequence(
        phonemeSequencer: PhonemeSequencer(audioService: fake, phonemeAudioRefs: _shipPhonemeAudioRefs),
      );

      final states = await _drain(sequence.play(_wordShip()), fake);

      expect(states, hasLength(3));
      expect(states.map((s) => s.highlightedGraphemeIndex).toList(), [0, 1, 2]);
      expect(states.every((s) => s.currentHelpTier == HelpLevel.soundOut), isTrue);
    });

    test('digraph "sh" highlights as ONE unit (index 0), never split s-h', () async {
      final fake = FakeAudioService();
      final sequence = SoundOutSequence(
        phonemeSequencer: PhonemeSequencer(audioService: fake, phonemeAudioRefs: _shipPhonemeAudioRefs),
      );
      final word = _wordShip();

      final states = await _drain(sequence.play(word), fake);

      expect(states.first.highlightedGraphemeIndex, 0);
      expect(word.graphemePhonemeMap[states.first.highlightedGraphemeIndex].graphemes, 'sh');
      // Exactly one HelpState covers "sh" -- there is no separate event for
      // 's' or 'h' because graphemePhonemeMap itself has no such entries.
      expect(states.where((s) => s.highlightedGraphemeIndex == 0), hasLength(1));
    });

    test('play() is tagged with the sequence channel (default help)', () async {
      final fake = FakeAudioService();
      final sequence = SoundOutSequence(
        phonemeSequencer: PhonemeSequencer(audioService: fake, phonemeAudioRefs: _shipPhonemeAudioRefs),
      );

      await _drain(sequence.play(_wordShip()), fake);

      final channels = fake.callLog.whereType<PlayLogEntry>().map((e) => e.channel).toSet();
      expect(channels, {AudioChannel.help});
    });
  });

  group('POSITIVE: "cake" (silent-e) highlight sequence matches graphemePhonemeMap', () {
    test('highlights indices 0,1,2 (c,a,k) only -- silent "e" (index 3) is skipped', () async {
      final fake = FakeAudioService();
      final sequence = SoundOutSequence(
        phonemeSequencer: PhonemeSequencer(
          audioService: fake,
          phonemeAudioRefs: {..._cakePhonemeAudioRefs, 'K': 'audio/phonemes/K.wav'},
        ),
      );
      final word = _wordCake();

      final states = await _drain(sequence.play(word), fake);

      expect(states, hasLength(3));
      expect(states.map((s) => s.highlightedGraphemeIndex).toList(), [0, 1, 2]);
      expect(states.any((s) => s.highlightedGraphemeIndex == 3), isFalse);
      expect(word.graphemePhonemeMap[3].graphemes, 'e');
      expect(word.graphemePhonemeMap[3].phonemeId, isEmpty);
    });

    test('no audio call is made for the silent-e index', () async {
      final fake = FakeAudioService();
      final sequence = SoundOutSequence(
        phonemeSequencer: PhonemeSequencer(
          audioService: fake,
          phonemeAudioRefs: {..._cakePhonemeAudioRefs, 'K': 'audio/phonemes/K.wav'},
        ),
      );

      await _drain(sequence.play(_wordCake()), fake);

      expect(fake.callLog.whereType<PlayLogEntry>(), hasLength(3));
    });
  });

  group('NEGATIVE: propagated audio/content errors', () {
    test('a phonemeId absent from phonemeAudioRefs errors the stream, stopping the sequence', () async {
      final fake = FakeAudioService();
      final sequence = SoundOutSequence(
        phonemeSequencer: PhonemeSequencer(
          audioService: fake,
          phonemeAudioRefs: const {'SH': 'audio/phonemes/SH.wav'}, // 'IH' missing
        ),
      );

      final states = <HelpState>[];
      Object? capturedError;
      try {
        await for (final state in sequence.play(_wordShip())) {
          states.add(state);
          final handle = fake.callLog.whereType<PlayLogEntry>().last.handle;
          fake.completePlayback(handle);
        }
      } catch (e) {
        capturedError = e;
      }

      expect(capturedError, isA<PhonemeAudioNotFoundException>());
      expect(states, hasLength(1));
      expect(states.single.highlightedGraphemeIndex, 0);
    });

    test('an AudioService-level missing ref propagates through as a stream error', () async {
      final fake = FakeAudioService(missingRefs: const {'audio/phonemes/SH.wav'});
      final sequence = SoundOutSequence(
        phonemeSequencer: PhonemeSequencer(audioService: fake, phonemeAudioRefs: _shipPhonemeAudioRefs),
      );

      await expectLater(
        sequence.play(_wordShip()),
        emitsError(isA<AudioRefNotFoundException>()),
      );
    });
  });

  group('EDGE: channel override and degenerate sequences', () {
    test('channel is forwarded verbatim when overridden', () async {
      final fake = FakeAudioService();
      final sequence = SoundOutSequence(
        phonemeSequencer: PhonemeSequencer(audioService: fake, phonemeAudioRefs: _shipPhonemeAudioRefs),
      );

      await _drain(sequence.play(_wordShip(), channel: AudioChannel.narration), fake);

      final channels = fake.callLog.whereType<PlayLogEntry>().map((e) => e.channel).toSet();
      expect(channels, {AudioChannel.narration});
    });

    test('a single-phoneme word emits exactly one HelpState', () async {
      final word = WordToken(
        text: 'a',
        graphemePhonemeMap: const [(graphemes: 'a', phonemeId: 'AH')],
        pronunciationAudioRef: 'audio/words/a.wav',
      );
      final fake = FakeAudioService();
      final sequence = SoundOutSequence(
        phonemeSequencer: PhonemeSequencer(audioService: fake, phonemeAudioRefs: const {'AH': 'audio/phonemes/AH.wav'}),
      );

      final states = await _drain(sequence.play(word), fake);

      expect(states, hasLength(1));
      expect(states.single.highlightedGraphemeIndex, 0);
      expect(states.single.currentHelpTier, HelpLevel.soundOut);
    });

    test('a word that is entirely silent letters emits no HelpState and the stream simply closes', () async {
      final word = WordToken(
        text: 'xx',
        graphemePhonemeMap: const [
          (graphemes: 'x', phonemeId: ''),
          (graphemes: 'x', phonemeId: ''),
        ],
        pronunciationAudioRef: 'audio/words/xx.wav',
      );
      final fake = FakeAudioService();
      final sequence = SoundOutSequence(
        phonemeSequencer: PhonemeSequencer(audioService: fake, phonemeAudioRefs: const {}),
      );

      final states = await _drain(sequence.play(word), fake);

      expect(states, isEmpty);
      expect(fake.callLog, isEmpty);
    });
  });
}

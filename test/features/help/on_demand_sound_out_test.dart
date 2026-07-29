// Unit tests for lib/features/help/on_demand_sound_out.dart (owner
// direction 2026-07-29: "sounding out the phonics of everything").
//
// Pinned contract this suite locks in:
//  - a pass plays a word's phonemes gaplessly in graphemePhonemeMap order
//    on AudioChannel.help, emitting one (wordIndex, graphemeIndex)
//    highlight tick as each clip starts and a single `null` when the pass
//    ends; silent letters (empty phonemeId) play nothing and tick nothing;
//  - listening is paused synchronously at the start of a pass and resumed
//    exactly once when the pass ends — finished, cancelled, superseded, or
//    errored (swallow-and-resume, NarrationController's posture);
//  - passes never overlap: a second play() stops the first (its current
//    clip is stopped, no further clips of it play) and the pause/resume
//    bracket spans the whole chain — one pause, one resume;
//  - playGrapheme plays exactly ONE clip for the named cluster; a silent
//    letter, an out-of-range index, a missing clip, and an audio error are
//    all gentle no-ops;
//  - dispose closes the highlight stream and makes every later call inert.
//
// Harness: FakeAudioService drain patterns from
// test/features/help/sound_out_highlight_test.dart, adapted to the pass's
// own Future (the pass drives itself off completionOf, so the driver
// completes the most recent play until the pass future resolves).

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/help/on_demand_sound_out.dart';

// ---------------------------------------------------------------------------
// Fixtures -- "ship" (digraph) and "cake" (silent-e), per the Unit 6 suites.
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

const Map<String, AudioRef> _refs = {
  'SH': 'audio/phonemes/SH.wav',
  'IH': 'audio/phonemes/IH.wav',
  'P': 'audio/phonemes/P.wav',
  'K': 'audio/phonemes/K.wav',
  'EY': 'audio/phonemes/EY.wav',
};

/// Records the pause/resume bracket in call order.
class _ListeningLog {
  final List<String> calls = [];
  void pause() => calls.add('pause');
  void resume() => calls.add('resume');
}

class _Rig {
  _Rig({Map<String, AudioRef> refs = _refs, Set<AudioRef> missingRefs = const {}})
      : fake = FakeAudioService(missingRefs: missingRefs) {
    controller = OnDemandSoundOut(
      audioService: fake,
      phonemeAudioRefs: refs,
      pauseListening: listening.pause,
      resumeListening: listening.resume,
    );
    sub = controller.highlights.listen(ticks.add);
  }

  final FakeAudioService fake;
  final _ListeningLog listening = _ListeningLog();
  late final OnDemandSoundOut controller;
  final List<OnDemandGrapheme?> ticks = [];
  late final StreamSubscription<OnDemandGrapheme?> sub;

  List<PlayLogEntry> get plays => fake.callLog.whereType<PlayLogEntry>().toList();
  List<StopLogEntry> get stops => fake.callLog.whereType<StopLogEntry>().toList();

  /// Flushes pending microtasks so the pass can advance to its next await.
  Future<void> flush([int turns = 4]) async {
    for (var i = 0; i < turns; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Drives [pass] to completion by completing the most recent clip each
  /// turn -- the FakeAudioService drain pattern, one layer up.
  Future<void> drain(Future<void> pass) async {
    var done = false;
    unawaited(pass.whenComplete(() => done = true));
    while (!done) {
      await Future<void>.delayed(Duration.zero);
      final entries = plays;
      if (entries.isNotEmpty) {
        fake.completePlayback(entries.last.handle);
      }
    }
    await flush();
  }

  Future<void> tearDown() async {
    controller.dispose();
    await sub.cancel();
  }
}

void main() {
  group('POSITIVE: one pass sequences clips and highlight ticks in order', () {
    test('"ship" plays SH, IH, P gaplessly on the help channel with one tick '
        'per cluster, then a null clear', () async {
      final rig = _Rig();
      await rig.drain(rig.controller.play(wordIndex: 7, word: _wordShip()));

      expect(rig.plays.map((e) => e.ref).toList(), [
        'audio/phonemes/SH.wav',
        'audio/phonemes/IH.wav',
        'audio/phonemes/P.wav',
      ]);
      expect(rig.plays.map((e) => e.channel).toSet(), {AudioChannel.help});
      expect(rig.ticks, [
        (wordIndex: 7, graphemeIndex: 0),
        (wordIndex: 7, graphemeIndex: 1),
        (wordIndex: 7, graphemeIndex: 2),
        null,
      ]);
      await rig.tearDown();
    });

    test('listening is paused synchronously at play() and resumed exactly '
        'once after the last clip', () async {
      final rig = _Rig();
      final pass = rig.controller.play(wordIndex: 0, word: _wordShip());
      // play() runs synchronously up to its first await: the bracket is
      // already open before any clip resolves.
      expect(rig.listening.calls, ['pause']);
      await rig.drain(pass);
      expect(rig.listening.calls, ['pause', 'resume']);
      await rig.tearDown();
    });

    test('EDGE: "cake" skips the silent e -- three clips, ticks 0,1,2, no '
        'tick for index 3', () async {
      final rig = _Rig();
      await rig.drain(rig.controller.play(wordIndex: 2, word: _wordCake()));

      expect(rig.plays, hasLength(3));
      expect(
        rig.ticks.whereType<OnDemandGrapheme>().map((t) => t.graphemeIndex),
        [0, 1, 2],
      );
      expect(
        rig.ticks.whereType<OnDemandGrapheme>().any((t) => t.graphemeIndex == 3),
        isFalse,
      );
      expect(rig.ticks.last, isNull);
      await rig.tearDown();
    });
  });

  group('POSITIVE: cancellation', () {
    test('cancel() mid-pass stops the current clip, plays nothing further, '
        'clears the highlight, and resumes listening', () async {
      final rig = _Rig();
      final pass = rig.controller.play(wordIndex: 0, word: _wordShip());
      await rig.flush();
      expect(rig.plays, hasLength(1)); // SH is sounding, not yet complete.
      expect(rig.controller.isPlaying, isTrue);

      rig.controller.cancel();
      await pass;
      await rig.flush();

      expect(rig.plays, hasLength(1), reason: 'no further phoneme plays');
      expect(rig.stops, hasLength(1), reason: 'the sounding clip is stopped');
      expect(rig.ticks.last, isNull);
      expect(rig.listening.calls, ['pause', 'resume']);
      expect(rig.controller.isPlaying, isFalse);
      await rig.tearDown();
    });

    test('EDGE: cancel() with nothing running is a no-op -- no resume owed',
        () async {
      final rig = _Rig();
      rig.controller.cancel();
      await rig.flush();
      expect(rig.listening.calls, isEmpty);
      expect(rig.fake.callLog, isEmpty);
      await rig.tearDown();
    });
  });

  group('POSITIVE: overlap -- a second request stops the first', () {
    test('play() during a pass supersedes it: old clip stopped, only the new '
        'word\'s remaining clips play, ONE pause and ONE resume overall',
        () async {
      final rig = _Rig();
      final first = rig.controller.play(wordIndex: 0, word: _wordShip());
      await rig.flush();
      expect(rig.plays.map((e) => e.ref).toList(), ['audio/phonemes/SH.wav']);

      final second = rig.controller.play(wordIndex: 1, word: _wordCake());
      await rig.drain(second);
      await first; // The superseded pass also completes -- nothing hangs.
      await rig.flush();

      expect(rig.plays.map((e) => e.ref).toList(), [
        'audio/phonemes/SH.wav', // first pass, stopped
        'audio/phonemes/K.wav',
        'audio/phonemes/EY.wav',
        'audio/phonemes/K.wav',
      ]);
      expect(rig.stops, hasLength(1), reason: 'SH stopped by supersession');
      expect(rig.listening.calls, ['pause', 'resume'],
          reason: 'the bracket spans the whole chain of passes');
      // Ticks: ship cluster 0, then cake clusters under the NEW word index,
      // then a single clear.
      expect(rig.ticks, [
        (wordIndex: 0, graphemeIndex: 0),
        (wordIndex: 1, graphemeIndex: 0),
        (wordIndex: 1, graphemeIndex: 1),
        (wordIndex: 1, graphemeIndex: 2),
        null,
      ]);
      await rig.tearDown();
    });
  });

  group('NEGATIVE: always resumes on audio/content problems', () {
    test('an AudioService-level missing ref ends the pass quietly: no throw, '
        'highlight cleared, listening resumed', () async {
      final rig = _Rig(missingRefs: const {'audio/phonemes/SH.wav'});
      await rig.controller.play(wordIndex: 0, word: _wordShip());
      await rig.flush();

      expect(rig.listening.calls, ['pause', 'resume']);
      expect(rig.ticks, [null], reason: 'nothing sounded, one clear');
      expect(rig.controller.isPlaying, isFalse);
      await rig.tearDown();
    });

    test('a phonemeId absent from the shipped map stops the sequence after '
        'the clips before it, and still resumes', () async {
      final rig = _Rig(refs: const {'SH': 'audio/phonemes/SH.wav'});
      await rig.drain(rig.controller.play(wordIndex: 0, word: _wordShip()));

      expect(rig.plays, hasLength(1));
      expect(rig.ticks, [(wordIndex: 0, graphemeIndex: 0), null]);
      expect(rig.listening.calls, ['pause', 'resume']);
      await rig.tearDown();
    });

    test('EDGE: a word of only silent letters brackets and clears without a '
        'single audio call', () async {
      final word = WordToken(
        text: 'xx',
        graphemePhonemeMap: const [
          (graphemes: 'x', phonemeId: ''),
          (graphemes: 'x', phonemeId: ''),
        ],
        pronunciationAudioRef: 'audio/words/xx.wav',
      );
      final rig = _Rig();
      await rig.controller.play(wordIndex: 0, word: word);
      await rig.flush();

      expect(rig.fake.callLog, isEmpty);
      expect(rig.ticks, [null]);
      expect(rig.listening.calls, ['pause', 'resume']);
      await rig.tearDown();
    });
  });

  group('playGrapheme -- the tappable-chip path', () {
    test('POSITIVE: plays exactly the named cluster\'s clip, once, on the '
        'help channel, with no highlight tick and no listening bracket',
        () async {
      final rig = _Rig();
      final call = rig.controller.playGrapheme(_wordShip(), 1);
      await rig.flush();
      expect(rig.plays.map((e) => e.ref).toList(), ['audio/phonemes/IH.wav']);
      expect(rig.plays.single.channel, AudioChannel.help);
      rig.fake.completePlayback(rig.plays.single.handle);
      await call;

      expect(rig.ticks, isEmpty);
      expect(rig.listening.calls, isEmpty);
      await rig.tearDown();
    });

    test('NEGATIVE: a silent-letter chip is a gentle no-op -- no audio, no '
        'error', () async {
      final rig = _Rig();
      await rig.controller.playGrapheme(_wordCake(), 3);
      await rig.flush();
      expect(rig.fake.callLog, isEmpty);
      await rig.tearDown();
    });

    test('NEGATIVE: out-of-range indices and a missing clip are gentle '
        'no-ops too', () async {
      final rig = _Rig(refs: const {});
      await rig.controller.playGrapheme(_wordShip(), -1);
      await rig.controller.playGrapheme(_wordShip(), 99);
      await rig.controller.playGrapheme(_wordShip(), 0); // 'SH' not in map
      await rig.flush();
      expect(rig.fake.callLog, isEmpty);
      await rig.tearDown();
    });

    test('NEGATIVE: an AudioService error is swallowed', () async {
      final rig = _Rig(missingRefs: const {'audio/phonemes/IH.wav'});
      await rig.controller.playGrapheme(_wordShip(), 1);
      await rig.flush();
      expect(rig.plays, isEmpty);
      await rig.tearDown();
    });
  });

  group('EDGE: dispose', () {
    test('dispose closes the highlight stream, stops the running pass, and '
        'makes later calls inert', () async {
      final rig = _Rig();
      var closed = false;
      final sub2 = rig.controller.highlights.listen((_) {}, onDone: () => closed = true);

      final pass = rig.controller.play(wordIndex: 0, word: _wordShip());
      await rig.flush();
      rig.controller.dispose();
      await pass;
      await rig.flush();

      expect(closed, isTrue);
      expect(rig.stops, hasLength(1));
      // Inert afterwards: no new bracket, no new audio.
      final before = rig.listening.calls.length;
      await rig.controller.play(wordIndex: 1, word: _wordCake());
      await rig.controller.playGrapheme(_wordShip(), 0);
      rig.controller.cancel();
      await rig.flush();
      expect(rig.listening.calls.length, before);
      expect(rig.plays, hasLength(1));

      await sub2.cancel();
      await rig.sub.cancel();
    });
  });
}

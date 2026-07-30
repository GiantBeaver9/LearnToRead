// Pins the listening bracket around every StuckWordController help audio
// pass (audio-audit fix, 2026-07-30): help audio used to play over the OPEN
// microphone, letting the recognizer hear Tier 2 model the target word and
// self-accept it (recorded unaided-correct for a word the child never said),
// and letting Tier 1's phoneme bursts feed the tracker's A-12
// non-matching-burst counter.
//
// Pinned API surface (ADDITIVE to the constructor pinned by
// stuck_word_controller_test.dart -- every pre-existing construction site
// compiles and behaves identically):
//
//   StuckWordController({
//     ...existing required/optional params...,
//     VoidCallback pauseListening = <no-op>,
//     VoidCallback resumeListening = <no-op>,
//   });
//
// Contract this suite locks in:
//  - Tier 2's clip pair (model word + "your turn") is bracketed: pause
//    fires BEFORE the model clip is dispatched, resume fires only after the
//    "your turn" clip completes -- exactly one pause/resume per T2 firing.
//  - Tier 1's sound-out pass is bracketed the same way: pause before the
//    first phoneme is dispatched, resume when the sound-out stream closes.
//    The T1->T2 escalation timer (the controller's own post-Tier-1 T2 wait)
//    is unaffected by the bracket: Tier 2 still fires exactly t2 after the
//    sound-out closes even though the tracker would be paused for the
//    pass's duration (escalation never depends on tracker silence events,
//    which only ever *enter* Tier 1).
//  - The near-miss prompt's two clips are bracketed too (they play while
//    the mic is already listening for the NEXT word).
//  - Resume is unconditional (swallow-and-resume, the same posture as
//    NarrationController.replay / OnDemandSoundOut): a missing clip or any
//    audio error still closes the bracket, and the ladder keeps moving.
//  - A controller constructed WITHOUT the callbacks (every frozen suite's
//    construction shape) behaves byte-identically: same audio dispatches,
//    same resolutions, no callback ever required.
//  - Overlapping passes (a new word's tier firing while a superseded
//    word's clip is still winding down) never double-pause or resume under
//    live help audio: brackets are depth-counted, so pause fires only on
//    the first open and resume only when the last bracket closes --
//    pause/resume stay balanced at exactly one effective pair.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/domain/tuning.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/audio/phoneme_sequencer.dart';
import 'package:learn_to_read/features/help/help_recorder.dart';
import 'package:learn_to_read/features/help/near_miss_prompt.dart';
import 'package:learn_to_read/features/help/sound_out_sequence.dart';
import 'package:learn_to_read/features/help/stuck_word_controller.dart';
import 'package:learn_to_read/features/listening/contracts/tracker_events.dart';

// ---------------------------------------------------------------------------
// Fixtures (same words/refs as stuck_word_controller_test.dart).
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

WordToken _wordCat() => WordToken(
  text: 'cat',
  graphemePhonemeMap: const [
    (graphemes: 'c', phonemeId: 'K'),
    (graphemes: 'a', phonemeId: 'AE'),
    (graphemes: 't', phonemeId: 'T'),
  ],
  pronunciationAudioRef: 'audio/words/cat.wav',
);

const _phonemeAudioRefs = {
  'SH': 'audio/phonemes/SH.wav',
  'IH': 'audio/phonemes/IH.wav',
  'P': 'audio/phonemes/P.wav',
  'K': 'audio/phonemes/K.wav',
  'AE': 'audio/phonemes/AE.wav',
  'T': 'audio/phonemes/T.wav',
};

const _yourTurnRef = 'audio/prompts/your_turn.wav';
const _nearMissPromptRef = 'audio/prompts/that_is_it.wav';

class _RecordingHelpRecorder implements HelpRecorderApi {
  final List<({WordToken word, HelpLevel tier})> calls = [];

  @override
  Future<void> recordResolution({
    required WordToken word,
    required HelpLevel tier,
  }) async {
    calls.add((word: word, tier: tier));
  }
}

/// A `StuckWordController` wired to recording pause/resume callbacks.
///
/// Each pause/resume call is logged with the number of help-channel play
/// dispatches at that instant, so tests can pin not just how often the
/// bracket fired but exactly WHERE it fired relative to the clips.
class _Harness {
  _Harness({Set<AudioRef> missingRefs = const {}, bool wired = true})
    : fake = FakeAudioService(missingRefs: missingRefs) {
    final sequencer = PhonemeSequencer(
      audioService: fake,
      phonemeAudioRefs: _phonemeAudioRefs,
    );
    controller = wired
        ? StuckWordController(
            events: eventsController.stream,
            soundOutSequence: SoundOutSequence(phonemeSequencer: sequencer),
            audioService: fake,
            nearMissPrompt: NearMissPrompt(
              audioService: fake,
              promptLineAudioRef: _nearMissPromptRef,
            ),
            helpRecorder: recorder,
            yourTurnPromptAudioRef: _yourTurnRef,
            pauseListening: () {
              bracketCalls.add('pause');
              pausePlayCounts.add(helpPlayCount);
            },
            resumeListening: () {
              bracketCalls.add('resume');
              resumePlayCounts.add(helpPlayCount);
            },
          )
        // The frozen construction shape: no bracket callbacks at all. This
        // compiling is itself the source-compatibility assertion.
        : StuckWordController(
            events: eventsController.stream,
            soundOutSequence: SoundOutSequence(phonemeSequencer: sequencer),
            audioService: fake,
            nearMissPrompt: NearMissPrompt(
              audioService: fake,
              promptLineAudioRef: _nearMissPromptRef,
            ),
            helpRecorder: recorder,
            yourTurnPromptAudioRef: _yourTurnRef,
          );
    controller.wordHelpedStream.listen(helpedEvents.add);
  }

  final FakeAudioService fake;
  final _RecordingHelpRecorder recorder = _RecordingHelpRecorder();
  final StreamController<TrackerEvent> eventsController =
      StreamController<TrackerEvent>();
  late final StuckWordController controller;

  /// 'pause' / 'resume' entries, in call order.
  final List<String> bracketCalls = [];

  /// Help-channel play-dispatch count at the instant of each pause call.
  final List<int> pausePlayCounts = [];

  /// Help-channel play-dispatch count at the instant of each resume call.
  final List<int> resumePlayCounts = [];

  final List<WordHelped> helpedEvents = [];

  int get helpPlayCount => fake.callLog
      .whereType<PlayLogEntry>()
      .where((e) => e.channel == AudioChannel.help)
      .length;

  /// Refs of every help-channel play dispatched so far, in order.
  List<AudioRef> get helpPlayRefs => fake.callLog
      .whereType<PlayLogEntry>()
      .where((e) => e.channel == AudioChannel.help)
      .map((e) => e.ref)
      .toList();

  /// The handle of the most recent play of [ref].
  PlaybackHandle handleOf(AudioRef ref) => fake.callLog
      .whereType<PlayLogEntry>()
      .lastWhere((e) => e.ref == ref)
      .handle;

  /// Completes the most recent play of [ref] and flushes microtasks so the
  /// next queued clip (if any) is dispatched.
  void completeClip(FakeAsync async, AudioRef ref) {
    fake.completePlayback(handleOf(ref));
    async.flushMicrotasks();
  }

  void dispose() {
    controller.dispose();
    unawaited(eventsController.close());
  }
}

void main() {
  group('POSITIVE: Tier 2 clip pair is bracketed', () {
    test(
      'pause fires before the model clip; resume only after "your turn" completes',
      () {
        fakeAsync((async) {
          final h = _Harness();
          h.controller.watchWord(index: 0, word: _wordCat());
          async.elapse(kStruggleT1);
          h.completeClip(async, 'audio/phonemes/K.wav');
          h.completeClip(async, 'audio/phonemes/AE.wav');
          h.completeClip(async, 'audio/phonemes/T.wav');
          // Tier 1's own bracket has fully closed by now.
          expect(h.bracketCalls, ['pause', 'resume']);

          async.elapse(kTier2WaitT2); // Tier 2 fires: model clip dispatched.
          expect(h.helpPlayRefs.last, 'audio/words/cat.wav');
          expect(h.bracketCalls, ['pause', 'resume', 'pause']);
          expect(
            h.pausePlayCounts.last,
            3,
            reason: 'T2 pause must land BEFORE the model clip (4th play)',
          );

          h.completeClip(async, 'audio/words/cat.wav');
          expect(h.helpPlayRefs.last, _yourTurnRef);
          expect(
            h.bracketCalls,
            ['pause', 'resume', 'pause'],
            reason: 'no resume between the model word and "your turn"',
          );

          h.completeClip(async, _yourTurnRef);
          expect(h.bracketCalls, ['pause', 'resume', 'pause', 'resume']);
          expect(
            h.resumePlayCounts.last,
            5,
            reason: 'T2 resume must land after both clips are out',
          );
          h.dispose();
        });
      },
    );

    test('exactly one pause/resume per T2 firing, through auto-accept', () {
      fakeAsync((async) {
        final h = _Harness();
        h.controller.watchWord(index: 0, word: _wordCat());
        async.elapse(kStruggleT1);
        h.completeClip(async, 'audio/phonemes/K.wav');
        h.completeClip(async, 'audio/phonemes/AE.wav');
        h.completeClip(async, 'audio/phonemes/T.wav');
        async.elapse(kTier2WaitT2);
        h.completeClip(async, 'audio/words/cat.wav');
        h.completeClip(async, _yourTurnRef);

        async.elapse(kTier2WaitT2); // auto-accept: no further bracket calls.

        expect(h.helpedEvents, hasLength(1));
        expect(h.helpedEvents.single.tier, HelpLevel.modeled);
        expect(h.bracketCalls, ['pause', 'resume', 'pause', 'resume']);
        h.dispose();
      });
    });
  });

  group('POSITIVE: Tier 1 sound-out pass is bracketed', () {
    test('pause before the first phoneme; resume when the pass closes', () {
      fakeAsync((async) {
        final h = _Harness();
        h.controller.watchWord(index: 0, word: _wordShip());
        async.elapse(kStruggleT1);

        expect(h.bracketCalls, ['pause']);
        expect(
          h.pausePlayCounts.single,
          0,
          reason: 'paused before the first phoneme was dispatched',
        );

        h.completeClip(async, 'audio/phonemes/SH.wav');
        h.completeClip(async, 'audio/phonemes/IH.wav');
        expect(
          h.bracketCalls,
          ['pause'],
          reason: 'no resume between phonemes of one pass',
        );

        h.completeClip(async, 'audio/phonemes/P.wav'); // stream closes
        expect(h.bracketCalls, ['pause', 'resume']);
        expect(h.resumePlayCounts.single, 3);
        h.dispose();
      });
    });

    test(
      'escalation timing survives the bracket: Tier 2 fires exactly t2 after '
      'the sound-out closes (controller-internal timer, not tracker silence)',
      () {
        fakeAsync((async) {
          final h = _Harness();
          h.controller.watchWord(index: 0, word: _wordCat());
          async.elapse(kStruggleT1);
          h.completeClip(async, 'audio/phonemes/K.wav');
          h.completeClip(async, 'audio/phonemes/AE.wav');
          h.completeClip(async, 'audio/phonemes/T.wav');
          expect(h.bracketCalls, ['pause', 'resume']);

          // A real tracker was paused throughout the pass and its silence
          // detector restarted fresh on resume -- yet Tier 2 must still fire
          // exactly t2 later, on the ladder's own timer.
          async.elapse(kTier2WaitT2 - const Duration(milliseconds: 1));
          expect(
            h.helpPlayRefs.contains('audio/words/cat.wav'),
            isFalse,
          );
          async.elapse(const Duration(milliseconds: 1));
          expect(h.helpPlayRefs.last, 'audio/words/cat.wav');
          h.dispose();
        });
      },
    );

    test('a word accepted mid-sound-out still closes the bracket (resume)', () {
      fakeAsync((async) {
        final h = _Harness();
        h.controller.watchWord(index: 0, word: _wordShip());
        async.elapse(kStruggleT1); // only "SH" dispatched
        expect(h.bracketCalls, ['pause']);

        h.eventsController.add(const WordAccepted(index: 0));
        async.flushMicrotasks();

        expect(
          h.bracketCalls,
          ['pause', 'resume'],
          reason:
              'a cancelled sound-out never fires onDone, so the resolve path '
              'itself must close the bracket',
        );
        expect(h.helpedEvents.single.tier, HelpLevel.soundOut);
        h.dispose();
      });
    });
  });

  group('POSITIVE: near-miss prompt is bracketed', () {
    test('pause before the clip pair; resume after both complete', () {
      fakeAsync((async) {
        final h = _Harness();
        h.controller.watchWord(index: 0, word: _wordCat());
        async.elapse(const Duration(seconds: 1)); // no tier reached

        h.eventsController.add(const WordAcceptedNearMiss(index: 0));
        async.flushMicrotasks();

        // Both clips are dispatched up front (pinned NearMissPrompt order).
        expect(h.helpPlayRefs, [_nearMissPromptRef, 'audio/words/cat.wav']);
        expect(h.bracketCalls, ['pause']);
        expect(
          h.pausePlayCounts.single,
          0,
          reason: 'paused before the prompt line was dispatched',
        );

        h.completeClip(async, _nearMissPromptRef);
        expect(h.bracketCalls, ['pause']);

        h.completeClip(async, 'audio/words/cat.wav');
        expect(h.bracketCalls, ['pause', 'resume']);
        h.dispose();
      });
    });
  });

  group('NEGATIVE: audio errors still resume (swallow-and-resume)', () {
    test('Tier 2 model clip missing: resume fires, ladder auto-accepts', () {
      fakeAsync((async) {
        final h = _Harness(missingRefs: {'audio/words/cat.wav'});
        h.controller.watchWord(index: 0, word: _wordCat());
        async.elapse(kStruggleT1);
        h.completeClip(async, 'audio/phonemes/K.wav');
        h.completeClip(async, 'audio/phonemes/AE.wav');
        h.completeClip(async, 'audio/phonemes/T.wav');

        async.elapse(kTier2WaitT2); // Tier 2 fires; its play() throws.

        expect(
          h.bracketCalls,
          ['pause', 'resume', 'pause', 'resume'],
          reason: 'the T2 bracket must close on the error path',
        );

        async.elapse(kTier2WaitT2); // final T2 still runs: never blocked.
        expect(h.helpedEvents.single.tier, HelpLevel.modeled);
        h.dispose();
      });
    });

    test('"your turn" clip missing: resume still fires after the model', () {
      fakeAsync((async) {
        final h = _Harness(missingRefs: {_yourTurnRef});
        h.controller.watchWord(index: 0, word: _wordCat());
        async.elapse(kStruggleT1);
        h.completeClip(async, 'audio/phonemes/K.wav');
        h.completeClip(async, 'audio/phonemes/AE.wav');
        h.completeClip(async, 'audio/phonemes/T.wav');
        async.elapse(kTier2WaitT2);

        h.completeClip(async, 'audio/words/cat.wav'); // then play() throws

        expect(h.bracketCalls, ['pause', 'resume', 'pause', 'resume']);
        async.elapse(kTier2WaitT2);
        expect(h.helpedEvents.single.tier, HelpLevel.modeled);
        h.dispose();
      });
    });

    test('Tier 1 phoneme clip missing mid-pass: the pass still resumes', () {
      fakeAsync((async) {
        final h = _Harness(missingRefs: {'audio/phonemes/IH.wav'});
        h.controller.watchWord(index: 0, word: _wordShip());
        async.elapse(kStruggleT1);

        // SH plays; completing it makes the sequencer hit the missing IH,
        // which errors AND closes the stream -- the bracket must ride the
        // close, not the happy path.
        h.completeClip(async, 'audio/phonemes/SH.wav');

        expect(h.bracketCalls, ['pause', 'resume']);
        // And the ladder keeps moving: Tier 2 fires t2 later.
        async.elapse(kTier2WaitT2);
        expect(h.helpPlayRefs.last, 'audio/words/ship.wav');
        h.dispose();
      });
    });

    test('near-miss prompt line missing: resume still fires', () {
      fakeAsync((async) {
        final h = _Harness(missingRefs: {_nearMissPromptRef});
        h.controller.watchWord(index: 0, word: _wordCat());

        h.eventsController.add(const WordAcceptedNearMiss(index: 0));
        async.flushMicrotasks();

        expect(h.bracketCalls, ['pause', 'resume']);
        expect(h.recorder.calls.single.tier, HelpLevel.none);
        h.dispose();
      });
    });
  });

  group('NEGATIVE: unwired (default no-op) controller is unchanged', () {
    test(
      'the frozen construction shape compiles and runs the full ladder '
      'byte-identically -- no callback ever required',
      () {
        fakeAsync((async) {
          final h = _Harness(wired: false);
          h.controller.watchWord(index: 0, word: _wordCat());
          async.elapse(kStruggleT1);
          h.completeClip(async, 'audio/phonemes/K.wav');
          h.completeClip(async, 'audio/phonemes/AE.wav');
          h.completeClip(async, 'audio/phonemes/T.wav');
          async.elapse(kTier2WaitT2);
          h.completeClip(async, 'audio/words/cat.wav');
          h.completeClip(async, _yourTurnRef);
          async.elapse(kTier2WaitT2);

          // The exact audio sequence the frozen suite pins, unchanged.
          expect(h.helpPlayRefs, [
            'audio/phonemes/K.wav',
            'audio/phonemes/AE.wav',
            'audio/phonemes/T.wav',
            'audio/words/cat.wav',
            _yourTurnRef,
          ]);
          expect(h.helpedEvents.single.tier, HelpLevel.modeled);
          expect(h.recorder.calls.single.tier, HelpLevel.modeled);
          expect(h.bracketCalls, isEmpty);
          h.dispose();
        });
      },
    );
  });

  group('EDGE: rapid re-fire keeps the bracket balanced', () {
    test(
      'a new word\'s Tier 1 firing while the superseded word\'s Tier 2 clip '
      'is still playing neither double-pauses nor resumes under live audio',
      () {
        fakeAsync((async) {
          final h = _Harness();
          // Word 0 escalates all the way into Tier 2's model clip.
          h.controller.watchWord(index: 0, word: _wordCat());
          async.elapse(kStruggleT1);
          h.completeClip(async, 'audio/phonemes/K.wav');
          h.completeClip(async, 'audio/phonemes/AE.wav');
          h.completeClip(async, 'audio/phonemes/T.wav');
          async.elapse(kTier2WaitT2); // model clip playing; bracket open
          expect(h.bracketCalls, ['pause', 'resume', 'pause']);

          // The child moves on mid-clip: word 1 supersedes, then goes
          // silent long enough for ITS Tier 1 to fire while word 0's model
          // clip is still winding down.
          h.controller.watchWord(index: 1, word: _wordShip());
          async.elapse(kStruggleT1);
          expect(h.helpPlayRefs.last, 'audio/phonemes/SH.wav');
          expect(
            h.bracketCalls,
            ['pause', 'resume', 'pause'],
            reason: 'already paused: the overlapping pass must not re-pause',
          );

          // Word 0's model clip finally ends; its bracket closes -- but
          // word 1's pass is live, so listening must NOT resume yet.
          h.completeClip(async, 'audio/words/cat.wav');
          expect(
            h.bracketCalls,
            ['pause', 'resume', 'pause'],
            reason: 'no resume under word 1\'s live sound-out audio',
          );
          expect(
            h.helpPlayRefs.contains(_yourTurnRef),
            isFalse,
            reason: 'the superseded Tier 2 never plays its second clip',
          );

          // Word 1's pass ends: now the one balancing resume fires.
          h.completeClip(async, 'audio/phonemes/SH.wav');
          h.completeClip(async, 'audio/phonemes/IH.wav');
          h.completeClip(async, 'audio/phonemes/P.wav');
          expect(h.bracketCalls, ['pause', 'resume', 'pause', 'resume']);
          h.dispose();
        });
      },
    );

    test('rapid watchWord supersessions during Tier 1 stay balanced', () {
      fakeAsync((async) {
        final h = _Harness();
        h.controller.watchWord(index: 0, word: _wordShip());
        async.elapse(kStruggleT1); // word 0's Tier 1 starts (pause #1)
        expect(h.bracketCalls, ['pause']);

        // Supersede mid-pass, then again before anything else plays.
        h.controller.watchWord(index: 1, word: _wordCat());
        expect(
          h.bracketCalls,
          ['pause', 'resume'],
          reason: 'the cancelled pass closes its own bracket',
        );
        h.controller.watchWord(index: 2, word: _wordShip());
        expect(h.bracketCalls, ['pause', 'resume']);

        // Word 2's Tier 1 runs a full, cleanly bracketed pass.
        async.elapse(kStruggleT1);
        h.completeClip(async, 'audio/phonemes/SH.wav');
        h.completeClip(async, 'audio/phonemes/IH.wav');
        h.completeClip(async, 'audio/phonemes/P.wav');
        expect(h.bracketCalls, ['pause', 'resume', 'pause', 'resume']);
        h.dispose();
      });
    });
  });
}

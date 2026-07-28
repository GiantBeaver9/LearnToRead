// Property-style suite over lib/features/help/stuck_word_controller.dart
// (PRD §8 Unit 6 "never hard-blocks"; ticket stuck-word-scaffold accept
// entry 5: "no path exists where the child is blocked longer than T1 +
// Tier1 + T2 + Tier2 + T2 without the story advancing"). This suite is
// authored before the implementation exists, so it is EXPECTED to fail to
// compile until stuck_word_controller.dart (and its sibling files) are
// written per the pinned surface documented in stuck_word_controller_test.dart's
// header, which this file also relies on.
//
// What this suite pins beyond the single-scenario tests in
// stuck_word_controller_test.dart: the MAXIMUM blocked-duration bound holds
// across the whole space of "when does the child's production land"
// permutations, not just the couple of cases exercised elsewhere --
// including the permutation that matters most for "never hard-blocks":
// the child's production never lands at all. For every permutation, the
// controller must resolve (emit exactly one WordHelped, or -- for the
// unaided-before-any-struggle case -- record a plain resolution) at or
// before the pinned bound
//   T1 + Tier1AudioDuration + T2 + Tier2AudioDuration + T2
// and, for the "never arrives" permutation specifically, resolve EXACTLY
// at that bound (proving the auto-accept fires -- not later, not never).
// Tier1AudioDuration/Tier2AudioDuration are the (test-controlled, fake)
// wall-clock time the sounded-out phonemes / Tier 2's two clips take to
// play -- audio duration is not itself a tuning.dart constant (real
// playback length varies by clip), so this suite fixes a concrete,
// non-zero per-clip step to prove the bound holds with genuine audio time
// folded in, not just in the degenerate zero-duration case.

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

// A 2-phoneme word keeps the arithmetic in each permutation legible.
WordToken _wordAt() => WordToken(
  text: 'at',
  graphemePhonemeMap: const [
    (graphemes: 'a', phonemeId: 'AE'),
    (graphemes: 't', phonemeId: 'T'),
  ],
  pronunciationAudioRef: 'audio/words/at.wav',
);

const _phonemeAudioRefs = {'AE': 'audio/phonemes/AE.wav', 'T': 'audio/phonemes/T.wav'};
const _yourTurnRef = 'audio/prompts/your_turn.wav';
const _nearMissPromptRef = 'audio/prompts/that_is_it.wav';

const _phonemeStep = Duration(milliseconds: 250); // per-phoneme simulated audio duration
final _tier1AudioDuration = _phonemeStep * 2; // "at" has 2 phonemes
const _wordAudioStep = Duration(milliseconds: 300); // Tier 2's word-pronunciation clip
const _yourTurnStep = Duration(milliseconds: 200); // Tier 2's "your turn" clip
final _tier2AudioDuration = _wordAudioStep + _yourTurnStep;

// Duration's arithmetic operators are ordinary instance methods (not
// recognized constant operations), so this composed bound is `final`
// (computed once at load time), not `const`.
final _maxBlockedDuration = kStruggleT1 + _tier1AudioDuration + kTier2WaitT2 + _tier2AudioDuration + kTier2WaitT2;

class _RecordingHelpRecorder implements HelpRecorderApi {
  final List<({WordToken word, HelpLevel tier})> calls = [];

  @override
  Future<void> recordResolution({required WordToken word, required HelpLevel tier}) async {
    calls.add((word: word, tier: tier));
  }
}

class _Rig {
  _Rig({required this.fake, required this.recorder, required this.eventsController, required this.controller});

  final FakeAudioService fake;
  final _RecordingHelpRecorder recorder;
  final StreamController<TrackerEvent> eventsController;
  final StuckWordController controller;

  final List<WordHelped> helpedEvents = [];

  void dispose() {
    controller.dispose();
    unawaited(eventsController.close());
  }
}

_Rig _rig() {
  final fake = FakeAudioService();
  final recorder = _RecordingHelpRecorder();
  final eventsController = StreamController<TrackerEvent>();
  final controller = StuckWordController(
    events: eventsController.stream,
    soundOutSequence: SoundOutSequence(
      phonemeSequencer: PhonemeSequencer(audioService: fake, phonemeAudioRefs: _phonemeAudioRefs),
    ),
    audioService: fake,
    nearMissPrompt: NearMissPrompt(audioService: fake, promptLineAudioRef: _nearMissPromptRef),
    helpRecorder: recorder,
    yourTurnPromptAudioRef: _yourTurnRef,
  );
  final rig = _Rig(fake: fake, recorder: recorder, eventsController: eventsController, controller: controller);
  controller.wordHelpedStream.listen(rig.helpedEvents.add);
  return rig;
}

PlaybackHandle _lastHelpPlay(FakeAudioService fake) =>
    fake.callLog.whereType<PlayLogEntry>().lastWhere((e) => e.channel == AudioChannel.help).handle;

/// Completes the two "at" phonemes, one [_phonemeStep] apart, ending Tier 1.
void _drainTier1(_Rig rig, FakeAsync async) {
  async.elapse(_phonemeStep);
  rig.fake.completePlayback(_lastHelpPlay(rig.fake));
  async.flushMicrotasks();
  async.elapse(_phonemeStep);
  rig.fake.completePlayback(_lastHelpPlay(rig.fake));
  async.flushMicrotasks();
}

/// Completes Tier 2's word-pronunciation clip then its "your turn" clip,
/// [_wordAudioStep]/[_yourTurnStep] apart, ending Tier 2's own audio.
void _drainTier2Audio(_Rig rig, FakeAsync async) {
  async.elapse(_wordAudioStep);
  rig.fake.completePlayback(_lastHelpPlay(rig.fake));
  async.flushMicrotasks();
  async.elapse(_yourTurnStep);
  rig.fake.completePlayback(_lastHelpPlay(rig.fake));
  async.flushMicrotasks();
}

void main() {
  group('PROPERTY: resolution never exceeds T1 + Tier1 + T2 + Tier2 + T2', () {
    test('resolved immediately (before any struggle at all) -- tier none', () {
      fakeAsync((async) {
        final rig = _rig();
        rig.controller.watchWord(index: 0, word: _wordAt());

        rig.eventsController.add(const WordAccepted(index: 0));
        async.flushMicrotasks();

        expect(rig.recorder.calls, hasLength(1));
        expect(rig.recorder.calls.single.tier, HelpLevel.none);
        expect(rig.helpedEvents, isEmpty);
        expect(async.elapsed, Duration.zero);
        expect(async.elapsed, lessThanOrEqualTo(_maxBlockedDuration));
        rig.dispose();
      });
    });

    test('resolved during the initial silence, before T1 -- tier none', () {
      fakeAsync((async) {
        final rig = _rig();
        rig.controller.watchWord(index: 0, word: _wordAt());
        async.elapse(const Duration(seconds: 1));

        rig.eventsController.add(const WordAccepted(index: 0));
        async.flushMicrotasks();

        expect(rig.recorder.calls.single.tier, HelpLevel.none);
        expect(async.elapsed, const Duration(seconds: 1));
        expect(async.elapsed, lessThanOrEqualTo(_maxBlockedDuration));
        rig.dispose();
      });
    });

    test('resolved mid Tier-1 phoneme audio -- tier soundOut', () {
      fakeAsync((async) {
        final rig = _rig();
        rig.controller.watchWord(index: 0, word: _wordAt());
        async.elapse(kStruggleT1); // first phoneme (AE) now playing

        rig.eventsController.add(const WordAccepted(index: 0));
        async.flushMicrotasks();

        expect(rig.helpedEvents, hasLength(1));
        expect(rig.helpedEvents.single.tier, HelpLevel.soundOut);
        expect(async.elapsed, kStruggleT1);
        expect(async.elapsed, lessThanOrEqualTo(_maxBlockedDuration));
        rig.dispose();
      });
    });

    test('resolved during the post-Tier-1 T2 wait -- tier soundOut', () {
      fakeAsync((async) {
        final rig = _rig();
        rig.controller.watchWord(index: 0, word: _wordAt());
        async.elapse(kStruggleT1);
        _drainTier1(rig, async);

        async.elapse(const Duration(seconds: 1));
        rig.eventsController.add(const WordAccepted(index: 0));
        async.flushMicrotasks();

        expect(rig.helpedEvents, hasLength(1));
        expect(rig.helpedEvents.single.tier, HelpLevel.soundOut);
        expect(async.elapsed, kStruggleT1 + _tier1AudioDuration + const Duration(seconds: 1));
        expect(async.elapsed, lessThanOrEqualTo(_maxBlockedDuration));
        rig.dispose();
      });
    });

    test('resolved during the post-Tier-2 (final) T2 wait -- tier modeled, repeat-accepted', () {
      fakeAsync((async) {
        final rig = _rig();
        rig.controller.watchWord(index: 0, word: _wordAt());
        async.elapse(kStruggleT1);
        _drainTier1(rig, async);
        async.elapse(kTier2WaitT2);
        _drainTier2Audio(rig, async);

        async.elapse(const Duration(seconds: 1));
        rig.eventsController.add(const WordAccepted(index: 0));
        async.flushMicrotasks();

        expect(rig.helpedEvents, hasLength(1));
        expect(rig.helpedEvents.single.tier, HelpLevel.modeled);
        expect(
          async.elapsed,
          kStruggleT1 + _tier1AudioDuration + kTier2WaitT2 + _tier2AudioDuration + const Duration(seconds: 1),
        );
        expect(async.elapsed, lessThanOrEqualTo(_maxBlockedDuration));
        rig.dispose();
      });
    });

    test(
      'the child NEVER produces the word: auto-accepted exactly at the pinned bound -- tier modeled (never hard-blocks)',
      () {
        fakeAsync((async) {
          final rig = _rig();
          rig.controller.watchWord(index: 0, word: _wordAt());
          async.elapse(kStruggleT1);
          _drainTier1(rig, async);
          async.elapse(kTier2WaitT2);
          _drainTier2Audio(rig, async);

          expect(rig.helpedEvents, isEmpty, reason: 'still inside the final T2 wait');

          async.elapse(kTier2WaitT2); // no WordAccepted ever sent

          expect(rig.helpedEvents, hasLength(1));
          expect(rig.helpedEvents.single.tier, HelpLevel.modeled);
          expect(async.elapsed, _maxBlockedDuration);

          // Elapsing further changes nothing -- resolution already happened,
          // exactly once, exactly at the bound.
          async.elapse(const Duration(seconds: 30));
          expect(rig.helpedEvents, hasLength(1));

          rig.dispose();
        });
      },
    );
  });
}

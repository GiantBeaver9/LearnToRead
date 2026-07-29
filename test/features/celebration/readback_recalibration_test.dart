// Test suite for the RECALIBRATED celebration sequence (PRD §8 Unit 8
// "Narrated read-back (ratified; RECALIBRATED 2026-07-29, owner)"):
//
//  - The read-back is EVERY sentence of the story, in order (all pages,
//    all sentences with a narrationAudioRef), played sequentially over the
//    celebrate animation -- each clip starts when the previous completes
//    (AudioService.completionOf), not on a timer.
//  - The payoff (sting + rotated voice line + collect trigger + flight)
//    WAITS for the read-back to finish instead of running concurrently.
//  - Stories with no narration keep the immediate payoff (unchanged).
//  - The <=10 s ceiling and the tap-skip-after-2 s rules bound the
//    read-back too: a tap during the read-back stops the narration and
//    jumps straight to the payoff; if the read-back outlives the hold
//    phase's natural (ceiling-bounded) duration, the ceiling wins.
//  - Playback failures never wedge the sequence (swallow-and-continue).
//
// Uses the FakeAudioService completion-control pattern
// (FakeAudioService.completePlayback on handles pulled from callLog) shared
// with the rest of this frozen suite; API surface as pinned by
// celebration_controller_test.dart.
import 'dart:async';

import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/design/fake_rive_stage.dart';
import 'package:learn_to_read/design/rive_stage.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/celebration/celebration_controller.dart';

const _installId = 'a1b2c3d4-1234-4abc-8def-0123456789ab';
const _profileId = 'profile.amara';

const _stingRef = 'audio/celebration/sting/story.wav';
const _lineRef = 'audio/celebration/lines/great_job.wav';

WordToken _wordToken() => WordToken(
      text: 'cat',
      graphemePhonemeMap: const [(graphemes: 'c', phonemeId: 'K')],
      pronunciationAudioRef: 'audio/words/cat.wav',
    );

Sentence _sentence({String? narrationAudioRef}) => Sentence(
      words: [_wordToken()],
      narrationAudioRef: narrationAudioRef,
    );

Story _storyWithPages(List<Page> pages, {String id = 'story.multi'}) => Story(
      id: id,
      levelId: 'level.1',
      title: 'The Cat Went On',
      pages: pages,
      riveAnimationRef: 'rive/$id.riv',
      celebrationAudioRef: _stingRef,
      collectibleRef: 'collectible.$id',
      skillsExercised: const [],
      packId: 'pack.starter',
      contentVersion: '1',
    );

/// A multi-page, multi-sentence story with narration on every sentence
/// except one (which the read-back must skip): the playlist is s1, s2, s3
/// in page/sentence order.
Story _multiSentenceStory({String id = 'story.multi'}) => _storyWithPages(
      [
        Page(sentences: [
          _sentence(narrationAudioRef: 'audio/narration/$id.s1.wav'),
          _sentence(narrationAudioRef: 'audio/narration/$id.s2.wav'),
        ]),
        Page(sentences: [
          _sentence(), // no narrationAudioRef -- skipped by the read-back
          _sentence(narrationAudioRef: 'audio/narration/$id.s3.wav'),
        ]),
      ],
      id: id,
    );

List<String> _narrationRefsOf(String id) => [
      'audio/narration/$id.s1.wav',
      'audio/narration/$id.s2.wav',
      'audio/narration/$id.s3.wav',
    ];

/// A single-sentence (sentence-format) story with narration.
Story _singleSentenceStory({String id = 'story.single'}) => _storyWithPages(
      [
        Page(sentences: [
          _sentence(narrationAudioRef: 'audio/narration/$id.wav'),
        ]),
      ],
      id: id,
    );

/// A story with no narration anywhere.
Story _noNarrationStory({String id = 'story.silent'}) => _storyWithPages(
      [
        Page(sentences: [_sentence(), _sentence()]),
        Page(sentences: [_sentence()]),
      ],
      id: id,
    );

class _Harness {
  _Harness({Set<AudioRef> missingRefs = const {}})
      : db = AppDatabase(NativeDatabase.memory()),
        audio = FakeAudioService(missingRefs: missingRefs, clock: () => Duration.zero),
        stage = FakeStoryStage();

  final AppDatabase db;
  final FakeAudioService audio;
  final FakeStoryStage stage;
  final List<CelebrationResult> results = [];

  Future<void> close() => db.close();

  List<PlayLogEntry> get narrationPlays => audio.callLog
      .whereType<PlayLogEntry>()
      .where((e) => e.channel == AudioChannel.narration)
      .toList();

  List<PlayLogEntry> get celebrationPlays => audio.callLog
      .whereType<PlayLogEntry>()
      .where((e) => e.channel == AudioChannel.celebration)
      .toList();

  CelebrationController controller() => CelebrationController(
        stage: stage,
        audioService: audio,
        collectionDao: db.collectionDao,
        storyProgressDao: db.storyProgressDao,
        lineRotator: CelebrationLineRotator(
          lines: const [_lineRef],
          nextInt: (max) => 0,
        ),
        installId: _installId,
        onAnalyticsEvent: (_) {},
        onFinished: results.add,
      );
}

void main() {
  group('POSITIVE: multi-sentence read-back plays every narration ref '
      'sequentially, completion-gated, over the celebrate animation', () {
    test('each clip starts only when the previous completes (not on a '
        'timer), in page/sentence order, skipping narration-less '
        'sentences, while activeState stays celebrate', () {
      fakeAsync((async) {
        final h = _Harness();
        final story = _multiSentenceStory();
        final refs = _narrationRefsOf(story.id);
        unawaited(h.controller().run(
              story: story,
              profileId: _profileId,
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));

        // The FIRST clip plays in the same synchronous turn as celebrate.
        expect(h.narrationPlays.map((e) => e.ref), [refs[0]]);
        expect(h.stage.activeState, StoryStageInput.celebrate);
        async.flushMicrotasks();

        // Time alone never advances the read-back: the next clip is gated
        // on completion, not a timer.
        async.elapse(const Duration(milliseconds: 500));
        expect(h.narrationPlays, hasLength(1));

        h.audio.completePlayback(h.narrationPlays[0].handle);
        async.flushMicrotasks();
        expect(h.narrationPlays.map((e) => e.ref), [refs[0], refs[1]]);
        expect(h.stage.activeState, StoryStageInput.celebrate);

        async.elapse(const Duration(milliseconds: 500));
        expect(h.narrationPlays, hasLength(2));

        h.audio.completePlayback(h.narrationPlays[1].handle);
        async.flushMicrotasks();
        // The narration-less sentence is skipped: the third clip is s3.
        expect(h.narrationPlays.map((e) => e.ref), refs);

        // No payoff yet: no celebration-channel audio, no collect.
        expect(h.celebrationPlays, isEmpty);
        expect(h.stage.triggeredInputs, [StoryStageInput.celebrate]);
        expect(h.results, isEmpty);

        h.audio.completePlayback(h.narrationPlays[2].handle);
        async.elapse(const Duration(seconds: 10));
        expect(h.results, hasLength(1));
        unawaited(h.close());
      });
    });

    test('the payoff (sting, line, collect, finish) happens only after the '
        'LAST clip completes', () {
      fakeAsync((async) {
        final h = _Harness();
        final story = _multiSentenceStory();
        unawaited(h.controller().run(
              story: story,
              profileId: _profileId,
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));
        async.flushMicrotasks();

        // Complete the first two clips: still no payoff.
        h.audio.completePlayback(h.narrationPlays[0].handle);
        async.flushMicrotasks();
        h.audio.completePlayback(h.narrationPlays[1].handle);
        async.flushMicrotasks();
        expect(h.celebrationPlays, isEmpty);
        expect(h.stage.triggeredInputs, [StoryStageInput.celebrate]);
        expect(h.results, isEmpty);

        // Complete the last clip: the payoff lands -- sting then line,
        // then the collect trigger.
        h.audio.completePlayback(h.narrationPlays[2].handle);
        async.flushMicrotasks();
        expect(h.celebrationPlays.map((e) => e.ref), [_stingRef, _lineRef]);
        expect(h.stage.triggeredInputs,
            [StoryStageInput.celebrate, StoryStageInput.collect]);

        // onFinished fires after the collectible flight, not before.
        expect(h.results, isEmpty);
        async.elapse(DesignTokens.collectibleFlightDuration);
        expect(h.results, hasLength(1));
        expect(h.results.single.skipped, isFalse);
        expect(h.results.single.isFirstCompletion, isTrue);
        unawaited(h.close());
      });
    });
  });

  group('POSITIVE: single-sentence story -- old behavior except the payoff '
      'now follows the narration completion', () {
    test('one narration clip plays synchronously with celebrate; the sting '
        '+ line + collect wait for its completion', () {
      fakeAsync((async) {
        final h = _Harness();
        final story = _singleSentenceStory();
        unawaited(h.controller().run(
              story: story,
              profileId: _profileId,
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));

        expect(h.narrationPlays.map((e) => e.ref),
            ['audio/narration/${story.id}.wav']);
        expect(h.stage.triggeredInputs, [StoryStageInput.celebrate]);
        async.flushMicrotasks();
        expect(h.celebrationPlays, isEmpty);

        h.audio.completePlayback(h.narrationPlays.single.handle);
        async.flushMicrotasks();
        expect(h.celebrationPlays.map((e) => e.ref), [_stingRef, _lineRef]);
        expect(h.stage.triggeredInputs,
            [StoryStageInput.celebrate, StoryStageInput.collect]);

        async.elapse(DesignTokens.collectibleFlightDuration);
        expect(h.results, hasLength(1));
        expect(h.results.single.skipped, isFalse);
        unawaited(h.close());
      });
    });
  });

  group('NEGATIVE: a story with NO narration keeps the immediate payoff '
      '(current behavior unchanged)', () {
    test('sting + line play in the same synchronous turn as celebrate; '
        'collect fires at the natural hold duration', () {
      fakeAsync((async) {
        final h = _Harness();
        unawaited(h.controller().run(
              story: _noNarrationStory(),
              profileId: _profileId,
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));

        // Immediate payoff audio, no narration channel ever.
        expect(h.celebrationPlays.map((e) => e.ref), [_stingRef, _lineRef]);
        expect(h.narrationPlays, isEmpty);
        expect(async.elapsed, Duration.zero);

        // Collect still waits for the natural animation hold.
        async.elapse(kCelebrationDefaultAnimationDuration -
            const Duration(milliseconds: 1));
        expect(h.stage.triggeredInputs, [StoryStageInput.celebrate]);
        async.elapse(const Duration(milliseconds: 1));
        expect(h.stage.triggeredInputs,
            [StoryStageInput.celebrate, StoryStageInput.collect]);

        async.elapse(DesignTokens.collectibleFlightDuration);
        expect(h.results, hasLength(1));
        expect(h.narrationPlays, isEmpty);
        unawaited(h.close());
      });
    });
  });

  group('POSITIVE: a tap mid-read-back (after the 2 s unlock) stops the '
      'narration and jumps straight to the payoff', () {
    test('skip stops the active clip, plays sting + line, fires collect, '
        'and no further read-back clip ever starts', () {
      fakeAsync((async) {
        final h = _Harness();
        final controller = h.controller();
        unawaited(controller.run(
              story: _multiSentenceStory(),
              profileId: _profileId,
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));

        // 2.001 s in: the first clip is still playing (never completed).
        async.elapse(const Duration(milliseconds: 2001));
        expect(h.narrationPlays, hasLength(1));
        controller.skip();
        async.flushMicrotasks();

        // The active narration clip was stopped...
        final stopped = h.audio.callLog.whereType<StopLogEntry>().toList();
        expect(stopped, hasLength(1));
        expect(stopped.single.handle, h.narrationPlays.single.handle);
        // ...and the payoff ran immediately.
        expect(h.celebrationPlays.map((e) => e.ref), [_stingRef, _lineRef]);
        expect(h.stage.triggeredInputs,
            [StoryStageInput.celebrate, StoryStageInput.collect]);

        async.elapse(DesignTokens.collectibleFlightDuration);
        expect(h.results, hasLength(1));
        expect(h.results.single.skipped, isTrue);

        // The remaining read-back clips never start.
        async.elapse(const Duration(seconds: 10));
        expect(h.narrationPlays, hasLength(1));
        unawaited(h.close());
      });
    });
  });

  group('EDGE: a clip that fails to play never wedges the sequence '
      '(swallow-and-continue)', () {
    test('a missing-ref clip mid-read-back is skipped and the chain '
        'continues to the next clip, through to the payoff', () {
      fakeAsync((async) {
        final story = _multiSentenceStory();
        final refs = _narrationRefsOf(story.id);
        final h = _Harness(missingRefs: {refs[1]});
        unawaited(h.controller().run(
              story: story,
              profileId: _profileId,
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));
        async.flushMicrotasks();
        expect(h.narrationPlays.map((e) => e.ref), [refs[0]]);

        // Completing clip 1 hits the missing clip 2 (play throws), which is
        // swallowed; clip 3 starts immediately.
        h.audio.completePlayback(h.narrationPlays[0].handle);
        async.flushMicrotasks();
        expect(h.narrationPlays.map((e) => e.ref), [refs[0], refs[2]]);
        expect(h.celebrationPlays, isEmpty);

        // Completing the last clip still lands the payoff and finishes.
        h.audio.completePlayback(h.narrationPlays[1].handle);
        async.flushMicrotasks();
        expect(h.celebrationPlays.map((e) => e.ref), [_stingRef, _lineRef]);
        expect(h.stage.triggeredInputs,
            [StoryStageInput.celebrate, StoryStageInput.collect]);
        async.elapse(DesignTokens.collectibleFlightDuration);
        expect(h.results, hasLength(1));
        unawaited(h.close());
      });
    });
  });

  group('POSITIVE: the <=10 s ceiling stays authoritative over the '
      'read-back', () {
    test('a read-back that never finishes is cut at the natural hold '
        'duration: narration stopped, payoff + collect land there, and the '
        'sequence finishes at exactly the natural boundary, inside the '
        'budget', () {
      fakeAsync((async) {
        final h = _Harness();
        unawaited(h.controller().run(
              story: _multiSentenceStory(),
              profileId: _profileId,
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));

        // Just before the natural hold boundary: no payoff yet.
        async.elapse(kCelebrationDefaultAnimationDuration -
            const Duration(milliseconds: 1));
        expect(h.celebrationPlays, isEmpty);
        expect(h.stage.triggeredInputs, [StoryStageInput.celebrate]);

        // At the boundary the ceiling wins: the still-playing clip is
        // stopped and the payoff lands.
        async.elapse(const Duration(milliseconds: 1));
        expect(h.audio.callLog.whereType<StopLogEntry>(), hasLength(1));
        expect(h.celebrationPlays.map((e) => e.ref), [_stingRef, _lineRef]);
        expect(h.stage.triggeredInputs,
            [StoryStageInput.celebrate, StoryStageInput.collect]);

        async.elapse(DesignTokens.collectibleFlightDuration);
        expect(h.results, hasLength(1));
        expect(h.results.single.skipped, isFalse);
        expect(
          async.elapsed,
          kCelebrationDefaultAnimationDuration +
              DesignTokens.collectibleFlightDuration,
        );
        expect(async.elapsed, lessThanOrEqualTo(kCelebrationSequenceBudget));

        // No further read-back clip starts after the cut.
        async.elapse(const Duration(seconds: 10));
        expect(h.narrationPlays, hasLength(1));
        unawaited(h.close());
      });
    });
  });
}

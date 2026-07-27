// Test suite for lib/features/celebration/celebration_controller.dart's
// replay behavior (PRD §8 Unit 8 pinned_design: "Replay behavior
// (ratified): re-reading a completed story ends with the full animation +
// celebration audio; the collectible is granted only on first completion.";
// ticket celebration-sequence accept entry "Replay of a completed story
// plays the FULL animation + celebration audio but grants no second
// collectible (first-completion-only; test over local-storage idempotent
// grant)").
//
// Shares the pinned CelebrationController API surface documented at the top
// of celebration_controller_test.dart. lib/features/celebration/
// celebration_controller.dart does not exist yet: every import below fails
// to resolve, which is the expected red state.
//
// This suite exercises the REAL StoryProgressDao/CollectionDao (an
// in-memory Drift AppDatabase), not fakes, so "no second collectible" is
// proven over local-storage's actual idempotent-grant behavior, not a mock
// assumption -- matching how test/features/collection/collection_test.dart
// exercises CollectionDao end-to-end.
import 'dart:async';

import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/design/fake_rive_stage.dart';
import 'package:learn_to_read/design/rive_stage.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/analytics/events.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/celebration/celebration_controller.dart';

const _installId = 'a1b2c3d4-1234-4abc-8def-0123456789ab';
const _profileId = 'profile.amara';

WordToken _wordToken() => WordToken(
      text: 'cat',
      graphemePhonemeMap: const [(graphemes: 'c', phonemeId: 'K')],
      pronunciationAudioRef: 'audio/words/cat.wav',
    );

Story _story({String id = 'story.1'}) => Story(
      id: id,
      levelId: 'level.1',
      title: 'The Cat Sat',
      pages: [
        Page(sentences: [
          Sentence(words: [_wordToken()], narrationAudioRef: 'audio/narration/$id.wav'),
        ]),
      ],
      riveAnimationRef: 'rive/$id.riv',
      celebrationAudioRef: 'audio/celebration/sting/$id.wav',
      collectibleRef: 'collectible.cat',
      skillsExercised: const [],
      packId: 'pack.starter',
      contentVersion: '1',
    );

CelebrationLineRotator _rotator() => CelebrationLineRotator(
      lines: const ['audio/celebration/lines/great_job.wav'],
      nextInt: (max) => 0,
    );

class _Harness {
  _Harness()
      : db = AppDatabase(NativeDatabase.memory()),
        audio = FakeAudioService(clock: () => Duration.zero),
        stage = FakeStoryStage();

  final AppDatabase db;
  final FakeAudioService audio;
  final FakeStoryStage stage;
  final List<AnalyticsEvent> events = [];
  final List<CelebrationResult> results = [];

  Future<void> close() => db.close();

  CelebrationController controller() => CelebrationController(
        stage: stage,
        audioService: audio,
        collectionDao: db.collectionDao,
        storyProgressDao: db.storyProgressDao,
        lineRotator: _rotator(),
        installId: _installId,
        onAnalyticsEvent: events.add,
        onFinished: results.add,
      );

  /// Seeds the DB as if [story] was already completed once, `daysAgo` days
  /// before "now", with the collectible already granted -- the state a
  /// re-read starts from.
  Future<void> seedAlreadyCompleted(Story story, {int timesRead = 1}) async {
    final completedAt = DateTime(2026, 1, 1);
    await db.storyProgressDao.upsertProgress(StoryProgress(
      profileId: _profileId,
      storyId: story.id,
      status: StoryStatus.completed,
      completedAt: completedAt,
      timesRead: timesRead,
    ));
    await db.collectionDao.grantCollectible(
      profileId: _profileId,
      collectibleId: story.collectibleRef,
    );
  }
}

void main() {
  group('POSITIVE: replay plays the full sequence (celebrate + audio + '
      'collect + navigation), just like a first completion', () {
    test('celebrate and collect both still fire, audio still plays, and '
        'onFinished still fires', () {
      fakeAsync((async) {
        final h = _Harness();
        final story = _story();
        unawaited(h.seedAlreadyCompleted(story));
        async.flushMicrotasks();

        unawaited(h.controller().run(
              story: story,
              profileId: _profileId,
              profileOrdinal: 1,
              levelOrdinal: 1,
              nextStoryId: 'story.next',
            ));
        async.elapse(const Duration(seconds: 10));

        expect(h.stage.triggeredInputs,
            [StoryStageInput.celebrate, StoryStageInput.collect]);
        expect(h.audio.callLog.whereType<PlayLogEntry>(), hasLength(3),
            reason: 'narration + sting + line, exactly as a first completion');
        expect(h.results, hasLength(1));
        expect(h.results.single.nextStoryId, 'story.next');

        unawaited(h.close());
      });
    });
  });

  group('NEGATIVE: replay grants no second collectible', () {
    test('CollectionState still has exactly one entry for the collectible '
        'after replay -- idempotent over the real CollectionDao', () {
      fakeAsync((async) {
        final h = _Harness();
        final story = _story();
        unawaited(h.seedAlreadyCompleted(story));
        async.flushMicrotasks();

        unawaited(h.controller().run(
              story: story,
              profileId: _profileId,
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));
        async.elapse(const Duration(seconds: 10));

        CollectionState? state;
        h.db.collectionDao.getCollectionState(_profileId).then((s) => state = s);
        async.flushMicrotasks();
        expect(state!.earnedCollectibles, ['collectible.cat']);

        unawaited(h.close());
      });
    });

    test('collectible_earned analytics is NOT emitted on replay', () {
      fakeAsync((async) {
        final h = _Harness();
        final story = _story();
        unawaited(h.seedAlreadyCompleted(story));
        async.flushMicrotasks();

        unawaited(h.controller().run(
              story: story,
              profileId: _profileId,
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));
        async.elapse(const Duration(seconds: 10));

        expect(
          h.events.map((e) => e.name),
          isNot(contains(AnalyticsEventName.collectibleEarned)),
        );

        unawaited(h.close());
      });
    });

    test('CelebrationResult.isFirstCompletion is false on replay', () {
      fakeAsync((async) {
        final h = _Harness();
        final story = _story();
        unawaited(h.seedAlreadyCompleted(story));
        async.flushMicrotasks();

        unawaited(h.controller().run(
              story: story,
              profileId: _profileId,
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));
        async.elapse(const Duration(seconds: 10));

        expect(h.results.single.isFirstCompletion, isFalse);

        unawaited(h.close());
      });
    });
  });

  group('POSITIVE: replay still emits story_completed and still records '
      'the read', () {
    test('story_completed fires on replay just as it does on first '
        'completion', () {
      fakeAsync((async) {
        final h = _Harness();
        final story = _story();
        unawaited(h.seedAlreadyCompleted(story));
        async.flushMicrotasks();

        unawaited(h.controller().run(
              story: story,
              profileId: _profileId,
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));
        async.elapse(const Duration(seconds: 10));

        expect(h.events.map((e) => e.name), contains(AnalyticsEventName.storyCompleted));

        unawaited(h.close());
      });
    });

    test('EDGE: timesRead increments and the ORIGINAL completedAt is '
        'preserved (not overwritten) across the replay', () {
      fakeAsync((async) {
        final h = _Harness();
        final story = _story();
        unawaited(h.seedAlreadyCompleted(story, timesRead: 1));
        async.flushMicrotasks();

        unawaited(h.controller().run(
              story: story,
              profileId: _profileId,
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));
        async.elapse(const Duration(seconds: 10));

        StoryProgress? progress;
        h.db.storyProgressDao
            .getProgress(profileId: _profileId, storyId: story.id)
            .then((p) => progress = p);
        async.flushMicrotasks();

        expect(progress!.timesRead, 2);
        expect(progress!.completedAt, DateTime(2026, 1, 1));

        unawaited(h.close());
      });
    });
  });

  group('EDGE: a THIRD read still grants no collectible and still plays '
      'the full sequence', () {
    test('repeated replays remain idempotent on the collection and keep '
        'firing the full celebration', () {
      fakeAsync((async) {
        final h = _Harness();
        final story = _story();
        unawaited(h.seedAlreadyCompleted(story, timesRead: 2));
        async.flushMicrotasks();

        final controller = h.controller();
        unawaited(controller.run(
              story: story,
              profileId: _profileId,
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));
        async.elapse(const Duration(seconds: 10));

        expect(h.results.single.isFirstCompletion, isFalse);
        expect(h.stage.triggeredInputs, [StoryStageInput.celebrate, StoryStageInput.collect]);

        CollectionState? state;
        h.db.collectionDao.getCollectionState(_profileId).then((s) => state = s);
        async.flushMicrotasks();
        expect(state!.earnedCollectibles, ['collectible.cat']);

        unawaited(h.close());
      });
    });
  });
}

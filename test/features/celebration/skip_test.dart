// Test suite for lib/features/celebration/celebration_controller.dart's
// skip behavior and total-sequence budget (PRD §8 Unit 8 pinned_design:
// "total post-completion sequence <= 10 s and skippable by tap after the
// first 2 s"; ticket celebration-sequence accept entries "Skippable by tap
// after the first 2 s; skip before 2 s does nothing; skipping still
// persists the collectible" and "total post-completion sequence <= 10 s
// (fake-clock assertion on the sequence budget)").
//
// Shares the pinned CelebrationController API surface documented at the top
// of celebration_controller_test.dart. lib/features/celebration/
// celebration_controller.dart does not exist yet: every import below fails
// to resolve, which is the expected red state.
//
// All timing is driven by `package:fake_async` -- no real wall-clock sleeps
// anywhere in this suite.
import 'dart:async';

import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/design/fake_rive_stage.dart';
import 'package:learn_to_read/design/rive_stage.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
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
  final List<CelebrationResult> results = [];

  Future<void> close() => db.close();

  CelebrationController controller({
    Duration celebrationDuration = kCelebrationDefaultAnimationDuration,
    Duration skipUnlockDelay = kCelebrationSkipUnlockDelay,
    Duration sequenceBudget = kCelebrationSequenceBudget,
  }) =>
      CelebrationController(
        stage: stage,
        audioService: audio,
        collectionDao: db.collectionDao,
        storyProgressDao: db.storyProgressDao,
        lineRotator: _rotator(),
        installId: _installId,
        onAnalyticsEvent: (_) {},
        onFinished: results.add,
        celebrationDuration: celebrationDuration,
        skipUnlockDelay: skipUnlockDelay,
        sequenceBudget: sequenceBudget,
      );
}

void main() {
  group('NEGATIVE: skip before the 2 s unlock does nothing', () {
    test('a tap at 1.9 s is silently ignored -- the animation runs to its '
        'full natural duration', () {
      fakeAsync((async) {
        final h = _Harness();
        final controller = h.controller(celebrationDuration: const Duration(seconds: 4));
        unawaited(controller.run(
              story: _story(),
              profileId: _profileId,
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));

        async.elapse(const Duration(milliseconds: 1900));
        controller.skip();
        async.flushMicrotasks();

        // Ignored: collect has not fired, nothing finished early.
        expect(h.stage.triggeredInputs, [StoryStageInput.celebrate]);
        expect(h.results, isEmpty);

        // The sequence has NOT finished 1ms before its natural (un-shortened)
        // completion time (1900ms already elapsed + up to 2699 more = 4599ms
        // of the 4600ms natural total: 4s celebration + 600ms flight).
        async.elapse(const Duration(milliseconds: 2699));
        expect(h.results, isEmpty);

        // ...but has finished 2ms later, exactly at the natural boundary.
        async.elapse(const Duration(milliseconds: 2));
        expect(h.results, hasLength(1));
        expect(h.results.single.skipped, isFalse);

        unawaited(h.close());
      });
    });

    test('a tap at exactly 0 s (the instant run() starts) does nothing', () {
      fakeAsync((async) {
        final h = _Harness();
        final controller = h.controller();
        unawaited(controller.run(
              story: _story(),
              profileId: _profileId,
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));
        controller.skip();
        async.flushMicrotasks();

        expect(h.results, isEmpty);
        expect(h.stage.triggeredInputs, [StoryStageInput.celebrate]);

        async.elapse(const Duration(seconds: 10));
        expect(h.results.single.skipped, isFalse);

        unawaited(h.close());
      });
    });
  });

  group('POSITIVE: skip on/after the 2 s unlock ends the sequence early', () {
    test('a tap just after 2 s cuts the celebration short: collect fires '
        'immediately and the total sequence finishes well before the '
        'natural (un-skipped) duration', () {
      fakeAsync((async) {
        final h = _Harness();
        final controller = h.controller(celebrationDuration: const Duration(seconds: 4));
        unawaited(controller.run(
              story: _story(),
              profileId: _profileId,
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));

        async.elapse(const Duration(milliseconds: 2001));
        controller.skip();
        async.flushMicrotasks();

        expect(h.stage.triggeredInputs, [StoryStageInput.celebrate, StoryStageInput.collect],
            reason: 'skip should immediately end the animation-hold phase '
                'and fire the collect beat');

        async.elapse(DesignTokens.collectibleFlightDuration);
        expect(h.results, hasLength(1));
        expect(h.results.single.skipped, isTrue);
        expect(
          async.elapsed,
          lessThan(const Duration(seconds: 4) + DesignTokens.collectibleFlightDuration),
          reason: 'skipping must finish strictly earlier than the natural, '
              'un-skipped total duration',
        );

        unawaited(h.close());
      });
    });

    test('EDGE: skip called a second time after already accepted is a '
        'harmless no-op (no double-finish, no error)', () {
      fakeAsync((async) {
        final h = _Harness();
        final controller = h.controller();
        unawaited(controller.run(
              story: _story(),
              profileId: _profileId,
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));

        async.elapse(const Duration(seconds: 3));
        controller.skip();
        controller.skip();
        controller.skip();
        async.elapse(const Duration(seconds: 10));

        expect(h.results, hasLength(1));

        unawaited(h.close());
      });
    });

    test('EDGE: skip called after the sequence has already finished '
        'naturally does nothing (no error, no second result)', () {
      fakeAsync((async) {
        final h = _Harness();
        final controller = h.controller(celebrationDuration: const Duration(seconds: 1));
        unawaited(controller.run(
              story: _story(),
              profileId: _profileId,
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));
        async.elapse(const Duration(seconds: 10));
        expect(h.results, hasLength(1));

        controller.skip();
        async.elapse(const Duration(seconds: 10));
        expect(h.results, hasLength(1));

        unawaited(h.close());
      });
    });
  });

  group('POSITIVE: skip still persists the collectible', () {
    test('the collectible is already durably persisted before the 2 s '
        'skip-eligibility window even opens, so skipping can never lose it', () {
      fakeAsync((async) {
        final h = _Harness();
        final controller = h.controller();
        unawaited(controller.run(
              story: _story(),
              profileId: _profileId,
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));
        // Flush only microtasks -- no fake time elapses, well before the 2s
        // skip-unlock window -- and the grant is already committed.
        async.flushMicrotasks();

        CollectionState? state;
        h.db.collectionDao.getCollectionState(_profileId).then((s) => state = s);
        async.flushMicrotasks();
        expect(state!.earnedCollectibles, ['collectible.cat']);

        unawaited(h.close());
      });
    });

    test('the grant survives a real skip through to completion', () {
      fakeAsync((async) {
        final h = _Harness();
        final controller = h.controller();
        unawaited(controller.run(
              story: _story(),
              profileId: _profileId,
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));
        async.elapse(const Duration(seconds: 2, milliseconds: 1));
        controller.skip();
        async.elapse(const Duration(seconds: 10));

        expect(h.results.single.skipped, isTrue);

        CollectionState? state;
        h.db.collectionDao.getCollectionState(_profileId).then((s) => state = s);
        async.flushMicrotasks();
        expect(state!.earnedCollectibles, ['collectible.cat']);

        unawaited(h.close());
      });
    });
  });

  group('POSITIVE: total sequence budget (<=10 s, PRD §8 Unit 8)', () {
    test('the default (un-skipped) sequence finishes well before the 10 s '
        'budget', () {
      fakeAsync((async) {
        final h = _Harness();
        unawaited(h.controller().run(
              story: _story(),
              profileId: _profileId,
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));
        // The default celebrationDuration + the flight token is the whole
        // natural duration; confirm it lands there, comfortably inside the
        // 10s budget.
        async.elapse(kCelebrationDefaultAnimationDuration + DesignTokens.collectibleFlightDuration);

        expect(h.results, hasLength(1));
        expect(
          kCelebrationDefaultAnimationDuration + DesignTokens.collectibleFlightDuration,
          lessThanOrEqualTo(kCelebrationSequenceBudget),
        );

        unawaited(h.close());
      });
    });

    test('EDGE: a celebrationDuration configured at the exact budget '
        'boundary (sequenceBudget - collectibleFlightDuration) finishes '
        'exactly at the boundary, never after', () {
      fakeAsync((async) {
        final h = _Harness();
        final maxDuration = kCelebrationSequenceBudget - DesignTokens.collectibleFlightDuration;
        unawaited(h.controller(celebrationDuration: maxDuration).run(
              story: _story(),
              profileId: _profileId,
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));

        // 1ms before the budget boundary: not finished yet.
        async.elapse(kCelebrationSequenceBudget - const Duration(milliseconds: 1));
        expect(h.results, isEmpty);

        // 1ms later, exactly at the boundary: finished.
        async.elapse(const Duration(milliseconds: 1));
        expect(h.results, hasLength(1));
        expect(h.results.single.skipped, isFalse);
        expect(async.elapsed, kCelebrationSequenceBudget);

        unawaited(h.close());
      });
    });

    test('a skip well inside the window keeps the sequence comfortably '
        'under budget', () {
      fakeAsync((async) {
        final h = _Harness();
        final controller = h.controller(celebrationDuration: const Duration(seconds: 4));
        unawaited(controller.run(
              story: _story(),
              profileId: _profileId,
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));
        async.elapse(const Duration(seconds: 3));
        controller.skip();
        async.elapse(DesignTokens.collectibleFlightDuration);

        expect(h.results, hasLength(1));
        expect(async.elapsed, lessThanOrEqualTo(kCelebrationSequenceBudget));

        unawaited(h.close());
      });
    });
  });
}

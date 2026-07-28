// Test suite for lib/features/celebration/celebration_controller.dart (PRD
// §8 Unit 8 "Celebration: story animation & audio"; ticket
// celebration-sequence accept entries 1, 7, 8, 9).
//
// lib/features/celebration/celebration_controller.dart does not exist yet:
// every import below fails to resolve, which is the expected red state.
//
// Pinned API surface this suite (and its sibling files replay_test.dart,
// skip_test.dart, narrated_readback_test.dart) requires:
//
//   const Duration kCelebrationSkipUnlockDelay = Duration(seconds: 2);
//   const Duration kCelebrationSequenceBudget = Duration(seconds: 10);
//   const Duration kCelebrationDefaultAnimationDuration = Duration(seconds: 4);
//
//   class CelebrationLineRotator {
//     CelebrationLineRotator({
//       required List<AudioRef> lines,
//       required int Function(int exclusiveMax) nextInt,
//     });
//     AudioRef next();
//   }
//
//   class CelebrationResult {
//     final String completedStoryId;
//     final String? nextStoryId;
//     final bool skipped;
//     final bool isFirstCompletion;
//   }
//
//   class CelebrationController {
//     CelebrationController({
//       required StoryStage stage,
//       required AudioService audioService,
//       required CollectionDao collectionDao,
//       required StoryProgressDao storyProgressDao,
//       required CelebrationLineRotator lineRotator,
//       required String installId,
//       required void Function(AnalyticsEvent event) onAnalyticsEvent,
//       required void Function(CelebrationResult result) onFinished,
//       Duration celebrationDuration = kCelebrationDefaultAnimationDuration,
//       Duration skipUnlockDelay = kCelebrationSkipUnlockDelay,
//       Duration sequenceBudget = kCelebrationSequenceBudget,
//     });
//     bool get isRunning;
//     Future<void> run({
//       required Story story,
//       required String profileId,
//       required int profileOrdinal,
//       required int levelOrdinal,
//       String? nextStoryId,
//     });
//     void skip();
//   }
//
// Contract this suite locks in (builder-mechanical design choices the
// ticket leaves to the builder; behavior is pinned by the PRD, exact shapes
// are pinned by this suite so every sibling file agrees):
//  - run()'s synchronous prefix (the same event-loop turn as the call,
//    before any `await` inside run() suspends it) is, in order:
//      1. stage.trigger(StoryStageInput.celebrate)
//      2. IF the story has narration (narrated_readback_test.dart):
//         audioService.play(narrationRef, channel: AudioChannel.narration)
//      3. audioService.play(story.celebrationAudioRef, channel:
//         AudioChannel.celebration)  -- the happy sting
//      4. audioService.play(lineRotator.next(), channel:
//         AudioChannel.celebration)  -- the rotated recorded voice line
//    This fixed order is asserted via FakeAudioService.callLog and is a
//    proxy for accept #9 ("controller performs no synchronous work over one
//    frame budget during sequence transitions"): everything above executes
//    before the controller's first `await`, so a caller observes it
//    synchronously, in the same frame, with zero fake-clock time elapsed.
//  - Story-progress recording, collectible persistence (first completion
//    only) and analytics emission (story_completed always;
//    collectible_earned iff first completion) run next, fully awaited
//    *before* the animation-hold phase (and therefore before `skip()` can
//    even be actionable, since skipUnlockDelay >= 2s) -- see
//    skip_test.dart for "skip still persists the collectible".
//  - After the animation-hold phase ends (celebrationDuration elapsed
//    naturally, or an accepted skip() ending it early),
//    stage.trigger(StoryStageInput.collect) fires, then
//    DesignTokens.collectibleFlightDuration elapses, then
//    onFinished(CelebrationResult(...)) fires exactly once.
//  - The constructor throws ArgumentError if `celebrationDuration +
//    DesignTokens.collectibleFlightDuration` exceeds `sequenceBudget` -- the
//    <=10s total-sequence budget (PRD §8 Unit 8) is enforced structurally.
//  - CelebrationController depends on nothing but the StoryStage interface
//    (accept #8: "controller API takes only the StoryStage contract") --
//    any StoryStage implementation works, not just FakeStoryStage.
import 'dart:async';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/design/fake_rive_stage.dart';
import 'package:learn_to_read/design/rive_stage.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/analytics/events.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/celebration/celebration_controller.dart';

const _installId = 'a1b2c3d4-1234-4abc-8def-0123456789ab';

// ---------------------------------------------------------------------------
// Fixtures.
// ---------------------------------------------------------------------------

WordToken _wordToken({String text = 'cat'}) => WordToken(
      text: text,
      graphemePhonemeMap: const [(graphemes: 'c', phonemeId: 'K')],
      pronunciationAudioRef: 'audio/words/$text.wav',
    );

/// A sentence-format story (narration present -- see narrated_readback_test
/// for the narration-absent case).
Story _sentenceStory({
  String id = 'story.1',
  String celebrationAudioRef = 'audio/celebration/sting/story1.wav',
  String collectibleRef = 'collectible.1',
}) =>
    Story(
      id: id,
      levelId: 'level.1',
      title: 'The Cat Sat',
      pages: [
        Page(sentences: [
          Sentence(
            words: [_wordToken()],
            narrationAudioRef: 'audio/narration/$id.wav',
          ),
        ]),
      ],
      riveAnimationRef: 'rive/$id.riv',
      celebrationAudioRef: celebrationAudioRef,
      collectibleRef: collectibleRef,
      skillsExercised: const [],
      packId: 'pack.starter',
      contentVersion: '1',
    );

/// The fixed recorded celebration-line set used across this suite. Distinct
/// from any story's `celebrationAudioRef` (the sting) so tests can tell the
/// two apart by ref alone.
const _lineRefs = [
  'audio/celebration/lines/great_job.wav',
  'audio/celebration/lines/you_did_it.wav',
  'audio/celebration/lines/woohoo.wav',
];

int Function(int) _fixedNextInt(int value) => (_) => value;

/// A minimal, from-scratch StoryStage implementation -- deliberately NOT
/// FakeStoryStage -- used by the "depends only on the StoryStage contract"
/// test (accept #8) to prove the controller never assumes anything beyond
/// the interface.
class _BareStoryStage implements StoryStage {
  final List<StoryStageInput> log = [];
  StoryStageInput _active = StoryStageInput.idle;

  @override
  StoryStageInput get activeState => _active;

  @override
  void trigger(StoryStageInput input) {
    log.add(input);
    _active = input;
  }
}

/// A test harness bundling an in-memory DB, fake audio, a fake stage and
/// recorded analytics/result callbacks, with a factory for constructing a
/// CelebrationController wired to them.
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

  CelebrationController controller({
    CelebrationLineRotator? lineRotator,
    Duration celebrationDuration = kCelebrationDefaultAnimationDuration,
    Duration skipUnlockDelay = kCelebrationSkipUnlockDelay,
    Duration sequenceBudget = kCelebrationSequenceBudget,
    StoryStage? stageOverride,
  }) =>
      CelebrationController(
        stage: stageOverride ?? stage,
        audioService: audio,
        collectionDao: db.collectionDao,
        storyProgressDao: db.storyProgressDao,
        lineRotator: lineRotator ??
            CelebrationLineRotator(lines: _lineRefs, nextInt: _fixedNextInt(0)),
        installId: _installId,
        onAnalyticsEvent: events.add,
        onFinished: results.add,
        celebrationDuration: celebrationDuration,
        skipUnlockDelay: skipUnlockDelay,
        sequenceBudget: sequenceBudget,
      );
}

void main() {
  group('POSITIVE: celebrate input fires exactly once on the given stage', () {
    test('celebrate is triggered exactly once per run(), synchronously', () {
      fakeAsync((async) {
        final h = _Harness();
        unawaited(h.controller().run(
              story: _sentenceStory(),
              profileId: 'profile.1',
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));

        // Fires in the same synchronous turn, before any fake time elapses.
        expect(
          h.stage.triggeredInputs.where((i) => i == StoryStageInput.celebrate),
          hasLength(1),
        );
        expect(async.elapsed, Duration.zero);

        async.elapse(const Duration(seconds: 10));
        expect(
          h.stage.triggeredInputs.where((i) => i == StoryStageInput.celebrate),
          hasLength(1),
          reason: 'celebrate must not re-fire later in the sequence',
        );
        unawaited(h.close());
      });
    });
  });

  group('POSITIVE: audio ordering -- sting then rotated line', () {
    test(
      'sting (story.celebrationAudioRef, channel celebration) plays before '
      'the rotated line, which is also tagged celebration',
      () {
        fakeAsync((async) {
          final h = _Harness();
          final story = _sentenceStory(
            celebrationAudioRef: 'audio/celebration/sting/storyX.wav',
          );
          unawaited(h.controller().run(
                story: story,
                profileId: 'profile.1',
                profileOrdinal: 1,
                levelOrdinal: 1,
              ));
          async.elapse(const Duration(seconds: 10));

          final celebrationPlays = h.audio.callLog
              .whereType<PlayLogEntry>()
              .where((e) => e.channel == AudioChannel.celebration)
              .toList();
          expect(celebrationPlays, hasLength(2));
          expect(celebrationPlays[0].ref, 'audio/celebration/sting/storyX.wav');
          expect(celebrationPlays[1].ref, isIn(_lineRefs));
          unawaited(h.close());
        });
      },
    );

    test('the rotated line is chosen via CelebrationLineRotator.next(), not '
        'hardcoded', () {
      fakeAsync((async) {
        final h = _Harness();
        // nextInt always returns max-1 => Fisher-Yates no-ops => identity
        // order: the rotator dispenses _lineRefs[0] first.
        final rotator =
            CelebrationLineRotator(lines: _lineRefs, nextInt: (max) => max - 1);
        unawaited(h.controller(lineRotator: rotator).run(
              story: _sentenceStory(),
              profileId: 'profile.1',
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));
        async.elapse(const Duration(seconds: 10));

        final linePlay = h.audio.callLog
            .whereType<PlayLogEntry>()
            .where((e) => e.channel == AudioChannel.celebration)
            .last;
        expect(linePlay.ref, _lineRefs[0]);
        unawaited(h.close());
      });
    });
  });

  group(
    'POSITIVE: rotation across consecutive celebrations (accept 1 -- '
    '"consecutive celebrations pick different lines until the set cycles")',
    () {
      test(
        'a shared CelebrationLineRotator dispensed across 6 consecutive '
        'story completions (2 full cycles of the 3-line set) never repeats '
        'consecutively, and cycle 2 exactly replays cycle 1\'s order',
        () {
          fakeAsync((async) {
            final h = _Harness();
            final rotator = CelebrationLineRotator(
              lines: _lineRefs,
              nextInt: Random(7).nextInt,
            );

            final dispensed = <String>[];
            for (var i = 0; i < 6; i++) {
              final story = _sentenceStory(
                id: 'story.$i',
                celebrationAudioRef: 'audio/celebration/sting/story$i.wav',
                collectibleRef: 'collectible.$i',
              );
              unawaited(h.controller(lineRotator: rotator).run(
                    story: story,
                    profileId: 'profile.1',
                    profileOrdinal: 1,
                    levelOrdinal: 1,
                  ));
              async.elapse(const Duration(seconds: 10));

              final linePlay = h.audio.callLog
                  .whereType<PlayLogEntry>()
                  .where((e) => e.channel == AudioChannel.celebration)
                  .last;
              dispensed.add(linePlay.ref);
            }

            // Every consecutive pair differs.
            for (var i = 1; i < dispensed.length; i++) {
              expect(dispensed[i], isNot(equals(dispensed[i - 1])),
                  reason: 'celebrations $i and ${i - 1} repeated the same line');
            }
            // The first cycle (0-2) is a permutation of the full set.
            expect(dispensed.sublist(0, 3).toSet(), _lineRefs.toSet());
            // The rotation is a fixed cyclic order: cycle 2 replays cycle 1.
            expect(dispensed.sublist(3, 6), dispensed.sublist(0, 3));

            unawaited(h.close());
          });
        },
      );
    },
  );

  group('CelebrationLineRotator (unit-level rotation contract)', () {
    test('POSITIVE: dispenses a permutation of the fixed set before any '
        'repeat, then repeats the SAME permutation on the next cycle', () {
      final rotator = CelebrationLineRotator(lines: _lineRefs, nextInt: _fixedNextInt(0));
      final firstCycle = List.generate(3, (_) => rotator.next());
      final secondCycle = List.generate(3, (_) => rotator.next());
      expect(firstCycle.toSet(), _lineRefs.toSet());
      expect(secondCycle, firstCycle);
    });

    test('POSITIVE: two different injected RNGs produce different rotation '
        'orders -- the RNG is actually consulted, not ignored', () {
      final identityOrder =
          List.generate(3, (_) => CelebrationLineRotator(lines: _lineRefs, nextInt: (max) => max - 1).next());
      final reshuffled =
          List.generate(3, (_) => CelebrationLineRotator(lines: _lineRefs, nextInt: _fixedNextInt(0)).next());
      expect(identityOrder, isNot(equals(reshuffled)));
    });

    test('EDGE: a single-line set always returns that line and never '
        'consults the RNG', () {
      var calls = 0;
      final rotator = CelebrationLineRotator(
        lines: const ['audio/celebration/lines/only.wav'],
        nextInt: (max) {
          calls++;
          return 0;
        },
      );
      expect(rotator.next(), 'audio/celebration/lines/only.wav');
      expect(rotator.next(), 'audio/celebration/lines/only.wav');
      expect(calls, 0);
    });

    test('NEGATIVE: an empty line set throws ArgumentError at construction', () {
      expect(
        () => CelebrationLineRotator(lines: const [], nextInt: (max) => 0),
        throwsArgumentError,
      );
    });
  });

  group('POSITIVE: first-completion persistence + analytics', () {
    test('grants the collectible, records completion, and emits both '
        'collectible_earned and story_completed', () {
      fakeAsync((async) {
        final h = _Harness();
        final story = _sentenceStory(collectibleRef: 'collectible.cat');
        unawaited(h.controller().run(
              story: story,
              profileId: 'profile.1',
              profileOrdinal: 2,
              levelOrdinal: 3,
              nextStoryId: 'story.2',
            ));
        async.elapse(const Duration(seconds: 10));

        expect(h.results, hasLength(1));
        expect(h.results.single.isFirstCompletion, isTrue);

        expect(
          h.events.map((e) => e.name),
          containsAll(<AnalyticsEventName>[
            AnalyticsEventName.collectibleEarned,
            AnalyticsEventName.storyCompleted,
          ]),
        );
        for (final event in h.events) {
          expect(() => validateEventPayload(event.toPayload()), returnsNormally);
          expect(event.profileOrdinal, 2);
          expect(event.levelOrdinal, 3);
          expect(event.storyId, story.id);
        }

        unawaited(h.close());
      });
    });

    test('collectible is persisted to CollectionState via CollectionDao', () {
      fakeAsync((async) {
        final h = _Harness();
        final story = _sentenceStory(collectibleRef: 'collectible.cat');
        String? completedState;
        unawaited(h.controller().run(
              story: story,
              profileId: 'profile.amara',
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));
        async.elapse(const Duration(seconds: 10));

        h.db.collectionDao.getCollectionState('profile.amara').then((s) {
          completedState = s.earnedCollectibles.join(',');
        });
        async.flushMicrotasks();
        expect(completedState, 'collectible.cat');

        unawaited(h.close());
      });
    });

    test('story progress is recorded as completed (StoryProgressDao)', () {
      fakeAsync((async) {
        final h = _Harness();
        final story = _sentenceStory(id: 'story.42');
        unawaited(h.controller().run(
              story: story,
              profileId: 'profile.amara',
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));
        async.elapse(const Duration(seconds: 10));

        StoryStatus? status;
        h.db.storyProgressDao
            .getProgress(profileId: 'profile.amara', storyId: 'story.42')
            .then((p) => status = p?.status);
        async.flushMicrotasks();
        expect(status, StoryStatus.completed);

        unawaited(h.close());
      });
    });
  });

  group('NEGATIVE: budget enforcement', () {
    test('constructor throws ArgumentError when celebrationDuration + '
        'DesignTokens.collectibleFlightDuration exceeds sequenceBudget', () {
      final h = _Harness();
      expect(
        () => h.controller(
          celebrationDuration: const Duration(seconds: 10),
          sequenceBudget: const Duration(seconds: 10),
        ),
        throwsArgumentError,
      );
      unawaited(h.close());
    });

    test('a celebrationDuration that fits exactly at the budget boundary '
        'does not throw', () {
      final h = _Harness();
      expect(
        () => h.controller(
          celebrationDuration:
              const Duration(seconds: 10) - DesignTokens.collectibleFlightDuration,
          sequenceBudget: const Duration(seconds: 10),
        ),
        returnsNormally,
      );
      unawaited(h.close());
    });
  });

  group(
    'EDGE / [DEVICE]-proxy: no synchronous work over one frame budget '
    '(accept 9 headless proxy; the real 60fps measurement is owner/device)',
    () {
      test(
        'celebrate + all audio play() calls are dispatched in the same '
        'synchronous turn as run(), with zero fake-clock time elapsed',
        () {
          fakeAsync((async) {
            final h = _Harness();
            final story = _sentenceStory();
            unawaited(h.controller().run(
                  story: story,
                  profileId: 'profile.1',
                  profileOrdinal: 1,
                  levelOrdinal: 1,
                ));

            // Narration + sting + line = 3 play() calls, all synchronous.
            expect(h.audio.callLog.whereType<PlayLogEntry>(), hasLength(3));
            expect(h.stage.triggeredInputs, [StoryStageInput.celebrate]);
            expect(async.elapsed, Duration.zero);

            async.elapse(const Duration(seconds: 10));
            unawaited(h.close());
          });
        },
      );
    },
  );

  group(
    'POSITIVE: the controller depends only on the StoryStage contract '
    '(accept 8: "controller API takes only the StoryStage contract")',
    () {
      test('a from-scratch StoryStage implementation (not FakeStoryStage) '
          'works identically -- no hidden dependency on a concrete stage '
          'type or on story identity', () {
        fakeAsync((async) {
          final h = _Harness();
          final bareStage = _BareStoryStage();
          unawaited(h.controller(stageOverride: bareStage).run(
                story: _sentenceStory(id: 'story.unusual-id-🎈'),
                profileId: 'profile.1',
                profileOrdinal: 1,
                levelOrdinal: 1,
              ));
          async.elapse(const Duration(seconds: 10));

          expect(bareStage.log, [StoryStageInput.celebrate, StoryStageInput.collect]);
          unawaited(h.close());
        });
      });
    },
  );
}

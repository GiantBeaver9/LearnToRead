// Test suite for lib/features/celebration/celebration_controller.dart's
// narrated read-back and the fixture-story integration flow (PRD §8 Unit 8
// pinned_design: "Narrated read-back (ratified): where the story has
// narration audio (all sentence-format levels), the fluent narration
// replays over the start of the animation ... Skipped at levels without
// narration."; ticket celebration-sequence accept entries:
//   - "Narrated read-back: where the story has narration audio ... the
//     fluent narration replays over the START of the animation; absent at
//     levels without narration (both cases tested via FakeAudioService --
//     transcribed acceptance)."
//   - "Fixture-story integration test: completion triggers celebrate input,
//     read-back per narration presence, celebration audio plays,
//     collectible persisted to CollectionState, then navigation returns to
//     the map with the next story highlighted (navigation via injected
//     callback; transcribed acceptance)."
//
// Shares the pinned CelebrationController API surface documented at the top
// of celebration_controller_test.dart. lib/features/celebration/
// celebration_controller.dart does not exist yet: every import below fails
// to resolve, which is the expected red state.
//
// Narration-presence contract this suite pins (builder-mechanical, since
// the ticket leaves the exact shape to the builder): a story "has
// narration" iff its FIRST page's FIRST sentence carries a non-null
// `narrationAudioRef` -- matching the domain model's own pinned shape for
// sentence-format stories ("Sentence-format stories have exactly one page
// with one sentence", content_models.dart doc comment). The controller
// never inspects `Level.format`/`Level.narrationEnabled` directly (it is
// never given a `Level`) -- narration presence is read straight off the
// `Story` it is asked to celebrate.
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

/// A sentence-format story: exactly one page, one sentence, narration
/// present (the PRD's "all sentence-format levels" case).
Story _sentenceFormatStory({String id = 'story.sentence.1'}) => Story(
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
      celebrationAudioRef: 'audio/celebration/sting/$id.wav',
      collectibleRef: 'collectible.$id',
      skillsExercised: const [],
      packId: 'pack.starter',
      contentVersion: '1',
    );

/// A paragraph-format story: multiple pages/sentences, no narration audio
/// (the PRD's "levels without narration" default).
Story _paragraphFormatStory({String id = 'story.paragraph.1'}) => Story(
      id: id,
      levelId: 'level.9',
      title: 'A Long Adventure',
      pages: [
        Page(sentences: [
          Sentence(words: [_wordToken()]),
          Sentence(words: [_wordToken()]),
        ]),
        Page(sentences: [
          Sentence(words: [_wordToken()]),
        ]),
      ],
      riveAnimationRef: 'rive/$id.riv',
      celebrationAudioRef: 'audio/celebration/sting/$id.wav',
      collectibleRef: 'collectible.$id',
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
}

void main() {
  group('POSITIVE: narration plays for a sentence-format story', () {
    test("the sentence's narrationAudioRef plays on AudioChannel.narration, "
        'before the sting and the rotated line', () {
      fakeAsync((async) {
        final h = _Harness();
        final story = _sentenceFormatStory();
        unawaited(h.controller().run(
              story: story,
              profileId: _profileId,
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));
        async.elapse(const Duration(seconds: 10));

        final plays = h.audio.callLog.whereType<PlayLogEntry>().toList();
        expect(plays, hasLength(3));
        expect(plays[0].ref, 'audio/narration/story.sentence.1.wav');
        expect(plays[0].channel, AudioChannel.narration);
        expect(plays[1].channel, AudioChannel.celebration);
        expect(plays[2].channel, AudioChannel.celebration);

        unawaited(h.close());
      });
    });

    test('narration is issued in the SAME synchronous turn as celebrate '
        '(it plays over the START of the animation, not after a delay)', () {
      fakeAsync((async) {
        final h = _Harness();
        unawaited(h.controller().run(
              story: _sentenceFormatStory(),
              profileId: _profileId,
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));

        expect(h.stage.triggeredInputs, [StoryStageInput.celebrate]);
        expect(
          h.audio.callLog.whereType<PlayLogEntry>().where((e) => e.channel == AudioChannel.narration),
          hasLength(1),
        );
        expect(async.elapsed, Duration.zero);

        async.elapse(const Duration(seconds: 10));
        unawaited(h.close());
      });
    });
  });

  group('NEGATIVE: narration is absent for a paragraph-format (no '
      'narrationAudioRef) story', () {
    test('no AudioChannel.narration play() call is ever issued; only the '
        'sting and the rotated line play', () {
      fakeAsync((async) {
        final h = _Harness();
        unawaited(h.controller().run(
              story: _paragraphFormatStory(),
              profileId: _profileId,
              profileOrdinal: 1,
              levelOrdinal: 1,
            ));
        async.elapse(const Duration(seconds: 10));

        final plays = h.audio.callLog.whereType<PlayLogEntry>().toList();
        expect(plays, hasLength(2));
        expect(plays.map((e) => e.channel), everyElement(AudioChannel.celebration));
        expect(
          h.audio.callLog.whereType<PlayLogEntry>().where((e) => e.channel == AudioChannel.narration),
          isEmpty,
        );

        unawaited(h.close());
      });
    });
  });

  group(
    'Fixture-story integration test (accept 3): full flow end-to-end, '
    'WITH narration',
    () {
      test(
        'celebrate fires, narrated read-back plays, celebration audio '
        'plays, collectible is persisted to CollectionState, and '
        'onFinished carries the next-story-highlight payload',
        () {
          fakeAsync((async) {
            final h = _Harness();
            final story = _sentenceFormatStory(id: 'story.fixture.sentence');
            unawaited(h.controller().run(
                  story: story,
                  profileId: _profileId,
                  profileOrdinal: 1,
                  levelOrdinal: 1,
                  nextStoryId: 'story.fixture.next',
                ));
            async.elapse(const Duration(seconds: 10));

            // 1. celebrate input triggered.
            expect(h.stage.triggeredInputs, contains(StoryStageInput.celebrate));

            // 2. narrated read-back played (narration present).
            expect(
              h.audio.callLog.whereType<PlayLogEntry>().where((e) => e.channel == AudioChannel.narration),
              hasLength(1),
            );

            // 3. celebration audio (sting + rotated line) played.
            expect(
              h.audio.callLog.whereType<PlayLogEntry>().where((e) => e.channel == AudioChannel.celebration),
              hasLength(2),
            );

            // 4. collectible persisted to CollectionState.
            CollectionState? state;
            h.db.collectionDao.getCollectionState(_profileId).then((s) => state = s);
            async.flushMicrotasks();
            expect(state!.earnedCollectibles, [story.collectibleRef]);

            // 5. navigation returns to the map with the next-story payload.
            expect(h.results, hasLength(1));
            expect(h.results.single.completedStoryId, story.id);
            expect(h.results.single.nextStoryId, 'story.fixture.next');

            unawaited(h.close());
          });
        },
      );
    },
  );

  group(
    'Fixture-story integration test (accept 3): full flow end-to-end, '
    'WITHOUT narration',
    () {
      test(
        'celebrate fires, NO read-back plays, celebration audio plays, '
        'collectible is persisted, navigation still carries the '
        'next-story payload',
        () {
          fakeAsync((async) {
            final h = _Harness();
            final story = _paragraphFormatStory(id: 'story.fixture.paragraph');
            unawaited(h.controller().run(
                  story: story,
                  profileId: _profileId,
                  profileOrdinal: 1,
                  levelOrdinal: 9,
                  nextStoryId: 'story.fixture.next2',
                ));
            async.elapse(const Duration(seconds: 10));

            expect(h.stage.triggeredInputs, contains(StoryStageInput.celebrate));
            expect(
              h.audio.callLog.whereType<PlayLogEntry>().where((e) => e.channel == AudioChannel.narration),
              isEmpty,
            );
            expect(
              h.audio.callLog.whereType<PlayLogEntry>().where((e) => e.channel == AudioChannel.celebration),
              hasLength(2),
            );

            CollectionState? state;
            h.db.collectionDao.getCollectionState(_profileId).then((s) => state = s);
            async.flushMicrotasks();
            expect(state!.earnedCollectibles, [story.collectibleRef]);

            expect(h.results, hasLength(1));
            expect(h.results.single.completedStoryId, story.id);
            expect(h.results.single.nextStoryId, 'story.fixture.next2');

            unawaited(h.close());
          });
        },
      );
    },
  );

  group('EDGE: nextStoryId is nullable (the last story in the library has '
      'no next story to highlight)', () {
    test('onFinished still fires with nextStoryId == null; nothing else '
        'about the sequence changes', () {
      fakeAsync((async) {
        final h = _Harness();
        unawaited(h.controller().run(
              story: _sentenceFormatStory(),
              profileId: _profileId,
              profileOrdinal: 1,
              levelOrdinal: 1,
              // nextStoryId omitted -- defaults to null.
            ));
        async.elapse(const Duration(seconds: 10));

        expect(h.results, hasLength(1));
        expect(h.results.single.nextStoryId, isNull);

        unawaited(h.close());
      });
    });
  });
}

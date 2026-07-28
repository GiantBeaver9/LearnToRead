// Pins the rolling-window-of-3 unlock rule (PRD §8 Unit 2, ratified: "the
// child always has the next 3 uncompleted stories in global authored order
// ... and picks freely among them; completing one pulls the next authored
// story into the window, and unchosen stories remain offered until read
// ('no strict block': when fewer than 3 uncompleted stories remain at the
// current level, the window back-fills from the next level's authored
// order)"; ticket phonics-engine accept entry 3). This suite is authored
// before the implementation exists, so it is EXPECTED to fail to compile
// until phonics_engine.dart and scope_sequence_loader.dart are written --
// see phonics_engine_test.dart and scope_sequence_loader_test.dart for the
// full pinned API surface those files require; this file exercises the
// same `storiesFor`/`advance`/`isUnlocked` contract, focused specifically
// on window mechanics: refill, unchosen persistence, and level-boundary
// back-fill.
//
// All scenarios below use test/domain/phonics/fixtures/fixture_sequence.json,
// whose global authored order is:
//   level-1 (2 stories): story-1-1, story-1-2
//   level-2 (2 stories): story-2-1, story-2-2
//   level-3 (2 stories): story-3-1, story-3-2
//   level-4 (3 stories): story-4-1, story-4-2, story-4-3
// i.e. exactly 9 stories, level-1/level-2/level-3 each short of a full
// window of 3 by themselves -- deliberately chosen so every rolling-window
// scenario (including the very first, zero-completions state) exercises
// cross-level back-fill.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/domain/phonics/phonics_engine.dart';
import 'package:learn_to_read/domain/phonics/scope_sequence_loader.dart';

Profile _profile(String currentLevelId) => Profile(
      localId: 'profile-1',
      displayName: 'Kid',
      ageBand: AgeBand.fiveToSix,
      currentLevelId: currentLevelId,
      micConsent: false,
      cloudAsrConsent: false,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  late PhonicsContent content;

  setUpAll(() {
    content = loadPhonicsContent(
      File('test/domain/phonics/fixtures/fixture_sequence.json').readAsStringSync(),
    );
  });

  StoryRef storyById(String id) => content.stories.firstWhere((s) => s.id == id);

  List<String> availableIds(Profile profile, Set<String> completed) =>
      storiesFor(profile, content, completed).map((s) => s.id).toList();

  group('rolling window (positive: initial window, zero completions)', () {
    test('offers exactly the first 3 stories in global authored order, already back-filled from level-2', () {
      final profile = _profile('level-1');
      expect(
        availableIds(profile, <String>{}),
        ['story-1-1', 'story-1-2', 'story-2-1'],
      );
    });
  });

  group('rolling window (positive: refill on completion)', () {
    test('completing the head of the window pulls the next authored story in', () {
      final profile = _profile('level-1');
      final r1 = advance(profile, storyById('story-1-1'), content, <String>{});
      expect(
        availableIds(r1.profile, r1.completedStoryIds),
        ['story-1-1', 'story-1-2', 'story-2-1', 'story-2-2'],
        reason: 'story-1-1 stays (replayable) and story-2-2 is pulled in to refill the window',
      );
    });

    test('refill keeps happening as more stories complete', () {
      final profile = _profile('level-1');
      var completed = <String>{};
      var current = profile;
      for (final id in ['story-1-1', 'story-1-2']) {
        final r = advance(current, storyById(id), content, completed);
        current = r.profile;
        completed = r.completedStoryIds;
      }
      expect(
        availableIds(current, completed),
        ['story-1-1', 'story-1-2', 'story-2-1', 'story-2-2', 'story-3-1'],
      );
    });
  });

  group('rolling window (positive: unchosen stories persist)', () {
    test('a story offered but skipped remains offered after a sibling in the window is completed', () {
      final profile = _profile('level-1');
      // story-2-1 is unlocked from the very start (window back-fills to it
      // immediately); complete it while skipping story-1-1 and story-1-2.
      final r = advance(profile, storyById('story-2-1'), content, <String>{});

      expect(isUnlocked(r.profile, storyById('story-1-1'), content, r.completedStoryIds), isTrue,
          reason: 'unchosen stories remain offered until read');
      expect(isUnlocked(r.profile, storyById('story-1-2'), content, r.completedStoryIds), isTrue);
      expect(
        availableIds(r.profile, r.completedStoryIds),
        ['story-1-1', 'story-1-2', 'story-2-1', 'story-2-2'],
      );
    });

    test('an unchosen story can still be completed later, after other stories complete around it', () {
      final profile = _profile('level-1');
      final r1 = advance(profile, storyById('story-2-1'), content, <String>{});
      final r2 = advance(r1.profile, storyById('story-1-2'), content, r1.completedStoryIds);
      // story-1-1 was in the original window and was never removed.
      final r3 = advance(r2.profile, storyById('story-1-1'), content, r2.completedStoryIds);
      expect(r3.completedStoryIds, unorderedEquals(['story-2-1', 'story-1-2', 'story-1-1']));
    });
  });

  group('rolling window (positive: back-fill across level boundary)', () {
    test('completing all of level-1 advances currentLevelId and the window keeps back-filling into level-3', () {
      final profile = _profile('level-1');
      final r1 = advance(profile, storyById('story-1-1'), content, <String>{});
      final r2 = advance(r1.profile, storyById('story-1-2'), content, r1.completedStoryIds);

      expect(r2.profile.currentLevelId, 'level-2', reason: 'level-1 full set is now complete');
      expect(
        availableIds(r2.profile, r2.completedStoryIds),
        ['story-1-1', 'story-1-2', 'story-2-1', 'story-2-2', 'story-3-1'],
        reason: 'level-2 only has 2 uncompleted stories, so the window back-fills into level-3',
      );
    });

    test('completing level-1 and level-2 advances currentLevelId to level-3 and backfills into level-4', () {
      final profile = _profile('level-1');
      var completed = <String>{};
      var current = profile;
      for (final id in ['story-1-1', 'story-1-2', 'story-2-1', 'story-2-2']) {
        final r = advance(current, storyById(id), content, completed);
        current = r.profile;
        completed = r.completedStoryIds;
      }
      expect(current.currentLevelId, 'level-3');
      expect(
        availableIds(current, completed),
        [
          'story-1-1', 'story-1-2', 'story-2-1', 'story-2-2',
          'story-3-1', 'story-3-2', 'story-4-1',
        ],
        reason: 'level-3 only has 2 stories, so the window back-fills into level-4',
      );
    });
  });

  group('rolling window (negative)', () {
    test('a story past the current window cannot be completed out of order', () {
      final profile = _profile('level-1');
      // story-4-1 is nowhere near the initial window [story-1-1, story-1-2, story-2-1].
      expect(
        () => advance(profile, storyById('story-4-1'), content, <String>{}),
        throwsArgumentError,
      );
    });
  });

  group('rolling window (edge: fewer than window-size stories remain overall)', () {
    test('the window shrinks below 3 (or to 0) once near/at full completion, without error', () {
      final profile = _profile('level-1');
      final order = [
        'story-1-1', 'story-1-2', 'story-2-1', 'story-2-2',
        'story-3-1', 'story-3-2', 'story-4-1', 'story-4-2',
      ];
      var completed = <String>{};
      var current = profile;
      for (final id in order) {
        final r = advance(current, storyById(id), content, completed);
        current = r.profile;
        completed = r.completedStoryIds;
      }
      // Exactly one story (story-4-3) remains uncompleted: window has 1
      // entry, not 3, and no error is thrown.
      expect(availableIds(current, completed), [
        'story-1-1', 'story-1-2', 'story-2-1', 'story-2-2',
        'story-3-1', 'story-3-2', 'story-4-1', 'story-4-2', 'story-4-3',
      ]);

      final finalResult = advance(current, storyById('story-4-3'), content, completed);
      // Every story is now completed: the window portion is empty but the
      // replay portion still makes storiesFor non-empty.
      expect(finalResult.completedStoryIds, hasLength(9));
      expect(availableIds(finalResult.profile, finalResult.completedStoryIds), hasLength(9));
    });
  });
}

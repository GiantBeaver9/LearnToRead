// Pins the API of lib/domain/phonics/phonics_engine.dart (PRD §8 Unit 2
// pinned design: "Engine exposes: storiesFor(profile), advance(profile,
// story), isUnlocked(profile, story) -- pure functions over Profile +
// content data"; ticket phonics-engine accept entries 1, 4, and 5). This
// suite is authored before the implementation exists, so it is EXPECTED to
// fail to compile until phonics_engine.dart is written with exactly the
// shapes exercised below.
//
// Rolling-window mechanics (refill, unchosen persistence, level-boundary
// back-fill) are covered in depth by rolling_window_test.dart; this file
// focuses on the engine's pure-function contract, replayability, the
// currentLevelId/availability gating split, and the fixture-swap
// (data-driven) property. The zero-available-stories property test lives
// in no_empty_window_property_test.dart.
//
// Pinned API surface this suite requires:
//   const int kRollingWindowSize = 3;
//   List<StoryRef> storiesFor(
//     Profile profile, PhonicsContent content, Set<String> completedStoryIds,
//   )
//     Returns the entries of `content.stories`, in that same relative
//     order, that are either (a) present in `completedStoryIds` (replayable
//     forever) or (b) among the first `kRollingWindowSize` entries of
//     `content.stories` (in `content.stories` order) that are NOT in
//     `completedStoryIds` (the rolling window). Never consults
//     `profile.currentLevelId` -- level advancement gates vocab/twister
//     only, never story availability. Pure: does not mutate
//     `completedStoryIds`, and returns the same result for the same inputs
//     no matter how many times it is called.
//   bool isUnlocked(
//     Profile profile, StoryRef story, PhonicsContent content, Set<String> completedStoryIds,
//   )
//     Equivalent to
//     `storiesFor(profile, content, completedStoryIds).any((s) => s.id == story.id)`.
//   class AdvanceResult {
//     const AdvanceResult({required Profile profile, required Set<String> completedStoryIds});
//     Profile profile; Set<String> completedStoryIds; // getters
//   }
//   AdvanceResult advance(
//     Profile profile, StoryRef story, PhonicsContent content, Set<String> completedStoryIds,
//   )
//     Throws ArgumentError if
//     `!isUnlocked(profile, story, content, completedStoryIds)`. Otherwise
//     returns a NEW completed set (`{...completedStoryIds, story.id}`,
//     input set left unmutated) and a NEW Profile identical to `profile`
//     except `currentLevelId`, recomputed by: while the level in
//     `content.levels` whose id == currentLevelId has a non-empty story set
//     (within `content.stories`) that is now fully contained in the new
//     completed set, AND a next level (next entry by ascending ordinal in
//     `content.levels`) exists, move `currentLevelId` to that next level's
//     id; repeat. (`currentLevelId` advances only on full-level completion,
//     and may skip forward more than one level in a single `advance()` call
//     if this pushes multiple already-fully-completed levels' boundary.)

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/domain/phonics/phonics_engine.dart';
import 'package:learn_to_read/domain/phonics/scope_sequence_loader.dart';

String _readFixture(String name) =>
    File('test/domain/phonics/fixtures/$name').readAsStringSync();

Profile _profile({
  String currentLevelId = 'level-1',
  AgeBand ageBand = AgeBand.fiveToSix,
  String localId = 'profile-1',
}) =>
    Profile(
      localId: localId,
      displayName: 'Kid',
      ageBand: ageBand,
      currentLevelId: currentLevelId,
      micConsent: false,
      cloudAsrConsent: false,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  late PhonicsContent content;
  late PhonicsContent alternateContent;

  setUpAll(() {
    content = loadPhonicsContent(_readFixture('fixture_sequence.json'));
    alternateContent = loadPhonicsContent(_readFixture('alternate_sequence.json'));
  });

  StoryRef storyById(String id) => content.stories.firstWhere((s) => s.id == id);

  group('kRollingWindowSize (positive: pinned constant)', () {
    test('is exactly 3', () {
      expect(kRollingWindowSize, 3);
    });
  });

  group('storiesFor (positive: pure function contract)', () {
    test('returns the same result for the same inputs across repeated calls', () {
      final profile = _profile();
      final completed = <String>{'story-1-1'};
      final first = storiesFor(profile, content, completed);
      final second = storiesFor(profile, content, completed);
      expect(first, equals(second));
    });

    test('does not mutate the completedStoryIds set passed in', () {
      final profile = _profile();
      final completed = <String>{'story-1-1'};
      final snapshotBefore = Set<String>.from(completed);
      storiesFor(profile, content, completed);
      expect(completed, snapshotBefore);
    });

    test('returned entries preserve content.stories relative order', () {
      final profile = _profile();
      final result = storiesFor(profile, content, <String>{'story-2-1'});
      final resultIds = result.map((s) => s.id).toList();
      final expectedRelativeOrder =
          content.stories.map((s) => s.id).where(resultIds.contains).toList();
      expect(resultIds, expectedRelativeOrder);
    });
  });

  group('isUnlocked (positive/negative)', () {
    test('a story within the initial window is unlocked', () {
      final profile = _profile();
      expect(isUnlocked(profile, storyById('story-1-1'), content, <String>{}), isTrue);
    });

    test('a story beyond the initial window and not completed is locked', () {
      final profile = _profile();
      // story-4-3 is the last story in the 9-story fixture and cannot be
      // within a fresh window of 3 with zero completions.
      expect(isUnlocked(profile, storyById('story-4-3'), content, <String>{}), isFalse);
    });

    test('isUnlocked matches storiesFor membership for every story in content', () {
      final profile = _profile();
      final completed = <String>{'story-1-1'};
      final available = storiesFor(profile, content, completed).map((s) => s.id).toSet();
      for (final story in content.stories) {
        expect(
          isUnlocked(profile, story, content, completed),
          available.contains(story.id),
          reason: 'mismatch for ${story.id}',
        );
      }
    });
  });

  group('advance (negative)', () {
    test('throws ArgumentError when completing a locked story', () {
      final profile = _profile();
      expect(
        () => advance(profile, storyById('story-4-3'), content, <String>{}),
        throwsArgumentError,
      );
    });

    test('a failed advance() call does not mutate the completedStoryIds set passed in', () {
      final profile = _profile();
      final completed = <String>{};
      try {
        advance(profile, storyById('story-4-3'), content, completed);
      } catch (_) {
        // expected
      }
      expect(completed, isEmpty);
    });
  });

  group('advance (positive)', () {
    test('completing an unlocked story adds it to the returned completed set', () {
      final profile = _profile();
      final result = advance(profile, storyById('story-1-1'), content, <String>{});
      expect(result.completedStoryIds, contains('story-1-1'));
    });

    test('advance does not mutate the completedStoryIds set passed in', () {
      final profile = _profile();
      final completed = <String>{};
      advance(profile, storyById('story-1-1'), content, completed);
      expect(completed, isEmpty);
    });

    test('advance preserves every Profile field other than currentLevelId', () {
      final profile = _profile(currentLevelId: 'level-1', ageBand: AgeBand.sevenToEight);
      final result = advance(profile, storyById('story-1-1'), content, <String>{});
      expect(result.profile.localId, profile.localId);
      expect(result.profile.displayName, profile.displayName);
      expect(result.profile.ageBand, profile.ageBand);
      expect(result.profile.micConsent, profile.micConsent);
      expect(result.profile.cloudAsrConsent, profile.cloudAsrConsent);
      expect(result.profile.createdAt, profile.createdAt);
    });
  });

  group('level advancement gates vocab/twister state, not story availability', () {
    test('storiesFor and isUnlocked are identical for two profiles differing only in currentLevelId', () {
      final earlyProfile = _profile(currentLevelId: 'level-1');
      final advancedProfile = _profile(currentLevelId: 'level-4', localId: 'profile-2');
      final completed = <String>{'story-1-1', 'story-2-1'};

      expect(
        storiesFor(earlyProfile, content, completed),
        equals(storiesFor(advancedProfile, content, completed)),
      );
      for (final story in content.stories) {
        expect(
          isUnlocked(earlyProfile, story, content, completed),
          isUnlocked(advancedProfile, story, content, completed),
          reason: 'mismatch for ${story.id}',
        );
      }
    });

    test('currentLevelId does not change while level-1\'s story set is incomplete', () {
      final profile = _profile(currentLevelId: 'level-1');
      final result = advance(profile, storyById('story-1-1'), content, <String>{});
      expect(result.profile.currentLevelId, 'level-1');
    });

    test('currentLevelId advances to level-2 exactly when level-1\'s full story set completes', () {
      final profile = _profile(currentLevelId: 'level-1');
      final afterFirst = advance(profile, storyById('story-1-1'), content, <String>{});
      expect(afterFirst.profile.currentLevelId, 'level-1');

      final afterSecond = advance(
        afterFirst.profile,
        storyById('story-1-2'),
        content,
        afterFirst.completedStoryIds,
      );
      expect(afterSecond.profile.currentLevelId, 'level-2');
    });
  });

  group('replayability (positive)', () {
    test('a completed story stays unlocked and stays in storiesFor forever, across further completions', () {
      final profile0 = _profile();
      final r1 = advance(profile0, storyById('story-1-1'), content, <String>{});
      expect(isUnlocked(r1.profile, storyById('story-1-1'), content, r1.completedStoryIds), isTrue);
      expect(storiesFor(r1.profile, content, r1.completedStoryIds).map((s) => s.id),
          contains('story-1-1'));

      final r2 = advance(r1.profile, storyById('story-1-2'), content, r1.completedStoryIds);
      final r3 = advance(r2.profile, storyById('story-2-1'), content, r2.completedStoryIds);
      final r4 = advance(r3.profile, storyById('story-2-2'), content, r3.completedStoryIds);

      for (final r in [r2, r3, r4]) {
        expect(isUnlocked(r.profile, storyById('story-1-1'), content, r.completedStoryIds), isTrue,
            reason: 'story-1-1 must remain replayable forever');
        expect(storiesFor(r.profile, content, r.completedStoryIds).map((s) => s.id),
            contains('story-1-1'));
      }
    });
  });

  group('fixture-swap proves data-driven behavior (no code change)', () {
    test('the initial rolling window differs between fixtures because their level sizing differs', () {
      final fixtureProfile = _profile(currentLevelId: content.levels.first.id);
      final alternateProfile =
          _profile(currentLevelId: alternateContent.levels.first.id, localId: 'alt-profile');

      final fixtureWindow =
          storiesFor(fixtureProfile, content, <String>{}).map((s) => s.id).toList();
      final alternateWindow =
          storiesFor(alternateProfile, alternateContent, <String>{}).map((s) => s.id).toList();

      // fixture_sequence.json's level-1 has only 2 stories, so the window
      // of 3 backfills across the level-1/level-2 boundary immediately.
      expect(fixtureWindow, ['story-1-1', 'story-1-2', 'story-2-1']);
      expect(
        fixtureWindow.map((id) => content.stories.firstWhere((s) => s.id == id).levelId).toSet(),
        {'level-1', 'level-2'},
      );

      // alternate_sequence.json's level-1 has 4 stories, so the same
      // engine code produces a window that stays entirely within level 1 --
      // no backfill needed, purely because the underlying data differs.
      expect(alternateWindow, ['alt-story-1-1', 'alt-story-1-2', 'alt-story-1-3']);
      expect(
        alternateWindow
            .map((id) => alternateContent.stories.firstWhere((s) => s.id == id).levelId)
            .toSet(),
        {'alt-level-1'},
      );
    });
  });
}

// Pins the property test required by ticket phonics-engine accept entry 6
// / PRD §8 Unit 2 acceptance: "Property test: no reachable state where a
// profile has zero available stories." This suite exercises
// lib/domain/phonics/phonics_engine.dart's `storiesFor`/`advance` via
// randomized completion walks (fixed seeds, for reproducibility) over both
// fixture JSON files, and asserts `storiesFor(...)` is never empty at any
// point along the walk -- including the initial (zero-completion) state and
// the fully-completed terminal state, where non-emptiness is guaranteed
// only by replayability (PRD: "earlier stories remain replayable forever").
//
// See phonics_engine_test.dart for the full pinned API surface this file
// depends on (storiesFor/advance/isUnlocked/AdvanceResult); this file is
// authored before the implementation exists and is EXPECTED to fail to
// compile until that API exists.

import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/domain/phonics/phonics_engine.dart';
import 'package:learn_to_read/domain/phonics/scope_sequence_loader.dart';

Profile _profile(String seedLabel, String currentLevelId, AgeBand ageBand) => Profile(
      localId: 'walk-$seedLabel',
      displayName: 'Walker $seedLabel',
      ageBand: ageBand,
      currentLevelId: currentLevelId,
      micConsent: false,
      cloudAsrConsent: false,
      createdAt: DateTime(2026, 1, 1),
    );

/// Runs a single randomized completion walk over [content], asserting at
/// every step (before AND after each `advance()` call) that
/// `storiesFor(...)` is never empty -- the invariant under test. At each
/// step, picks uniformly at random among the currently-available
/// *uncompleted* stories and completes it, so the walk always makes
/// progress; once every story is completed the walk stops early (that
/// terminal, fully-completed state is itself asserted non-empty first).
void _runRandomWalk({
  required int seed,
  required PhonicsContent content,
  required AgeBand ageBand,
}) {
  final random = Random(seed);
  var profile = _profile('$seed', content.levels.first.id, ageBand);
  var completed = <String>{};

  final maxSteps = content.stories.length * 3;
  for (var step = 0; step < maxSteps; step++) {
    final available = storiesFor(profile, content, completed);
    expect(
      available,
      isNotEmpty,
      reason: 'seed=$seed step=$step: reachable state has zero available stories',
    );

    final uncompletedAvailable =
        available.where((s) => !completed.contains(s.id)).toList();
    if (uncompletedAvailable.isEmpty) {
      // Every story reachable right now is already completed -- nothing
      // left to progress toward; the walk is done.
      break;
    }

    final pick = uncompletedAvailable[random.nextInt(uncompletedAvailable.length)];
    expect(isUnlocked(profile, pick, content, completed), isTrue,
        reason: 'seed=$seed step=$step: picked a story storiesFor did not offer');

    final result = advance(profile, pick, content, completed);
    profile = result.profile;
    completed = result.completedStoryIds;

    expect(
      storiesFor(profile, content, completed),
      isNotEmpty,
      reason: 'seed=$seed step=$step: zero available stories immediately after advance()',
    );
  }

  // Terminal sanity check: whether or not every story got completed, the
  // walk must end in a state with at least one available (replayable)
  // story, given content.stories is non-empty.
  expect(storiesFor(profile, content, completed), isNotEmpty);
}

void main() {
  late PhonicsContent fixtureContent;
  late PhonicsContent alternateContent;

  setUpAll(() {
    fixtureContent = loadPhonicsContent(
      File('test/domain/phonics/fixtures/fixture_sequence.json').readAsStringSync(),
    );
    alternateContent = loadPhonicsContent(
      File('test/domain/phonics/fixtures/alternate_sequence.json').readAsStringSync(),
    );
  });

  group('no-empty-window property (positive: fixed-seed random walks, fixture_sequence.json)', () {
    for (final seed in [1, 7, 42, 1337, 99999]) {
      test('random completion walk never reaches zero available stories (seed=$seed)', () {
        _runRandomWalk(
          seed: seed,
          content: fixtureContent,
          ageBand: AgeBand.values[seed % AgeBand.values.length],
        );
      });
    }
  });

  group('no-empty-window property (positive: fixed-seed random walks, alternate_sequence.json)', () {
    for (final seed in [3, 21, 555]) {
      test('random completion walk never reaches zero available stories (seed=$seed)', () {
        _runRandomWalk(
          seed: seed,
          content: alternateContent,
          ageBand: AgeBand.values[seed % AgeBand.values.length],
        );
      });
    }
  });

  group('no-empty-window property (edge: boundary states)', () {
    test('the very first state (zero completions) already has a non-empty window', () {
      final profile = _profile('edge-start', fixtureContent.levels.first.id, AgeBand.fiveToSix);
      expect(storiesFor(profile, fixtureContent, <String>{}), isNotEmpty);
    });

    test('the fully-completed terminal state has a non-empty (all-replayable) window', () {
      final profile = _profile('edge-end', fixtureContent.levels.first.id, AgeBand.fiveToSix);
      var current = profile;
      var completed = <String>{};
      // Deterministically complete every story in a legal order by always
      // picking the first currently-available uncompleted story.
      while (completed.length < fixtureContent.stories.length) {
        final next = storiesFor(current, fixtureContent, completed)
            .firstWhere((s) => !completed.contains(s.id));
        final result = advance(current, next, fixtureContent, completed);
        current = result.profile;
        completed = result.completedStoryIds;
      }
      final finalWindow = storiesFor(current, fixtureContent, completed);
      expect(finalWindow, isNotEmpty);
      expect(finalWindow, hasLength(fixtureContent.stories.length));
    });
  });
}

/// Unit tests for the four §4 signal queries (PRD §4 "Success criteria" +
/// §8 Unit 12: "The four §4 signal queries run against fixture event data
/// and return correct values (tests are the executable definition of the
/// signals)"). No pass/fail thresholds are asserted anywhere in this file
/// (ratified: "no pass/fail targets in v1") — every assertion is against
/// a hand-computed raw numeric value from a fixture event stream.
///
/// Design notes this file pins (necessary to make the queries well
/// defined, but not spelled out verbatim in the PRD — flagged in the
/// build report as reasoned interpretations, not literal spec text):
///
/// 1. A "profile" for cohort purposes is the (installId, profileOrdinal)
///    pair — the payload contract has no other stable per-profile key.
/// 2. The event payload contract is closed ("payloads carry only: event
///    name, timestamp, random per-install UUID, profile ordinal, level
///    ordinal, story id, and event-specific fields") — there is no
///    sessionId field. Sessions are therefore reconstructed from
///    session_start boundaries: for a given profile's events sorted by
///    time, each session_start begins a new session bucket; every event
///    up to (not including) the next session_start for that profile
///    belongs to it.
/// 3. D7 profile return: a profile only enters the denominator once at
///    least 7 days have elapsed between its first session and `asOf`
///    (otherwise a recent cohort would be unfairly counted as
///    "not returned" before it has had the chance to return).
/// 4. help-rate trajectory: "help needed" = a word_read event with
///    result == helped (near_miss is deliberately NOT counted as help
///    needed — it is a separate signal per §5's near-miss note).
/// 5. post-help abandonment rate: reads story_abandoned's own
///    helpInLast30s field directly (already computed at emission time by
///    session_tracker) rather than re-deriving it from raw help_given
///    timestamps.
///
/// Imports lib/features/analytics/{events,event_schema,signal_queries}.dart,
/// none of which exist yet: this file fails to compile until they exist —
/// the expected red state.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/analytics/events.dart';
import 'package:learn_to_read/features/analytics/signal_queries.dart';

AnalyticsEvent _sessionStart({
  required String installId,
  required int profileOrdinal,
  required DateTime at,
  int levelOrdinal = 1,
}) {
  return AnalyticsEvent(
    name: AnalyticsEventName.sessionStart,
    timestamp: at,
    installId: installId,
    profileOrdinal: profileOrdinal,
    levelOrdinal: levelOrdinal,
  );
}

AnalyticsEvent _storyCompleted({
  required String installId,
  required int profileOrdinal,
  required DateTime at,
  required String storyId,
}) {
  return AnalyticsEvent(
    name: AnalyticsEventName.storyCompleted,
    timestamp: at,
    installId: installId,
    profileOrdinal: profileOrdinal,
    levelOrdinal: 1,
    storyId: storyId,
  );
}

AnalyticsEvent _wordRead({
  required String installId,
  required int profileOrdinal,
  required DateTime at,
  required String wordHash,
  required WordReadResult result,
}) {
  return AnalyticsEvent(
    name: AnalyticsEventName.wordRead,
    timestamp: at,
    installId: installId,
    profileOrdinal: profileOrdinal,
    levelOrdinal: 1,
    storyId: 's1',
    fields: {
      'result': result.wireValue,
      'wordHash': wordHash,
    },
  );
}

AnalyticsEvent _storyAbandoned({
  required String installId,
  required int profileOrdinal,
  required DateTime at,
  required bool helpInLast30s,
}) {
  return AnalyticsEvent(
    name: AnalyticsEventName.storyAbandoned,
    timestamp: at,
    installId: installId,
    profileOrdinal: profileOrdinal,
    levelOrdinal: 1,
    storyId: 's1',
    fields: {'helpInLast30s': helpInLast30s},
  );
}

AnalyticsEvent _storyStarted({
  required String installId,
  required int profileOrdinal,
  required DateTime at,
  required String storyId,
}) {
  return AnalyticsEvent(
    name: AnalyticsEventName.storyStarted,
    timestamp: at,
    installId: installId,
    profileOrdinal: profileOrdinal,
    levelOrdinal: 1,
    storyId: storyId,
  );
}

AnalyticsEvent _helpGiven({
  required String installId,
  required int profileOrdinal,
  required DateTime at,
}) {
  return AnalyticsEvent(
    name: AnalyticsEventName.helpGiven,
    timestamp: at,
    installId: installId,
    profileOrdinal: profileOrdinal,
    levelOrdinal: 1,
    storyId: 's1',
    fields: {'tier': HelpTier.soundOut.wireValue},
  );
}

void main() {
  group('Signal 1 — D7 profile return rate', () {
    // asOf is fixed so eligibility (>=7 days elapsed since first session)
    // is unambiguous for every fixture profile.
    final asOf = DateTime.utc(2026, 2, 1);

    test('POSITIVE: hand-computed rate over a 4-profile fixture', () {
      final events = <AnalyticsEvent>[
        // Profile A (inst-a/1): returns 9 days later. Eligible + returned.
        _sessionStart(
            installId: 'inst-a', profileOrdinal: 1, at: DateTime.utc(2026, 1, 1)),
        _sessionStart(
            installId: 'inst-a', profileOrdinal: 1, at: DateTime.utc(2026, 1, 10)),

        // Profile B (inst-b/1): only ever one session, but old enough to
        // be eligible. Eligible + NOT returned.
        _sessionStart(
            installId: 'inst-b', profileOrdinal: 1, at: DateTime.utc(2026, 1, 5)),

        // Profile C (inst-c/2): first session too recent relative to
        // asOf (4 days) — excluded from the denominator entirely.
        _sessionStart(
            installId: 'inst-c', profileOrdinal: 2, at: DateTime.utc(2026, 1, 28)),

        // Profile D (inst-d/1): an intermediate session at +5 days
        // (doesn't count alone) plus one at +8 days (does). Eligible +
        // returned.
        _sessionStart(
            installId: 'inst-d', profileOrdinal: 1, at: DateTime.utc(2026, 1, 1)),
        _sessionStart(
            installId: 'inst-d', profileOrdinal: 1, at: DateTime.utc(2026, 1, 6)),
        _sessionStart(
            installId: 'inst-d', profileOrdinal: 1, at: DateTime.utc(2026, 1, 9)),
      ];

      // Eligible: {A, B, D} = 3. Returned: {A, D} = 2. Rate = 2/3.
      expect(d7ProfileReturnRate(events, asOf: asOf), closeTo(2 / 3, 1e-9));
    });

    test('EDGE: a return at EXACTLY 7 days counts (inclusive boundary)',
        () {
      final events = <AnalyticsEvent>[
        _sessionStart(
            installId: 'inst-e', profileOrdinal: 1, at: DateTime.utc(2026, 1, 1)),
        _sessionStart(
            installId: 'inst-e', profileOrdinal: 1, at: DateTime.utc(2026, 1, 8)),
      ];

      expect(d7ProfileReturnRate(events, asOf: asOf), 1.0);
    });

    test('EDGE: empty event stream returns 0.0, not NaN or an exception',
        () {
      expect(d7ProfileReturnRate(<AnalyticsEvent>[], asOf: asOf), 0.0);
    });

    test('EDGE: a fixture with only ineligible (too-recent) profiles '
        'returns 0.0', () {
      final events = <AnalyticsEvent>[
        _sessionStart(
            installId: 'inst-f', profileOrdinal: 1, at: DateTime.utc(2026, 1, 30)),
      ];
      expect(d7ProfileReturnRate(events, asOf: asOf), 0.0);
    });
  });

  group('Signal 2 — median completed stories per session', () {
    test('POSITIVE: hand-computed median over 4 reconstructed sessions '
        'across 2 profiles', () {
      final events = <AnalyticsEvent>[
        // Profile X (inst-x/1): session 1 has 2 completions, session 2
        // has 1.
        _sessionStart(
            installId: 'inst-x',
            profileOrdinal: 1,
            at: DateTime.utc(2026, 1, 1, 10)),
        _storyCompleted(
            installId: 'inst-x',
            profileOrdinal: 1,
            at: DateTime.utc(2026, 1, 1, 10, 5),
            storyId: 's1'),
        _storyCompleted(
            installId: 'inst-x',
            profileOrdinal: 1,
            at: DateTime.utc(2026, 1, 1, 10, 10),
            storyId: 's2'),
        _sessionStart(
            installId: 'inst-x',
            profileOrdinal: 1,
            at: DateTime.utc(2026, 1, 1, 11)),
        _storyCompleted(
            installId: 'inst-x',
            profileOrdinal: 1,
            at: DateTime.utc(2026, 1, 1, 11, 5),
            storyId: 's3'),

        // Profile Y (inst-y/3): session 1 has 0 completions, session 2
        // has 3.
        _sessionStart(
            installId: 'inst-y',
            profileOrdinal: 3,
            at: DateTime.utc(2026, 1, 1, 9)),
        _sessionStart(
            installId: 'inst-y',
            profileOrdinal: 3,
            at: DateTime.utc(2026, 1, 1, 9, 30)),
        _storyCompleted(
            installId: 'inst-y',
            profileOrdinal: 3,
            at: DateTime.utc(2026, 1, 1, 9, 35),
            storyId: 't1'),
        _storyCompleted(
            installId: 'inst-y',
            profileOrdinal: 3,
            at: DateTime.utc(2026, 1, 1, 9, 40),
            storyId: 't2'),
        _storyCompleted(
            installId: 'inst-y',
            profileOrdinal: 3,
            at: DateTime.utc(2026, 1, 1, 9, 45),
            storyId: 't3'),
      ];

      // Session completion counts: [2, 1, 0, 3] -> sorted [0, 1, 2, 3]
      // -> median of an even-length list = average of the two middle
      // values = (1 + 2) / 2 = 1.5.
      expect(medianCompletedStoriesPerSession(events), 1.5);
    });

    test('EDGE: a single session returns exactly its own count (no '
        'averaging)', () {
      final events = <AnalyticsEvent>[
        _sessionStart(
            installId: 'inst-z', profileOrdinal: 1, at: DateTime.utc(2026, 1, 1)),
        _storyCompleted(
            installId: 'inst-z',
            profileOrdinal: 1,
            at: DateTime.utc(2026, 1, 1, 0, 5),
            storyId: 's1'),
      ];
      expect(medianCompletedStoriesPerSession(events), 1.0);
    });

    test('EDGE: empty event stream returns 0.0, not NaN or an exception',
        () {
      expect(medianCompletedStoriesPerSession(<AnalyticsEvent>[]), 0.0);
    });
  });

  group('Signal 3 — help-rate trajectory on repeated word encounters', () {
    test('POSITIVE: hand-computed per-encounter-position help rate shows '
        'a declining trajectory', () {
      final catHash = hashWord('cat');
      final dogHash = hashWord('dog');

      final events = <AnalyticsEvent>[
        // Profile P1 reads "cat" 3 times: helped, helped, correct.
        _wordRead(
            installId: 'inst-p1',
            profileOrdinal: 1,
            at: DateTime.utc(2026, 1, 1, 0, 0),
            wordHash: catHash,
            result: WordReadResult.helped),
        _wordRead(
            installId: 'inst-p1',
            profileOrdinal: 1,
            at: DateTime.utc(2026, 1, 1, 0, 1),
            wordHash: catHash,
            result: WordReadResult.helped),
        _wordRead(
            installId: 'inst-p1',
            profileOrdinal: 1,
            at: DateTime.utc(2026, 1, 1, 0, 2),
            wordHash: catHash,
            result: WordReadResult.correct),

        // Profile P1 reads "dog" 2 times: correct, correct (a shorter
        // group — proves position 3's denominator excludes it).
        _wordRead(
            installId: 'inst-p1',
            profileOrdinal: 1,
            at: DateTime.utc(2026, 1, 1, 0, 3),
            wordHash: dogHash,
            result: WordReadResult.correct),
        _wordRead(
            installId: 'inst-p1',
            profileOrdinal: 1,
            at: DateTime.utc(2026, 1, 1, 0, 4),
            wordHash: dogHash,
            result: WordReadResult.correct),

        // Profile P2 reads "cat" 3 times: helped, correct, correct.
        _wordRead(
            installId: 'inst-p2',
            profileOrdinal: 2,
            at: DateTime.utc(2026, 1, 1, 0, 0),
            wordHash: catHash,
            result: WordReadResult.helped),
        _wordRead(
            installId: 'inst-p2',
            profileOrdinal: 2,
            at: DateTime.utc(2026, 1, 1, 0, 1),
            wordHash: catHash,
            result: WordReadResult.correct),
        _wordRead(
            installId: 'inst-p2',
            profileOrdinal: 2,
            at: DateTime.utc(2026, 1, 1, 0, 2),
            wordHash: catHash,
            result: WordReadResult.correct),
      ];

      // Position 1 (3 groups: P1-cat, P1-dog, P2-cat): helped, correct,
      // helped => 2/3.
      // Position 2 (3 groups): helped, correct, correct => 1/3.
      // Position 3 (2 groups — P1-dog has no 3rd encounter): correct,
      // correct => 0/2 = 0.0.
      final trajectory = helpRateTrajectory(events);

      expect(trajectory[1], closeTo(2 / 3, 1e-9));
      expect(trajectory[2], closeTo(1 / 3, 1e-9));
      expect(trajectory[3], 0.0);
      expect(trajectory.keys, containsAll([1, 2, 3]));
    });

    test('NEGATIVE: a near_miss result does NOT count as "help needed" '
        '(only result == helped does)', () {
      final wordHash = hashWord('sun');
      final events = <AnalyticsEvent>[
        _wordRead(
            installId: 'inst-p1',
            profileOrdinal: 1,
            at: DateTime.utc(2026, 1, 1),
            wordHash: wordHash,
            result: WordReadResult.nearMiss),
        _wordRead(
            installId: 'inst-p2',
            profileOrdinal: 2,
            at: DateTime.utc(2026, 1, 1),
            wordHash: wordHash,
            result: WordReadResult.helped),
      ];

      // Only 1 of the 2 first-encounters was actually "helped".
      expect(helpRateTrajectory(events)[1], closeTo(0.5, 1e-9));
    });

    test('EDGE: empty event stream returns an empty map, not an '
        'exception', () {
      expect(helpRateTrajectory(<AnalyticsEvent>[]), isEmpty);
    });
  });

  group('Signal 4 — rate of sessions ending in post-help abandonment', () {
    test('POSITIVE: hand-computed rate over 4 reconstructed sessions, 2 '
        'of which end in a post-help abandonment', () {
      const installId = 'inst-z';
      const profileOrdinal = 1;

      final events = <AnalyticsEvent>[
        // Session 1: help given, then abandoned within 30s. Counts.
        _sessionStart(
            installId: installId,
            profileOrdinal: profileOrdinal,
            at: DateTime.utc(2026, 1, 1, 8, 0)),
        _storyStarted(
            installId: installId,
            profileOrdinal: profileOrdinal,
            at: DateTime.utc(2026, 1, 1, 8, 1),
            storyId: 's1'),
        _helpGiven(
            installId: installId,
            profileOrdinal: profileOrdinal,
            at: DateTime.utc(2026, 1, 1, 8, 3)),
        _storyAbandoned(
            installId: installId,
            profileOrdinal: profileOrdinal,
            at: DateTime.utc(2026, 1, 1, 8, 3, 20),
            helpInLast30s: true),

        // Session 2: normal completion. Does not count.
        _sessionStart(
            installId: installId,
            profileOrdinal: profileOrdinal,
            at: DateTime.utc(2026, 1, 1, 9, 0)),
        _storyStarted(
            installId: installId,
            profileOrdinal: profileOrdinal,
            at: DateTime.utc(2026, 1, 1, 9, 1),
            storyId: 's2'),
        _storyCompleted(
            installId: installId,
            profileOrdinal: profileOrdinal,
            at: DateTime.utc(2026, 1, 1, 9, 10),
            storyId: 's2'),

        // Session 3: abandoned but with NO help in the preceding 30s.
        // Does not count toward the post-HELP abandonment rate.
        _sessionStart(
            installId: installId,
            profileOrdinal: profileOrdinal,
            at: DateTime.utc(2026, 1, 1, 10, 0)),
        _storyStarted(
            installId: installId,
            profileOrdinal: profileOrdinal,
            at: DateTime.utc(2026, 1, 1, 10, 1),
            storyId: 's3'),
        _storyAbandoned(
            installId: installId,
            profileOrdinal: profileOrdinal,
            at: DateTime.utc(2026, 1, 1, 10, 2),
            helpInLast30s: false),

        // Session 4: help given, then abandoned within 30s. Counts.
        _sessionStart(
            installId: installId,
            profileOrdinal: profileOrdinal,
            at: DateTime.utc(2026, 1, 1, 11, 0)),
        _storyStarted(
            installId: installId,
            profileOrdinal: profileOrdinal,
            at: DateTime.utc(2026, 1, 1, 11, 1),
            storyId: 's4'),
        _helpGiven(
            installId: installId,
            profileOrdinal: profileOrdinal,
            at: DateTime.utc(2026, 1, 1, 11, 0, 50)),
        _storyAbandoned(
            installId: installId,
            profileOrdinal: profileOrdinal,
            at: DateTime.utc(2026, 1, 1, 11, 1, 10),
            helpInLast30s: true),
      ];

      // 4 total sessions, 2 end in a post-help abandonment => 0.5.
      expect(postHelpAbandonmentRate(events), 0.5);
    });

    test('EDGE: a fixture with no abandonment at all returns 0.0', () {
      final events = <AnalyticsEvent>[
        _sessionStart(
            installId: 'inst-w', profileOrdinal: 1, at: DateTime.utc(2026, 1, 1)),
        _storyStarted(
            installId: 'inst-w',
            profileOrdinal: 1,
            at: DateTime.utc(2026, 1, 1, 0, 1),
            storyId: 's1'),
        _storyCompleted(
            installId: 'inst-w',
            profileOrdinal: 1,
            at: DateTime.utc(2026, 1, 1, 0, 5),
            storyId: 's1'),
      ];
      expect(postHelpAbandonmentRate(events), 0.0);
    });

    test('EDGE: empty event stream returns 0.0, not NaN or an exception',
        () {
      expect(postHelpAbandonmentRate(<AnalyticsEvent>[]), 0.0);
    });
  });
}

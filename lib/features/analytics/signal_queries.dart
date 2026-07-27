/// The four §4 signal queries — the executable definition of the pilot's
/// instrumentation contract (PRD §4, §8 Unit 12: "The four §4 signals each
/// have a defined query over these events, written down with the schema
/// (the queries are part of this unit's deliverable, not an afterthought).
/// No pass/fail thresholds are encoded — signals are for observation").
///
/// Every function here is pure: events in, number out. There is no
/// threshold, no verdict, and no "good/bad" anywhere in this file, by
/// ratified decision.
///
/// Two definitions are shared by all four queries and are written down in
/// `docs/analytics/signals.md`:
///
/// - **Profile identity.** The payload contract is closed and carries no
///   profile id, so a profile is the `(installId, profileOrdinal)` pair —
///   the only stable per-profile key that exists in the data.
/// - **Session reconstruction.** There is no `sessionId` field either.
///   Sessions are reconstructed from `session_start` boundaries: for one
///   profile's events in time order, each `session_start` opens a session
///   that owns every subsequent event up to (not including) that profile's
///   next `session_start`.
library;

import 'event_schema.dart';
import 'events.dart';

/// The "did they come back?" horizon for signal 1 (§4.1, D7).
const Duration kD7Window = Duration(days: 7);

/// Signal 1 (§4.1, retention) — **D7 profile return rate**.
///
/// Denominator: profiles *eligible* to have returned, i.e. whose first
/// session is at least [kD7Window] before [asOf]. A profile that first
/// appeared two days ago has not failed to return — it has not had the
/// chance — so counting it would drag the rate down purely as a function
/// of when the pilot data was cut.
///
/// Numerator: eligible profiles with at least one `session_start` at or
/// after `firstSession + 7 days` (the boundary is inclusive: a return
/// exactly 7 days later counts).
///
/// Returns 0.0 for an empty denominator rather than NaN.
double d7ProfileReturnRate(
  Iterable<AnalyticsEvent> events, {
  required DateTime asOf,
  Duration window = kD7Window,
}) {
  final sessionStartsByProfile = <_ProfileKey, List<DateTime>>{};
  for (final event in events) {
    if (event.name != AnalyticsEventName.sessionStart) continue;
    sessionStartsByProfile
        .putIfAbsent(_keyOf(event), () => <DateTime>[])
        .add(event.timestamp);
  }

  var eligible = 0;
  var returned = 0;
  for (final starts in sessionStartsByProfile.values) {
    final first = starts.reduce((a, b) => a.isBefore(b) ? a : b);
    final horizon = first.add(window);
    if (asOf.isBefore(horizon)) continue; // Not yet eligible.
    eligible++;
    if (starts.any((start) => !start.isBefore(horizon))) returned++;
  }

  if (eligible == 0) return 0.0;
  return returned / eligible;
}

/// Signal 2 (§4.2, usage) — **median completed stories per reading
/// session**.
///
/// Counts `story_completed` events per reconstructed session (a session
/// with zero completions counts as a 0, not as a missing data point), then
/// takes the median across every session in the data: the middle value for
/// an odd count, the mean of the two middle values for an even count.
///
/// Returns 0.0 when there are no sessions at all.
double medianCompletedStoriesPerSession(Iterable<AnalyticsEvent> events) {
  final sessions = reconstructSessions(events);
  if (sessions.isEmpty) return 0.0;

  final counts = sessions
      .map((session) => session
          .where((event) => event.name == AnalyticsEventName.storyCompleted)
          .length)
      .toList()
    ..sort();

  final middle = counts.length ~/ 2;
  if (counts.length.isOdd) return counts[middle].toDouble();
  return (counts[middle - 1] + counts[middle]) / 2;
}

/// Signal 3 (§4.3, learning) — **help-rate trajectory on repeated
/// encounters of the same word**.
///
/// Groups `word_read` events by `(installId, profileOrdinal, wordHash)`
/// and numbers each group's events in time order: 1st encounter, 2nd
/// encounter, and so on. The returned map is keyed by that encounter
/// number and holds the fraction of groups reaching that encounter whose
/// result was `helped`.
///
/// `near_miss` deliberately does **not** count as "help needed": §5 keeps
/// near misses distinguishable precisely so "close enough" acceptances are
/// not confused with the child being stuck. Only `helped` is help.
///
/// A declining series across keys 1, 2, 3... is the learning signal. No
/// threshold on "declining enough" is encoded, by ratified decision.
Map<int, double> helpRateTrajectory(Iterable<AnalyticsEvent> events) {
  final groups = <_WordKey, List<AnalyticsEvent>>{};
  for (final event in _stableSortByTimestamp(events.toList())) {
    if (event.name != AnalyticsEventName.wordRead) continue;
    final wordHash = event.fields['wordHash'];
    if (wordHash is! String) continue;
    groups
        .putIfAbsent(
          (event.installId, event.profileOrdinal, wordHash),
          () => <AnalyticsEvent>[],
        )
        .add(event);
  }

  final totals = <int, int>{};
  final helped = <int, int>{};
  for (final encounters in groups.values) {
    for (var position = 1; position <= encounters.length; position++) {
      totals[position] = (totals[position] ?? 0) + 1;
      if (encounters[position - 1].fields['result'] ==
          WordReadResult.helped.wireValue) {
        helped[position] = (helped[position] ?? 0) + 1;
      }
    }
  }

  return <int, double>{
    for (final entry in totals.entries)
      entry.key: (helped[entry.key] ?? 0) / entry.value,
  };
}

/// Signal 4 (§4.4, frustration) — **rate of sessions ending in mid-story
/// abandonment after a stuck-word event**.
///
/// Denominator: every reconstructed session. Numerator: sessions
/// containing at least one `story_abandoned` whose `helpInLast30s` is
/// true.
///
/// The `helpInLast30s` flag is read straight off the event rather than
/// re-derived from `help_given` timestamps: `SessionTracker` computes it at
/// emission time, when it still knows the ordering, and the query must not
/// invent a second, subtly different definition of the same marker.
///
/// Returns 0.0 when there are no sessions at all.
double postHelpAbandonmentRate(Iterable<AnalyticsEvent> events) {
  final sessions = reconstructSessions(events);
  if (sessions.isEmpty) return 0.0;

  final matching = sessions
      .where((session) => session.any((event) =>
          event.name == AnalyticsEventName.storyAbandoned &&
          event.fields['helpInLast30s'] == true))
      .length;

  return matching / sessions.length;
}

/// Reconstructs sessions from `session_start` boundaries, per profile.
///
/// Returns one list of events per session, each in time order. Events that
/// precede a profile's first `session_start` belong to no session and are
/// discarded (they cannot be attributed without inventing a boundary).
List<List<AnalyticsEvent>> reconstructSessions(Iterable<AnalyticsEvent> events) {
  final byProfile = <_ProfileKey, List<AnalyticsEvent>>{};
  for (final event in events) {
    byProfile.putIfAbsent(_keyOf(event), () => <AnalyticsEvent>[]).add(event);
  }

  final sessions = <List<AnalyticsEvent>>[];
  for (final profileEvents in byProfile.values) {
    // Stable sort: ties keep their original (emission) order, which is the
    // only tie-break the data can offer.
    final ordered = _stableSortByTimestamp(profileEvents);
    List<AnalyticsEvent>? current;
    for (final event in ordered) {
      if (event.name == AnalyticsEventName.sessionStart) {
        current = <AnalyticsEvent>[];
        sessions.add(current);
      }
      current?.add(event);
    }
  }
  return sessions;
}

/// `(installId, profileOrdinal)` — the only stable per-profile key the
/// closed payload contract offers.
typedef _ProfileKey = (String installId, int profileOrdinal);

/// A profile's encounters with one specific (hashed) word.
typedef _WordKey = (String installId, int profileOrdinal, String wordHash);

_ProfileKey _keyOf(AnalyticsEvent event) =>
    (event.installId, event.profileOrdinal);

List<AnalyticsEvent> _stableSortByTimestamp(List<AnalyticsEvent> events) {
  final indexed = <(int, AnalyticsEvent)>[
    for (var i = 0; i < events.length; i++) (i, events[i]),
  ]..sort((a, b) {
      final byTime = a.$2.timestamp.compareTo(b.$2.timestamp);
      return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
    });
  return [for (final entry in indexed) entry.$2];
}

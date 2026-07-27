# The four §4 signal queries

PRD §4 instruments four signals from day one, with **no pass/fail targets
in v1** (ratified) — they exist to observe the pilot and steer iteration.
§8 Unit 12 makes the queries themselves a deliverable: "the four §4 signals
each have a defined query over these events, written down with the schema
(the queries are part of this unit's deliverable, not an afterthought)".

This file is that written-down definition. The implementation is
`lib/features/analytics/signal_queries.dart`; the executable definition —
hand-computed expected values over fixture event streams — is
`test/features/analytics/signal_queries_test.dart`.

Every query is a pure function: events in, number out. No thresholds, no
verdicts, no "good/bad" anywhere.

---

## Shared definitions

Two things every query needs are not fields in the payload, because the §5
payload contract is closed. Both are derived, and both are derived the same
way in all four queries.

### Profile identity

A **profile**, for cohort purposes, is the pair
`(installId, profileOrdinal)`.

There is no profile id in the payload and there never will be — the whole
point of the ordinal is that it is not an identifier. The install UUID plus
the ordinal is the only stable per-profile key the data offers. (Two
children on the same device are two profiles; the same child re-installing
is a new profile. Both are accepted limitations of an anonymous scheme.)

### Session reconstruction

There is no `sessionId` field either. Sessions are **reconstructed from
`session_start` boundaries**:

> For one profile's events in time order, each `session_start` opens a
> session that owns every subsequent event up to (but not including) that
> profile's next `session_start`.

Events preceding a profile's first `session_start` belong to no session and
are discarded — they cannot be attributed without inventing a boundary.
Ties in timestamp keep their original (emission) order.

This is exactly the boundary `SessionTracker` enforces at emission time: a
session ends on close, on a >120 s background, or on a profile switch, and
in every one of those cases the next session begins with a fresh
`session_start`. So reconstructing from `session_start` reproduces the
pinned §8 Unit 12 boundary rather than approximating it.

Implementation: `reconstructSessions(events)`.

---

## Signal 1 — D7 profile return rate (§4.1, retention)

> "Rate of new child profiles with a reading session 7 days after their
> first (D7 profile return)."

```dart
double d7ProfileReturnRate(
  Iterable<AnalyticsEvent> events, {
  required DateTime asOf,
  Duration window = kD7Window, // 7 days
});
```

**Definition.** Over `session_start` events only, grouped by profile:

- `firstSession(p)` = the earliest `session_start` timestamp for profile
  `p`; `horizon(p) = firstSession(p) + 7 days`.
- **Denominator — eligible profiles:** profiles where
  `asOf >= horizon(p)`. A profile that first appeared two days before the
  data cut has not *failed* to return; it has not had the chance. Counting
  it would drag the rate down purely as a function of when the pilot data
  was cut, so it is excluded entirely.
- **Numerator — returned profiles:** eligible profiles with at least one
  `session_start` at `>= horizon(p)`. The boundary is **inclusive**: a
  return exactly 7 days later counts. Sessions between day 0 and day 7 do
  not count on their own — this is D7 return, not "any repeat use".
- **Result:** `returned / eligible`, or `0.0` when no profile is eligible
  (never NaN).

**Worked example** (from the test fixture, `asOf = 2026-02-01`):

| Profile | Sessions | Eligible? | Returned? |
|---|---|---|---|
| A | Jan 1, Jan 10 | yes | yes (+9d) |
| B | Jan 5 | yes | no |
| C | Jan 28 | no (only 4 days elapsed) | — |
| D | Jan 1, Jan 6, Jan 9 | yes | yes (+8d; the +5d session alone would not count) |

Rate = 2 / 3.

---

## Signal 2 — Median completed stories per session (§4.2, usage)

> "Completed stories per reading session (median)."

```dart
double medianCompletedStoriesPerSession(Iterable<AnalyticsEvent> events);
```

**Definition.** Reconstruct sessions (above). For each session, count its
`story_completed` events — a session with zero completions counts as a
**0**, not as a missing data point; sessions where nothing was finished are
exactly what this signal needs to see. Take the median across all sessions
from all profiles: the middle value for an odd number of sessions, the mean
of the two middle values for an even number. Returns `0.0` when there are
no sessions.

Median, not mean, by §4's wording — one marathon session must not move the
number the way a mean would.

**Worked example** (from the test fixture): four reconstructed sessions
with completion counts `[2, 1, 0, 3]` → sorted `[0, 1, 2, 3]` → median
`(1 + 2) / 2` = **1.5**.

---

## Signal 3 — Help-rate trajectory on repeated word encounters (§4.3, learning)

> "Help-rate trajectory on repeated encounters of the same word (does
> needing help decline?)."

```dart
Map<int, double> helpRateTrajectory(Iterable<AnalyticsEvent> events);
```

**Definition.** Over `word_read` events only, grouped by
`(installId, profileOrdinal, wordHash)` — one group is one child's history
with one word. Sort each group by time and number its events 1, 2, 3, …
(the *encounter number*). The result maps encounter number → the fraction
of groups that reached that encounter whose result was `helped`.

- Denominators shrink with encounter number: a word a child met twice
  contributes to positions 1 and 2 only. Position 3's rate is computed over
  the groups that actually have a third encounter.
- **`near_miss` does NOT count as help needed.** Only `result == helped`
  does. §5 keeps near misses distinguishable precisely so "close enough"
  acceptances are not confused with the child being stuck; folding them in
  here would silently redefine the learning signal.
- Words are compared by their A-14 hash, which is computed on the
  *lowercased* word — so "Cat" at the start of a sentence and "cat" mid
  sentence are the same word, as they must be.
- Returns an empty map for an empty event stream.

A declining series across keys 1, 2, 3, … is the learning signal. How much
decline is "good" is deliberately not encoded.

**Worked example** (from the test fixture): three word-groups, two with
three encounters and one with two →
position 1 = 2/3, position 2 = 1/3, position 3 = 0/2 = 0.0.

---

## Signal 4 — Post-help abandonment rate (§4.4, frustration)

> "Rate of sessions ending with mid-story abandonment after a stuck-word
> event (proxy for 'recognition or scaffold frustrated the child')."

```dart
double postHelpAbandonmentRate(Iterable<AnalyticsEvent> events);
```

**Definition.** Reconstruct sessions (above).

- **Denominator:** every reconstructed session.
- **Numerator:** sessions containing at least one `story_abandoned` whose
  `helpInLast30s` is `true`.
- **Result:** `numerator / denominator`, or `0.0` when there are no
  sessions.

An abandonment with `helpInLast30s == false` does **not** count: this is
the *post-help* abandonment rate specifically — the child who was helped
and then walked away — not the general abandonment rate.

The `helpInLast30s` flag is read straight off the event rather than
re-derived from `help_given` timestamps. `SessionTracker` computes it at
emission time, when it still knows the exact ordering (including the
background-timeout case, where the session is dated at the moment of
backgrounding); re-deriving it in the query would create a second, subtly
different definition of the same marker.

**Worked example** (from the test fixture): four sessions — help then
abandon (counts), a clean completion, an abandonment with no recent help,
help then abandon (counts) → **0.5**.

---

## What is deliberately absent

- **No thresholds.** No function returns a pass/fail, and no constant in
  this feature encodes a target. §4, ratified: "no pass/fail targets in
  v1".
- **No cohorting by age, device, or geography.** None of those are in the
  payload, by design (§8 Unit 12: never collected).
- **No per-child longitudinal joins across installs.** An install UUID is
  per install; a re-install is a new profile. This is the price of
  anonymity and it is accepted.

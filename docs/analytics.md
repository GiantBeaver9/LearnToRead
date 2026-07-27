# Anonymous analytics (Unit: analytics)

COPPA-safe, anonymous, offline-first instrumentation for the four §4 pilot
signals: the §5 event vocabulary, a strict payload schema that is the
project's PII tripwire, a 30-day offline queue, session/abandonment
semantics, a build-flag kill switch, and the four signal queries.

Source: `lib/features/analytics/{events,event_schema,transport,event_queue,
session_tracker,analytics_client,signal_queries}.dart`.
PRD refs: §4 (the four signals), §5 (analytics events, payload contract),
§8 Unit 12, §9 A-5 (self-hosted endpoint), §9 A-14 (word hash).
Ticket: `docs/tickets/analytics.json`. Pinned by
`test/features/analytics/*.dart` (6 files — see each test file's header for
its exact pinned API surface). Signal definitions:
[`docs/analytics/signals.md`](analytics/signals.md).

## The privacy posture, in three rules

1. **No third-party tracker SDK, ever.** Nothing under
   `lib/features/analytics/` imports one; `pii_guard_test.dart` scans the
   tree in CI. The only non-first-party import in the feature is
   `package:crypto` (SHA-256) and `dart:io` (HTTPS + files).
2. **Word text never leaves the device.** `hashWord` (A-14: SHA-256 of the
   *lowercased* word, truncated to 16 lowercase hex chars) is the only way
   a word reaches a payload, and the schema rejects a `wordHash` that is
   not exactly 16 lowercase hex chars — so a plaintext word passed by
   mistake fails validation rather than shipping.
3. **The schema is an allowlist, not a blocklist.** `validateEventPayload`
   rejects *any* key it does not explicitly declare for that event type.
   Nobody can add `childName`, `transcript`, `deviceId`, `latitude` or an
   unplanned extra by "not being on the banned list" — it has to be
   declared here on purpose, in review.

Never collected, per §8 Unit 12: names, age (not even the age band —
that lives only in the device-local `Profile`), audio, transcripts,
IDFA/AAID or any device identifier, location.

## The event vocabulary (`events.dart`)

Exactly the twelve §5 events, no more:

`session_start`, `story_started`, `word_read`, `help_given`,
`story_completed`, `story_abandoned`, `vocab_card_opened`,
`collectible_earned`, `twister_started`, `twister_completed`,
`sound_card_played`, `sound_card_echo`.

Closed value sets: `WordReadResult` = `correct | near_miss | helped`;
`HelpTier` = `sound_out | modeled` (there is no `none` tier — `help_given`
only fires when help was actually given).

## The payload contract (`event_schema.dart`)

`AnalyticsEvent.toPayload()` produces exactly these keys and no others:

| Key | Type | Notes |
|---|---|---|
| `event` | String | one of the twelve wire names |
| `timestamp` | String | UTC ISO-8601 |
| `installId` | String | random per-install UUID — not a device id |
| `profileOrdinal` | int | 1–4 (§8 Unit 10 caps profiles at 4) |
| `levelOrdinal` | int | positive |
| `storyId` | String | present only for story-scoped events; a null id is **omitted**, never emitted as `null` |
| event-specific | — | see below |

Event-specific fields, all mandatory on their event:

| Event | Fields | `storyId` |
|---|---|---|
| `word_read` | `result` (`correct`/`near_miss`/`helped`), `wordHash` (16 lowercase hex) | required |
| `help_given` | `tier` (`sound_out`/`modeled`) | required |
| `story_abandoned` | `helpInLast30s` (bool) | required |
| `sound_card_echo` | `matched` (bool) | forbidden |
| `story_started`, `story_completed` | — | required |
| `vocab_card_opened`, `collectible_earned` | — | optional |
| `session_start`, `twister_started`, `twister_completed`, `sound_card_played` | — | forbidden |

`validateEventPayload` throws `SchemaViolation` on anything else: unknown
event name, missing/ill-typed base field, `profileOrdinal` outside 1–4,
non-positive `levelOrdinal`, non-UUID `installId`, non-ISO-8601
`timestamp`, a missing or invalid event-specific field, a `storyId` on an
event that has no story, or **any undeclared key at all**.

`Clock` (`typedef Clock = DateTime Function()`) is the injectable clock
every time-sensitive component here takes; `systemClock()` is the
production one. No component in this feature calls `DateTime.now()`
directly, which is why the 30-day expiry, the 120 s session timeout and the
30 s help window are all testable without sleeping.

## Transport (`transport.dart`)

`AnalyticsTransport.send(batch) -> TransportResult{success, failure}` is
the seam the whole feature is tested through — no test opens a socket.

`HttpsAnalyticsTransport` is the one production implementation: a thin
`dart:io` `HttpClient` adapter that POSTs `{"events": [...]}` as JSON to a
self-controlled `https://` endpoint (A-5), refuses a non-HTTPS endpoint at
construction, sends no cookies and no identifying headers, follows no
redirects, and maps any non-2xx response or any I/O failure to
`TransportResult.failure` so the batch simply stays queued. The endpoint
URL itself is **OQ-6** (blocks pilot distribution, not build).
`NullAnalyticsTransport` is the "no endpoint configured yet" default.

## Offline queue (`event_queue.dart`)

`EventQueue(transport:, clock:, storageDirectory:, batchSize: 50,
maxAge: 30 days)`.

- `enqueue(payload)` appends to `<storageDirectory>/analytics_queue.jsonl`
  and **never touches the transport**. Each line is
  `{"enqueuedAt": <iso>, "payload": {...}}`; a corrupt line (torn write) is
  skipped on read rather than poisoning every future flush.
- `pendingEvents()` returns the queued payloads, oldest first.
- `flush()` returns `({int sent, int dropped})`. It first prunes everything
  queued longer than `maxAge` (30 days, §8 Unit 12) and persists that
  pruning immediately — an expired event must never be transmitted, even if
  the flush that discovered it then fails. It then sends the survivors in
  `batchSize` batches, **stopping at the first batch the transport
  refuses**, and persists after each accepted batch, so a connectivity drop
  mid-flush costs nothing and never double-sends.

Persistence is its own small file store, deliberately *not* the Drift user
database: file ownership stays disjoint from user data, and injecting the
directory (`path_provider` in the app, a temp dir in tests) keeps it
headless-testable.

## Sessions and abandonment (`session_tracker.dart`)

Pinned semantics (§8 Unit 12, verbatim): a session starts at profile
selection and ends when the app is backgrounded for more than 120 s, is
closed, or the profile switches; `story_abandoned` fires when the reading
screen is exited after `story_started` but before `story_completed` —
including via session end — and carries whether help occurred in the
preceding 30 s.

`SessionTracker(clock:, installId:, onEvent:, backgroundTimeout: 120 s,
helpWindow: 30 s)` emits only the two events nobody else can know about
(`session_start`, `story_abandoned`); every other event is emitted by the
screen that causes it. It holds no timers — the app shell calls
`onBackground`/`onForeground`/`onClose`, navigation calls
`onReadingScreenExited`, the reading screen calls `onStoryStarted`,
`onStoryCompleted` and `onHelpGiven`.

`startSession` is also the profile switch: called while a session is open
it ends the old one first (running the same abandonment check, attributing
the abandonment to the **old** profile) and then starts the new one.

Abandonment fires at most once per started-but-uncompleted story: a direct
reading-screen exit and a later session end cannot double-fire.

For a background timeout, the session is dated at the moment of
*backgrounding*, not at the moment the app came back — that is when the
child actually stopped reading, so "helped, then walked away" still
registers as post-help frustration however long the app then sat closed.

## Kill switch (`analytics_client.dart`)

`AnalyticsClient(enabled:, queue:)` is the only surface screens use:
`track(event)` and `flush()`.

One build flag turns the whole feature off:
`--dart-define=DISABLE_ANALYTICS=true` (read as `kAnalyticsEnabled`, which
production passes to `enabled`). A disabled client short-circuits *before*
anything else happens: no schema validation, no serialization, no file
write, no transport call, and no throw even if handed a structurally
malformed event. Not "queued but never sent" — a review build leaves no
analytics residue on the device at all.

When enabled, `track` validates before queueing. A violation is a
programming error at the emitting call site, so it trips an `assert` in
debug/test builds; in release the event is dropped rather than crashing a
child's reading session — and an invalid payload is never transmitted
either way.

## Signals (`signal_queries.dart`)

Four pure functions, defined in full in
[`docs/analytics/signals.md`](analytics/signals.md):
`d7ProfileReturnRate`, `medianCompletedStoriesPerSession`,
`helpRateTrajectory`, `postHelpAbandonmentRate`. No pass/fail threshold is
encoded anywhere — ratified in §4, and the tests assert raw hand-computed
values only.

## Wiring left to other units

Event *emission* from screens belongs to the screen tickets (via
`AnalyticsClient`); wiring `SessionTracker` to app lifecycle and navigation
belongs to app-shell. This unit ships the vocabulary, the gate, the queue,
the semantics, the switch and the queries.

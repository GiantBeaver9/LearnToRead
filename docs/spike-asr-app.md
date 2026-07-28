# Unit 0 — recognition spike: implementation notes

Ticket: `docs/tickets/spike-asr-app.json`. Spec: `PRD.md` §8 Unit 0, §9 A-10,
§7 R1. Owner run instructions live in `docs/spike/README.md`; this document
covers what the code in `lib/spike/` actually does and how its pieces fit
together, for whoever picks this ticket's output back up (Unit 4's engine
adapter, or a future spike iteration).

This is disposable spike code (PRD §8 pinned design: "Code is disposable —
do not architect it into the main app"). Nothing here is imported by, or
shares state with, the main app (`lib/main.dart` and friends).

## Files

| File | Responsibility |
| --- | --- |
| `lib/spike/spike_main.dart` | Separate entrypoint (`flutter run -t lib/spike/spike_main.dart`); boots `SpikeApp`, a bare `MaterialApp` wrapping `SpikeScreen`. |
| `lib/spike/spike_screen.dart` | The UI: hardcoded sentence, mic start/stop button, live hypothesis list. Also defines `kSpikeSentence` and `spikeBiasingWordsFor`. |
| `lib/spike/spike_channel.dart` | `SpikeChannel`: Dart-side wrapper over the platform method + event channels. |
| `lib/spike/hypothesis_log.dart` | `HypothesisEvent`, `SpikeSessionLog`, `SpikeSessionLogRotator`: the decoded event model and the JSON-lines session log format. |
| `ios/Runner/SpikeSpeechHandler.swift` | iOS native handler: SFSpeechRecognizer with `contextualStrings` biasing. Self-registering, not wired into `AppDelegate.swift` (see README). |
| `android/.../SpikeSpeechHandler.kt` | Android native handler: `SpeechRecognizer` with (API 33+) biasing extras. Self-registering, not wired into `MainActivity.kt` (see README). |

## Channel contract

Both native handlers and `SpikeChannel` agree on:

- **Method channel** `SpikeChannel.methodChannelName`
  (`"learn_to_read/spike/method"`):
  - `start` — arguments `{"sentence": String, "biasingWords": [String]}`.
    Errors surface as a `PlatformException` with code `MIC_PERMISSION_DENIED`
    or `ENGINE_UNAVAILABLE`.
  - `stop` — no arguments. Errors surface with code `STOP_FAILED` if the
    engine wasn't running.
- **Event channel** `SpikeChannel.eventChannelName`
  (`"learn_to_read/spike/events"`): streams one map per hypothesis:
  - `timestampMs` (int, millis since epoch) — optional; `HypothesisEvent`
    falls back to "now" if absent.
  - `isFinal` (bool) — defaults to `false` (partial) if absent.
  - `text` (String) — defaults to `''` if absent.
  - `confidence` (num, optional) — coerced to `double`; `null` if absent.
  - `biasingWords` (`[String]`, optional) — defaults to `[]` if absent.
  - `phoneDetail` (`[Map]`, optional) — **presence of this key**, not
    whether it's non-empty, is what `HypothesisEvent.phoneDetailPresent`
    records. Neither native handler currently populates it (see below).
  - A platform-side error event (`FlutterError`/`PlatformException`)
    surfaces to Dart as a `SpikeChannelException`, never a raw
    `PlatformException`.

`SpikeChannel.start()`/`.stop()` wrap `PlatformException` into
`SpikeChannelException` the same way. See doc comments in
`lib/spike/spike_channel.dart` for why `hypotheses()` is implemented as a
`map`/`handleError` transform rather than an `async*` generator: the latter
adds a scheduling hop that (as verified against the frozen widget tests)
can delay a UI update by an extra frame relative to when the platform event
arrives.

## Hypothesis + log model (`hypothesis_log.dart`)

- `HypothesisEvent.fromChannelPayload` decodes a raw channel payload
  (tolerant of missing keys, per the contract above).
- `HypothesisEvent.toJson`/`.fromJson` define the **persisted** log record
  shape (ISO-8601 timestamp string, all fields present including nulls) —
  distinct from the wire payload shape, though the field values line up.
- `SpikeSessionLog` holds one recording session's metadata (`sentence`,
  `biasingWords`, `sessionId`, `startedAt`) plus its ordered
  `HypothesisEvent`s, and serializes to **JSON lines**: a header line
  (`{"type": "session", ...}`) followed by one line per event. This is
  deliberately not a single JSON array/object, so a log can be appended to
  or tailed without re-parsing the whole file.
- `SpikeSessionLog.fileNameFor`/`.fileName` produce a deterministic,
  filesystem-safe `.jsonl` name from `sessionId` + `startedAt`.
- `SpikeSessionLogRotator` starts a new `SpikeSessionLog` per recording
  session (`startSession`), moving the previous one (events intact) into
  `history`. `SpikeScreen` uses one rotator instance for the lifetime of an
  app run, so the owner can run every child's session in a single launch
  (see `docs/spike/README.md` §3).

## UI (`spike_screen.dart`)

`SpikeScreen` is a `StatefulWidget` that:

1. Subscribes to `SpikeChannel().hypotheses()` in `initState`, appending
   every event to a visible list (`spikeHypothesisListKey`) and, if a
   session is in progress, to the rotator's current `SpikeSessionLog`.
2. On each event appended to a session, best-effort persists that
   session's full JSON-lines log to the app's documents directory
   (`_persistLog`) — wrapped in a `try`/`catch` so a missing
   `path_provider` platform implementation (e.g. under `flutter test`, or a
   transient real-device write failure) never crashes the spike; the
   in-memory log is unaffected either way.
3. Toggles recording on `spikeRecordButtonKey` tap: starts a new rotator
   session and calls `SpikeChannel.start()`, or calls
   `SpikeChannel.stop()`. A `SpikeChannelException` during either rolls the
   `_recording` flag back and shows the error inline rather than crashing.

`spikeBiasingWordsFor(String sentence)` splits a sentence into its
contextual-biasing word list: collapses whitespace, strips trailing
sentence punctuation per word, and returns `[]` for a blank sentence. This
feeds both `SpikeChannel.start()`'s `biasingWords` argument and the
`SpikeSessionLog`'s recorded `biasingWords`.

## Known open question this spike exists to answer

Neither native handler currently sets a `phoneDetail` key on any emitted
hypothesis (see the doc comments in both `SpikeSpeechHandler.swift` and
`SpikeSpeechHandler.kt`): as implemented, `SFSpeechRecognizer` and Android's
`SpeechRecognizer` do not expose phone-level detail through their public
APIs. This means `HypothesisEvent.phoneDetailPresent` will read `false` for
every event from a real device run *as currently implemented* — which is
itself part of the answer to the Unit 0 / Unit 14 question ("is any usable
phone-level detail exposed"). If the owner's research turns up an
undocumented/private API or an alternate engine that does expose it, that
would change `emitHypothesis`/the Kotlin equivalent to populate the key
(even with an empty array, to still distinguish "supported, found nothing"
from "not supported") — but implementing that speculatively wasn't pinned
by the ticket, so it wasn't invented here.

## Testing

`test/spike/hypothesis_log_test.dart` and `test/spike/spike_channel_test.dart`
are the frozen, pinned suite covering everything Dart-side (event decoding,
JSON round-trip, log rotation, channel wire contract, UI smoke via mocked
platform channels). The native Swift/Kotlin handlers cannot be compiled or
run in this container; they are correct-by-inspection against the channel
contract above and require owner device testing (see
`docs/spike/README.md`).

One frozen widget test — "a live hypothesis pushed on the event channel
appears in the scrolling view" — could not be made to pass; see this
ticket's build report for the detailed root-cause analysis (a Flutter
`AutomatedTestWidgetsFlutterBinding.pump()` timing property, not specific
to this implementation).

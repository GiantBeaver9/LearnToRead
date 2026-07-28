# Listening Tracker (Unit 4 runtime — engine + matcher orchestration)

## Overview

The listening pipeline's runtime. `ReadingTracker` opens a consent-gated
microphone session, starts an `AsrEngine` biased with the expected sentence
words, feeds every finalized hypothesis to the `WordMatcher`
(`lib/features/listening/matcher/` — reused, never forked), and turns the
matcher's typed `MatchResult`s into the **single pinned event stream** that
Units 5–6 consume:

| Event | Emitted when |
| --- | --- |
| `WordAccepted(index)` | matcher grades `exact` (including a lookahead back-filled word) |
| `WordAcceptedNearMiss(index)` | matcher grades `nearMiss` — Unit 6's near-miss prompt path |
| `StruggleDetected(index)` | A-12(a) burst run, or A-12(b) sustained silence |
| `Silence(duration)` | the T1 window elapsed with no speech on the current word |
| `WordHelped(index, tier)` | Unit 6's scaffold reports back via `helpCompleted(tier)` |

Everything below that stream is invisible above it. Platform on-device
recognition (A-10), a substituted metered cloud engine, and the tap fallback
all produce identically shaped acceptance events, so the reading screen
(Unit 5) contains no recognition logic and no engine knowledge.

**No audio is ever stored.** The tracker's entire input surface is
`Hypothesis` *strings* and its entire output surface is `TrackerEvent`. None
of the five sources imports `dart:io` or `path_provider`, constructs a file
or directory handle, or writes bytes — `no_audio_storage_test.dart` gates
this statically over the real tree on every run, plus a dynamic check that
nothing but the five pinned event types is ever observable on `eventsStream`.

## Files

### reading_tracker.dart

```dart
ReadingTracker({
  required AsrEngine engine,
  required List<WordToken> sentence,
  required bool micConsent,
  AsrEngine? onDeviceFallbackEngine,   // A-7 downgrade ONLY, never the tap chain
  bool engineIsMetered = false,
  CloudMinuteCap? cloudMinuteCap,      // required when engineIsMetered
  Duration struggleSilenceThreshold = kStruggleT1,
  int struggleConsecutiveNonMatchingBursts = kStruggleConsecutiveNonMatchingBursts,
});

Stream<TrackerEvent> get eventsStream;  // broadcast, sync delivery
bool get isListening;                   // mic/ASR open right now
bool get isTapMode;                     // degraded to tap input
bool get micConsent;

void start();
void stop();
void pause();
void resume();
void tapCurrentWord();
void helpCompleted(HelpLevel tier);
void updateMicConsent(bool consent);
```

**Expected-text hybridization is always on.** `engine.start(biasing)` is
never called with anything but `sentence.map((w) => w.text)` — the same list
on every start, resume, and A-7 downgrade. PRD §6: "never open-ended
transcription."

**Event routing** (one matcher result → one event, in the matcher's emission
order, so a lookahead back-fill emits two separate events, current word
first):

- `MatchKind.exact` → `WordAccepted(wordIndex)`, burst counter reset to 0.
- `MatchKind.nearMiss` → `WordAcceptedNearMiss(wordIndex)`, counter reset.
- `MatchKind.reject` → **no event by itself**; increments the per-word
  consecutive non-matching burst counter (A-12a).
- Empty results (non-speech junk, punctuation-only, repeats of the last
  accepted word) feed **neither** the struggle counter **nor** the silence
  window — the matcher already classifies them as non-events.

**Struggle path (a), A-12a.** Reaching
`struggleConsecutiveNonMatchingBursts` (tuning default 2) rejects in a row on
the same word emits `StruggleDetected(index)` and resets the counter. The
counter also resets whenever the current word advances by *any* path — ASR
acceptance, near-miss, lookahead back-fill, tap, or help.

**Struggle path (b), A-12b.** See `silence_detector.dart` below.

**Fallback chain** (pinned: engine failure or mic unavailable →
tap-the-word, always available, visually discreet):

1. **No consent at start** — no engine is started at all. `engine.start()` is
   never called; the tracker begins directly in tap mode.
2. **Engine failure at start** (the mic-unavailable shape: the hypothesis
   stream throws on first access) — the failed engine is stopped for cleanup
   and the tracker enters tap mode. `start()` never throws to the caller.
3. **Engine failure mid-stream** (a fatal error on the hypothesis stream) —
   the subscription is cancelled, the engine stopped, tap mode entered. Words
   accepted before the failure stay accepted.
4. **Consent revoked mid-session** (`updateMicConsent(false)`) — the engine is
   stopped immediately and the tracker degrades to tap mode. Granting consent
   back restarts recognition at the same word, unless the tracker is in tap
   mode because the *engine* failed (a failed engine is not retried
   mid-sentence).

In every case `eventsStream` **never errors and never closes**; only
`isTapMode` flips. The discreet tap affordance itself belongs to the reading
screen (Unit 5); this unit only exposes the state and the input method.

**Mic lifecycle.** `isListening` is the design system's listening-indicator
state: true only between `start()`/`resume()` and `pause()`/`stop()`, with
consent, on a healthy engine. `pause()` (narration playing, vocab card open)
stops the engine and disarms the silence countdown; `resume()` starts the
engine again with the same biasing context, at the same word, with a **fresh**
silence window — paused time is never counted as silence.

**A-7 silent downgrade.** With `engineIsMetered: true`, listening time accrues
against the injected `CloudMinuteCap` on a 1-second internal tick while the
mic is open. At the cap the tracker stops the metered engine and starts
`onDeviceFallbackEngine` with the same biasing context — no error, no stream
interruption, nothing user-visible (R2). This is an *engine swap*, distinct
from the tap fallback; if no on-device engine was supplied, the tap fallback
is the last link. With `engineIsMetered: false` the cap is never touched even
if one is supplied.

### silence_detector.dart

```dart
SilenceDetector({required Duration threshold, required void Function(Duration) onThreshold});
Duration get threshold;  bool get isRunning;
void start();  void noteActivity();  void stop();
```

A standalone, single-shot countdown — the whole of A-12(b). `onThreshold`
fires exactly once per `start()`/`noteActivity()` cycle with
`duration == threshold`; it never repeats on its own. The tracker arms it on
`start()`/`resume()` and re-arms it on every **non-empty** matcher result
(accept, near-miss, reject, or back-fill — i.e. any burst that carried real
speech, matching or not) and on every word advance. It is disarmed while
paused, after `stop()`, and once the sentence is complete.

When it fires the tracker emits, in this pinned order,
`Silence(duration: T1)` **then** `StruggleDetected(index: currentIndex)`.

Timing is `Timer`-based with no wall-clock sleeps anywhere, so `fake_async`
drives the whole pipeline deterministically.

### tap_engine.dart

```dart
class TapEngine implements AsrEngine {
  List<String>? get recordedBiasingContext;
  int get stopCallCount;
  void tapWord(String word);   // pushes an exact-text Hypothesis
}
```

The **production** tap fallback, not a test stub. A tap is an `AsrEngine`
hypothesis like any other, so it travels the identical matcher path and
produces a `WordAccepted` that is indistinguishable in shape from an ASR
acceptance — which is what makes "engine choice is invisible above this
interface" literally true rather than aspirational.

Delivery is synchronous (a `sync` broadcast stream) so a tap resolves in the
same turn as the gesture. The tracker subscribes to its own `TapEngine` for
the **whole** session, not just after a fallback: `tapCurrentWord()` works in
every mode, including while the ASR engine is healthy and listening, and is a
silent no-op once the sentence is complete or after `stop()`.

### cloud_minute_cap.dart

```dart
const int kCloudDailyCapMinutes = 20;   // A-7

class CloudMinuteCap {
  CloudMinuteCap({int dailyCapMinutes = kCloudDailyCapMinutes});
  int get dailyCapMinutes;  Duration get dailyCap;
  Duration get usedToday;   bool get isCapReached;   // usedToday >= dailyCap
  void recordUsage(Duration elapsed);  void reset();
}
```

A pure in-memory tally: no clock, no storage, no engine. The cap boundary is
inclusive, so the downgrade happens *at* 20 minutes rather than one tick past
it.

**Not pinned by this unit:** day-boundary persistence — exactly when a "new
day" begins and how the tally survives an app restart. `reset()` is the
mechanism; whichever unit wires a `CloudMinuteCap` to profile storage owns
its trigger.

### mic_session.dart

```dart
class MicSession {
  MicSession({required bool consentGranted});
  bool get consentGranted;  bool get isOpen;  bool get canOpen;
  bool open();  void close();  void updateConsent(bool granted);
}
```

The tracker's bookkeeping of *may we open the mic* and *is it open right now*
— deliberately platform-free (acquiring the OS microphone is the engine's job
behind the `AsrEngine` seam). Consent (Unit 10) takes effect immediately: it
is read at session start and again on every change, and revoking it closes
the session in the same call. `isOpen` is surfaced as
`ReadingTracker.isListening`, which is exactly what the design system's small
non-alarming listening indicator renders.

## App-shell wiring, and the T1 relationship with stuck-word-scaffold

The tracker owns **T1 only**. The stuck-word scaffold (Unit 6) owns T2 and
every help tier. The handoff is one-directional plus one callback:

```
ReadingTracker ──eventsStream──▶ StuckWordScaffold ──▶ reading screen
       ▲                                  │
       └──────── helpCompleted(tier) ─────┘
```

- **T1 (`kStruggleT1`, this unit)** is a *detection* window: how long the
  current word may go without matching speech before the tracker declares a
  struggle. It is injected as `ReadingTracker.struggleSilenceThreshold` and
  defaults to the tuning file, so the app shell normally passes nothing.
- **T2 (`kTier2WaitT2`, Unit 6)** is an *escalation* window that starts
  **after** `StruggleDetected` arrives — how long tier-1 sound-out help runs
  before tier-2 modelling engages. The two timers are deliberately separate
  and never share a `Timer`: the tracker knows nothing about help tiers, and
  the scaffold knows nothing about hypotheses.
- Both constants live in `lib/domain/tuning.dart`. A pilot tuning pass is a
  single-file change; neither value is ever hardcoded at a call site.
- When the scaffold finishes helping a word it calls back into
  `helpCompleted(tier)`. The tracker emits `WordHelped(index, tier)`, advances
  exactly one word, resets the struggle counter, and re-arms T1 — so the
  matcher and the scaffold can never drift out of sync on the current word.
  The helped word turns green like any other; the fact is recorded invisibly
  in `WordHelpRecord`.
- A near-miss emits `WordAcceptedNearMiss` and **nothing else** — no tier
  escalates from a near-miss. The warm re-model prompt is entirely the
  scaffold's.
- Mic ownership follows the screen: the shell constructs a tracker when the
  reading screen opens and calls `stop()` when it closes, and calls
  `pause()`/`resume()` around narration playback and vocabulary cards. The mic
  is never open on navigation or parent screens.

## Design note: synchronous delivery of engine hypotheses

The acceptance criterion "engine choice is invisible above this interface"
is pinned as an *observational* equivalence: the same scripted read must
produce the same events whether it arrives by tap or from an engine. Tap
delivery is synchronous, but an engine whose hypothesis stream is generated
at subscription time would otherwise only deliver on a later microtask,
making the ASR path observably later than the tap path for the same input.

So the engine subscription is created inside a forked `Zone` that, for the
duration of that subscribe call, collects scheduled microtasks into a local
queue and drains them in place (bounded, then handed back to the real queue).
Outside that window the zone delegates to its parent unchanged, so ordinary
asynchronous engines — platform channels, broadcast controllers — behave
exactly as they always did, `fake_async` still owns the clock, and no timing
guarantee is weakened. It is a *widening* of when events may arrive (as early
as possible), never a narrowing.

## Testing

The frozen suite is `test/features/listening/tracker/` (6 files):
`reading_tracker_test.dart` (canonical API), `fixture_contract_test.dart`,
`fallback_test.dart`, `silence_detector_test.dart`, `cloud_cap_test.dart`,
`no_audio_storage_test.dart`. All timing is `fake_async`; there is no real
engine in the container, so every engine interaction goes through
`FakeAsrEngine`, hand-rolled doubles, or `TapEngine`.

**Boundary coverage worth knowing about:** the A-12b threshold is tested at
3.9 s (must not fire) and 4.1 s (must already have fired) against the 4 s
default, both for the detector alone and end-to-end through the tracker; the
single-shot property is tested by staying silent for a further 3×T1.

## Post-POC backlog (recorded, per PRD §8 Unit 4)

- **Noise / cross-talk fixtures.** POC fixtures are happy-path only (quiet
  room, one child, cooperative reading). Noise robustness, accents, and
  cross-talk are explicitly deferred.
- **Contract tests against real recorded child audio.** PRD §8 Unit 4's
  "small recorded fixture set" is realized here headlessly as scripted
  hypothesis fixtures; running the same scenarios against real recorded
  children is an owner-run `[DEVICE]` item tracked with the other device
  items. The PRD item is narrowed, not dropped.
- **Cloud-minute-cap day boundary.** See `cloud_minute_cap.dart` above —
  `reset()` exists, its calendar trigger and persistence are another unit's.
- **`platform-asr-adapter`** plugs into this tracker later with no change
  here; that is precisely the acceptance of the `AsrEngine` interface.

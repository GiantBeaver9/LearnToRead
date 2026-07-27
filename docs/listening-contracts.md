# Listening Contracts (Unit 4)

## Overview

The listening pipeline's contract layer defines the engine-agnostic ASR interface, tracker event stream types, help-state contract, and fake implementations for testing.

This layer abstracts over:
- **Engine choice**: on-device (A-10), cloud, or tap fallback — all expose the same interface
- **Hypothesis delivery**: word-level and optional phone-level hypotheses
- **Event stream**: a single typed stream consumed by Units 5–6 for reading screen and stuck-word help

No audio is ever stored; the interface exposes only hypotheses and events.

## Files

### asr_engine.dart

Defines the engine-agnostic ASR interface and hypothesis type.

**Hypothesis**: Carries word hypotheses (ranked by confidence) and optional phone-level detail.
- `wordHypotheses: List<String>` — candidate words (e.g., `['cat', 'can', 'car']`)
- `phoneHypotheses: List<String>?` — aligned phoneme sequence, null if engine does not provide phones

**AsrEngine**: Abstract interface every ASR engine implements.
- `start(List<String> biasingContext)` — activates listening with contextual word biasing
- `stop()` — ends listening
- `Stream<Hypothesis> hypothesesStream` — emits hypotheses during active listening

The biasing context (expected words from the sentence) lets the engine focus on relevant hypotheses; the matching layer (Unit 5 word-matcher) scores them against the known next word.

### tracker_events.dart

Defines the single event stream contract consumed by Units 5–6.

**TrackerEvent** base class for all event types:
- `WordAccepted(int index)` — word read correctly (exact or near-miss promoted)
- `WordAcceptedNearMiss(int index)` — close-enough phonetic match (e.g., "gat" for "cat"), triggers near-miss prompt
- `StruggleDetected(int index)` — two consecutive failed bursts or silence, triggers Tier 1 help
- `Silence(Duration duration)` — sustained silence detected
- `WordHelped(int index, HelpLevel tier)` — word received Tier 1 (soundOut) or Tier 2 (modeled) help, emitted by scaffold controller

Engine choice is invisible above this interface; these events abstract over on-device, cloud, and tap-fallback flows.

### help_state.dart

Shared contract for help rendering and production.

**HelpState**: Captures current help tier and grapheme highlight index.
- `currentHelpTier: HelpLevel` — active help level (none, soundOut, modeled)
- `highlightedGraphemeIndex: int` — during Tier 1 sound-out, index into the word's `graphemePhonemeMap` of the grapheme cluster being highlighted (digraphs highlight as one unit)

Consumed by the reading screen to render help UI; produced by the stuck-word scaffold.

### fake_asr_engine.dart

**FakeAsrEngine**: Scripted hypothesis playback for testing.

Constructor:
- `script: List<Hypothesis>` — predefined hypotheses to emit
- `delayBetweenHypotheses: Duration` — delay before each emission (default: zero)
- `shouldFail: bool` — if true, hypotheses stream throws (simulates engine unavailability)

Features:
- Records `recordedBiasingContext` from the most recent `start()` call for test assertions
- Works with or without fake_async for deterministic timing
- Enables tests to verify expected-text hybridization and handle engine failure paths

Example:
```dart
final engine = FakeAsrEngine(
  script: [
    Hypothesis(wordHypotheses: ['cat'], phoneHypotheses: ['K', 'AE', 'T']),
    Hypothesis(wordHypotheses: ['can', 'cat'], phoneHypotheses: null),
  ],
  delayBetweenHypotheses: Duration(milliseconds: 100),
);

engine.start(['cat', 'sat', 'on']);
final hyps = await engine.hypothesesStream.take(2).toList();
expect(engine.recordedBiasingContext, ['cat', 'sat', 'on']);
```

### fake_reading_tracker.dart

**FakeReadingTracker**: Scripted tracker event stream for testing.

Constructor:
- `script: List<TrackerEvent>` — predefined events to emit
- `delayBetweenEvents: Duration` — delay before each emission (default: zero)

Features:
- Emits events from the script in order
- Supports standard Stream operations: `take()`, `where()`, `forEach()`, etc.
- No matcher or engine involved; pure scripted replay for Units 5–6–14 tests

Example:
```dart
final tracker = FakeReadingTracker(
  script: [
    WordAccepted(index: 0),
    WordAccepted(index: 1),
    StruggleDetected(index: 2),
    WordHelped(index: 2, tier: HelpLevel.soundOut),
    WordAccepted(index: 2),
  ],
);

// Reading screen consumes the stream and updates UI
final events = await tracker.eventsStream.take(3).toList();
```

## Design Rationale

**Pure Dart, no Flutter except foundation imports**: Contract types are domain models with no UI dependencies, enabling portable testing and reuse across platforms.

**Equatable and printable**: All types implement `==`, `hashCode`, and `toString()` for reliable test assertions and debugging.

**Engine abstraction**: Every ASR engine (on-device, cloud, fallback) exposes the same `start/stop/hypothesesStream` interface. Unit 4's matching layer consumes hypotheses, never directly calling the engine.

**Single event stream**: Units 5–6 consume one typed stream of tracker events (word accepted, struggle, silence, help). Engine choice is transparent above this interface.

**Phone-level detail optional**: Engines providing only word hypotheses set `phoneHypotheses: null`; Unit 14's sound mode approximates downstream by phonetic distance if needed (per PRD Unit 0 spike validation).

**Fakes enable offline testing**: FakeAsrEngine and FakeReadingTracker let Unit 5 (reading screen), Unit 6 (stuck-word scaffold), and Unit 14 (twisters) tests run without the full matching pipeline or microphone, providing fast feedback and deterministic timing.

## Test Coverage

**contracts_test.dart** (67 tests):
- Hypothesis construction, equality, printability
- AsrEngine interface contract
- TrackerEvent types (wordAccepted, struggle, silence, helped) with boundary and edge cases
- HelpState equality, highlight index semantics, digraph handling
- Type-safety and polymorphism (all events inherit TrackerEvent)

**fake_engine_test.dart** (48 tests):
- FakeAsrEngine construction, lifecycle (start/stop)
- Biasing context recording and assertion
- Hypothesis stream emission with configurable delays
- Error injection (shouldFail flag simulating engine unavailability)
- Large scripts and many hypotheses (scalability)
- FakeReadingTracker construction, event emission, stream consumption patterns
- Integration: both fakes working together

All tests are pure Dart (no UI); tests pass with or without fake_async timing simulation.

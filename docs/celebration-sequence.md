# Celebration sequence (Unit 8)

## Overview

`CelebrationController` drives the post-completion payoff: the child
finishes reading a story and the app plays the celebration animation +
audio, persists the completion (and, on a first completion, the
collectible), then flies the collectible to the collection icon before
returning to the map with the next story highlighted (PRD §8 Unit 8).

This ticket delivers the controller: pure logic + fake-driven tests, fully
headless. No real Rive assets or audio files exist in this container --
`FakeStoryStage` (`lib/design/fake_rive_stage.dart`) and `FakeAudioService`
(`lib/features/audio/fake_audio_service.dart`) stand in throughout, and all
timing is driven by `package:fake_async`. The real 60 fps device
measurement (PRD §8 Unit 8 acceptance, A-6) and the widget/screen that
wires this controller into the reading flow's UI are out of this ticket's
scope.

## Files

### `lib/features/celebration/celebration_controller.dart`

`CelebrationController` -- runs one story's celebration end to end.

- Constructor takes the `StoryStage` to drive, the `AudioService` to play
  through, the `CollectionDao`/`StoryProgressDao` to persist to, a
  `CelebrationLineRotator`, the per-install UUID, an `onAnalyticsEvent`
  callback, an `onFinished` callback, and three overridable durations
  (`celebrationDuration`, `skipUnlockDelay`, `sequenceBudget`, defaulting to
  the `kCelebration*` constants below). Throws `ArgumentError` at
  construction if `celebrationDuration + DesignTokens.collectibleFlightDuration`
  would exceed `sequenceBudget` -- the PRD's "total post-completion
  sequence <= 10 s" is therefore a structural guarantee, not a runtime
  race.
- `bool get isRunning`.
- `Future<void> run({required Story story, required String profileId,
  required int profileOrdinal, required int levelOrdinal, String?
  nextStoryId})` -- see "Sequence" below.
- `void skip()` -- ends the animation-hold phase early once
  `skipUnlockDelay` has elapsed; a no-op before that, before the hold
  phase has started, or after it has already ended. Safe to call any
  number of times.

`CelebrationLineRotator` -- dispenses the fixed recorded celebration-line
set (PRD: "rotated randomly so it doesn't repeat verbatim every story").
Implemented as a **shuffle-cycle**: the set is Fisher-Yates shuffled
exactly once, at construction, using the injected `int Function(int
exclusiveMax) nextInt`; every call to `next()` thereafter just walks that
fixed order and wraps around, replaying the same permutation every full
cycle. This guarantees no two consecutive dispenses repeat (for two or
more lines) without ever consulting the RNG again after construction. A
single-line set never consults `nextInt` at all (nothing to shuffle); an
empty set throws `ArgumentError` at construction.

`CelebrationResult` -- the value handed to `onFinished`: `completedStoryId`,
the nullable `nextStoryId` (the return-navigation payload's next-story
highlight), `skipped`, and `isFirstCompletion`.

Constants: `kCelebrationSkipUnlockDelay` (2 s), `kCelebrationSequenceBudget`
(10 s), `kCelebrationDefaultAnimationDuration` (4 s).

## Sequence

`run()`'s synchronous prefix -- everything up to its first `await` --
executes in the same event-loop turn as the call, with zero fake-clock
time elapsed (asserted directly by the suite; the headless proxy for "no
synchronous work over a frame budget during the transition"):

1. `stage.trigger(StoryStageInput.celebrate)`.
2. If the story has narration -- its first page's first sentence carries a
   non-null `narrationAudioRef` (the domain model's own pinned shape for
   "has narration": sentence-format stories have exactly one page with one
   sentence) -- play it on `AudioChannel.narration`. The controller reads
   this straight off the `Story`; it is never given a `Level` and never
   inspects `Level.format`/`Level.narrationEnabled`.
3. Play `story.celebrationAudioRef` (the sting) on `AudioChannel.celebration`.
4. Play `lineRotator.next()` (the rotated voice line) on
   `AudioChannel.celebration`.

Then, fully awaited *before* the animation-hold phase begins (and
therefore before `skip()` can even be actionable, since `skipUnlockDelay`
is always >= the time these awaits take):

5. Look up existing `StoryProgress` to determine `isFirstCompletion`, then
   call `StoryProgressDao.recordCompletion` (increments `timesRead`;
   preserves the original `completedAt` on a replay). On first completion
   only, call `CollectionDao.grantCollectible`.
6. Emit `story_completed` (always) and `collectible_earned` (iff first
   completion) via `onAnalyticsEvent`, both carrying `storyId`.

Because persistence and analytics happen before the hold phase, the
collectible is durably granted before the skip window even opens --
skipping can never lose it, including on the very first frame.

7. **Animation-hold phase**: waits for `celebrationDuration` to elapse
   naturally, or for an accepted `skip()` (only actionable once
   `skipUnlockDelay` has elapsed) to end it early.
8. `stage.trigger(StoryStageInput.collect)`.
9. Waits `DesignTokens.collectibleFlightDuration` (Unit 1's collectible-flight
   motion token).
10. `onFinished(CelebrationResult(...))` fires exactly once.

## Replay behavior

Re-reading an already-completed story runs the identical sequence --
`celebrate` and `collect` both fire, narration/sting/line all play, the
full animation-hold + flight timing applies -- but `isFirstCompletion` is
`false`: no second collectible is granted (idempotent over
`CollectionDao.grantCollectible`'s primary-key semantics),
`collectible_earned` is not emitted, and `StoryProgress.completedAt` is
preserved from the original completion while `timesRead` increments.
`story_completed` still fires on every read, including replays.

## What is deliberately not here

- `lib/features/celebration/celebration_view.dart` and
  `lib/features/celebration/collectible_flight.dart` -- listed in the
  ticket's file list, but no frozen test in `test/features/celebration/`
  pins any API surface for a widget or a flight-animation type, and the
  reading-screen integration that would host them is a separate ticket.
  Building them now would mean inventing an unpinned, untested API
  surface, so this ticket delivers the controller only; the widget layer
  is a later ticket's job once its own tests pin the shape.
- No real Rive rendering and no real audio playback -- both are
  owner/device-verified integration concerns layered on top of
  `RiveStoryStage` (`lib/design/rive_stage.dart`) and the real
  `AudioService` adapter, neither of which this ticket touches.
- No Rive-input validation -- a story pack whose artboard lacks
  `idle`/`celebrate`/`collect` fails Unit 3's pack-build linter, not this
  runtime controller (PRD §8 Unit 8: "A story whose Rive file lacks the
  required inputs fails pack validation, not runtime").

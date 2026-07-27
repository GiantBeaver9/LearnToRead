# Progress Map + Collection Scene — Behavior Documentation

**Unit:** 9 (Progress map / child home + collection scene), touching Unit 2 (rolling window), Unit 14 (tongue-twister boosters)
**References:** PRD §8 Unit 9, §8 Unit 2, §8 Unit 14, §5 StoryProgress / CollectionState / Collectible
**Implementation:** `lib/features/map/map_node.dart`, `lib/features/map/trail_layout.dart`, `lib/features/map/progress_map_screen.dart`, `lib/features/collection/scene_slots.dart`, `lib/features/collection/collection_screen.dart`

## Overview

Two per-profile screens:

- **`ProgressMapScreen`** — the child's home screen: an illustrated trail of every authored story in the reading level path, interleaved with tongue-twister booster nodes.
- **`CollectionScreen`** — one persistent illustrated scene (e.g. a garden) where every collectible this profile has earned lives at its authored `sceneSlot`.

Both screens are pure `StatelessWidget`s driven entirely by data their caller supplies (`Profile`, `StoryProgress` map, `CollectionState`, catalogs). Neither screen computes progress, unlocks, or the rolling window itself — that is phonics-engine's job (Unit 2) and local-storage's job (persistence); this ticket only renders what it is handed and reports taps back via callbacks.

## `MapNode` (`map_node.dart`)

The single visual unit rendered on the trail, for both a story stepping-stone and a twister booster (`MapNodeKind.story` / `MapNodeKind.twisterBooster`).

- **`visualState`** (`asleep` / `awake` / `completed`) is supplied by the caller, never computed by `MapNode` itself.
- **`isTappable`** is `true` unless `visualState == asleep`.
- **Tap gating is enforced inside `MapNode`, not just by its caller**: the outer `GestureDetector`'s `onTap` is wired to the widget's own `onTap` only while `isTappable`; an asleep node swallows a tap even when a non-null `onTap` was supplied. This makes "tapping an asleep story does nothing" hold structurally, independent of what any screen passes in.
- **Structural markers** (present/absent by state, the headless proxy for the "distinct visual treatment" a pixel golden would otherwise pin):
  - `map-node-thumbnail-<id>` — completed only
  - `map-node-awake-animation-<id>` — awake only
  - `map-node-asleep-marker-<id>` — asleep only
  - `map-node-twister-badge-<id>` — twister-booster kind only
  - `map-node-highlight-<id>` — `highlighted == true` only
- **Visual placeholder treatment**: a circular token-colored node (twister boosters use `DesignTokens.surfaceBackground`, stories use `DesignTokens.readingBackground`) with a token-ink icon; an awake node is wrapped in `_GentlePulse`, a small looping `ScaleTransition` standing in for "gently animated" until the owner-commissioned trail animation lands (PRD §10 OQ-4). A twister booster additionally renders a small badge dot in the corner. A highlighted node gets a thicker accent-colored ring. All of this is placeholder painting behind the real illustration — no golden pins these pixels (see the frozen suite's `[DEVICE]`-skipped goldens).

## `buildTrail` (`trail_layout.dart`)

Interleaves tongue-twister boosters into the story trail. The PRD only pins a density guideline ("~1 per 3 stories"); this ticket pins the exact placement rule:

> Each twister is inserted immediately after the **last** story entry sharing its `levelId`, scanning `stories` in authored order. A twister whose `levelId` matches no story in `stories` is appended at the trail's end rather than dropped. Twisters sharing a `levelId` preserve their relative `twisters` input order.

Implementation: one pass over `stories` tracking, per `levelId`, the index of that level's last story; twisters for a level are spliced in immediately after that index is reached. Any `levelId` never matched during that pass is treated as orphaned and appended at the end, in original `twisters` order.

## `ProgressMapScreen` (`progress_map_screen.dart`)

- **Per-story visual state** is derived *solely* from `storyProgress[story.id]?.status`:
  - absent row or `StoryStatus.locked` → `asleep`
  - `StoryStatus.available` → `awake`
  - `StoryStatus.completed` → `completed`

  This is the screen's one piece of business logic, and it is intentionally this dumb: the rolling window itself is phonics-engine's `storiesFor` decision, already baked into `status` by the time it reaches this widget. The screen never recomputes it.
- **Tap routing**: a story node's `onTap` calls `onReReadStory(id)` when completed, `onStartStory(id)` when awake, and is `null` when asleep (belt-and-suspenders — `MapNode` would swallow it anyway).
- **Twister nodes**: `visualState` is `awake` iff `unlockedTwisterLevelIds.contains(twister.levelId)`, else `asleep`. There is no `completed` state for a twister — unlocked twisters are always replayable, and tapping one always calls `onOpenTwister(id)` (never a different callback based on completion count).
- **Highlight**: exactly the story node whose id equals `highlightedStoryId` renders `highlighted: true`. `null`, or an id absent from `stories`, highlights nothing and never throws. Twister nodes are never highlighted.
- **Layout**: a vertical, scrollable `ListView` (so an arbitrarily long trail never overflows) with nodes alternating left/right alignment, giving a winding-trail feel with only token-styled placeholder shapes — the real illustrated trail is an owner-commissioned asset (PRD §10 OQ-4).
- **Per-profile only**: the widget's API takes exactly one `Profile`; there is no multi-profile input, so no comparative/leaderboard surface can exist to render.

## `SceneSlotLayout` (`scene_slots.dart`)

Pure layout math for the collection scene's `sceneSlot` addressing. PRD §5 leaves the exact `Collectible.sceneSlot` string format to content authoring; this ticket pins it as `"row:col"` (both non-negative integers):

- `parseSlot` — parses `"row:col"`; throws `FormatException` for a missing separator, non-numeric parts, or a negative coordinate.
- `offsetForSlot` — `Offset(col * cellWidth, row * cellHeight)`.
- `canvasSizeFor` — the smallest canvas that fits every given slot without clipping: `((maxCol + 1) * cellWidth, (maxRow + 1) * cellHeight)`, or `Size.zero` for an empty slot set. Growth is unbounded in both directions as more slots are authored — there is no fixed cap.

## `CollectionScreen` (`collection_screen.dart`)

- **Filtering is the screen's job**: callers pass the *full* authored `collectibles` catalog plus this profile's `CollectionState`; the screen itself intersects `collectionState.earnedCollectibles` against the catalog. A collectible absent from `earnedCollectibles` renders no node at all, even though it's present in the catalog — callers never pre-filter.
- **Poke reaction**: tapping a collectible's node calls `stageFor(collectible.id).trigger(StoryStageInput.collect)` on *that* collectible's own `StoryStage` only; every other collectible's stage is untouched. Each tap fires its own `collect` trigger (no debouncing/dedup — a collectible can be poked repeatedly for its reaction).
- **Layout**: a positioned `Stack` sized to `SceneSlotLayout.canvasSizeFor(...)`, inside a vertically scrollable `SingleChildScrollView` — the scene's extension direction is scrollable/vertical (rows grow with more authored packs), pinned by the ticket's `pinned_design` and matching `canvasSizeFor`'s row-growth doc comment. This is what lets a beyond-launch collectible count (tested at 40) render without overflow: the canvas simply grows taller and scrolls.
- **Per-profile only**: same structural argument as `ProgressMapScreen` — the widget's API has no multi-profile input.

## Design Token Usage

All colors, fonts, and spacing in every file above are drawn from `DesignTokens` (`wordUnreadInk`, `wordVocabBlue`, `screenBackground`, `surfaceBackground`, `readingBackground`, `displayFontFamily`, and the `spacing*` scale). No inline `Color(0x...)` literal, `Colors.*` reference, or inline `TextStyle(fontFamily: ...)` literal appears anywhere under `lib/features/map/` or `lib/features/collection/` (enforced by `test/design/token_lint_test.dart`).

## What Is Deliberately Out of Scope Here

- **The rolling window itself** (which 3 stories are "available") is phonics-engine's `storiesFor`; this ticket only renders the `status` it already decided.
- **Granting collectibles** (`CollectionDao.grantCollectible`, "adds exactly one collectible on first completion, none on re-read") is local-storage's DAO contract; this ticket only renders whatever `CollectionState` it's handed.
- **The twister flow screen** (what happens after `onOpenTwister` fires) belongs to twister-flow's ticket — `ProgressMapScreen` only exposes the navigation callback.
- **Real trail/scene illustrations** are owner-commissioned (PRD §10 OQ-4); every file here paints token-styled placeholder shapes behind that future artwork without touching structural markers or API shape, so the real art can drop in later as a pure asset swap.

## Testing Strategy

The frozen suite (`test/features/map/`, `test/features/collection/`, ~85 tests) is exercised end-to-end, including:

- `MapNode` state/tap-gating/structural-marker coverage (`map_states_test.dart`).
- `ProgressMapScreen` StoryProgress-to-visual-state mapping, tap routing, and return-navigation highlight, including a real in-memory Drift round-trip through `StoryProgressDao` (`progress_map_test.dart`).
- `buildTrail`'s interleave rule plus booster-node rendering/tap-navigation on the screen (`twister_nodes_test.dart`).
- `SceneSlotLayout` parsing/offset/canvas math, `CollectionScreen` earned/unearned filtering and per-instance poke isolation, including a real in-memory Drift round-trip through `CollectionDao` (`collection_test.dart`).
- Profile-switch isolation for both screens against the real DB, with an explicit "no other profile's id renders anywhere" assertion (`profile_switch_test.dart`).
- All four layout classes for both screens, including a 40-collectible beyond-launch fixture, asserting no render/overflow exception (`layout_classes_test.dart`); the corresponding pixel goldens are `[DEVICE]`-skip-marked and routed to the owner pending real illustration assets.

## References

- **PRD §8 Unit 9:** Progress map + collection scene overview
- **PRD §8 Unit 2:** Rolling window / story availability (consumed, not recomputed, here)
- **PRD §8 Unit 14:** Tongue-twister boosters
- **PRD §5:** `StoryProgress`, `CollectionState`, `Collectible` domain shapes
- **PRD §10 OQ-4:** Real trail/scene illustration sign-off (owner task)

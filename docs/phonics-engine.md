# Phonics engine (Unit: phonics-engine)

Scope & sequence loading, age-band placement, and rolling-window-of-3 story
unlocking. Pure Dart, headless, no I/O beyond a JSON-text-in / typed-data-out
loader — no Flutter imports, no persistence.

Source: `lib/domain/phonics/scope_sequence_loader.dart`,
`lib/domain/phonics/placement.dart`, `lib/domain/phonics/phonics_engine.dart`.
PRD refs: §8 Unit 2, §5 `PhonicsSkill`/`Level`/`Profile`/`StoryProgress`.

## Scope & sequence loader (`scope_sequence_loader.dart`)

`loadPhonicsContent(String jsonText) -> PhonicsContent` parses a
scope-&-sequence JSON document into typed data. This is deliberately the
*only* place in this unit that touches JSON — the real scope & sequence
table (which skills at which level, heart-word lists) is authored content
owned by the content pipeline (Unit 3 / OQ-5); this loader only pins the
JSON *shape*, not the table's contents. `test/domain/phonics/fixtures/` ships
two structurally different fixtures (`fixture_sequence.json`,
`alternate_sequence.json`) precisely to prove the engine is data-driven:
swapping the fixture changes behavior with zero code changes.

**JSON shape:**
```json
{
  "levels": [
    {
      "id": "level-1", "ordinal": 1,
      "format": "sentence | multiSentence | paragraph",
      "vocabEnabled": false,
      "heartWords": ["the", "a"],
      "skills": [
        {"id": "skill-cvc-short-a", "name": "CVC short a", "sequenceOrder": 1, "introducesGraphemes": ["a"]}
      ]
    }
  ],
  "stories": [
    {"id": "story-1-1", "levelId": "level-1"}
  ]
}
```

**Types:**
- `StoryRef { id, levelId }` — a lightweight, value-equal reference to an
  authored `Story`. The phonics engine only needs identity, order, and level
  membership, never the full `Story` (pages, audio refs, etc — the
  content-pack loader's concern), hence a narrower type than
  `content_models.Story`.
- `PhonicsContent { levels: [Level], heartWordsByLevelId: {levelId: [String]}, stories: [StoryRef] }`.

**Parsing contract:**
- `levels` is sorted ascending by `ordinal` regardless of raw JSON array
  order (defensive).
- `stories` preserves the *exact* order of the JSON `"stories"` array — that
  order **is** the global authored order the rolling-window unlock rule
  trusts (PRD: "the next 3 uncompleted stories in global authored order
  (which is level-ordered)"). It is never re-derived or re-sorted from level
  ordinals.
- `heartWordsByLevelId` maps every level id to its `"heartWords"` list, or
  `[]` if the key is absent.
- Throws `FormatException` for: input that isn't valid JSON at all; a
  missing `"levels"` or `"stories"` root key; a level/skill/story object
  missing a required field; an unrecognized `"format"` string; or a story
  whose `"levelId"` matches no level's `"id"`.

## Placement (`placement.dart`)

```dart
String placeStartingLevel({
  required AgeBand ageBand,
  required PhonicsContent content,
  String? parentOverrideLevelId,
})
```

Picks the starting `Level.id` for a profile (PRD: "Profile start level from
age band: 5-6 -> level 1; 7-8 -> first multiSentence level; 9-10 -> first
paragraph level. Parent can override in parent corner.").

- `parentOverrideLevelId`, when non-null (including the empty string), wins
  outright over `ageBand`: if it matches a level id in `content.levels`, it
  is returned verbatim; otherwise throws `ArgumentError`.
- Else, by `ageBand` over `content.levels` (ascending ordinal, as guaranteed
  by the loader):
  - `AgeBand.fiveToSix` → `content.levels.first.id`.
  - `AgeBand.sevenToEight` → the first level with
    `format == LevelFormat.multiSentence`; `StateError` if none exists.
  - `AgeBand.nineToTen` → the first level with
    `format == LevelFormat.paragraph`; `StateError` if none exists.
- Throws `StateError` if `content.levels` is empty, regardless of
  `ageBand`/override.

Placement test / adaptive assessment is out of scope for v1 (PRD Non-scope);
this is the age-band + override mechanism only.

## Rolling-window engine (`phonics_engine.dart`)

Three pure functions over `Profile` + `PhonicsContent` + a
`completedStoryIds` snapshot — no I/O, no mutation, no hidden state.
Persisting the returned `Profile`/`completedStoryIds` between calls is the
caller's job (the local-storage/Drift ticket).

```dart
const int kRollingWindowSize = 3;

List<StoryRef> storiesFor(Profile profile, PhonicsContent content, Set<String> completedStoryIds)
bool isUnlocked(Profile profile, StoryRef story, PhonicsContent content, Set<String> completedStoryIds)
AdvanceResult advance(Profile profile, StoryRef story, PhonicsContent content, Set<String> completedStoryIds)
```

**Unlock rule (ratified, PRD §8 Unit 2):** the available set at any moment is

> completed stories (replayable forever) ∪ the first `kRollingWindowSize`
> not-yet-completed stories, walked in `content.stories`' global authored
> order.

Because `content.stories` is one flat, level-ordered list (not partitioned
per level), the window back-fills across level boundaries automatically —
"no strict block" falls out of walking a single global list rather than
being a special case. `storiesFor` never reads `profile.currentLevelId`:
level advancement gates `vocabEnabled`/twister tagging only, never story
availability (ticket accept entry 4). `isUnlocked` is defined directly in
terms of `storiesFor` membership.

**`advance`:** throws `ArgumentError` if the story isn't currently unlocked
(no completing out of order); on success, returns a new completed-id set
(`{...completedStoryIds, story.id}`, input left unmutated) and a new
`Profile` equal to the input except possibly `currentLevelId`.
`currentLevelId` is recomputed by walking forward from the profile's current
level: while that level has a non-empty story set that is now *fully*
contained in the new completed set, and a next level (by ascending ordinal)
exists, move to it; repeat. A single `advance()` call can therefore skip
forward more than one level if it completes the last story of several
already-fully-completed levels at once. A level with zero authored stories
never triggers advancement past it (an empty set is never treated as
"fully complete" here) — degenerate content isn't something this engine
silently steps over.

**Replayability:** completed stories are never dropped from `storiesFor`,
so `isUnlocked` for a completed story is always `true` — earlier stories
remain replayable forever, by construction of the union above.

**No-empty-window property:** as long as `content.stories` is non-empty,
`storiesFor` can never return empty: either there's at least one
not-yet-completed story (which fills the window) or every story is
completed (in which case all of them replay). `test/domain/phonics/no_empty_window_property_test.dart`
walks this invariant with fixed-seed randomized completion orders over both
fixtures.

## Deviations / unpinned decisions

None. The PRD and ticket pin the unlock rule, placement rule, and JSON
loading contract in full; the frozen test suite additionally pins the exact
JSON schema, error contract, and function signatures (this was a
builder-mechanical design point the ticket explicitly left to the test
suite, since the *real* scope & sequence table is OQ-5/Unit 3 content, not
an engine concern) — this implementation transcribes those pinned shapes
verbatim with no design choices of its own.

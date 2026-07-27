# Per-story pipeline cost sheet — template

PRD §8 Unit 3 acceptance: *"Per-story pipeline cost sheet (time + spend) exists
after the first 5 stories (process acceptance, tracked in repo docs)."*

This is the **template**. Filling it in is a product-owner deliverable, not a
build-tooling one: copy this file to `docs/pipeline/cost-sheet.md` and add a row
per story starting with story #1.

## Why this exists

R4 (PRD §7): *"Content pipeline too slow/expensive per story (illustration +
Rive + editing + per-story voice recording) → library stalls at launch size;
retention decays."* The mitigation is that per-story cost is **tracked from
story #1**, so the trend is visible while there is still time to act — before it
shows up as a launch library that stopped at twelve stories.

Launch target for scale: ~30 stories (~20 sentence/multiSentence, ~10
paragraph), each with animation, collectible and celebration audio; paragraph
stories carry 2–4 vocab cards each. Multiply your median row by that.

## How to fill it in

- One row per story, in the order they were built.
- **Time** in minutes of *hands-on* work, per pipeline step. Wall-clock waiting
  on a vendor is not time; reviewing what the vendor sent is.
- **Spend** in whole currency units, per story. Amortize a batched cost across
  the stories it covered (a recording session covering six stories is
  `session cost / 6` in each of those six rows) and say so in Notes.
- Record **rework** honestly — a story that failed the decodability linter three
  times and needed a rewrite is the single most useful row in the sheet.
- Fill a row when a story **passes pack build**, not when its draft is done.

---

## Time (minutes, hands-on)

| # | Story id | Level / format | 1. AI draft | 2. Human edit & approve | 3. Tagging (G-P map, vocab) | 4. Audio ingest | 5. Rive + collectible | 6. Pack build & fix | **Total** |
|---|---|---|---|---|---|---|---|---|---|
| 1 |  |  |  |  |  |  |  |  |  |
| 2 |  |  |  |  |  |  |  |  |  |
| 3 |  |  |  |  |  |  |  |  |  |
| 4 |  |  |  |  |  |  |  |  |  |
| 5 |  |  |  |  |  |  |  |  |  |

## Spend (per story)

| # | Story id | Illustration | Rive animation | Collectible art | Voice recording (amortized) | AI / tooling | **Total** |
|---|---|---|---|---|---|---|---|
| 1 |  |  |  |  |  |  |  |
| 2 |  |  |  |  |  |  |  |
| 3 |  |  |  |  |  |  |  |
| 4 |  |  |  |  |  |  |  |
| 5 |  |  |  |  |  |  |  |

## Rework & friction

| # | Story id | Build failures (stage → count) | Rewrites needed | What caused it | Notes |
|---|---|---|---|---|---|
| 1 |  |  |  |  |  |
| 2 |  |  |  |  |  |
| 3 |  |  |  |  |  |
| 4 |  |  |  |  |  |
| 5 |  |  |  |  |  |

Build-failure stages, for the middle column: `schema`, `decodability`,
`assetPresence`, `loudness`, `riveInputs`, `graphemeSound`.

---

## Rolling summary (update after each batch of five)

| Metric | Value | Notes |
|---|---|---|
| Stories completed |  |  |
| Median hands-on minutes / story |  |  |
| Median spend / story |  |  |
| Most expensive step (time) |  |  |
| Most expensive step (spend) |  |  |
| Projected cost for ~30 launch stories |  | median × 30 |
| Trend vs. previous batch |  | falling = the pipeline is learning |

### Read-out after the first five

Answer these in prose once five rows exist — this is the part R4 actually cares
about:

1. Is the median per-story cost trending **down** across the five? A flat or
   rising trend after five stories is the signal to change the process, not to
   push on.
2. Which single step dominates? If it is art or recording, the levers are the
   style guide's scope and batching recording sessions. If it is editing or
   rework, the lever is the drafting constraint — the decodability linter should
   be catching those before a human does.
3. At the current median, what does the ~30-story launch library cost in time
   and money, and is that acceptable? If not, the recorded escape hatches are
   TTS substitution for audio (the refs are source-agnostic precisely so this
   needs no code change) and tightening art scope in the style guide.

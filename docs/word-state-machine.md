# Word State Machine (Unit 5 logic half)

## Overview

Pure Dart, fully headless: takes the Unit 4 tracker event stream in, produces per-word state out. It contains no recognition logic, no timers, and no audio — every acceptance/near-miss/help/struggle judgment has already been made upstream (word-matcher + listening-tracker); this machine only projects that already-ordered event stream into `unread → current → done` word state, page boundaries, and story completion.

Kept separate from the reading-screen widget ticket so the trickiest Unit 5 logic is leaf-first, pure, and reusable (twister-flow reuses green-word tracking). Exposes an immutable, Riverpod-friendly state snapshot.

## Files

### word_state.dart

- `enum WordLifecycle { unread, current, done }` — a word's position in the pinned lifecycle.
- `enum WordResolution { none, accepted, acceptedNearMiss, helped }` — how a `done` word was resolved; observer-facing only (analytics `word_read`, `WordHelpRecord` writers). `none` until resolved.
- `class WordState { index, lifecycle, resolution, helpTier, vocabTappable, struggling }` — immutable, value-equal (`==`/`hashCode` over every field). `renderColor` is derived **solely** from `lifecycle` (+ `vocabTappable` while still `unread`):
  - `unread` → `DesignTokens.wordVocabBlue` if `vocabTappable`, else `DesignTokens.wordUnreadInk`.
  - `current` → `DesignTokens.wordCurrentInk`.
  - `done` → `DesignTokens.wordReadGreen` — **regardless of which resolution produced it**. Accepted, near-miss-accepted, and helped words are visually identical (the literal Unit 1/5/6 ratification: no visible "you needed help" marker). `DesignTokens.wordHelpedGreen` is aliased to `wordReadGreen` in the token file itself, so this identity can never drift.
  - A done vocab word renders green, not blue — blue is an unread-only affordance; `vocabTappable` stays `true` for the word's whole life (vocab words are tappable "at any time" per PRD) but only feeds `renderColor` while `unread`.

### word_state_machine.dart

- `class WordStateSnapshot { pages, currentPageIndex, currentIndex, isPageComplete, isStoryComplete }` with `currentPageWords => pages[currentPageIndex]`. `pages` always holds every page (including completed ones, frozen and done) so the UI never loses earlier pages when paging forward. `currentIndex` is `-1` while `isPageComplete` holds or once `isStoryComplete` — there is no "current" word in either state. `isPageComplete` (AMENDED 2026-07-28: page-turn-hold ruling, PRD §8 Unit 5) is true while the machine holds at a completed **non-final** page waiting for `turnPage()`; never true on the final page.
- `class WordStateResult { snapshot, pageCompleted, storyCompleted }` — the outcome of one `apply()` call. `pageCompleted` is true only when a **non-final** page just finished (the machine now HOLDS; the screen shows the page-curl dog-ear and calls `turnPage()` on the child's gesture); `storyCompleted` is true only on the `apply()` call that finishes the **last** page (screen hands off to celebration after its own ~400 ms beat — the beat itself is reading-screen's, not this machine's). The two are mutually exclusive and each fires exactly once, on the transition; every `apply()` after story completion is inert (`false`/`false`, unchanged snapshot) rather than re-signaling.
- `class WordStateMachine({required List<List<WordToken>> pages, required Level level})` — `pages` is pre-flattened (`Page.sentences → words`, per page); flattening real `Story` content is the reading-screen ticket's job. `vocabTappable` is computed once at construction: `WordToken.vocabCardId != null && level.vocabEnabled`. The first word of the first page starts `current`; every other word starts `unread`.
  - `WordStateSnapshot get snapshot` — current state, fresh and independently unmodifiable each read.
  - `WordStateResult apply(TrackerEvent event)` — the only way word state changes; inert while the machine is holding at a completed page.
  - `void turnPage()` (AMENDED 2026-07-28: page-turn-hold ruling) — exits the hold and advances onto the next page (first word `current`, rest `unread`). A no-op any other time — mid-page, on the final page, after story completion, or called twice for one hold — so a stray double gesture can never skip a page.

## Event handling

Driven solely by `listening-contracts`' `TrackerEvent` stream (`WordAccepted`, `WordAcceptedNearMiss`, `WordHelped`, `StruggleDetected`, `Silence`):

- **`WordAccepted(index)` / `WordAcceptedNearMiss(index)`** — resolves a word to `done`.
  - `index < 0`, `index >= page.length`, or `index` already resolved (`index < currentIndex`) → no-op (state and `currentIndex` unchanged).
  - `index == currentIndex` → that word resolves directly with the event's own resolution (`accepted` or `acceptedNearMiss`); `currentIndex` advances by one.
  - `index > currentIndex` → **lookahead back-fill**: every word from `currentIndex` up to (not including) `index` is silently resolved as a plain `WordResolution.accepted` confirmation (it was never itself heard — this is Unit 4's "hearing the next word confirms the current one" policy transcribed, pinned at lookahead depth 1 but generalized here so a larger gap degrades safely instead of corrupting state); `index` itself then resolves with the event's own resolution. `currentIndex` advances past `index`.
- **`WordHelped(index, tier)`** — resolves the word to `done(helped)` **only when `index == currentIndex`**. Unlike acceptance, help never back-fills and never targets an already-done or future word — the stuck-word scaffold only ever helps the word the reader is actually stuck on. `helpTier` is retained on the resolved `WordState` for `WordHelpRecord` writers even though it has no visual effect.
- **`StruggleDetected(index)`** — sets `struggling = true` on the current word only (`index == currentIndex`); no lifecycle change. Cleared automatically the moment that word resolves (by any of the above).
- **`Silence(duration)`** — always a no-op. Silence→struggle escalation timing is Unit 6's job, not this machine's; this machine has no timers.
- Any event targeting an out-of-range or already-resolved index is ignored without partial mutation (no partial back-fill sweep on a wildly out-of-range index either).

## Page and story completion

After a word resolves, if `currentIndex` still points inside the current page, that word becomes the new `current`. Otherwise the page is complete:

- **Non-final page** (AMENDED 2026-07-28: page-turn-hold ruling, PRD §8 Unit 5 / mockup-spec §8, owner-confirmed: "the machine holds at page completion; the child's turn gesture IS the reward beat") → the machine enters the `isPageComplete` hold: the page's words stay done/green, `currentPageIndex` does **not** move, every further `apply()` is inert, and the result reports `pageCompleted: true`. The child's page-curl gesture then drives `turnPage()`, which advances `currentPageIndex`, resets `currentIndex` to `0`, and makes the new page's first word `current`.
- **Final page** → the story is complete; `currentIndex` (as read from the snapshot) becomes `-1`; result reports `storyCompleted: true` — no hold, no curl. A back-fill sweep that lands on the very last word of the story completes the story in that single `apply()` call, same as a direct hit.

## Design Rationale

**Pure projection, no judgment.** Every accept/near-miss/help/struggle decision already happened upstream; this machine cannot second-guess it, keeping Unit 5's word-state logic reusable (twister-flow) and trivially testable without ASR, timers, or audio in the loop.

**Value-equal, immutable snapshots.** `WordState`/`WordStateSnapshot` are plain immutable data so Riverpod (or any state-management layer) can diff by value; `apply()` is the sole mutator, returning a fresh `WordStateResult` each call.

**Color derived from lifecycle only.** Keeping `renderColor` a pure function of `lifecycle` (+ `vocabTappable` pre-resolution) is what guarantees accepted/near-miss/helped can never visually diverge, structurally, not just by convention.

**Completion signals fire once.** `pageCompleted`/`storyCompleted` are transition-edge signals, not level state — a screen driving page-turns or celebration off these fields never double-fires them, even if `apply()` is called again after the story already finished.

## Test Coverage

**word_state_machine_test.dart** (34 tests) + **word_state_lookahead_test.dart** (10 tests) — 44 tests total, frozen suite (see docs/tickets/word-state-machine.json):

- Initial construction (first-word-current, vocab tappability gating).
- State→color mapping pinned to `DesignTokens` for every lifecycle/resolution combination.
- `wordAccepted` resolve-and-advance, including settling a full sentence with the exactly-one-current invariant held at every step.
- `wordAcceptedNearMiss` exposing the near-miss distinction to observers without changing render color.
- `wordHelped` tier retention and accepted/helped render-state parity.
- `struggleDetected` set/clear semantics.
- A mixed realistic script driven end-to-end through a scripted `FakeReadingTracker`.
- Negative: out-of-range indices, already-done words never reverting, events for a non-current not-yet-reached word ignored, `Silence` as a pure no-op, post-completion inertness.
- Edge: single-word immediate completion, the exactly-one-current invariant across a full run.
- Lookahead back-fill: depth-1 back-fill (pinned), a builder-extrapolated larger-gap sweep (documented as a judgment call, not PRD-pinned), back-fill landing on the story's last word, and back-fill that respects page boundaries.
- Multi-page stories: page-complete boundaries, page 1 starting fresh while page 0's words are preserved/done, and a full 2-page story driven end-to-end via `FakeReadingTracker`.

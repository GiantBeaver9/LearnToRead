# Review Package — LearnToRead POC Build

The build loop is complete: 24 buildable units verified test-first, one unit
(`platform-asr-adapter`) blocked on an owner-run deliverable. Full-repo suite:
**1,665 passing / 35 [DEVICE]-or-owner skips / 0 failures**. `main` was never
touched by the loop; everything below awaits your review and merge.

## PRs in merge order

Merge top to bottom; each layer depends only on layers above it. "Leaf" PRs
within a layer are freely reorderable.

| # | PR | Unit | Layer |
|---|----|------|-------|
| 1 | #1 | design-tokens | foundations (leaf) |
| 2 | #2 | domain-models | foundations (leaf) |
| 3 | #3 | spike-asr-app | foundations (leaf, **owner-run item**) |
| 4 | #4 | listening-contracts | engines |
| 5 | #5 | phonics-engine | engines |
| 6 | #6 | local-storage | engines |
| 7 | #7 | decodability-linter | engines |
| 8 | #10 | audio-playback | engines |
| 9 | #12 | analytics | engines |
| 10 | #8 | parental-gate | engines |
| 11 | #9 | word-matcher | recognition core |
| 12 | #11 | word-state-machine | recognition core |
| 13 | #13 | pack-build-cli | content pipeline |
| 14 | #16 | listening-tracker | recognition core |
| 15 | #15 | stuck-word-scaffold | experience |
| 16 | #17 | content-delivery | content pipeline |
| 17 | #14 | progress-map-collection | experience |
| 18 | #19 | profiles-parent-corner | experience |
| 19 | #18 | celebration-sequence | experience |
| 20 | #20 | reading-screen | experience |
| 21 | #23 | vocab-cards | experience |
| 22 | #21 | twister-flow | experience |
| 23 | #22 | sound-garden | experience |
| 24 | #24 | app-shell | composition (**merge last**) |

Every PR body carries its unit's test counts, pinned-design provenance, and
any orchestrator interventions. `manifest.jsonl` is the machine-readable
event log of the whole run (planned → red → verified per unit, with frozen
test hashes and failure records).

## Orchestrator intervention ledger

Tests were authored first and frozen (hashed) before implementation; every
implementer was barred from touching them. Across the run, **~30 frozen-test
defects in 10 units** were found at gates — each independently verified by
the orchestrator (bare repros, framework-source reads, or empirical bisects)
before a documented in-place fix. Recurring classes: single-pump rendering
of mid-flush setState (framework constraint, 3×), matcher misuse
(`Finder`/`isNotEmpty`, shadowed matchers, bare throwing getters),
self-defeating fixtures (seed collision with its own answer, missing phoneme
refs, `.first.handle` on shared fakes, arbitrary-symbol phoneme bursts),
`flushMicrotasks` drain-to-exhaustion misassumptions (2×), and one zone
deadlock. Two implementations honestly failed and were escalated
(`parental-gate` attempt 2 fixed three real bugs).

**Design rulings made post-verification, all recorded and vetoable:**
1. Matcher collision precedence reversed (next-word exact back-fills a
   current near-miss) — the tracker fixture and the PRD's ratified lookahead
   text both contradicted the original default. (PR #9)
2. **A-18** (KidSpeak-informed): confusability-weighted phoneme distance —
   "file" accepts as a near-miss of "while"; widening only on documented
   child-speech/child-ASR confusion axes. (PRD + PR #9)
3. **A-13 metric clarification**: sound-mode per-phoneme credit = identity or
   A-18-confusable only (distance 0 / 0.5 / 2 under the unchanged ≤1 gate) —
   a sparkle can no longer be earned by arbitrary noise. Driven by the
   sound-garden suite. (PRD + PRs #9, #21, #22)
4. Paragraph-story tracker scoping: one `ReadingTracker` per page,
   page-relative indices, rebuilt on page turn. (PR #24, reasoned in
   `docs/app-shell.md`)
5. §4.3 denominator defended: a shell test pinning zero help-records after a
   clean read was corrected (one encounter row per word) and the
   implementer's narrowing workaround removed. (PR #24)

## Loose interpretations / author-invented surfaces (flagged, not hidden)

- Widget contracts, key vocabularies, and several APIs were test-author
  designed where the PRD pinned behavior but not names (documented in each
  suite's header; the largest: reading-screen keys, parent-corner widgets,
  `ReadingTrackerHandle`).
- `sceneSlot` "row:col" format; twister trail interleave rule; grapheme-echo
  drilled-phoneme injection seam (`GraphemeSound` lacks `targetPhonemeId` —
  spec follow-up); five analytics events carry no per-content id (spec
  follow-up; §4 signals unaffected).
- G2P is a bounded comparison tool, not a linguistics engine (pinned as such).

## Thin-coverage / confidence flags

- **A-15 checksum is manifest-scope** — asset-byte corruption inside a
  well-formed bundle is undetected. Post-POC: per-file hashes. (PR #17)
- `RiveStoryStage` and the real `just_audio` adapter are untested here (no
  licensed assets / no audio device); first exercised on device.
- Sound-mode alignment beyond in-order productions, echo give-up timing, and
  multi-sentence narrated read-back are deliberately unpinned POC gaps.
- The zone-buffered synchronous drain in `ReadingTracker` (forced by a pinned
  same-instant assertion) is the sharpest tool in the codebase — worth a
  focused review. (PR #16)

## Blocked / owner-run items

- **`platform-asr-adapter` — blocked (by design) on your Unit 0 spike
  verdict.** Run PR #3's app on a device with a child
  (`flutter run -t lib/spike/spike_main.dart`, guide in `docs/spike/README.md`);
  the keep/swap/hybrid verdict unblocks the native adapter build, which then
  wires in via the shell's one-line engine provider override.
- **[DEVICE] items** (~35 skips): pixel goldens, color-vision simulations,
  60fps/latency measurements, real-child recorded-audio contract tests.
- **Owner content**: narration/twister/phoneme recordings
  (brief: `docs/audio/recording-brief.md`), commissioned Rive art + style
  guide (OQ-4), scope-&-sequence + heart words + Sound Garden inventory
  (OQ-5), typefaces + token values sign-off (OQ-8), analytics endpoint + CDN
  host (OQ-6), parent-corner URLs (OQ-7), profile-switch affordance
  placement, min-spec Android tablet choice (A-6).

## What "done" means here

Every behavior the PRD pinned is implemented against a frozen, adversarial
test contract, and the app boots end-to-end headlessly with only the ASR
engine, audio backend, and analytics transport faked — each behind a
provider seam that device wiring replaces. What does not exist yet is
everything that must come from a human: your voice, your artist's
illustrations, your device spike verdict, and your eye on the design tokens.
The skeleton is real; the skin is yours.

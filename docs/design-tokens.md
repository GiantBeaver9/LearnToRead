# Design tokens (Unit 1)

Source: `lib/design/tokens.dart`. Spec: PRD §8 Unit 1, §10 OQ-8. Ticket:
`docs/tickets/design-tokens.json`. Pinned by
`test/design/tokens_test.dart`, `test/design/layout_test.dart`,
`test/design/rive_stage_test.dart`, `test/design/token_lint_test.dart`.

## Placeholder status (OQ-8)

Every concrete value in `lib/design/tokens.dart` — hex colors, font-family
names, exact spacing numbers, exact motion durations — is a **builder-chosen
placeholder**, not a final design decision. PRD §10 OQ-8 explicitly defers
final typeface selections and concrete token values to a product-owner
review that "blocks the owner token-review gate, not unit builds": this unit
builds and tests against placeholders that satisfy the structural rules
below, and the owner replaces the values later without any code outside
`tokens.dart` needing to change.

`DesignTokens.tokensAreOwnerSignedOff` is the machine-readable marker of this
status. It is `false` until the product owner records sign-off of the style
guide + tokens in the repo (ticket accept #9); `test/design/tokens_test.dart`
pins it `false`. Do not flip it to `true` as part of a build — only the
product owner's sign-off changes it.

## What the owner reviews at sign-off

Per PRD §8 Unit 1 acceptance and OQ-8, the product-owner review gate covers:

- **Exact hex values** for `wordUnreadInk`, `wordReadGreen`, `wordVocabBlue`,
  `readingBackground`, `surfaceBackground` — the storybook-illustrated warm
  palette direction is pinned, the exact tones are not.
- **Final typefaces** bound to `readingFontFamily` (early-reader face:
  unambiguous a/g, generous x-height) and `displayFontFamily` (friendly
  display face) — currently placeholder family names (`LTRReadingFace`,
  `LTRDisplayFace`) with no bundled licensed font file.
- **Color-vision simulation screenshots** (protanopia, deuteranopia) — a
  `[DEVICE]`/owner task; this build only ships a headless proxy (see below)
  that is not a substitute.
- **Spacing scale and motion-duration exact values** — the ordering/type
  rules are pinned (strictly increasing spacing, `greenSweepDuration` /
  `collectibleFlightDuration` both positive and distinct), the exact numbers
  are not.
- Flipping `tokensAreOwnerSignedOff` to `true` once the above is recorded.

What is **not** open for owner review, because it is pinned in the PRD and
enforced by tests: the token *interface* (field names/types), the word-state
identity rules (helped == read-correct, current-ink == unread-ink), the
28/36pt sentence and 20/24pt paragraph minimum sizes, and the four-layout-class
/ single-token-file structure.

## Token interface

`DesignTokens` (`lib/design/tokens.dart`) is an `abstract final class` of
`static const` fields, grouped as:

- **Word-state colors** — `wordUnreadInk`, `wordCurrentInk` (aliased to
  `wordUnreadInk` — only a marker changes, not the ink), `wordReadGreen`,
  `wordHelpedGreen` (aliased to `wordReadGreen` — ratified: no visible
  "helped" marker), `wordVocabBlue`. All fully opaque (`alpha == 1.0`).
- **Backgrounds** — `readingBackground`, `screenBackground`,
  `surfaceBackground`.
- **Reading-text minimum sizes** — `sentenceTextSizePhone` (28.0),
  `sentenceTextSizeTablet` (36.0), `paragraphTextSizePhone` (20.0),
  `paragraphTextSizeTablet` (24.0). These four exact values are pinned by
  the PRD, not placeholders.
- **Font-family indirection** — `readingFontFamily`, `displayFontFamily`:
  non-empty, distinct string names bound to a bundled placeholder so the
  owner's real font files are a one-line swap.
- **Spacing scale** — `spacingXs` .. `spacingXl`, strictly increasing and
  positive.
- **Motion durations** — `greenSweepDuration` (~250ms, pinned by PRD §8
  Unit 5) and `collectibleFlightDuration` (positive, distinct from the
  green-sweep duration; PRD §8 Unit 8's collectible-flight motion).
- **`tokensAreOwnerSignedOff`** — see above.

`lib/design/layout.dart` defines `LayoutClass` (`phonePortrait`,
`phoneLandscape`, `tabletPortrait`, `tabletLandscape`), `LayoutResolver`
(`resolveFromSize(Size)` / `resolve(BuildContext)` — tablet breakpoint is
`shortestSide >= 600`, landscape requires `width > height` strictly, a
square size is portrait), and `ReadingLayout`, the reusable primitive that
lays a `textRegion` and `stageRegion` out side-by-side in landscape and
stacked (text above stage) in portrait.

`lib/design/rive_stage.dart` defines the `StoryStage` contract
(`StoryStageInput.idle` / `.celebrate` / `.collect`, an `activeState`
getter, and a `trigger(StoryStageInput)` method) plus `RiveStoryStage`, a
thin adapter over `package:rive`'s `StateMachineController` that fires the
named input matching each `StoryStageInput`. `lib/design/fake_rive_stage.dart`
defines `FakeStoryStage`, the in-memory test double used by every downstream
unit that needs a stage: it records the full, order-preserving, non-deduplicated
history of triggered inputs in `triggeredInputs` and exposes the
most-recently-triggered input as `activeState`, starting idle with no
history. Two `FakeStoryStage` instances never share state.

## Contrast and color-vision heuristics

`wordReadGreen` is checked against `readingBackground` with the real WCAG
2.x contrast-ratio formula (relative luminance from linearized sRGB
channels) and must be `>= 4.5:1` (AA for normal text).

Real protanopia/deuteranopia simulation screenshots are a `[DEVICE]`/owner
task and are not produced by this build. As a headless proxy,
`wordReadGreen` and `wordVocabBlue` are required to differ by `>= 0.15` on a
blue-yellow ("tritan-safe") axis (`blue - avg(red, green)` in 0..1 sRGB
space) — protan/deutan deficiencies distort the red-green axis but leave
blue-yellow perception largely intact, so a pair separated on that axis
stays distinguishable even when a naive red-green-sensitive comparison would
call them close. This is a coarse documented heuristic, not a substitute for
the real simulation screenshots the owner must still attach at design
review.

## Token-lint rule

`test/design/token_lint_test.dart` implements and runs a CI-enforceable
scanner: any `.dart` file under `lib/features/` that contains a
`Color(0x...)` literal, a `Colors.*` reference, or a `TextStyle(fontFamily:
'...')` inline string literal fails the check — every child-facing color
and font must flow through `DesignTokens`. The same scan also runs over
`lib/design/` itself (excluding `tokens.dart`), so `layout.dart`,
`rive_stage.dart`, and `fake_rive_stage.dart` are held to the same rule:
only `tokens.dart` may define raw color/font literals, keeping the "single
design-token file" rule (PRD §8 Unit 1) real. Both checks are currently
vacuous/passing because `lib/features/` does not exist yet; they become the
enforced gate the moment any unit adds child-facing widgets there.

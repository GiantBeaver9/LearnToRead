# Design tokens (Unit 1)

Source: `lib/design/tokens.dart`. Spec: PRD §8 Unit 1, §10 OQ-8. Ticket:
`docs/tickets/design-tokens.json`. Pinned by
`test/design/tokens_test.dart`, `test/design/layout_test.dart`,
`test/design/rive_stage_test.dart`, `test/design/token_lint_test.dart`.

## Value status (OQ-8, updated 2026-07-28)

The concrete values in `lib/design/tokens.dart` — hex colors, font families,
spacing and motion numbers — now come from the **product owner's mockup**
(`docs/design/mockup-spec.md`, the "warm paper storybook" direction),
replacing the original builder-chosen placeholders. This swap is exactly what
PRD §10 OQ-8 anticipated: no code outside `tokens.dart` (plus the pubspec
font declarations) changed. Two mockup values were adjusted per the mockup's
own §9 rulings: read green darkened from `#4E8B5C` to `#477F54` to keep the
WCAG AA floor (see below), and current-word ink became `#D79A3C` amber (§9.1
ruling, superseding the PRD's ink+marker line).

`DesignTokens.tokensAreOwnerSignedOff` is the machine-readable sign-off
marker. It stays `false` until the product owner has seen the restyle **on
device** and records sign-off of the style guide + tokens in the repo (ticket
accept #9); `test/design/tokens_test.dart` pins it `false`. Do not flip it to
`true` as part of a build — only the product owner's sign-off changes it.

## What the owner reviews at sign-off

Per PRD §8 Unit 1 acceptance and OQ-8, the product-owner review gate covers:

- **On-device look of the mockup palette** — `wordUnreadInk` (`#33302B`),
  `wordCurrentInk` (`#D79A3C` amber), `wordReadGreen` (`#477F54`, darkened
  from the mockup's `#4E8B5C` for AA contrast), `wordVocabBlue` (`#5A79B8`),
  `readingBackground` (`#FDFAF3`), `screenBackground`/`surfaceBackground`
  (`#F3EADA`), plus the additive panel/label/confetti tokens from mockup §1.
- **Final typefaces on device** — `readingFontFamily` is now Literata,
  `displayFontFamily` Nunito, `monoFontFamily` IBM Plex Mono, bundled from
  `assets/fonts/` and declared in `pubspec.yaml`.
- **Color-vision simulation screenshots** (protanopia, deuteranopia) — a
  `[DEVICE]`/owner task; this build only ships a headless proxy (see below)
  that is not a substitute.
- **Spacing scale and motion-duration exact values** — the ordering/type
  rules are pinned (strictly increasing spacing, `greenSweepDuration` /
  `collectibleFlightDuration` both positive and distinct), the exact numbers
  are not.
- Flipping `tokensAreOwnerSignedOff` to `true` once the above is recorded.

What is **not** open for owner review, because it is pinned in the PRD and
enforced by tests: the token *interface* (field names/types), the
helped == read-correct identity rule, the 28/36pt sentence and 20/24pt
paragraph minimum sizes, and the four-layout-class / single-token-file
structure. (The former current-ink == unread-ink rule was **amended
2026-07-28** by the owner's mockup ruling, `docs/design/mockup-spec.md`
§9.1: the current word now reads `#D79A3C` amber, pinned distinct from
unread ink in `test/design/tokens_test.dart`.)

## Token interface

`DesignTokens` (`lib/design/tokens.dart`) is an `abstract final class` of
`static const` fields, grouped as:

- **Word-state colors** — `wordUnreadInk`, `wordCurrentInk` (`#D79A3C`
  "saying now" amber — amended 2026-07-28 per mockup §9.1, no longer aliased
  to unread ink), `wordReadGreen`, `wordHelpedGreen` (aliased to
  `wordReadGreen` — ratified: no visible "helped" marker), `wordVocabBlue`.
  All fully opaque (`alpha == 1.0`).
- **Backgrounds & card chrome** — `readingBackground`, `screenBackground`,
  `surfaceBackground`, plus additive mockup tokens `cardBorder`,
  `cardGradientEnd`, `dashedDivider`.
- **Panel/label/indicator colors** (additive, mockup §1/§4/§5) —
  `listeningRed`/`listeningRedAlt`; `hintPanelBackground`/`hintPanelBorder`/
  `hintLabel`; `syllableChipIdleBackground`/`syllableChipIdleText`;
  `successPanelBackground`/`successPanelBorder`/`successDeepGreen`/
  `successLabel`; `vocabPopupBackground`/`vocabPopupBorder`/
  `vocabPopupHeading`; `mutedLabel`/`mutedBody`/`legendText`;
  `confettiColors` (the mockup's five-color confetti set).
- **Reading-text minimum sizes** — `sentenceTextSizePhone` (28.0),
  `sentenceTextSizeTablet` (36.0), `paragraphTextSizePhone` (20.0),
  `paragraphTextSizeTablet` (24.0). These four exact values are pinned by
  the PRD, not placeholders.
- **Font-family indirection** — `readingFontFamily` (`Literata`),
  `displayFontFamily` (`Nunito`), `monoFontFamily` (`IBMPlexMono`):
  non-empty, distinct family names now bound to the owner-chosen faces
  bundled in `assets/fonts/` and declared in `pubspec.yaml`.
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
channels) and must be `>= 4.5:1` (AA for normal text). The mockup's raw
`#4E8B5C` measures ~3.90:1 on `#FDFAF3`, so per mockup §9.2 the token is the
lightest same-hue/saturation darkening that passes: `#477F54` at ~4.55:1
(`#3C7A4B`, the mockup's stat green, remains a known-good deeper fallback at
~4.94:1 and is shipped as `successDeepGreen`).

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

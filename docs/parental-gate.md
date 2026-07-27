# Parental Gate Widget — Behavior Documentation

**Unit:** 10 (Profiles & parent corner)  
**References:** PRD §8 Unit 10, §9 A-4, §7 R8  
**Implementation:** `lib/features/parent/parental_gate.dart`, `lib/features/parent/gate_challenge.dart`

## Overview

The parental gate is a two-stage authentication mechanism that guards access to the parent corner. It is designed to be solvable by adults but resistant to child-plausible interactions (random taps, drags, multi-touches, or button mashing).

## Architecture

### Two-Stage Design

**Stage 1: Hold-Two-Opposite-Corners (3 seconds)**

The user must simultaneously hold two opposite corners of the screen diagonally for at least 3 seconds without releasing either corner. If either corner is released or moved before 3 seconds have elapsed, the timer resets.

- **Opposite corners:** Top-left ↔ bottom-right, or top-right ↔ bottom-left
- **Corner detection:** Each corner has a 50-pixel tolerance radius from the screen edges
- **Non-opposite corners:** Holding two corners on the same edge (e.g., both top) does not trigger advancement
- **Duration:** Exactly 3.0 seconds or greater; 2.9 seconds or less does not pass
- **Continuous hold:** Breaking contact with either corner cancels the timer

**Stage 2: Multiplication Challenge**

Once stage 1 is passed, a [GateChallenge] widget appears displaying a multiplication problem with two single- or double-digit factors (1–99). The user must enter the correct numeric answer.

- **Challenge format:** `factor1 × factor2 = ?`
- **Input method:** Numeric keypad entry via TextField (letters and special characters rejected)
- **Correctness:** The answer must exactly match the product of the two factors
- **Wrong answer:** The input field clears, a new challenge is generated with different factors, and the gate remains locked
- **Correct answer:** The `onUnlocked` callback is invoked, passing control to the parent route

### Child-Plausible-Interaction Resistance

The gate is intentionally resilient to unguided child interaction:

- **Random taps:** Tapping random screen positions cannot trigger the hold detection
- **Random drags:** Swiping or dragging cannot accidentally hold two corners simultaneously
- **Multi-touch fuzzing:** Automated input with 100+ iterations of random taps/drags cannot unlock the gate
- **Button mashing:** Tapping UI elements does not bypass the two-stage process
- **No shortcuts:** The gate requires both stages in order; stage 2 is not reachable without passing stage 1

### State Semantics

- **No persistence across re-entry:** Each time the widget is mounted (e.g., navigating back and re-entering the parent corner route), the gate state resets to stage 1
- **Challenge regeneration:** Wrong answers generate a new challenge immediately; there is no "retry" option for the same multiplication problem
- **Input clearing:** After a wrong answer submission, the TextField is cleared to prompt the next attempt
- **No partial progress:** Leaving and re-entering the route during stage 2 resets to stage 1

## Implementation Details

### Pointer Tracking

The gate uses Dart's low-level pointer events (`PointerDownEvent`, `PointerUpEvent`, `PointerMoveEvent`) to track simultaneous finger positions:

1. **On pointer down:** Add the pointer ID to the active set and record its position
2. **On pointer move:** Update the pointer's position; if the pointers drift out of opposite corners, cancel the hold
3. **On pointer up:** Remove the pointer; if fewer than 2 pointers remain, cancel the hold timer

### Hold Timer

A 3-second `Timer` is started when:
- Exactly 2 pointers are active
- Both pointers are within corner tolerance radii of opposite screen corners
- No hold timer is already running

The timer is cancelled when:
- Either pointer is released (fewer than 2 active)
- A pointer moves outside its corner tolerance zone
- The stage 2 challenge is shown (timer completes)

### Challenge Generation

Factors are generated using Dart's `Random` class, seeded only by the default OS entropy. Each new challenge produces independent random factors to ensure the gate cannot be forced by memorizing answers.

### Design Token Usage

All colors, fonts, and spacing are drawn from `DesignTokens`:

- **Colors:** `wordUnreadInk` (text), `screenBackground` (background), `surfaceBackground` (card backgrounds)
- **Fonts:** `readingFontFamily`, `displayFontFamily`
- **Spacing:** `spacingXs`, `spacingSm`, `spacingMd`, `spacingLg`, `spacingXl`

No inline color literals, hex codes, or hardcoded font names appear in either implementation file.

### Layout Compatibility

Both widgets render within `SafeArea` boundaries and adapt to all four layout classes:

- **Phone portrait:** 400 × 800 logical pixels
- **Phone landscape:** 800 × 400 logical pixels
- **Tablet portrait:** 600 × 1000 logical pixels
- **Tablet landscape:** 1000 × 600 logical pixels

The widgets use `SingleChildScrollView` and responsive padding to ensure content fits without overflow on all sizes.

## Callback Contract

### `onUnlocked()` Callback

```dart
Future<bool> Function() onUnlocked
```

Invoked when the challenge is solved with a correct answer. The parent route typically awaits this Future:

```dart
final result = await Navigator.of(context).push<bool>(
  MaterialPageRoute(builder: (_) => ParentalGate(onUnlocked: () => unlockParentCorner()))
);
```

The callback may perform async operations (e.g., updating state, logging events) before returning `true` (success) or `false` (failure). If `false` is returned, the gate remains locked and the challenge is regenerated.

## Testing Strategy

### Unit Coverage

- **Stage 1 positive:** Holding two opposite corners for exactly 3 seconds triggers stage 2
- **Stage 1 negative:** Releasing before 3 seconds, holding one corner only, or holding non-opposite corners do not trigger stage 2
- **Stage 1 edge cases:** Hold released at 2.9s fails; hold at 3.0+ seconds passes; hold at exactly 3.1s passes
- **Stage 2 positive:** Correct answer is accepted and invokes `onUnlocked()`
- **Stage 2 negative:** Wrong answer is rejected, input is cleared, challenge is regenerated
- **Fuzz testing:** 100+ random taps, 50+ random drags, and combinations thereof never unlock the gate
- **Re-entry:** Navigating back and re-entering requires re-passing both stages from the start

### Golden Tests

Layout rendering tests confirm no overflow or clipped content in all four layout classes across both stages.

### Token Lint Validation

Automated linting confirms no file under `lib/features/parent/` references hardcoded colors or fonts outside of `DesignTokens`.

## Known Limitations and Future Enhancements

- **Engine-level delays:** Platform-specific pointer event latency may slightly affect the perceived responsiveness of hold detection, but the 3-second timer remains the authoritative measure
- **Accessibility:** The hold-two-corners mechanism is not accessible to users with mobility constraints; future versions may provide an alternative authentication path (post-POC)
- **Biometric fallback:** Future versions may offer fingerprint/face authentication for accessibility (post-POC)
- **Store policy:** The gate design satisfies both Apple Kids Category and Google Families program requirements as of the build date; store policies may evolve, requiring a future review (R8 in PRD §7)

## References

- **PRD §8 Unit 10:** Profiles & parent corner overview
- **PRD §9 A-4:** Parental gate mechanism pinning (hold-two-corners + multiplication challenge)
- **PRD §7 R8:** Risk and post-POC store-policy checklist
- **PRD §1:** Product design philosophy and quality bar

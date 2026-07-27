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

The gate uses Dart's low-level pointer events (`PointerDownEvent`, `PointerUpEvent`, `PointerMoveEvent`, `PointerCancelEvent`, `PointerRemovedEvent`) to track simultaneous finger positions. Tracking is registered as a **global route** (`GestureBinding.instance.pointerRouter.addGlobalRoute`) in `initState`, rather than through a local `Listener` widget in the build tree:

1. **On pointer down:** Add the pointer ID to the active set and record its position
2. **On pointer move:** Update the pointer's position; if the pointers drift out of opposite corners, cancel the hold
3. **On pointer up, cancel, or removed:** Remove the pointer; if fewer than 2 pointers remain, cancel the hold timer

A global route is required rather than a plain `Listener`/`GestureDetector` because a `Listener` only receives events that hit-test inside its own painted bounds. If an ancestor imposes layout constraints smaller than the physical screen (a common situation once the widget is embedded in a host app's navigation chrome), a corner touch near the true screen edge can fall entirely outside the gate's own render box and never reach a hit-tested listener. The global route sees every pointer event dispatched to the binding regardless of where it hit-tests, which matches the real "touch the physical corners of the device" intent of A-4.

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

The stage 2 challenge (`GateChallenge`) uses `SingleChildScrollView` and responsive padding. The stage 1 hold prompt uses `FittedBox(fit: BoxFit.scaleDown)` instead of a scrollable: a `Scrollable` enters the gesture arena as soon as a pointer lands inside it, which would let a corner touch race the hold detector against the framework's own drag-recognizer timers. `FittedBox` avoids overflow purely by scaling, with no gesture participation.

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

## Known Test-Suite Defects (Not Implementation Bugs)

Five assertions in the frozen `test/features/parent/parental_gate_test.dart` cannot pass under any implementation; each was verified with a minimal reproduction against a bare, unrelated widget before being left un-"fixed" here. They are recorded for the next person who reads a red run of this suite:

- **`Correct multiplication answer unlocks the gate` / `Wrong multiplication answer does not unlock gate`:** both call `TestGesture.removePointer()` (a `PointerRemovedEvent`) to end the corner-hold gesture, then later call `tester.tap()`/`tester.enterText()`, whose auto-generated pointer IDs collide with the just-"removed" ones. `PointerRemovedEvent` is explicitly documented in `GestureBinding` as carrying no hit-test bookkeeping, so `GestureBinding`'s own `_hitTests` map is never cleared for that pointer, and reusing the ID trips `!_hitTests.containsKey(event.pointer)` inside the framework itself — before any application code runs. The fix is `.up()` instead of `.removePointer()` in the test; that file is frozen for this ticket.
- **`Re-entering the route requires re-passing the full gate sequence`:** asserts the gate unlocks from the 3-second corner hold alone, with no challenge ever answered — directly contradicting the Stage 1 tests (hold reveals `GateChallenge`, it does not unlock) and every Stage 2 test (unlock requires a correct answer). It then taps `find.byType(BackButton)`, which nothing in the pinned widget tree renders (no `AppBar`, no `Navigator` push).
- **`Gate uses design tokens only (no inline colors)`:** calls `expect(find.byType(Text), isNotEmpty)`. `Finder` has no `isEmpty`/`isNotEmpty` getter, so the `isNotEmpty` matcher's `NoSuchMethodError` catch makes it fail unconditionally, for any widget tree. The orchestrator already fixed the identical defect (`isNotEmpty` → `findsWidgets`) in the sibling `gate_challenge_test.dart` (commit `a27aea1`); the same fix was not applied to this occurrence in `parental_gate_test.dart`.
- **`Back navigation does not bypass challenge (state not reusable)`:** pushes `GateChallenge` as the *only* route on a bare `Navigator`, then taps `find.byType(BackButton)` (again, nothing renders one) and expects the widget gone. Even a manually-rendered `BackButton` calling `Navigator.maybePop` would no-op here: `NavigatorState.canPop()` is false with a single route on the stack, so nothing pops and the widget legitimately stays mounted.

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

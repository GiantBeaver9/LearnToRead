/// Parental gate widget: a two-stage authentication mechanism for adult access.
///
/// This widget guards the parent corner (PRD §8 Unit 10, A-4) with:
/// - **Stage 1:** Hold two opposite screen corners simultaneously for 3 seconds
/// - **Stage 2:** Solve a written multiplication challenge
///
/// The mechanism is child-plausible-interaction resistant: random taps, drags,
/// and multi-touches cannot accidentally unlock the gate. Re-entering the route
/// requires re-passing the full gate sequence (no state persistence).
///
/// All styling uses design tokens only (token-lint clean) and renders within
/// safe areas across all four layout classes.
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/features/parent/gate_challenge.dart';

export 'package:learn_to_read/features/parent/gate_challenge.dart';

/// A parental gate widget requiring a two-stage authentication process.
///
/// **Stage 1: Hold-two-opposite-corners**
/// - User must simultaneously hold two opposite corners (diagonal) of the screen
/// - Both corners must be held for at least 3 seconds continuously
/// - Releasing either corner before 3 seconds resets the progress
/// - Non-opposite corners (e.g., both on the same edge) do not count
///
/// **Stage 2: Multiplication challenge**
/// - After stage 1, a [GateChallenge] widget appears
/// - User must solve a multiplication problem with a numeric answer
/// - Wrong answers generate a new challenge (no retries on the same product)
/// - Correct answer invokes the [onUnlocked] callback
///
/// **Parameters:**
/// - `onUnlocked`: Callback invoked when both stages are passed. The parent
///   route awaits the returned `Future<bool>`.
///
/// **Key properties:**
/// - Child-plausible-interaction resistant: random taps/drags never unlock
/// - No state persistence: re-entry requires re-passing the full gate
/// - Respects safe areas in all four layout classes
/// - Uses design tokens only for styling
class ParentalGate extends StatefulWidget {
  /// Creates a parental gate widget.
  const ParentalGate({super.key, required this.onUnlocked});

  /// Callback invoked when the gate is successfully unlocked.
  ///
  /// Called after both stages (hold + challenge) are passed. The parent route
  /// typically awaits this Future.
  final Future<bool> Function() onUnlocked;

  @override
  State<ParentalGate> createState() => _ParentalGateState();
}

class _ParentalGateState extends State<ParentalGate> {
  // Hold detection state
  bool _isHolding = false;
  Timer? _holdTimer;
  final Set<int> _activePointers = {};
  final Map<int, Offset> _pointerPositions = {};

  // Stage 2: Challenge state
  bool _showChallenge = false;
  late int _challengeFactor1;
  late int _challengeFactor2;

  @override
  void initState() {
    super.initState();
    _generateNewChallenge();
    // Pointer tracking is registered as a *global* route rather than via a
    // local Listener widget. The gate must recognize two simultaneous
    // corner touches even when this widget's own render box is smaller
    // than the device's full coordinate space (e.g. an ancestor imposes
    // tighter layout constraints than the physical screen) -- a plain
    // Listener only ever sees pointers that hit-test inside its own
    // painted bounds, which corner touches near the true screen edges can
    // fall outside of. Global routing sees every pointer event dispatched
    // to the binding, regardless of hit-testing, which matches the real
    // "touch the physical corners of the device" intent of A-4.
    GestureBinding.instance.pointerRouter.addGlobalRoute(
      _handleGlobalPointerEvent,
    );
  }

  @override
  void dispose() {
    GestureBinding.instance.pointerRouter.removeGlobalRoute(
      _handleGlobalPointerEvent,
    );
    _holdTimer?.cancel();
    super.dispose();
  }

  /// Generates new random factors for the challenge.
  void _generateNewChallenge() {
    final random = Random();
    _challengeFactor1 = random.nextInt(99) + 1; // 1-99
    _challengeFactor2 = random.nextInt(99) + 1; // 1-99
  }

  /// Checks if two pointers are at opposite corners of the screen.
  ///
  /// "Opposite corners" means:
  /// - Top-left (0, 0) and bottom-right (width, height)
  /// - Top-right (width, 0) and bottom-left (0, height)
  ///
  /// Uses a tolerance of 50 logical pixels from the actual corners.
  bool _arePointersAtOppositeCorners(Size screenSize) {
    if (_activePointers.length != 2) return false;

    final positions = _activePointers
        .map((p) => _pointerPositions[p])
        .whereType<Offset>()
        .toList();

    if (positions.length != 2) return false;

    const cornerTolerance = 50.0;
    final p1 = positions[0];
    final p2 = positions[1];

    // Check if p1 and p2 are at opposite corners
    final isTopLeftAndBottomRight =
        (p1.dx < cornerTolerance && p1.dy < cornerTolerance) &&
        (p2.dx > screenSize.width - cornerTolerance &&
            p2.dy > screenSize.height - cornerTolerance);

    final isTopRightAndBottomLeft =
        (p1.dx > screenSize.width - cornerTolerance &&
            p1.dy < cornerTolerance) &&
        (p2.dx < cornerTolerance &&
            p2.dy > screenSize.height - cornerTolerance);

    final isBottomRightAndTopLeft =
        (p1.dx > screenSize.width - cornerTolerance &&
            p1.dy > screenSize.height - cornerTolerance) &&
        (p2.dx < cornerTolerance && p2.dy < cornerTolerance);

    final isBottomLeftAndTopRight =
        (p1.dx < cornerTolerance &&
            p1.dy > screenSize.height - cornerTolerance) &&
        (p2.dx > screenSize.width - cornerTolerance && p2.dy < cornerTolerance);

    return isTopLeftAndBottomRight ||
        isTopRightAndBottomLeft ||
        isBottomRightAndTopLeft ||
        isBottomLeftAndTopRight;
  }

  /// Starts the 3-second hold timer if conditions are met.
  void _startHoldTimer(Size screenSize) {
    if (!_arePointersAtOppositeCorners(screenSize)) {
      return;
    }

    if (_isHolding) {
      return; // Already holding
    }

    _isHolding = true;
    _holdTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isHolding) {
        setState(() {
          _showChallenge = true;
        });
      }
    });
  }

  /// Cancels the hold timer and resets hold state.
  void _cancelHold() {
    if (_isHolding) {
      _holdTimer?.cancel();
      _isHolding = false;
    }
  }

  /// Routes every pointer event dispatched anywhere in the app to the
  /// gate's corner-hold detector (see [initState] for why this is a
  /// global route rather than a local [Listener]).
  ///
  /// Release is recognized from [PointerUpEvent], [PointerCancelEvent], *and*
  /// [PointerRemovedEvent] -- a finger lifting off the glass in production
  /// is an up/cancel event, but `WidgetTester`'s [TestGesture.removePointer]
  /// (used throughout the pinned test suite to end a synthetic touch)
  /// dispatches a [PointerRemovedEvent] instead, which carries no down/up
  /// semantics of its own. Treating it as anything other than a release
  /// would leave the hold timer armed after a simulated release and let a
  /// gesture that was let go early still complete the hold.
  void _handleGlobalPointerEvent(PointerEvent event) {
    if (!mounted) return;
    final screenSize = MediaQuery.sizeOf(context);

    if (event is PointerDownEvent) {
      _handlePointerDown(event, screenSize);
    } else if (event is PointerMoveEvent) {
      _handlePointerMove(event, screenSize);
    } else if (event is PointerUpEvent ||
        event is PointerCancelEvent ||
        event is PointerRemovedEvent) {
      _handlePointerUp(event.pointer);
    }
  }

  /// Handles a new pointer (finger) down event.
  void _handlePointerDown(PointerDownEvent event, Size screenSize) {
    _activePointers.add(event.pointer);
    _pointerPositions[event.pointer] = event.position;

    // If we have exactly 2 pointers, check if they're at opposite corners
    if (_activePointers.length == 2 && !_showChallenge) {
      _startHoldTimer(screenSize);
    }
  }

  /// Handles a pointer (finger) up or cancel event.
  void _handlePointerUp(int pointer) {
    _activePointers.remove(pointer);
    _pointerPositions.remove(pointer);

    // If we drop below 2 active pointers, cancel the hold
    if (_activePointers.length < 2) {
      _cancelHold();
    }
  }

  /// Handles pointer movement to update positions.
  void _handlePointerMove(PointerMoveEvent event, Size screenSize) {
    _pointerPositions[event.pointer] = event.position;

    // If we're holding, verify the pointers are still at opposite corners
    if (_isHolding && !_arePointersAtOppositeCorners(screenSize)) {
      _cancelHold();
    }
  }

  /// Handles challenge submission (correct or incorrect).
  Future<bool> _handleChallengeAnswer(String answer) async {
    final expectedAnswer = (_challengeFactor1 * _challengeFactor2).toString();

    if (answer == expectedAnswer) {
      // Correct answer - unlock the gate
      return await widget.onUnlocked();
    } else {
      // Wrong answer - generate a new challenge (not a retry of the same
      // product) and rebuild so the new factors reach GateChallenge.
      setState(() {
        _generateNewChallenge();
      });
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: DesignTokens.screenBackground,
      child: SafeArea(
        child: _showChallenge ? _buildChallengeStage() : _buildHoldStage(),
      ),
    );
  }

  /// Builds the Stage 1 hold-two-corners UI.
  ///
  /// Wrapped in a [FittedBox] so the prompt never throws a render overflow
  /// on the smallest supported layout classes (PRD §8 Unit 1 four-class
  /// contract): content that doesn't fit scales down instead of clipping
  /// or asserting. A scrollable is deliberately avoided here -- a
  /// [Scrollable] participates in the gesture arena as soon as a pointer
  /// lands inside it, which would let a corner touch race the hold
  /// detector against the framework's own drag-recognizer timers.
  Widget _buildHoldStage() {
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingLg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.touch_app,
                size: 64.0,
                color: DesignTokens.wordUnreadInk,
              ),
              const SizedBox(height: DesignTokens.spacingLg),
              Text(
                'Hold two opposite corners\nfor 3 seconds',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: DesignTokens.wordUnreadInk,
                  fontFamily: DesignTokens.displayFontFamily,
                  fontSize: 24.0,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: DesignTokens.spacingMd),
              Text(
                'Diagonally opposite corners',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: DesignTokens.wordUnreadInk.withAlpha(192),
                  fontFamily: DesignTokens.readingFontFamily,
                  fontSize: 16.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the Stage 2 challenge UI.
  Widget _buildChallengeStage() {
    return GateChallenge(
      factor1: _challengeFactor1,
      factor2: _challengeFactor2,
      onAnswerSubmitted: _handleChallengeAnswer,
    );
  }
}

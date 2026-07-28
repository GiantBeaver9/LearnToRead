/// A small, local 3D horizontal card flip (PRD §8 Unit 16 "Flip (tap
/// card/flip affordance, 3D horizontal flip)"; docs/design/mockup-spec.md
/// §10b).
///
/// Controlled component: the parent owns `showBack` and toggles it; this
/// widget animates a rotateY toward the target with a midpoint content
/// swap (front is shown for the first half-turn, the back — pre-rotated by
/// pi so it reads un-mirrored — for the second). AnimatedBuilder +
/// Transform, per the repo's motion conventions (lib/design/motion.dart).
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Flips horizontally between [front] and [back] when [showBack] changes.
class FlipCard extends StatefulWidget {
  const FlipCard({
    super.key,
    required this.front,
    required this.back,
    required this.showBack,
    this.duration = const Duration(milliseconds: 420),
  });

  final Widget front;
  final Widget back;

  /// Which face the card should settle on. Mounting with `showBack: true`
  /// starts settled on the back (no entrance flip).
  final bool showBack;

  /// Full half-turn duration.
  final Duration duration;

  @override
  State<FlipCard> createState() => _FlipCardState();
}

class _FlipCardState extends State<FlipCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
    value: widget.showBack ? 1.0 : 0.0,
  );
  late final CurvedAnimation _animation = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void didUpdateWidget(FlipCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.showBack == oldWidget.showBack) return;
    if (widget.showBack) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (BuildContext context, Widget? child) {
        final double t = _animation.value;
        final bool showingFront = t < 0.5;
        final Widget face = showingFront
            ? widget.front
            // Pre-rotate the back face by pi so that, combined with the
            // outer rotation, it reads left-to-right (un-mirrored).
            : Transform(
                alignment: Alignment.center,
                transform: Matrix4.rotationY(math.pi),
                child: widget.back,
              );
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.0015) // perspective
            ..rotateY(math.pi * t),
          child: face,
        );
      },
    );
  }
}

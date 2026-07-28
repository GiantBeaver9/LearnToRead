// Celebration confetti — pure-code port of the owner mockup's completion
// overlay (docs/design/mockup-spec.md §6, motion inventory §7):
//
//   ribbon   fall + spin to 520°, fade in by 12% / out at end
//                                       2.4-4.2s linear, delayed 0-1.1s
//   ringOut  scale 0.2→1.6, fade 0.9→0  1.1s ease-out
//   spark    radial fly 70-150px + fade 1.25s cubic-bezier(.15,.7,.3,1),
//                                       delayed 0-1.4s
//
// One AnimationController drives the whole overlay; every random parameter
// is drawn up-front from `Random(seed)` in generation order, so two
// overlays with equal (intensity, seed) are particle-for-particle
// identical — tests rely on this determinism.
//
// COLORS — the spec §1 five-color confetti set
// `#C6412F #D79A3C #4E8B5C #5A79B8 #B85C8A`, taken verbatim from
// [DesignTokens.confettiColors] (tokenized by the A-19 retheme; the
// local [confettiColors] alias is kept for API stability).
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// The spec §1 five-color confetti set — [DesignTokens.confettiColors]
/// verbatim (the mockup's brighter green/blue are correct here: confetti
/// is decoration, not text, so the AA-darkened word colors do not apply).
const List<Color> confettiColors = DesignTokens.confettiColors;

/// One falling, spinning confetti ribbon (spec §6). All values are drawn
/// deterministically from the overlay's seeded [math.Random].
@immutable
class ConfettiRibbon {
  const ConfettiRibbon({
    required this.xFraction,
    required this.width,
    required this.height,
    required this.durationSeconds,
    required this.delaySeconds,
    required this.color,
  });

  /// Horizontal position as a fraction of the overlay width (0-1).
  final double xFraction;

  /// Rect width, 5-11 px.
  final double width;

  /// Rect height, 12-26 px.
  final double height;

  /// Fall duration, 2.4-4.2 s (linear).
  final double durationSeconds;

  /// Start delay, 0-1.1 s.
  final double delaySeconds;

  final Color color;

  /// The moment (seconds from overlay start) this ribbon lands.
  double get endSeconds => delaySeconds + durationSeconds;

  @override
  bool operator ==(Object other) =>
      other is ConfettiRibbon &&
      other.xFraction == xFraction &&
      other.width == width &&
      other.height == height &&
      other.durationSeconds == durationSeconds &&
      other.delaySeconds == delaySeconds &&
      other.color == color;

  @override
  int get hashCode => Object.hash(
      xFraction, width, height, durationSeconds, delaySeconds, color);
}

/// One radial spark of a burst cluster (spec §6): a 7 px dot flying
/// 70-150 px outward over 1.25 s with cubic-bezier(.15,.7,.3,1), fading out.
@immutable
class ConfettiSpark {
  const ConfettiSpark({
    required this.angleRadians,
    required this.distance,
    required this.delaySeconds,
    required this.color,
  });

  final double angleRadians;

  /// Radial flight distance, 70-150 px.
  final double distance;

  /// Start delay, 0-1.4 s.
  final double delaySeconds;

  final Color color;

  /// Spec §6: 1.25s spark flight.
  static const double durationSeconds = 1.25;

  /// Spec §6: cubic-bezier(.15,.7,.3,1).
  static const Curve curve = Cubic(0.15, 0.7, 0.3, 1.0);

  double get endSeconds => delaySeconds + durationSeconds;

  @override
  bool operator ==(Object other) =>
      other is ConfettiSpark &&
      other.angleRadians == angleRadians &&
      other.distance == distance &&
      other.delaySeconds == delaySeconds &&
      other.color == color;

  @override
  int get hashCode =>
      Object.hash(angleRadians, distance, delaySeconds, color);
}

/// One burst cluster (spec §6): an expanding, fading ring plus 16 radial
/// sparks, centered at 18-82% x / 14-46% y.
@immutable
class ConfettiBurst {
  const ConfettiBurst({
    required this.xFraction,
    required this.yFraction,
    required this.ringColor,
    required this.sparks,
  });

  final double xFraction;
  final double yFraction;
  final Color ringColor;
  final List<ConfettiSpark> sparks;

  /// Spec §6: ring expands over 1.1s ease-out.
  static const double ringDurationSeconds = 1.1;

  /// Spec §6: 120px ring at scale 1 (drawn as radius 60 × scale).
  static const double ringBaseRadius = 60.0;

  double get endSeconds {
    double end = ringDurationSeconds;
    for (final ConfettiSpark spark in sparks) {
      end = math.max(end, spark.endSeconds);
    }
    return end;
  }

  @override
  bool operator ==(Object other) {
    if (other is! ConfettiBurst ||
        other.xFraction != xFraction ||
        other.yFraction != yFraction ||
        other.ringColor != ringColor ||
        other.sparks.length != sparks.length) {
      return false;
    }
    for (int i = 0; i < sparks.length; i++) {
      if (other.sparks[i] != sparks[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode =>
      Object.hash(xFraction, yFraction, ringColor, Object.hashAll(sparks));
}

/// Full-screen, non-interactive celebration overlay (spec §6): plays
/// `16 + 10 × intensity` falling ribbons plus `min(3, intensity)` burst
/// clusters once, then calls [onFinished] after the last ribbon lands.
///
/// All randomness comes from `Random(seed)`, so equal (intensity, seed)
/// pairs replay the identical celebration — deterministic under test.
/// Wrapped in [IgnorePointer]; it never intercepts the child's touches.
class ConfettiOverlay extends StatefulWidget {
  const ConfettiOverlay({
    super.key,
    required this.intensity,
    required this.seed,
    this.onFinished,
  });

  /// Celebration strength; spec §6: `min(3, stories-in-a-row)`.
  final int intensity;

  /// Seed for every random parameter (positions, sizes, delays, colors).
  final int seed;

  /// Called once, when the animation completes (last ribbon landed).
  final VoidCallback? onFinished;

  @override
  State<ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late final List<ConfettiRibbon> _ribbons;
  late final List<ConfettiBurst> _bursts;
  late final double _totalSeconds;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    final math.Random random = math.Random(widget.seed);

    double range(double min, double max) =>
        min + random.nextDouble() * (max - min);
    Color pick() => confettiColors[random.nextInt(confettiColors.length)];

    final int ribbonCount = 16 + 10 * math.max(0, widget.intensity);
    _ribbons = List<ConfettiRibbon>.generate(ribbonCount, (_) {
      return ConfettiRibbon(
        xFraction: random.nextDouble(),
        width: range(5, 11),
        height: range(12, 26),
        durationSeconds: range(2.4, 4.2),
        delaySeconds: range(0, 1.1),
        color: pick(),
      );
    });

    final int burstCount = math.max(0, math.min(3, widget.intensity));
    _bursts = List<ConfettiBurst>.generate(burstCount, (_) {
      final double x = range(0.18, 0.82);
      final double y = range(0.14, 0.46);
      final Color ringColor = pick();
      final List<ConfettiSpark> sparks =
          List<ConfettiSpark>.generate(16, (int i) {
        return ConfettiSpark(
          angleRadians: (i / 16) * 2 * math.pi + range(-0.12, 0.12),
          distance: range(70, 150),
          delaySeconds: range(0, 1.4),
          color: pick(),
        );
      });
      return ConfettiBurst(
        xFraction: x,
        yFraction: y,
        ringColor: ringColor,
        sparks: sparks,
      );
    });

    double total = 0;
    for (final ConfettiRibbon ribbon in _ribbons) {
      total = math.max(total, ribbon.endSeconds);
    }
    for (final ConfettiBurst burst in _bursts) {
      total = math.max(total, burst.endSeconds);
    }
    _totalSeconds = total;

    _controller = AnimationController(
      vsync: this,
      duration: Duration(microseconds: (_totalSeconds * 1e6).round()),
    );
    _controller.addStatusListener((AnimationStatus status) {
      if (status == AnimationStatus.completed) {
        widget.onFinished?.call();
      }
    });
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          return CustomPaint(
            size: Size.infinite,
            isComplex: true,
            willChange: !_controller.isCompleted,
            painter: ConfettiPainter(
              ribbons: _ribbons,
              bursts: _bursts,
              timeSeconds: _controller.value * _totalSeconds,
            ),
          );
        },
      ),
    );
  }
}

/// Paints one frame of the confetti celebration at [timeSeconds].
///
/// Pure function of (ribbons, bursts, timeSeconds, canvas size): equal
/// inputs paint identically, which is what the determinism tests pin.
class ConfettiPainter extends CustomPainter {
  const ConfettiPainter({
    required this.ribbons,
    required this.bursts,
    required this.timeSeconds,
  });

  final List<ConfettiRibbon> ribbons;
  final List<ConfettiBurst> bursts;
  final double timeSeconds;

  /// Spec §6: rotates to 520° over the fall.
  static const double _ribbonSpinRadians = 520 * math.pi / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint();

    for (final ConfettiRibbon ribbon in ribbons) {
      final double p = ((timeSeconds - ribbon.delaySeconds) /
              ribbon.durationSeconds)
          .clamp(0.0, 1.0);
      if (p <= 0.0 || p >= 1.0) continue;
      // Fade in by 12%, out over the final 10%.
      final double opacity = math.min(
        p < 0.12 ? p / 0.12 : 1.0,
        p > 0.9 ? (1.0 - p) / 0.1 : 1.0,
      );
      final double startY = -0.05 * size.height - ribbon.height;
      final double endY = 1.05 * size.height;
      final double y = startY + (endY - startY) * p;
      final double x = ribbon.xFraction * size.width;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(_ribbonSpinRadians * p);
      paint
        ..style = PaintingStyle.fill
        ..color = ribbon.color.withValues(alpha: opacity);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset.zero,
            width: ribbon.width,
            height: ribbon.height,
          ),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }

    for (final ConfettiBurst burst in bursts) {
      final Offset center = Offset(
        burst.xFraction * size.width,
        burst.yFraction * size.height,
      );

      // Expanding, fading ring: scale 0.2→1.6, opacity 0.9→0, 1.1s ease-out.
      final double ringP =
          (timeSeconds / ConfettiBurst.ringDurationSeconds).clamp(0.0, 1.0);
      if (ringP > 0.0 && ringP < 1.0) {
        final double eased = Curves.easeOut.transform(ringP);
        final double scale = 0.2 + (1.6 - 0.2) * eased;
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color =
              burst.ringColor.withValues(alpha: 0.9 * (1.0 - ringP));
        canvas.drawCircle(center, ConfettiBurst.ringBaseRadius * scale, paint);
      }

      for (final ConfettiSpark spark in burst.sparks) {
        final double sp = ((timeSeconds - spark.delaySeconds) /
                ConfettiSpark.durationSeconds)
            .clamp(0.0, 1.0);
        if (sp <= 0.0 || sp >= 1.0) continue;
        final double eased = ConfettiSpark.curve.transform(sp);
        final Offset position = center +
            Offset(math.cos(spark.angleRadians), math.sin(spark.angleRadians)) *
                (spark.distance * eased);
        paint
          ..style = PaintingStyle.fill
          ..color = spark.color.withValues(alpha: 1.0 - sp);
        canvas.drawCircle(position, 3.5, paint);
      }
    }
  }

  @override
  bool shouldRepaint(ConfettiPainter oldDelegate) =>
      oldDelegate.timeSeconds != timeSeconds ||
      !identical(oldDelegate.ribbons, ribbons) ||
      !identical(oldDelegate.bursts, bursts);
}

/// The tongue-twister sparkle celebration (PRD §8 Unit 14: "playful sparkle
/// celebration. No collectible (collectibles remain story-tied)"; ticket
/// twister-flow).
///
/// Deliberately a *different* celebration from the story one (Unit 8), and
/// structurally so, not just stylistically:
///
/// - **No Rive story artboard.** The story celebration drives a `RiveStage`
///   artboard; a twister has no story scene to animate, so nothing here
///   touches Rive at all.
/// - **No collectible flight.** Twisters grant no collectible, so the
///   post-celebration flight beat (`DesignTokens.collectibleFlightDuration`)
///   that follows a story completion has no counterpart here. This widget
///   finishes at exactly its own [kSparkleCelebrationDuration] with nothing
///   tacked on after it.
/// - **Its own, shorter duration.** Two seconds, against the story
///   celebration's `kCelebrationDefaultAnimationDuration` — a booster is a
///   quick "nice one!", not a chapter ending. There is likewise no skip
///   affordance and no celebration voice line to rotate: the whole
///   post-completion sequence *is* this widget.
///
/// The constructor takes only [onFinished] and [duration]: no story stage,
/// no collectible ref, no analytics sink. There is structurally nothing for
/// a story-shaped reward to hang off.
///
/// **Placeholder art (PRD §10 OQ-8).** The shipped treatment is
/// owner-commissioned illustration/motion in the Unit 1 storybook direction.
/// Until that asset lands this paints a token-colored sparkle burst — enough
/// to read as a distinct, playful beat, and deliberately not something a
/// pixel golden should be pinned to (see the `[DEVICE]` skip in
/// twister_flow_test.dart).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'package:learn_to_read/design/tokens.dart';

/// How long the sparkle beat lasts before [SparkleCelebration.onFinished]
/// fires. Shorter than the story celebration's
/// `kCelebrationDefaultAnimationDuration` on purpose — see the library doc.
const Duration kSparkleCelebrationDuration = Duration(seconds: 2);

/// A playful, self-contained sparkle beat shown when a tongue twister is
/// completed.
///
/// Calls [onFinished] exactly once, [duration] after it is first built. The
/// caller owns what happens next (dismissing the node, offering the
/// "faster" second pass); this widget grants nothing and records nothing.
class SparkleCelebration extends StatelessWidget {
  /// Creates a sparkle celebration that finishes after [duration].
  const SparkleCelebration({
    super.key,
    required this.onFinished,
    this.duration = kSparkleCelebrationDuration,
  });

  /// Invoked once, [duration] after the celebration first appears.
  final VoidCallback onFinished;

  /// How long the beat lasts. Defaults to [kSparkleCelebrationDuration].
  final Duration duration;

  @override
  Widget build(BuildContext context) =>
      _SparkleStage(onFinished: onFinished, duration: duration);
}

/// Owns the one-shot finish timer. Private so [SparkleCelebration]'s public
/// shape stays the pinned stateless one.
class _SparkleStage extends StatefulWidget {
  const _SparkleStage({required this.onFinished, required this.duration});

  final VoidCallback onFinished;
  final Duration duration;

  @override
  State<_SparkleStage> createState() => _SparkleStageState();
}

class _SparkleStageState extends State<_SparkleStage> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // A plain timer, not an animation controller: the beat's *length* is the
    // contract (nothing is appended after it), while the motion inside it is
    // placeholder art until the commissioned asset lands.
    _timer = Timer(widget.duration, widget.onFinished);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: DesignTokens.screenBackground,
      child: Center(
        child: SizedBox.square(
          dimension: 240,
          child: CustomPaint(painter: const _SparkleBurstPainter()),
        ),
      ),
    );
  }
}

/// Paints a small ring of four-point sparkles in token colors.
///
/// Placeholder composition (OQ-8): geometry only, no bundled asset, no Rive
/// artboard, no collectible.
class _SparkleBurstPainter extends CustomPainter {
  const _SparkleBurstPainter();

  static const int _sparkleCount = 7;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2;
    final paint = Paint()..style = PaintingStyle.fill;

    for (var i = 0; i < _sparkleCount; i++) {
      final angle = (2 * math.pi * i) / _sparkleCount;
      final distance = radius * (i.isEven ? 0.82 : 0.52);
      final origin = center + Offset(math.cos(angle), math.sin(angle)) * distance;
      final armLength = radius * (i.isEven ? 0.16 : 0.11);
      paint.color = i.isEven
          ? DesignTokens.wordReadGreen
          : DesignTokens.wordVocabBlue;
      canvas.drawPath(_sparklePath(origin, armLength), paint);
    }
  }

  /// A four-point "twinkle": two crossed spikes with pinched waists.
  Path _sparklePath(Offset origin, double arm) {
    final waist = arm * 0.24;
    return Path()
      ..moveTo(origin.dx, origin.dy - arm)
      ..quadraticBezierTo(origin.dx + waist, origin.dy - waist, origin.dx + arm, origin.dy)
      ..quadraticBezierTo(origin.dx + waist, origin.dy + waist, origin.dx, origin.dy + arm)
      ..quadraticBezierTo(origin.dx - waist, origin.dy + waist, origin.dx - arm, origin.dy)
      ..quadraticBezierTo(origin.dx - waist, origin.dy - waist, origin.dx, origin.dy - arm)
      ..close();
  }

  @override
  bool shouldRepaint(covariant _SparkleBurstPainter oldDelegate) => false;
}

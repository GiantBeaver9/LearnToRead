// Reusable motion library — Flutter ports of the owner mockup's CSS
// keyframe animations (docs/design/mockup-spec.md §4 listening pill,
// §7 motion inventory). Durations and curves are copied EXACTLY from the
// spec's motion inventory table:
//
//   fadeUp       opacity 0→1, y +14→0            380ms ease-out (320-420ms band)
//   sceneReveal  scale .94, rot −0.6° → identity  620ms cubic-bezier(.2,.9,.25,1)
//   pulseWord    y −2px + scale 1.04 at 50%       1.3s ease-in-out, infinite
//   wave         scaleY 0.35↔1, origin bottom     900ms ease-in-out ∞, 120ms stagger
//
// The listening-waveform reds flow from [DesignTokens.listeningRed] /
// [DesignTokens.listeningRedAlt] (tokenized by the A-19 retheme); the
// local aliases below are kept for API stability. No raw colors exist in
// this file.
import 'package:flutter/widgets.dart';

import 'tokens.dart';

/// Listening-waveform bar red (`#C6412F`, spec §4) —
/// [DesignTokens.listeningRed].
const Color kListeningRed = DesignTokens.listeningRed;

/// Alternate (odd-index) waveform bar red (`#D0684F`, spec §4) —
/// [DesignTokens.listeningRedAlt].
const Color kListeningRedAlt = DesignTokens.listeningRedAlt;

/// A symmetric up-then-down keyframe ramp: 0 at [t]=0, 1 at [t]=0.5, 0 at
/// [t]=1, easing in and out of each keyframe segment exactly like a CSS
/// `ease-in-out` animation with a 50% peak keyframe.
double _upDownKeyframe(double t) {
  final double clamped = t.clamp(0.0, 1.0);
  return clamped <= 0.5
      ? Curves.easeInOut.transform(clamped * 2)
      : Curves.easeInOut.transform((1 - clamped) * 2);
}

/// `fadeUp` (spec §7): fades the child in (opacity 0→1) while translating it
/// up from +14 logical px to rest, once, on mount.
///
/// Defaults: 380 ms, [Curves.easeOut] — the middle of the spec's
/// 320-420 ms band; callers with a spec'd exact duration (hint panel 380,
/// vocab popup 320, done column 420) pass it explicitly.
class FadeUp extends StatefulWidget {
  const FadeUp({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 380),
    this.curve = Curves.easeOut,
  });

  final Widget child;
  final Duration duration;
  final Curve curve;

  @override
  State<FadeUp> createState() => _FadeUpState();
}

class _FadeUpState extends State<FadeUp> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..forward();
  late final CurvedAnimation _animation = CurvedAnimation(
    parent: _controller,
    curve: widget.curve,
  );

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: AnimatedBuilder(
        animation: _animation,
        child: widget.child,
        builder: (BuildContext context, Widget? child) {
          final double dy = 14.0 * (1 - _animation.value);
          if (dy == 0.0) return child!;
          return Transform.translate(offset: Offset(0, dy), child: child);
        },
      ),
    );
  }
}

/// `sceneReveal` (spec §5/§7): the done-state stage entrance — from
/// opacity 0, scale 0.94, rotation −0.6° to identity over 620 ms with
/// cubic-bezier(.2,.9,.25,1). Plays once on mount.
class SceneReveal extends StatefulWidget {
  const SceneReveal({super.key, required this.child});

  final Widget child;

  /// Spec §7: 620ms.
  static const Duration duration = Duration(milliseconds: 620);

  /// Spec §7: cubic-bezier(.2,.9,.25,1).
  static const Curve curve = Cubic(0.2, 0.9, 0.25, 1.0);

  @override
  State<SceneReveal> createState() => _SceneRevealState();
}

class _SceneRevealState extends State<SceneReveal>
    with SingleTickerProviderStateMixin {
  static const double _startScale = 0.94;
  static const double _startRotationDegrees = -0.6;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: SceneReveal.duration,
  )..forward();
  late final CurvedAnimation _animation = CurvedAnimation(
    parent: _controller,
    curve: SceneReveal.curve,
  );

  @override
  void dispose() {
    _animation.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _animation,
      child: AnimatedBuilder(
        animation: _animation,
        child: widget.child,
        builder: (BuildContext context, Widget? child) {
          final double v = _animation.value;
          final double scale = _startScale + (1 - _startScale) * v;
          final double radians =
              _startRotationDegrees * (1 - v) * (3.1415926535897932 / 180);
          return Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationZ(radians)..scale(scale, scale),
            child: child,
          );
        },
      ),
    );
  }
}

/// `pulseWord` (spec §3/§7): the stuck/hint-word pulse — while [active],
/// loops translateY(−2px) + scale(1.04) at the 50% keyframe over 1.3 s
/// ease-in-out, infinitely.
///
/// While inactive the child is rendered statically (no transform in the
/// tree). Toggling [active] off mid-cycle settles cleanly: the pulse glides
/// back to identity at its natural speed instead of snapping.
class PulseWord extends StatefulWidget {
  const PulseWord({super.key, required this.child, required this.active});

  final Widget child;
  final bool active;

  /// Spec §7: 1.3s per cycle.
  static const Duration period = Duration(milliseconds: 1300);

  @override
  State<PulseWord> createState() => _PulseWordState();
}

class _PulseWordState extends State<PulseWord>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: PulseWord.period,
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(PulseWord oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active == oldWidget.active) return;
    if (widget.active) {
      _controller.repeat();
    } else {
      _settle();
    }
  }

  /// Glides the cycle to its nearest identity keyframe (0.0 or 1.0) at the
  /// loop's natural speed, so a mid-cycle deactivation never snaps.
  void _settle() {
    final double v = _controller.value;
    _controller.stop();
    if (v == 0.0 || v == 1.0) return;
    if (v <= 0.5) {
      _controller.animateBack(0.0, duration: PulseWord.period * v);
    } else {
      _controller.animateTo(1.0, duration: PulseWord.period * (1 - v));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (BuildContext context, Widget? child) {
        final double v = _upDownKeyframe(_controller.value);
        if (v == 0.0) return child!;
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.translationValues(0, -2.0 * v, 0)
            ..scale(1 + 0.04 * v, 1 + 0.04 * v),
          child: child,
        );
      },
    );
  }
}

/// `wave` (spec §4/§7): the listening-pill waveform — [barCount] rounded
/// bars, 4 px wide, colors alternating [color]/[altColor] (defaults: the two
/// listening reds), each bar's scaleY oscillating 0.35↔1 about its bottom
/// edge over 900 ms ease-in-out, repeating forever with a 120 ms stagger
/// per bar.
class WaveBars extends StatefulWidget {
  const WaveBars({
    super.key,
    this.barCount = 6,
    this.height = 26,
    this.color,
    this.altColor,
  });

  final int barCount;
  final double height;

  /// Even-index bar color; defaults to [kListeningRed].
  final Color? color;

  /// Odd-index bar color; defaults to [kListeningRedAlt].
  final Color? altColor;

  /// Spec §7: 900ms per cycle.
  static const Duration period = Duration(milliseconds: 900);

  /// Spec §7: 120ms stagger per bar.
  static const Duration stagger = Duration(milliseconds: 120);

  static const double _barWidth = 4.0;
  static const double _barGap = 3.0;
  static const double _minScaleY = 0.35;

  @override
  State<WaveBars> createState() => _WaveBarsState();
}

class _WaveBarsState extends State<WaveBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: WaveBars.period,
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double _scaleYForBar(int index) {
    final double staggerFraction = WaveBars.stagger.inMilliseconds /
        WaveBars.period.inMilliseconds;
    final double phase =
        (_controller.value - index * staggerFraction) % 1.0;
    final double positivePhase = phase < 0 ? phase + 1.0 : phase;
    return WaveBars._minScaleY +
        (1 - WaveBars._minScaleY) * _upDownKeyframe(positivePhase);
  }

  @override
  Widget build(BuildContext context) {
    final Color evenColor = widget.color ?? kListeningRed;
    final Color oddColor = widget.altColor ?? kListeningRedAlt;
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            for (int i = 0; i < widget.barCount; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: WaveBars._barGap),
              Transform.scale(
                scaleY: _scaleYForBar(i),
                alignment: Alignment.bottomCenter,
                child: Container(
                  width: WaveBars._barWidth,
                  height: widget.height,
                  decoration: BoxDecoration(
                    color: i.isEven ? evenColor : oddColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

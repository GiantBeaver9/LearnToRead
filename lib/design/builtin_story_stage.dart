// BuiltInStoryStage — a pure-code, token-styled [StoryStage] so story
// completion shows a VISIBLE animation today (owner direction: "getting
// basic animation running"), while licensed Rive art remains a future
// deliverable (see rive_stage.dart's file comment).
//
// The stage is a warm "Sound It Out" storybook scene drawn entirely with
// canvas primitives and [DesignTokens] colors (token-lint: this file is
// under lib/design/ and therefore may not define raw color/font literals —
// every color below is a token or a derivation of tokens via lerp/alpha):
//
//   idle       a calm parchment sky, a soft amber sun, slowly drifting
//              clouds, rolling hills, and a row of gently bobbing syllable
//              chips ("sound pebbles") — quiet enough to sit beside a
//              child who is reading;
//   celebrate  the scene wakes up: the pebbles bounce and brighten to the
//              full confetti palette, the sun grows rays, and sparkle
//              rings + radial glints burst over the scene (mockup-spec §5
//              scene-reveal / §6 ringOut+spark language);
//   collect    an amber star arcs across the sky and settles on the
//              nearest hill, leaving a short fading trail, after which
//              only the calm ambient motion remains.
//
// Every random arrangement parameter is drawn up-front from
// `Random(sceneSeed)` in generation order ([BuiltInStoryScene.generate]),
// so two stages with equal seeds render pixel-identical scenes —
// deterministic under test, and different stories can look different by
// seeding differently.
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'rive_stage.dart';
import 'tokens.dart';

/// A [StoryStage] whose scene is drawn in code rather than played from a
/// Rive artboard.
///
/// It is also a [ChangeNotifier]: [trigger] updates [activeState] and
/// notifies, so [BuiltInStoryStageView] (and tests) can observe state
/// changes. Re-triggering the same input notifies again — [triggerCount]
/// distinguishes the firings — so, e.g., poking a collectible twice replays
/// the collect beat twice.
class BuiltInStoryStage extends ChangeNotifier implements StoryStage {
  BuiltInStoryStage({this.sceneSeed = 0});

  /// Seed for the scene's deterministic arrangement (cloud/pebble/burst
  /// placement). Equal seeds produce identical scenes.
  final int sceneSeed;

  StoryStageInput _activeState = StoryStageInput.idle;
  int _triggerCount = 0;

  @override
  StoryStageInput get activeState => _activeState;

  /// How many times [trigger] has fired, counting repeats of the same
  /// input. The view uses this to restart a beat on a repeated trigger.
  int get triggerCount => _triggerCount;

  @override
  void trigger(StoryStageInput input) {
    _activeState = input;
    _triggerCount++;
    notifyListeners();
  }
}

/// One drifting cloud of the idle sky.
@immutable
class SceneCloud {
  const SceneCloud({
    required this.yFraction,
    required this.radiusFraction,
    required this.speed,
    required this.phase,
  });

  /// Vertical center, as a fraction of stage height.
  final double yFraction;

  /// Puff radius, as a fraction of stage width.
  final double radiusFraction;

  /// Horizontal crossings per ambient cycle (slow: well under 1).
  final double speed;

  /// Starting horizontal phase (0-1 of the drift loop).
  final double phase;

  @override
  bool operator ==(Object other) =>
      other is SceneCloud &&
      other.yFraction == yFraction &&
      other.radiusFraction == radiusFraction &&
      other.speed == speed &&
      other.phase == phase;

  @override
  int get hashCode => Object.hash(yFraction, radiusFraction, speed, phase);
}

/// One "sound pebble" — a rounded syllable-chip shape resting on the hills.
@immutable
class SceneChip {
  const SceneChip({
    required this.xFraction,
    required this.widthFraction,
    required this.colorIndex,
    required this.bobPhase,
  });

  /// Horizontal center, as a fraction of stage width.
  final double xFraction;

  /// Chip width, as a fraction of stage width.
  final double widthFraction;

  /// Index into [DesignTokens.confettiColors].
  final int colorIndex;

  /// Stagger phase for the gentle ambient bob (0-1).
  final double bobPhase;

  @override
  bool operator ==(Object other) =>
      other is SceneChip &&
      other.xFraction == xFraction &&
      other.widthFraction == widthFraction &&
      other.colorIndex == colorIndex &&
      other.bobPhase == bobPhase;

  @override
  int get hashCode =>
      Object.hash(xFraction, widthFraction, colorIndex, bobPhase);
}

/// The full deterministic arrangement of one stage scene.
///
/// Pure value object: equal seeds generate equal scenes (`==` compares every
/// element), which is what the determinism tests pin.
@immutable
class BuiltInStoryScene {
  const BuiltInStoryScene({
    required this.seed,
    required this.sunXFraction,
    required this.sunYFraction,
    required this.clouds,
    required this.chips,
    required this.burstXFractions,
    required this.burstYFractions,
    required this.sparkleAngleOffset,
    required this.hillShiftFraction,
  });

  /// Generates the scene arrangement for [seed]; every random parameter is
  /// drawn from `Random(seed)` in a fixed order.
  factory BuiltInStoryScene.generate(int seed) {
    final math.Random random = math.Random(seed);
    double range(double min, double max) =>
        min + random.nextDouble() * (max - min);

    final double sunX = range(0.14, 0.86);
    final double sunY = range(0.16, 0.28);
    final List<SceneCloud> clouds = List<SceneCloud>.generate(3, (_) {
      return SceneCloud(
        yFraction: range(0.12, 0.42),
        radiusFraction: range(0.06, 0.11),
        speed: range(0.35, 0.8),
        phase: random.nextDouble(),
      );
    });
    final int chipCount = 3 + random.nextInt(2);
    final List<SceneChip> chips = List<SceneChip>.generate(chipCount, (int i) {
      final double lane = (i + 0.5) / chipCount;
      return SceneChip(
        xFraction: (lane + range(-0.06, 0.06)).clamp(0.08, 0.92),
        widthFraction: range(0.09, 0.14),
        colorIndex: random.nextInt(DesignTokens.confettiColors.length),
        bobPhase: random.nextDouble(),
      );
    });
    final List<double> burstX =
        List<double>.generate(2, (_) => range(0.22, 0.78));
    final List<double> burstY =
        List<double>.generate(2, (_) => range(0.18, 0.48));

    return BuiltInStoryScene(
      seed: seed,
      sunXFraction: sunX,
      sunYFraction: sunY,
      clouds: clouds,
      chips: chips,
      burstXFractions: burstX,
      burstYFractions: burstY,
      sparkleAngleOffset: range(0, 2 * math.pi),
      hillShiftFraction: range(-0.12, 0.12),
    );
  }

  final int seed;
  final double sunXFraction;
  final double sunYFraction;
  final List<SceneCloud> clouds;
  final List<SceneChip> chips;

  /// Celebrate sparkle-ring centers (fractions of width/height).
  final List<double> burstXFractions;
  final List<double> burstYFractions;

  /// Rotation offset for the celebrate glint fan.
  final double sparkleAngleOffset;

  /// Horizontal offset of the near hill's crest (fraction of width).
  final double hillShiftFraction;

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      other is BuiltInStoryScene &&
      other.seed == seed &&
      other.sunXFraction == sunXFraction &&
      other.sunYFraction == sunYFraction &&
      _listEquals(other.clouds, clouds) &&
      _listEquals(other.chips, chips) &&
      _listEquals(other.burstXFractions, burstXFractions) &&
      _listEquals(other.burstYFractions, burstYFractions) &&
      other.sparkleAngleOffset == sparkleAngleOffset &&
      other.hillShiftFraction == hillShiftFraction;

  @override
  int get hashCode => Object.hash(
        seed,
        sunXFraction,
        sunYFraction,
        Object.hashAll(clouds),
        Object.hashAll(chips),
        Object.hashAll(burstXFractions),
        Object.hashAll(burstYFractions),
        sparkleAngleOffset,
        hillShiftFraction,
      );
}

/// Renders a [BuiltInStoryStage] and animates it per [StoryStage] state.
///
/// The view listens to the stage (a [ChangeNotifier]) and rebuilds on every
/// trigger. Two animation drivers exist:
///
///  * an ambient loop (slow, calm — the only motion while idle), and
///  * a finite "beat" that plays once per celebrate/collect trigger
///    (collect's duration is [DesignTokens.collectibleFlightDuration], the
///    same token the celebration controller waits on).
///
/// Tickers run through [TickerProviderStateMixin], so `TickerMode`
/// (e.g. a paused route) mutes them; disposal stops them outright. Tests
/// drive this view with stepped pumps — the ambient loop never settles.
class BuiltInStoryStageView extends StatefulWidget {
  const BuiltInStoryStageView({super.key, required this.stage});

  final BuiltInStoryStage stage;

  /// One full ambient cycle (cloud drift / pebble bob) — slow and calm.
  static const Duration ambientPeriod = Duration(seconds: 6);

  /// The celebrate wake-up beat length.
  static const Duration celebrateBeatDuration = Duration(milliseconds: 1100);

  @override
  State<BuiltInStoryStageView> createState() => _BuiltInStoryStageViewState();
}

class _BuiltInStoryStageViewState extends State<BuiltInStoryStageView>
    with TickerProviderStateMixin {
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: BuiltInStoryStageView.ambientPeriod,
  )..repeat();

  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: BuiltInStoryStageView.celebrateBeatDuration,
  );

  late BuiltInStoryScene _scene;

  @override
  void initState() {
    super.initState();
    _scene = BuiltInStoryScene.generate(widget.stage.sceneSeed);
    widget.stage.addListener(_onStageChanged);
    _syncBeatToState();
  }

  @override
  void didUpdateWidget(BuiltInStoryStageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.stage, widget.stage)) return;
    oldWidget.stage.removeListener(_onStageChanged);
    widget.stage.addListener(_onStageChanged);
    _scene = BuiltInStoryScene.generate(widget.stage.sceneSeed);
    _syncBeatToState();
  }

  @override
  void dispose() {
    widget.stage.removeListener(_onStageChanged);
    _ambient.dispose();
    _beat.dispose();
    super.dispose();
  }

  void _onStageChanged() {
    if (!mounted) return;
    setState(_syncBeatToState);
  }

  /// Restarts/stops the finite beat to match the stage's active state.
  void _syncBeatToState() {
    switch (widget.stage.activeState) {
      case StoryStageInput.idle:
        _beat.stop();
        _beat.value = 0;
      case StoryStageInput.celebrate:
        _beat.duration = BuiltInStoryStageView.celebrateBeatDuration;
        _beat.forward(from: 0);
      case StoryStageInput.collect:
        _beat.duration = DesignTokens.collectibleFlightDuration;
        _beat.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final StoryStageInput state = widget.stage.activeState;
    return RepaintBoundary(
      key: const ValueKey<String>('builtin-story-stage'),
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[_ambient, _beat]),
        builder: (BuildContext context, Widget? child) {
          return CustomPaint(
            // A per-state key so tests (and tooling) can see which scene
            // program is on stage without inspecting paint output.
            key: ValueKey<String>('builtin-stage-${state.name}'),
            isComplex: true,
            willChange: true,
            painter: BuiltInStoryStagePainter(
              scene: _scene,
              state: state,
              ambientValue: _ambient.value,
              beatValue: _beat.value,
            ),
            child: const SizedBox.expand(),
          );
        },
      ),
    );
  }
}

/// Paints one frame of the built-in scene.
///
/// Pure function of (scene, state, ambientValue, beatValue, canvas size):
/// equal inputs paint identically.
class BuiltInStoryStagePainter extends CustomPainter {
  const BuiltInStoryStagePainter({
    required this.scene,
    required this.state,
    required this.ambientValue,
    required this.beatValue,
  });

  final BuiltInStoryScene scene;
  final StoryStageInput state;

  /// Ambient loop progress, 0-1 (wraps).
  final double ambientValue;

  /// Finite beat progress, 0-1 (0 while idle).
  final double beatValue;

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    if (w <= 0 || h <= 0) return;
    final Paint paint = Paint()..isAntiAlias = true;

    // How "awake" the scene is: 0 while idle/collect, ramping to 1 over the
    // celebrate beat (and holding there while celebrate stays active).
    final double wake = state == StoryStageInput.celebrate
        ? Curves.easeOut.transform(beatValue.clamp(0.0, 1.0))
        : 0.0;

    _paintSky(canvas, size, paint, wake);
    _paintSun(canvas, size, paint, wake);
    _paintClouds(canvas, size, paint);
    _paintHills(canvas, size, paint);
    _paintChips(canvas, size, paint, wake);
    if (state == StoryStageInput.celebrate) {
      _paintCelebrateBursts(canvas, size, paint);
    }
    if (state == StoryStageInput.collect) {
      _paintCollectStar(canvas, size, paint);
    }
  }

  // -- layers ------------------------------------------------------------

  void _paintSky(Canvas canvas, Size size, Paint paint, double wake) {
    final Color calmTop = Color.lerp(
      DesignTokens.hintPanelBackground,
      DesignTokens.readingBackground,
      0.55,
    )!;
    // Celebration brightens the sky toward the warm hint parchment.
    final Color top =
        Color.lerp(calmTop, DesignTokens.hintPanelBackground, wake)!;
    final Color bottom = Color.lerp(
      DesignTokens.screenBackground,
      DesignTokens.hintPanelBackground,
      wake * 0.5,
    )!;
    final Rect rect = Offset.zero & size;
    paint
      ..style = PaintingStyle.fill
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[top, bottom],
      ).createShader(rect);
    canvas.drawRect(rect, paint);
    paint.shader = null;
  }

  void _paintSun(Canvas canvas, Size size, Paint paint, double wake) {
    final Offset center =
        Offset(scene.sunXFraction * size.width, scene.sunYFraction * size.height);
    final double radius = size.shortestSide * (0.075 + 0.02 * wake);

    // Soft halo, breathing very slightly with the ambient loop.
    final double breathe =
        0.5 + 0.5 * math.sin(2 * math.pi * ambientValue);
    paint
      ..style = PaintingStyle.fill
      ..color = DesignTokens.wordCurrentInk
          .withValues(alpha: 0.14 + 0.05 * breathe + 0.1 * wake);
    canvas.drawCircle(center, radius * (1.9 + 0.12 * breathe), paint);

    // Rays fan out as the scene wakes up.
    if (wake > 0) {
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.shortestSide * 0.014
        ..strokeCap = StrokeCap.round
        ..color = DesignTokens.wordCurrentInk.withValues(alpha: 0.75 * wake);
      for (int i = 0; i < 8; i++) {
        final double angle =
            i * math.pi / 4 + 2 * math.pi * ambientValue * 0.1;
        final Offset direction = Offset(math.cos(angle), math.sin(angle));
        canvas.drawLine(
          center + direction * radius * 1.45,
          center + direction * radius * (1.45 + 0.55 * wake),
          paint,
        );
      }
      paint
        ..style = PaintingStyle.fill
        ..strokeCap = StrokeCap.butt;
    }

    paint.color = Color.lerp(
      DesignTokens.wordCurrentInk,
      DesignTokens.readingBackground,
      0.18,
    )!;
    canvas.drawCircle(center, radius, paint);
  }

  void _paintClouds(Canvas canvas, Size size, Paint paint) {
    paint
      ..style = PaintingStyle.fill
      ..color = DesignTokens.readingBackground.withValues(alpha: 0.9);
    for (final SceneCloud cloud in scene.clouds) {
      // Drift left-to-right on a loop that extends past both edges.
      final double t = (cloud.phase + ambientValue * cloud.speed) % 1.0;
      final double x = (-0.25 + 1.5 * t) * size.width;
      final double y = cloud.yFraction * size.height;
      final double r = cloud.radiusFraction * size.width;
      canvas.drawCircle(Offset(x, y), r, paint);
      canvas.drawCircle(Offset(x - r * 0.9, y + r * 0.25), r * 0.72, paint);
      canvas.drawCircle(Offset(x + r * 0.9, y + r * 0.28), r * 0.66, paint);
    }
  }

  void _paintHills(Canvas canvas, Size size, Paint paint) {
    final double w = size.width;
    final double h = size.height;
    final double shift = scene.hillShiftFraction * w;

    paint
      ..style = PaintingStyle.fill
      ..color = Color.lerp(
        DesignTokens.successPanelBackground,
        DesignTokens.successDeepGreen,
        0.16,
      )!;
    final Path farHill = Path()
      ..moveTo(0, h * 0.82)
      ..quadraticBezierTo(w * 0.28 - shift, h * 0.66, w * 0.62, h * 0.8)
      ..quadraticBezierTo(w * 0.85, h * 0.88, w, h * 0.84)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(farHill, paint);

    paint.color = Color.lerp(
      DesignTokens.successPanelBackground,
      DesignTokens.successDeepGreen,
      0.3,
    )!;
    final Path nearHill = Path()
      ..moveTo(0, h * 0.92)
      ..quadraticBezierTo(w * 0.55 + shift, h * 0.74, w, h * 0.9)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(nearHill, paint);
  }

  void _paintChips(Canvas canvas, Size size, Paint paint, double wake) {
    final double w = size.width;
    final double h = size.height;
    paint.style = PaintingStyle.fill;

    for (int i = 0; i < scene.chips.length; i++) {
      final SceneChip chip = scene.chips[i];
      final double chipW = chip.widthFraction * w * 1.0;
      final double chipH = chipW * 0.68;

      // Gentle staggered bob; amplitude grows a little when awake.
      final double bob = math.sin(
            2 * math.pi * (ambientValue + chip.bobPhase),
          ) *
          (h * 0.006 + h * 0.012 * wake);

      // Celebrate: an overshooting pop plus a settling wobble.
      final double pop = wake == 0
          ? 0.0
          : Curves.easeOutBack.transform(beatValue.clamp(0.0, 1.0));
      final double scale = 1 + 0.3 * pop;
      final double wobble = wake == 0
          ? 0.0
          : math.sin(beatValue * math.pi * 3) * 0.1 * (1 - beatValue);

      final Color base = DesignTokens
          .confettiColors[chip.colorIndex % DesignTokens.confettiColors.length];
      // Muted while reading; full-strength when the scene wakes up.
      paint.color = Color.lerp(
        base.withValues(alpha: 0.55),
        base,
        wake,
      )!;

      final Offset center = Offset(
        chip.xFraction * w,
        h * 0.82 - chipH / 2 + bob,
      );
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(wobble);
      canvas.scale(scale, scale);
      final RRect rrect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: chipW, height: chipH),
        Radius.circular(chipH * 0.42),
      );
      canvas.drawRRect(rrect, paint);
      // A small parchment highlight so the pebble reads as a chip face.
      paint.color = DesignTokens.readingBackground
          .withValues(alpha: 0.35 + 0.25 * wake);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(0, -chipH * 0.18),
            width: chipW * 0.62,
            height: chipH * 0.28,
          ),
          Radius.circular(chipH * 0.14),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  void _paintCelebrateBursts(Canvas canvas, Size size, Paint paint) {
    final double t = beatValue.clamp(0.0, 1.0);
    if (t >= 1.0) return; // Bursts are the beat's transient flourish.
    final double eased = Curves.easeOut.transform(t);

    // Expanding, fading sparkle rings (the mockup's ringOut language).
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    for (int i = 0; i < scene.burstXFractions.length; i++) {
      final Offset center = Offset(
        scene.burstXFractions[i] * size.width,
        scene.burstYFractions[i] * size.height,
      );
      final Color ringColor = DesignTokens
          .confettiColors[(scene.seed + i) % DesignTokens.confettiColors.length];
      paint.color = ringColor.withValues(alpha: 0.9 * (1 - t));
      canvas.drawCircle(
        center,
        size.shortestSide * (0.08 + 0.4 * eased),
        paint,
      );
    }

    // Radial glints flying out from the scene's heart.
    paint.style = PaintingStyle.fill;
    final Offset heart = Offset(size.width * 0.5, size.height * 0.45);
    for (int i = 0; i < 10; i++) {
      final double angle =
          scene.sparkleAngleOffset + i * 2 * math.pi / 10;
      final double reach =
          size.shortestSide * (0.16 + 0.3 * ((i * 37) % 100) / 100);
      final Offset position = heart +
          Offset(math.cos(angle), math.sin(angle)) * reach * eased;
      final Color glint =
          DesignTokens.confettiColors[i % DesignTokens.confettiColors.length];
      paint.color = glint.withValues(alpha: 1 - t);
      canvas.drawCircle(position, size.shortestSide * 0.014, paint);
    }
  }

  void _paintCollectStar(Canvas canvas, Size size, Paint paint) {
    final double w = size.width;
    final double h = size.height;
    final double t = Curves.easeInOutCubic.transform(beatValue.clamp(0.0, 1.0));

    // Quadratic arc from the upper left across the sky to the near hill.
    Offset arc(double p) {
      const Offset a = Offset(0.14, 0.24);
      const Offset control = Offset(0.5, -0.04);
      const Offset b = Offset(0.8, 0.78);
      final double inv = 1 - p;
      final Offset f = a * (inv * inv) + control * (2 * inv * p) + b * (p * p);
      return Offset(f.dx * w, f.dy * h);
    }

    // Fading trail behind the flying star.
    if (t < 1.0) {
      paint.style = PaintingStyle.fill;
      for (int i = 1; i <= 3; i++) {
        final double back = t - i * 0.07;
        if (back <= 0) continue;
        paint.color = DesignTokens.wordCurrentInk
            .withValues(alpha: (1 - t) * (0.5 - 0.13 * i));
        canvas.drawCircle(arc(back), size.shortestSide * 0.014, paint);
      }
    }

    // Settled: a soft resting glow plus a gentle ambient bob.
    final double bob = t >= 1.0
        ? math.sin(2 * math.pi * ambientValue) * h * 0.006
        : 0.0;
    final Offset position = arc(t) + Offset(0, bob);
    final double radius = size.shortestSide * (0.05 + 0.015 * t);

    if (t >= 1.0) {
      paint
        ..style = PaintingStyle.fill
        ..color = DesignTokens.wordCurrentInk.withValues(alpha: 0.2);
      canvas.drawCircle(position, radius * 1.7, paint);
    }

    paint
      ..style = PaintingStyle.fill
      ..color = Color.lerp(
        DesignTokens.wordCurrentInk,
        DesignTokens.readingBackground,
        0.12,
      )!;
    canvas.drawPath(_starPath(position, radius, rotation: t * 2 * math.pi), paint);
  }

  /// A five-point star centered at [center] with outer radius [radius].
  static Path _starPath(Offset center, double radius,
      {double rotation = 0}) {
    final Path path = Path();
    const int points = 5;
    final double inner = radius * 0.45;
    for (int i = 0; i < points * 2; i++) {
      final double r = i.isEven ? radius : inner;
      final double angle = rotation - math.pi / 2 + i * math.pi / points;
      final Offset vertex =
          center + Offset(math.cos(angle), math.sin(angle)) * r;
      if (i == 0) {
        path.moveTo(vertex.dx, vertex.dy);
      } else {
        path.lineTo(vertex.dx, vertex.dy);
      }
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(BuiltInStoryStagePainter oldDelegate) =>
      oldDelegate.ambientValue != ambientValue ||
      oldDelegate.beatValue != beatValue ||
      oldDelegate.state != state ||
      oldDelegate.scene != scene;
}

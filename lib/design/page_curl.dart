// Book-style bottom-right page curl (mockup spec §8, owner addition).
//
// A small folded dog-ear sits at the bottom-right corner of the reading card
// when the current page is complete. The child drags it (or taps it) and the
// page curls over like a real paper page, revealing the next page underneath.
// Release past [PageCurlCorner.completeThreshold] completes the turn (fires
// [PageCurlCorner.onTurned] exactly once, at animation end); an earlier
// release springs back. Forward-only, per spec.
//
// Technique (see docs/design/page-curl-notes.md): a two-layer
// clip-plus-painted-overleaf curl, NOT a cloth simulation. The fold line is
// parameterised by its intersections with the bottom and right card edges,
// lerped from the resting dog-ear to past the top-left corner. The top page
// is clipped to the un-turned side of the fold; the curled-back paper face
// is the corner-side region reflected across the fold line, filled with a
// fold-perpendicular gradient plus a soft cast shadow. One Path clip, one
// polygon fill, one blur per frame — 60fps-simple.
//
// Token-lint note: test/design/token_lint_test.dart scans every file under
// lib/design/ except tokens.dart, so this file may not contain raw color
// literals. All paper/shadow shades below are derived from the nearest
// [DesignTokens] members instead (readingBackground is already slightly
// lighter than the card, exactly what the curled-back face needs).
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import 'tokens.dart';

// ---------------------------------------------------------------------------
// Paper shades, derived from tokens (no raw literals allowed in this file).
// ---------------------------------------------------------------------------

/// Lifted-tip shade of the curled-back paper face: the lightest paper tone we
/// have, slightly lighter than the card, so the fold reads as catching light.
final Color _paperTipColor = DesignTokens.readingBackground;

/// Crease-side shade of the curled-back face: the same paper warmed toward
/// the surface tone, so the gradient darkens into the fold.
final Color _paperCreaseColor = Color.lerp(
  DesignTokens.readingBackground,
  DesignTokens.surfaceBackground,
  0.6,
)!;

/// Soft shadow the lifted paper casts along the fold.
final Color _foldShadowColor =
    DesignTokens.wordUnreadInk.withValues(alpha: 0.20);

/// Hairline edge around the folded face, suggesting paper thickness.
final Color _paperEdgeColor = Color.lerp(
  DesignTokens.surfaceBackground,
  DesignTokens.wordUnreadInk,
  0.3,
)!.withValues(alpha: 0.35);

/// Resting dog-ear: fold intersections this far along the bottom and right
/// edges (a 45-degree corner fold, ~48px — inviting but not shouting).
const double _dogEarSize = 48.0;

/// Side of the square corner region that accepts drags/taps (comfortably
/// larger than the dog-ear itself; >= 44px child tap target).
const double _hitRegionSize = 88.0;

/// A book-style bottom-right page-curl corner (mockup spec §8).
///
/// When [enabled], a folded dog-ear invites the child to drag (or tap) the
/// bottom-right corner; the [page] curls away revealing [nextPage], exactly
/// like turning a paper page. Releasing past [completeThreshold] completes
/// the turn and fires [onTurned] exactly once at animation end; releasing
/// earlier springs back. When not [enabled], [page] renders plain with no
/// dog-ear and no gesture handling.
///
/// The widget is purely visual/gestural: on completion it calls [onTurned]
/// (the existing page-advance path) and rewinds itself; the parent is
/// expected to swap in the new page content in response.
class PageCurlCorner extends StatefulWidget {
  const PageCurlCorner({
    required this.page,
    required this.nextPage,
    required this.enabled,
    required this.onTurned,
    this.completeThreshold = 0.4,
    this.settleDuration = const Duration(milliseconds: 350),
    super.key,
  });

  /// The current page content (the reading card's face).
  final Widget page;

  /// The next page's content, revealed underneath as the page curls.
  final Widget nextPage;

  /// Whether the curl affordance is active (multi-page story, page complete).
  final bool enabled;

  /// Called exactly once per completed turn, at animation end — the same
  /// page-advance path the previous page-turn control invoked.
  final VoidCallback onTurned;

  /// Curl progress (0..1) beyond which releasing the drag completes the
  /// turn; below it the page springs back.
  final double completeThreshold;

  /// Duration of a full settle animation (complete-the-turn or spring-back
  /// is scaled by the distance remaining).
  final Duration settleDuration;

  @override
  State<PageCurlCorner> createState() => _PageCurlCornerState();
}

class _PageCurlCornerState extends State<PageCurlCorner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// True while the finish-the-turn animation runs; gestures are ignored so
  /// the completed turn cannot be interrupted (and fires exactly once).
  bool _completing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.settleDuration,
    );
  }

  @override
  void didUpdateWidget(PageCurlCorner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && oldWidget.enabled) {
      _controller.stop();
      _controller.value = 0.0;
      _completing = false;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onPanStart(DragStartDetails details) {
    if (_completing) return;
    // Grabbing the corner interrupts any in-flight spring-back.
    _controller.stop();
  }

  void _onPanUpdate(DragUpdateDetails details, Size size) {
    if (_completing) return;
    final diagonal = math.sqrt(
      size.width * size.width + size.height * size.height,
    );
    if (diagonal <= 0) return;
    // Progress is the drag distance projected onto the corner-to-top-left
    // diagonal, normalized to the card diagonal.
    final along = (details.delta.dx * -size.width +
            details.delta.dy * -size.height) /
        diagonal;
    _controller.value = (_controller.value + along / diagonal).clamp(0.0, 1.0);
  }

  void _onPanEnd() {
    if (_completing) return;
    if (_controller.value >= widget.completeThreshold) {
      _finishTurn();
    } else {
      _springBack();
    }
  }

  void _onTap() {
    if (_completing) return;
    _finishTurn();
  }

  /// Animates the remaining curl to 1.0, then fires [PageCurlCorner.onTurned]
  /// exactly once and rewinds so the parent can swap in the new page.
  void _finishTurn() {
    _completing = true;
    _controller
        .animateTo(
          1.0,
          duration: widget.settleDuration * (1.0 - _controller.value),
          curve: Curves.easeInOut,
        )
        .whenCompleteOrCancel(() {
      if (!mounted) return;
      final completed = _controller.status == AnimationStatus.completed;
      _completing = false;
      if (completed) {
        _controller.value = 0.0;
        widget.onTurned();
      }
    });
  }

  void _springBack() {
    _controller.animateBack(
      0.0,
      duration: widget.settleDuration * _controller.value,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.page;
    return ClipRect(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, constraints.maxHeight);
          return AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final geometry =
                  PageCurlGeometry.compute(size, _controller.value);
              return Stack(
                fit: StackFit.expand,
                children: [
                  widget.nextPage,
                  ClipPath(
                    clipper: _TopPageClipper(geometry),
                    child: widget.page,
                  ),
                  IgnorePointer(
                    child: CustomPaint(
                      painter: PageCurlOverlayPainter(geometry),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    width: math.min(_hitRegionSize, size.width),
                    height: math.min(_hitRegionSize, size.height),
                    child: Semantics(
                      button: true,
                      label: 'Turn the page',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _onTap,
                        onPanStart: _onPanStart,
                        onPanUpdate: (details) => _onPanUpdate(details, size),
                        onPanEnd: (_) => _onPanEnd(),
                        onPanCancel: _onPanEnd,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// The 2D fold geometry of the curl at a given progress, for a card of a
/// given size. Public so widget tests can inspect the live curl progress via
/// [PageCurlOverlayPainter.geometry].
class PageCurlGeometry {
  PageCurlGeometry._({
    required this.size,
    required this.progress,
    required this.visiblePage,
    required this.overleaf,
    required this.foldStart,
    required this.foldEnd,
    required this.liftedTip,
  });

  /// Computes the fold for [progress] in 0..1 on a card of [size].
  ///
  /// The fold line is parameterised by its intersections with the bottom
  /// edge (`a` from the corner) and the right edge (`b` from the corner),
  /// lerped from the resting dog-ear (a 45-degree, [_dogEarSize] corner
  /// fold) to twice the card dimensions — at which point the fold has swept
  /// past the top-left corner and the page is fully turned.
  factory PageCurlGeometry.compute(Size size, double progress) {
    final w = size.width;
    final h = size.height;
    final t = progress.clamp(0.0, 1.0);
    final dogEar = math.min(_dogEarSize, 0.5 * math.min(w, h));
    final a = ui.lerpDouble(dogEar, 2.0 * w, t)!;
    final b = ui.lerpDouble(dogEar, 2.0 * h, t)!;

    // Fold line through its (possibly off-card) edge intersections.
    final foldStart = Offset(w - a, h); // on/beyond the bottom edge
    final foldEnd = Offset(w, h - b); // on/beyond the right edge

    // Signed side of the fold line; the bottom-right corner is positive.
    final fold = foldEnd - foldStart;
    double sideOf(Offset p) =>
        fold.dx * (p.dy - foldStart.dy) - fold.dy * (p.dx - foldStart.dx);

    final rect = <Offset>[
      Offset.zero,
      Offset(w, 0),
      Offset(w, h),
      Offset(0, h),
    ];
    final visiblePage = _clipToHalfPlane(rect, sideOf, keepPositive: false);
    final cornerRegion = _clipToHalfPlane(rect, sideOf, keepPositive: true);

    final foldDir = fold / fold.distance;
    Offset reflect(Offset p) {
      final v = p - foldStart;
      final along = v.dx * foldDir.dx + v.dy * foldDir.dy;
      return foldStart +
          Offset(foldDir.dx * along * 2.0 - v.dx,
              foldDir.dy * along * 2.0 - v.dy);
    }

    return PageCurlGeometry._(
      size: size,
      progress: t,
      visiblePage: visiblePage,
      overleaf: cornerRegion.map(reflect).toList(growable: false),
      foldStart: foldStart,
      foldEnd: foldEnd,
      liftedTip: reflect(Offset(w, h)),
    );
  }

  final Size size;

  /// Curl progress in 0..1 (0 = resting dog-ear, 1 = fully turned).
  final double progress;

  /// Polygon (card coordinates) of the still-visible top-page region; empty
  /// when the page is fully turned.
  final List<Offset> visiblePage;

  /// Polygon of the curled-back paper face (the turned corner region
  /// reflected across the fold line); empty only in degenerate layouts.
  final List<Offset> overleaf;

  /// Fold-line intersection with the bottom edge's line.
  final Offset foldStart;

  /// Fold-line intersection with the right edge's line.
  final Offset foldEnd;

  /// Where the card's bottom-right corner has been lifted to.
  final Offset liftedTip;

  /// One-edge Sutherland-Hodgman: clips [polygon] to the half-plane where
  /// [sideOf] is >= 0 ([keepPositive]) or <= 0.
  static List<Offset> _clipToHalfPlane(
    List<Offset> polygon,
    double Function(Offset) sideOf, {
    required bool keepPositive,
  }) {
    final out = <Offset>[];
    for (var i = 0; i < polygon.length; i++) {
      final current = polygon[i];
      final next = polygon[(i + 1) % polygon.length];
      final sCurrent = keepPositive ? sideOf(current) : -sideOf(current);
      final sNext = keepPositive ? sideOf(next) : -sideOf(next);
      if (sCurrent >= 0) out.add(current);
      if ((sCurrent > 0 && sNext < 0) || (sCurrent < 0 && sNext > 0)) {
        final f = sCurrent / (sCurrent - sNext);
        out.add(current + (next - current) * f);
      }
    }
    return out;
  }
}

/// Clips the top page to the not-yet-turned side of the fold.
class _TopPageClipper extends CustomClipper<Path> {
  const _TopPageClipper(this.geometry);

  final PageCurlGeometry geometry;

  @override
  Path getClip(Size size) {
    if (geometry.visiblePage.length < 3) return Path();
    return Path()..addPolygon(geometry.visiblePage, true);
  }

  @override
  bool shouldReclip(_TopPageClipper oldClipper) =>
      oldClipper.geometry.progress != geometry.progress ||
      oldClipper.geometry.size != geometry.size;
}

/// Paints the curled-back paper face (the "overleaf") with its
/// fold-perpendicular gradient, hairline paper edge, and soft cast shadow.
/// Public so widget tests can find the overlay and read [geometry].
class PageCurlOverlayPainter extends CustomPainter {
  const PageCurlOverlayPainter(this.geometry);

  final PageCurlGeometry geometry;

  @override
  void paint(Canvas canvas, Size size) {
    if (geometry.overleaf.length < 3) return;
    final face = Path()..addPolygon(geometry.overleaf, true);

    // Soft shadow the lifted paper casts back toward the corner.
    canvas.drawPath(
      face.shift(const Offset(2, 3)),
      Paint()
        ..color = _foldShadowColor
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 5),
    );

    // Paper face: lightest at the lifted tip, darkening into the crease.
    final creaseAnchor = Offset(
      (geometry.foldStart.dx + geometry.foldEnd.dx) / 2,
      (geometry.foldStart.dy + geometry.foldEnd.dy) / 2,
    );
    final facePaint = Paint();
    if (geometry.liftedTip != creaseAnchor) {
      facePaint.shader = ui.Gradient.linear(
        geometry.liftedTip,
        creaseAnchor,
        <Color>[_paperTipColor, _paperCreaseColor],
      );
    } else {
      facePaint.color = _paperTipColor;
    }
    canvas.drawPath(face, facePaint);

    // Hairline edge suggesting paper thickness.
    canvas.drawPath(
      face,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = _paperEdgeColor,
    );
  }

  @override
  bool shouldRepaint(PageCurlOverlayPainter oldDelegate) =>
      oldDelegate.geometry.progress != geometry.progress ||
      oldDelegate.geometry.size != geometry.size;
}

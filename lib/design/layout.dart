// Layout classes and the reading-screen layout primitive (PRD §8 Unit 1).
//
// Every screen defines exactly four layout classes — phone/tablet crossed
// with portrait/landscape — resolved purely from the available size. The
// reading screen additionally uses [ReadingLayout], the shared primitive
// that arranges a text region and a Rive stage region: side-by-side in
// landscape (book-like), stacked text-above-stage in portrait.
import 'package:flutter/widgets.dart';

/// The four layout classes every child-facing screen must define
/// (PRD §8 Unit 1 acceptance).
enum LayoutClass {
  phonePortrait,
  phoneLandscape,
  tabletPortrait,
  tabletLandscape,
}

/// Resolves a [LayoutClass] from a device size or [BuildContext].
///
/// Classification rules (pinned by test/design/layout_test.dart):
/// - Tablet vs phone is decided by `size.shortestSide` against
///   [tabletShortestSideBreakpoint], inclusive (`>=` is tablet).
/// - Landscape requires `width` strictly greater than `height`; an exactly
///   square size is treated as portrait.
abstract final class LayoutResolver {
  /// Shortest-side breakpoint (logical pixels) at/above which a size is
  /// classified as tablet rather than phone.
  static const double tabletShortestSideBreakpoint = 600.0;

  /// Pure resolution logic: classify a raw [Size] into a [LayoutClass].
  static LayoutClass resolveFromSize(Size size) {
    final isTablet = size.shortestSide >= tabletShortestSideBreakpoint;
    final isLandscape = size.width > size.height;
    if (isTablet) {
      return isLandscape ? LayoutClass.tabletLandscape : LayoutClass.tabletPortrait;
    }
    return isLandscape ? LayoutClass.phoneLandscape : LayoutClass.phonePortrait;
  }

  /// Resolves the [LayoutClass] for the ambient [MediaQuery] size of
  /// [context].
  static LayoutClass resolve(BuildContext context) {
    return resolveFromSize(MediaQuery.sizeOf(context));
  }
}

/// The reading-screen layout primitive (PRD §8 Unit 1, accept #7): arranges
/// a text region and an animation-stage region.
///
/// - Landscape (phoneLandscape / tabletLandscape): [textRegion] and
///   [stageRegion] sit side-by-side, book-like.
/// - Portrait (phonePortrait / tabletPortrait): [textRegion] stacks above
///   [stageRegion].
///
/// This widget only arranges the two regions; it does not itself define
/// their contents, so any screen that pairs reading text with the Rive
/// stage (or a placeholder) can reuse it directly.
class ReadingLayout extends StatelessWidget {
  const ReadingLayout({
    super.key,
    required this.textRegion,
    required this.stageRegion,
  });

  /// The reading-text region.
  final Widget textRegion;

  /// The animation-stage region (Rive stage or its fake in tests).
  final Widget stageRegion;

  @override
  Widget build(BuildContext context) {
    final layoutClass = LayoutResolver.resolve(context);
    final isLandscape = layoutClass == LayoutClass.phoneLandscape ||
        layoutClass == LayoutClass.tabletLandscape;

    if (isLandscape) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(child: textRegion),
          Expanded(child: stageRegion),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(child: textRegion),
        Expanded(child: stageRegion),
      ],
    );
  }
}

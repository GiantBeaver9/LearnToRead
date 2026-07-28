// Pins lib/design/layout.dart: the four layout classes (accept #6) and the
// reading-screen layout primitive rule — landscape side-by-side (book-like),
// portrait text-above-stage (accept #7).
//
// lib/design/layout.dart does not exist yet: this file fails to
// compile/analyze until it is created, which is the expected red state.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/design/layout.dart';

/// Resizes the actual test viewport (not just an ambient MediaQuery) so
/// rendered rects (tester.getRect/getTopLeft) reflect [size] exactly — the
/// default flutter_test surface gives the root *tight* constraints (its
/// own fixed size), so a merely-nested SizedBox cannot shrink/grow it.
Future<void> _pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData(size: size),
      child: Directionality(textDirection: TextDirection.ltr, child: child),
    ),
  );
}

/// True if two rects overlap on the horizontal axis (share any x range).
bool _horizontallyOverlap(Rect a, Rect b) {
  return a.right > b.left + 0.5 && b.right > a.left + 0.5;
}

void main() {
  group('LayoutClass enum — exactly four classes (accept #6)', () {
    test('POSITIVE: exactly four values, named as pinned', () {
      final names = LayoutClass.values.map((v) => v.name).toSet();
      expect(LayoutClass.values.length, equals(4));
      expect(
        names,
        equals(<String>{'phonePortrait', 'phoneLandscape', 'tabletPortrait', 'tabletLandscape'}),
      );
    });
  });

  group('LayoutResolver.resolveFromSize — pure resolution logic', () {
    test('POSITIVE: iPhone-SE-like portrait size resolves phonePortrait', () {
      expect(LayoutResolver.resolveFromSize(const Size(375, 667)), LayoutClass.phonePortrait);
    });

    test('POSITIVE: iPhone-SE-like landscape size resolves phoneLandscape', () {
      expect(LayoutResolver.resolveFromSize(const Size(667, 375)), LayoutClass.phoneLandscape);
    });

    test('POSITIVE: iPad-like portrait size resolves tabletPortrait', () {
      expect(LayoutResolver.resolveFromSize(const Size(768, 1024)), LayoutClass.tabletPortrait);
    });

    test('POSITIVE: iPad-like landscape size resolves tabletLandscape', () {
      expect(LayoutResolver.resolveFromSize(const Size(1024, 768)), LayoutClass.tabletLandscape);
    });

    test(
      'EDGE: shortestSide exactly at the tablet breakpoint (600) resolves '
      'to a tablet class (boundary is inclusive)',
      () {
        expect(
          LayoutResolver.resolveFromSize(const Size(600, 800)),
          LayoutClass.tabletPortrait,
        );
      },
    );

    test(
      'EDGE: shortestSide one logical pixel below the tablet breakpoint '
      '(599) resolves to a phone class',
      () {
        expect(
          LayoutResolver.resolveFromSize(const Size(599, 800)),
          LayoutClass.phonePortrait,
        );
      },
    );

    test(
      'EDGE: a perfectly square size (width == height) is treated as '
      'portrait, not landscape (landscape requires width strictly greater '
      'than height)',
      () {
        expect(
          LayoutResolver.resolveFromSize(const Size(600, 600)),
          LayoutClass.tabletPortrait,
        );
      },
    );

    test(
      'NEGATIVE: classification is driven by shortestSide, not raw width — '
      'a short, wide window with a small shortest side stays phone-class '
      'even though its width alone would exceed the tablet breakpoint',
      () {
        expect(
          LayoutResolver.resolveFromSize(const Size(800, 300)),
          LayoutClass.phoneLandscape,
        );
      },
    );
  });

  group('LayoutResolver.resolve(context) — MediaQuery integration', () {
    testWidgets(
      'POSITIVE: resolve(context) matches resolveFromSize(size) for the '
      'ambient MediaQuery size',
      (tester) async {
        LayoutClass? resolved;
        await _pumpAt(
          tester,
          const Size(768, 1024),
          Builder(
            builder: (context) {
              resolved = LayoutResolver.resolve(context);
              return const SizedBox.shrink();
            },
          ),
        );
        expect(resolved, equals(LayoutResolver.resolveFromSize(const Size(768, 1024))));
        expect(resolved, equals(LayoutClass.tabletPortrait));
      },
    );
  });

  group(
    'ReadingLayout primitive — landscape side-by-side / portrait stacked '
    '(accept #7, all four layout classes)',
    () {
      final textKey = const ValueKey('reading-layout-text-region');
      final stageKey = const ValueKey('reading-layout-stage-region');

      Widget buildRegions() {
        return ReadingLayout(
          textRegion: ColoredBox(key: textKey, color: const Color(0xFFFFFFFF)),
          stageRegion: ColoredBox(key: stageKey, color: const Color(0xFF000000)),
        );
      }

      testWidgets(
        'POSITIVE: phonePortrait stacks text region above stage region '
        '(no vertical overlap, text before stage)',
        (tester) async {
          await _pumpAt(tester, const Size(375, 667), buildRegions());
          final textRect = tester.getRect(find.byKey(textKey));
          final stageRect = tester.getRect(find.byKey(stageKey));
          expect(textRect.bottom, lessThanOrEqualTo(stageRect.top + 0.5));
        },
      );

      testWidgets(
        'POSITIVE: tabletPortrait stacks text region above stage region',
        (tester) async {
          await _pumpAt(tester, const Size(768, 1024), buildRegions());
          final textRect = tester.getRect(find.byKey(textKey));
          final stageRect = tester.getRect(find.byKey(stageKey));
          expect(textRect.bottom, lessThanOrEqualTo(stageRect.top + 0.5));
        },
      );

      testWidgets(
        'POSITIVE: phoneLandscape places text region and stage region '
        'side-by-side (no horizontal overlap, aligned on the same row)',
        (tester) async {
          await _pumpAt(tester, const Size(667, 375), buildRegions());
          final textRect = tester.getRect(find.byKey(textKey));
          final stageRect = tester.getRect(find.byKey(stageKey));
          expect(_horizontallyOverlap(textRect, stageRect), isFalse);
          expect(textRect.top, closeTo(stageRect.top, 0.5));
        },
      );

      testWidgets(
        'POSITIVE: tabletLandscape places text region and stage region '
        'side-by-side (no horizontal overlap, aligned on the same row)',
        (tester) async {
          await _pumpAt(tester, const Size(1024, 768), buildRegions());
          final textRect = tester.getRect(find.byKey(textKey));
          final stageRect = tester.getRect(find.byKey(stageKey));
          expect(_horizontallyOverlap(textRect, stageRect), isFalse);
          expect(textRect.top, closeTo(stageRect.top, 0.5));
        },
      );

      testWidgets(
        'NEGATIVE: a portrait layout does NOT place the regions side-by-side '
        '(they must vertically, not horizontally, partition the space)',
        (tester) async {
          await _pumpAt(tester, const Size(375, 667), buildRegions());
          final textRect = tester.getRect(find.byKey(textKey));
          final stageRect = tester.getRect(find.byKey(stageKey));
          // Stacked regions each span the full available width.
          expect(textRect.width, closeTo(375, 0.5));
          expect(stageRect.width, closeTo(375, 0.5));
        },
      );

      testWidgets(
        'NEGATIVE: a landscape layout does NOT stack the regions '
        '(neither region alone spans the full available height)',
        (tester) async {
          await _pumpAt(tester, const Size(667, 375), buildRegions());
          final textRect = tester.getRect(find.byKey(textKey));
          final stageRect = tester.getRect(find.byKey(stageKey));
          expect(textRect.height, closeTo(375, 0.5));
          expect(stageRect.height, closeTo(375, 0.5));
          // But together they still fill the row (no gap/overlap).
          expect(textRect.width + stageRect.width, closeTo(667, 0.5));
        },
      );

      testWidgets(
        'EDGE: at the exact tablet breakpoint size (600x800, portrait), '
        'the layout still stacks text-above-stage',
        (tester) async {
          await _pumpAt(tester, const Size(600, 800), buildRegions());
          final textRect = tester.getRect(find.byKey(textKey));
          final stageRect = tester.getRect(find.byKey(stageKey));
          expect(textRect.bottom, lessThanOrEqualTo(stageRect.top + 0.5));
        },
      );
    },
  );
}

// Tests for lib/design/motion.dart — the reusable motion library ported
// from the owner mockup (docs/design/mockup-spec.md §4, §7).
//
// Harness notes: PulseWord(active: true) and WaveBars loop forever, so
// these tests NEVER use pumpAndSettle — only fixed tester.pump(duration)
// steps — and every test dismounts the tree (pumpWidget(SizedBox())) at
// the end so looping tickers are disposed.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/design/motion.dart';

Widget _harness(Widget child) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Center(child: child),
  );
}

void main() {
  group('FadeUp', () {
    testWidgets(
        'starts fully transparent and reaches full opacity after its '
        'default 380ms duration', (WidgetTester tester) async {
      await tester.pumpWidget(
        _harness(const FadeUp(child: SizedBox(width: 10, height: 10))),
      );

      final FadeTransition atStart =
          tester.widget<FadeTransition>(find.byType(FadeTransition));
      expect(atStart.opacity.value, 0.0);

      await tester.pump(const Duration(milliseconds: 190));
      final FadeTransition midway =
          tester.widget<FadeTransition>(find.byType(FadeTransition));
      expect(midway.opacity.value, greaterThan(0.0));
      expect(midway.opacity.value, lessThan(1.0));

      await tester.pump(const Duration(milliseconds: 190));
      final FadeTransition atEnd =
          tester.widget<FadeTransition>(find.byType(FadeTransition));
      expect(atEnd.opacity.value, 1.0);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('honors a custom duration', (WidgetTester tester) async {
      await tester.pumpWidget(
        _harness(const FadeUp(
          duration: Duration(milliseconds: 200),
          child: SizedBox(width: 10, height: 10),
        )),
      );

      await tester.pump(const Duration(milliseconds: 200));
      final FadeTransition atEnd =
          tester.widget<FadeTransition>(find.byType(FadeTransition));
      expect(atEnd.opacity.value, 1.0);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('translates up from +14 to rest (no offset once done)',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _harness(const FadeUp(child: SizedBox(width: 10, height: 10))),
      );

      // Mid-flight: a translate transform is present.
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(Transform), findsOneWidget);

      // Done: renders the child statically, no leftover transform.
      await tester.pump(const Duration(milliseconds: 280));
      expect(find.byType(Transform), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('SceneReveal', () {
    testWidgets(
        'starts scaled/rotated/transparent and reaches exact identity and '
        'full opacity after 620ms', (WidgetTester tester) async {
      await tester.pumpWidget(
        _harness(const SceneReveal(child: SizedBox(width: 40, height: 40))),
      );

      final Transform atStart =
          tester.widget<Transform>(find.byType(Transform));
      expect(atStart.transform, isNot(equals(Matrix4.identity())));
      final FadeTransition fadeAtStart =
          tester.widget<FadeTransition>(find.byType(FadeTransition));
      expect(fadeAtStart.opacity.value, 0.0);

      await tester.pump(const Duration(milliseconds: 620));
      final Transform atEnd = tester.widget<Transform>(find.byType(Transform));
      expect(atEnd.transform, equals(Matrix4.identity()));
      final FadeTransition fadeAtEnd =
          tester.widget<FadeTransition>(find.byType(FadeTransition));
      expect(fadeAtEnd.opacity.value, 1.0);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('PulseWord', () {
    testWidgets('animates while active: transform changes between frames',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _harness(const PulseWord(
          active: true,
          child: SizedBox(width: 30, height: 12),
        )),
      );

      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(Transform), findsOneWidget);
      final Matrix4 first =
          tester.widget<Transform>(find.byType(Transform)).transform;

      await tester.pump(const Duration(milliseconds: 200));
      final Matrix4 second =
          tester.widget<Transform>(find.byType(Transform)).transform;
      expect(second, isNot(equals(first)));

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('renders the child statically while inactive (no transform)',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _harness(const PulseWord(
          active: false,
          child: SizedBox(width: 30, height: 12),
        )),
      );

      expect(find.byType(Transform), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(Transform), findsNothing);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(Transform), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('settles cleanly back to identity when toggled off mid-cycle',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        _harness(const PulseWord(
          active: true,
          child: SizedBox(width: 30, height: 12),
        )),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(Transform), findsOneWidget);

      // Toggle off mid-cycle: it glides back rather than snapping...
      await tester.pumpWidget(
        _harness(const PulseWord(
          active: false,
          child: SizedBox(width: 30, height: 12),
        )),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(Transform), findsOneWidget);

      // ...and within one settle glide (< one 1.3s period) it is static.
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byType(Transform), findsNothing);

      // And it stays static afterwards.
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(Transform), findsNothing);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('WaveBars', () {
    testWidgets('builds barCount bars (default 6)',
        (WidgetTester tester) async {
      await tester.pumpWidget(_harness(const WaveBars()));
      expect(
        find.descendant(
          of: find.byType(WaveBars),
          matching: find.byType(Transform),
        ),
        findsNWidgets(6),
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('builds a custom barCount', (WidgetTester tester) async {
      await tester.pumpWidget(_harness(const WaveBars(barCount: 4)));
      expect(
        find.descendant(
          of: find.byType(WaveBars),
          matching: find.byType(Transform),
        ),
        findsNWidgets(4),
      );
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('animates: bar transforms differ across two frames',
        (WidgetTester tester) async {
      await tester.pumpWidget(_harness(const WaveBars()));

      List<Matrix4> matrices() => tester
          .widgetList<Transform>(find.descendant(
            of: find.byType(WaveBars),
            matching: find.byType(Transform),
          ))
          .map((Transform t) => t.transform)
          .toList();

      final List<Matrix4> first = matrices();
      await tester.pump(const Duration(milliseconds: 150));
      final List<Matrix4> second = matrices();

      expect(second.length, first.length);
      bool anyDiffer = false;
      for (int i = 0; i < first.length; i++) {
        if (first[i] != second[i]) anyDiffer = true;
      }
      expect(anyDiffer, isTrue,
          reason: 'bar scale transforms should change between frames');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('staggers bars: neighboring bars are out of phase',
        (WidgetTester tester) async {
      await tester.pumpWidget(_harness(const WaveBars()));
      await tester.pump(const Duration(milliseconds: 150));

      final List<Matrix4> matrices = tester
          .widgetList<Transform>(find.descendant(
            of: find.byType(WaveBars),
            matching: find.byType(Transform),
          ))
          .map((Transform t) => t.transform)
          .toList();
      expect(matrices[0], isNot(equals(matrices[1])));

      await tester.pumpWidget(const SizedBox());
    });
  });
}

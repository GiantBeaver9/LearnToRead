// Tests for lib/design/confetti.dart — the celebration overlay ported from
// the owner mockup (docs/design/mockup-spec.md §6).
//
// Harness notes: never pumpAndSettle mid-animation (fixed pump(duration)
// steps only); every test dismounts the tree (pumpWidget(SizedBox())) at
// the end so the controller is disposed. The overlay's total runtime is
// seed-dependent but bounded: >= 2.4s (shortest possible ribbon) and
// <= 5.3s (max delay 1.1s + max fall 4.2s), so pumping 6s total is always
// past the end and pumping 1s is always before it.
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/design/confetti.dart';

ConfettiPainter _painterOf(WidgetTester tester) {
  final CustomPaint paint =
      tester.widget<CustomPaint>(find.byType(CustomPaint));
  return paint.painter! as ConfettiPainter;
}

void main() {
  group('structure scales with intensity (spec §6)', () {
    Future<void> expectStructure(
      WidgetTester tester, {
      required int intensity,
      required int ribbons,
      required int bursts,
    }) async {
      await tester.pumpWidget(
        ConfettiOverlay(intensity: intensity, seed: 99),
      );
      final ConfettiPainter painter = _painterOf(tester);
      expect(painter.ribbons, hasLength(ribbons),
          reason: 'ribbons = 16 + 10 x intensity');
      expect(painter.bursts, hasLength(bursts),
          reason: 'bursts = min(3, intensity)');
      for (final ConfettiBurst burst in painter.bursts) {
        expect(burst.sparks, hasLength(16),
            reason: 'every burst has 16 radial sparks');
      }
      await tester.pumpWidget(const SizedBox());
    }

    testWidgets('intensity 0: 16 ribbons, no bursts', (tester) async {
      await expectStructure(tester, intensity: 0, ribbons: 16, bursts: 0);
    });

    testWidgets('intensity 1: 26 ribbons, 1 burst', (tester) async {
      await expectStructure(tester, intensity: 1, ribbons: 26, bursts: 1);
    });

    testWidgets('intensity 3: 46 ribbons, 3 bursts (capped)', (tester) async {
      await expectStructure(tester, intensity: 3, ribbons: 46, bursts: 3);
    });

    testWidgets('ribbon/burst parameters stay inside spec ranges',
        (tester) async {
      await tester.pumpWidget(const ConfettiOverlay(intensity: 3, seed: 7));
      final ConfettiPainter painter = _painterOf(tester);
      for (final ConfettiRibbon ribbon in painter.ribbons) {
        expect(ribbon.width, inInclusiveRange(5, 11));
        expect(ribbon.height, inInclusiveRange(12, 26));
        expect(ribbon.durationSeconds, inInclusiveRange(2.4, 4.2));
        expect(ribbon.delaySeconds, inInclusiveRange(0, 1.1));
        expect(confettiColors, contains(ribbon.color));
      }
      for (final ConfettiBurst burst in painter.bursts) {
        expect(burst.xFraction, inInclusiveRange(0.18, 0.82));
        expect(burst.yFraction, inInclusiveRange(0.14, 0.46));
        for (final ConfettiSpark spark in burst.sparks) {
          expect(spark.distance, inInclusiveRange(70, 150));
          expect(spark.delaySeconds, inInclusiveRange(0, 1.4));
          expect(confettiColors, contains(spark.color));
        }
      }
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('determinism (seeded Random)', () {
    testWidgets(
        'equal (seed, intensity) at the same tick paints identically: '
        'identical particle lists and painter time', (tester) async {
      await tester.pumpWidget(const ConfettiOverlay(intensity: 2, seed: 1234));
      await tester.pump(const Duration(milliseconds: 1000));
      final ConfettiPainter first = _painterOf(tester);
      final List<ConfettiRibbon> firstRibbons =
          List<ConfettiRibbon>.of(first.ribbons);
      final List<ConfettiBurst> firstBursts =
          List<ConfettiBurst>.of(first.bursts);
      final double firstTime = first.timeSeconds;
      await tester.pumpWidget(const SizedBox());

      // A brand-new overlay with the same seed, pumped the same amount.
      await tester.pumpWidget(const ConfettiOverlay(intensity: 2, seed: 1234));
      await tester.pump(const Duration(milliseconds: 1000));
      final ConfettiPainter second = _painterOf(tester);

      expect(listEquals(second.ribbons, firstRibbons), isTrue,
          reason: 'same seed must generate identical ribbons');
      expect(listEquals(second.bursts, firstBursts), isTrue,
          reason: 'same seed must generate identical bursts');
      expect(second.timeSeconds, firstTime,
          reason: 'same seed => same total duration => same tick time');

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        'painter reports no repaint needed for an identical frame '
        '(shouldRepaint is time/particle driven)', (tester) async {
      await tester.pumpWidget(const ConfettiOverlay(intensity: 2, seed: 5));
      await tester.pump(const Duration(milliseconds: 500));
      final ConfettiPainter before = _painterOf(tester);
      await tester.pump(Duration.zero); // same tick, no time advance
      final ConfettiPainter after = _painterOf(tester);
      expect(after.shouldRepaint(before), isFalse);

      await tester.pump(const Duration(milliseconds: 100));
      final ConfettiPainter later = _painterOf(tester);
      expect(later.shouldRepaint(before), isTrue);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('different seeds generate different celebrations',
        (tester) async {
      await tester.pumpWidget(const ConfettiOverlay(intensity: 2, seed: 1));
      final List<ConfettiRibbon> a =
          List<ConfettiRibbon>.of(_painterOf(tester).ribbons);
      await tester.pumpWidget(const SizedBox());

      await tester.pumpWidget(const ConfettiOverlay(intensity: 2, seed: 2));
      final List<ConfettiRibbon> b =
          List<ConfettiRibbon>.of(_painterOf(tester).ribbons);
      expect(listEquals(a, b), isFalse);

      await tester.pumpWidget(const SizedBox());
    });
  });

  group('lifecycle', () {
    testWidgets(
        'onFinished fires exactly once, after the last ribbon lands, '
        'not before', (tester) async {
      int finished = 0;
      await tester.pumpWidget(
        ConfettiOverlay(
          intensity: 3,
          seed: 42,
          onFinished: () => finished++,
        ),
      );

      // Well before the earliest possible end (2.4s): not finished.
      await tester.pump(const Duration(milliseconds: 1000));
      expect(finished, 0);

      // Step past the latest possible end (5.3s).
      for (int i = 0; i < 11; i++) {
        await tester.pump(const Duration(milliseconds: 500));
      }
      expect(finished, 1);

      // No double-fire afterwards.
      await tester.pump(const Duration(milliseconds: 500));
      expect(finished, 1);

      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('overlay ignores pointers (never blocks the child UI)',
        (tester) async {
      await tester.pumpWidget(const ConfettiOverlay(intensity: 1, seed: 3));
      final IgnorePointer ignore = tester.widget<IgnorePointer>(
        find.descendant(
          of: find.byType(ConfettiOverlay),
          matching: find.byType(IgnorePointer),
        ),
      );
      expect(ignore.ignoring, isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  });
}

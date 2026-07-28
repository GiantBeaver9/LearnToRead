// Pins lib/design/page_curl.dart — the book-style bottom-right page curl
// (mockup spec §8). Behavior under test:
// - dog-ear (curl overlay + gesture region) present iff enabled;
// - drag past completeThreshold -> onTurned exactly once, next page shown;
// - drag released below threshold -> springs back, onTurned never fires;
// - tap on the dog-ear -> full animated turn, onTurned once at animation end;
// - disabled -> dragging the corner does nothing;
// - a second turn after re-enable works.
//
// Harness notes: the 400x300 card is centered on the default 800x600 test
// surface, so the card occupies (200,150)-(600,450) and its bottom-right
// corner hit region is around (590,440). Drags are split into several
// moveBy steps so the pan slop only eats part of the first step; gestures
// always end with .up() (repo harness gotcha), and animations are pumped to
// completion with pumpAndSettle.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/design/page_curl.dart';

/// The curl overlay painted by an enabled [PageCurlCorner].
Finder _overlayFinder() => find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint && widget.painter is PageCurlOverlayPainter,
    );

/// Reads the live curl progress off the overlay painter.
double _progressOf(WidgetTester tester) {
  final paint = tester.widget<CustomPaint>(_overlayFinder());
  return (paint.painter! as PageCurlOverlayPainter).geometry.progress;
}

/// Point inside the corner hit region of the centered 400x300 card.
const Offset _cornerPoint = Offset(590, 440);

/// A long diagonal drag: 6 x 50px along the corner-to-top-left diagonal =
/// 300px of a 500px diagonal, comfortably past the 0.4 threshold even after
/// pan slop.
const Offset _bigStep = Offset(-40, -30);

/// A short diagonal drag: 3 x 40px = 120px -> progress <= 0.24, always
/// below the 0.4 threshold.
const Offset _smallStep = Offset(-32, -24);

class _Harness extends StatefulWidget {
  const _Harness({
    super.key,
    required this.turns,
    this.initiallyEnabled = true,
    this.disableAfterTurn = false,
  });

  /// Page index recorded per onTurned call — length is the call count.
  final List<int> turns;

  final bool initiallyEnabled;

  /// Simulates the app disabling the curl after a turn (new page not yet
  /// complete), so tests can exercise re-enabling.
  final bool disableAfterTurn;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  static const List<String> pages = ['Page 1', 'Page 2', 'Page 3'];
  int index = 0;
  late bool enabled = widget.initiallyEnabled;

  void setEnabled(bool value) => setState(() => enabled = value);

  void _handleTurned() {
    setState(() {
      widget.turns.add(index);
      index += 1;
      if (widget.disableAfterTurn) enabled = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasNext = index < pages.length - 1;
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: SizedBox(
          width: 400,
          height: 300,
          child: PageCurlCorner(
            enabled: enabled && hasNext,
            page: Text(pages[index]),
            nextPage:
                hasNext ? Text(pages[index + 1]) : const SizedBox.shrink(),
            onTurned: _handleTurned,
          ),
        ),
      ),
    );
  }
}

Future<void> _dragCorner(
  WidgetTester tester, {
  required Offset step,
  required int steps,
}) async {
  final gesture = await tester.startGesture(_cornerPoint);
  for (var i = 0; i < steps; i++) {
    await gesture.moveBy(step);
    await tester.pump();
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'POSITIVE: dog-ear (curl overlay + gesture region) present when enabled, '
    'resting at progress 0',
    (tester) async {
      await tester.pumpWidget(_Harness(turns: <int>[]));
      expect(_overlayFinder(), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(PageCurlCorner),
          matching: find.byType(GestureDetector),
        ),
        findsOneWidget,
      );
      expect(_progressOf(tester), 0.0);
      // Both the page and the next page are in the tree (next underneath).
      expect(find.text('Page 1'), findsOneWidget);
      expect(find.text('Page 2'), findsOneWidget);
    },
  );

  testWidgets(
    'NEGATIVE: when disabled, no dog-ear and no gesture handling — the page '
    'renders plain',
    (tester) async {
      await tester.pumpWidget(_Harness(turns: <int>[], initiallyEnabled: false));
      expect(_overlayFinder(), findsNothing);
      expect(
        find.descendant(
          of: find.byType(PageCurlCorner),
          matching: find.byType(GestureDetector),
        ),
        findsNothing,
      );
      expect(find.text('Page 1'), findsOneWidget);
      expect(find.text('Page 2'), findsNothing);
    },
  );

  testWidgets(
    'POSITIVE: drag past the threshold -> onTurned exactly once and the next '
    'page is revealed',
    (tester) async {
      final turns = <int>[];
      await tester.pumpWidget(_Harness(turns: turns));

      await _dragCorner(tester, step: _bigStep, steps: 6);

      expect(turns, hasLength(1));
      expect(find.text('Page 2'), findsOneWidget);
      expect(find.text('Page 1'), findsNothing);

      // Extra frames later it has still fired exactly once.
      await tester.pump(const Duration(seconds: 1));
      expect(turns, hasLength(1));
    },
  );

  testWidgets(
    'POSITIVE: drag released below the threshold springs back — onTurned '
    'never fires and the page stays',
    (tester) async {
      final turns = <int>[];
      await tester.pumpWidget(_Harness(turns: turns));

      final gesture = await tester.startGesture(_cornerPoint);
      for (var i = 0; i < 3; i++) {
        await gesture.moveBy(_smallStep);
        await tester.pump();
      }
      // Mid-drag the curl has lifted, but is below the threshold.
      expect(_progressOf(tester), greaterThan(0.0));
      expect(_progressOf(tester), lessThan(0.4));

      await gesture.up();
      await tester.pumpAndSettle();

      expect(turns, isEmpty);
      expect(_progressOf(tester), 0.0); // sprang back to the resting dog-ear
      expect(find.text('Page 1'), findsOneWidget);
    },
  );

  testWidgets(
    'POSITIVE: tap on the dog-ear -> full animated turn, onTurned exactly '
    'once at animation end',
    (tester) async {
      final turns = <int>[];
      await tester.pumpWidget(_Harness(turns: turns));

      await tester.tapAt(_cornerPoint);
      await tester.pump();
      // Fires at animation END, not on the tap itself.
      expect(turns, isEmpty);

      await tester.pumpAndSettle();
      expect(turns, hasLength(1));
      expect(find.text('Page 2'), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
      expect(turns, hasLength(1));
    },
  );

  testWidgets(
    'NEGATIVE: when disabled, dragging the corner region does nothing',
    (tester) async {
      final turns = <int>[];
      await tester.pumpWidget(_Harness(turns: turns, initiallyEnabled: false));

      await _dragCorner(tester, step: _bigStep, steps: 6);

      expect(turns, isEmpty);
      expect(find.text('Page 1'), findsOneWidget);
      expect(_overlayFinder(), findsNothing);
    },
  );

  testWidgets(
    'POSITIVE: a second turn after re-enable works (and fires once per turn)',
    (tester) async {
      final turns = <int>[];
      final key = GlobalKey<_HarnessState>();
      await tester.pumpWidget(
        _Harness(key: key, turns: turns, disableAfterTurn: true),
      );

      // First turn (tap), after which the harness disables the curl.
      await tester.tapAt(_cornerPoint);
      await tester.pumpAndSettle();
      expect(turns, hasLength(1));
      expect(find.text('Page 2'), findsOneWidget);
      expect(_overlayFinder(), findsNothing);

      // Dragging while disabled does nothing.
      await _dragCorner(tester, step: _bigStep, steps: 6);
      expect(turns, hasLength(1));

      // Re-enable (page complete again) and turn again with a drag.
      key.currentState!.setEnabled(true);
      await tester.pump();
      expect(_overlayFinder(), findsOneWidget);

      await _dragCorner(tester, step: _bigStep, steps: 6);
      expect(turns, hasLength(2));
      expect(find.text('Page 3'), findsOneWidget);
      expect(find.text('Page 2'), findsNothing);
    },
  );
}

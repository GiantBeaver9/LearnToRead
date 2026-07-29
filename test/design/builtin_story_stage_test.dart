// Tests for the code-drawn story stage (lib/design/builtin_story_stage.dart):
//
//  * the [StoryStage] contract (fresh = idle; trigger updates activeState;
//    the celebrate -> collect sequence CelebrationController drives),
//  * per-state view structure (a distinct find-able key per active state),
//  * deterministic scene generation for equal seeds,
//  * ticker hygiene (paused via TickerMode -> no scheduled frames; dismount
//    disposes cleanly).
//
// The ambient loop repeats forever, so every widget test here uses stepped
// pumps (never pumpAndSettle) and dismounts the view before ending.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:learn_to_read/design/builtin_story_stage.dart';
import 'package:learn_to_read/design/rive_stage.dart';
import 'package:learn_to_read/design/tokens.dart';

Widget _host(BuiltInStoryStage stage, {bool tickersEnabled = true}) {
  return TickerMode(
    enabled: tickersEnabled,
    child: Center(
      child: SizedBox(
        width: 320,
        height: 240,
        child: BuiltInStoryStageView(stage: stage),
      ),
    ),
  );
}

/// Dismounts whatever is pumped so the view's tickers are disposed before
/// the test ends.
Future<void> _dismount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

void main() {
  group('BuiltInStoryStage: the StoryStage contract', () {
    test('a fresh stage reports idle before any trigger', () {
      expect(BuiltInStoryStage().activeState, StoryStageInput.idle);
      expect(BuiltInStoryStage().triggerCount, 0);
    });

    test('trigger(celebrate) makes celebrate the active state', () {
      final stage = BuiltInStoryStage();
      stage.trigger(StoryStageInput.celebrate);
      expect(stage.activeState, StoryStageInput.celebrate);
    });

    test('trigger(collect) makes collect the active state', () {
      final stage = BuiltInStoryStage();
      stage.trigger(StoryStageInput.collect);
      expect(stage.activeState, StoryStageInput.collect);
    });

    test('trigger(idle) returns the stage to idle', () {
      final stage = BuiltInStoryStage();
      stage.trigger(StoryStageInput.celebrate);
      stage.trigger(StoryStageInput.idle);
      expect(stage.activeState, StoryStageInput.idle);
    });

    test(
      'the CelebrationController sequence — celebrate, then collect — is '
      'observable in order via the ChangeNotifier',
      () {
        // CelebrationController.run fires celebrate synchronously, then
        // collect after the hold phase (celebration_controller.dart); this
        // stage must surface exactly that order to its listeners.
        final stage = BuiltInStoryStage();
        final observed = <StoryStageInput>[];
        stage.addListener(() => observed.add(stage.activeState));

        stage.trigger(StoryStageInput.celebrate);
        stage.trigger(StoryStageInput.collect);

        expect(observed,
            <StoryStageInput>[StoryStageInput.celebrate, StoryStageInput.collect]);
        expect(stage.activeState, StoryStageInput.collect);
        expect(stage.triggerCount, 2);
      },
    );

    test('re-triggering the same input notifies again (replayable beats)', () {
      final stage = BuiltInStoryStage();
      var notifications = 0;
      stage.addListener(() => notifications++);
      stage.trigger(StoryStageInput.collect);
      stage.trigger(StoryStageInput.collect);
      expect(notifications, 2);
      expect(stage.triggerCount, 2);
    });
  });

  group('BuiltInStoryScene: deterministic generation', () {
    test('equal seeds generate identical scenes', () {
      expect(
        BuiltInStoryScene.generate(42),
        equals(BuiltInStoryScene.generate(42)),
      );
      expect(
        BuiltInStoryScene.generate(42).hashCode,
        BuiltInStoryScene.generate(42).hashCode,
      );
    });

    test('different seeds generate different scenes', () {
      expect(
        BuiltInStoryScene.generate(1),
        isNot(equals(BuiltInStoryScene.generate(2))),
      );
    });

    test('every chip color index addresses the token confetti palette', () {
      for (final seed in <int>[0, 1, 7, 99, 12345]) {
        final scene = BuiltInStoryScene.generate(seed);
        for (final chip in scene.chips) {
          expect(chip.colorIndex, greaterThanOrEqualTo(0));
          expect(chip.colorIndex,
              lessThan(DesignTokens.confettiColors.length));
        }
        expect(scene.chips, isNotEmpty);
        expect(scene.clouds, isNotEmpty);
      }
    });
  });

  group('BuiltInStoryStageView: per-state structure', () {
    testWidgets('idle renders the idle scene program', (tester) async {
      final stage = BuiltInStoryStage(sceneSeed: 3);
      await tester.pumpWidget(_host(stage));
      await tester.pump(const Duration(milliseconds: 50));

      expect(
          find.byKey(const ValueKey<String>('builtin-story-stage')), findsOneWidget);
      expect(
          find.byKey(const ValueKey<String>('builtin-stage-idle')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('builtin-stage-celebrate')),
          findsNothing);
      expect(find.byKey(const ValueKey<String>('builtin-stage-collect')),
          findsNothing);

      await _dismount(tester);
    });

    testWidgets('trigger(celebrate) swaps to the celebrate scene program',
        (tester) async {
      final stage = BuiltInStoryStage(sceneSeed: 3);
      await tester.pumpWidget(_host(stage));
      await tester.pump(const Duration(milliseconds: 50));

      stage.trigger(StoryStageInput.celebrate);
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('builtin-stage-celebrate')),
          findsOneWidget);
      expect(find.byKey(const ValueKey<String>('builtin-stage-idle')),
          findsNothing);

      // Step through the finite celebrate beat; the view stays on the
      // celebrate program (awake scene) after the beat completes.
      for (var i = 0; i < 15; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const ValueKey<String>('builtin-stage-celebrate')),
          findsOneWidget);

      await _dismount(tester);
    });

    testWidgets(
        'the full celebration sequence: celebrate, collect (flight token '
        'duration), then idle again', (tester) async {
      final stage = BuiltInStoryStage(sceneSeed: 8);
      await tester.pumpWidget(_host(stage));
      await tester.pump(const Duration(milliseconds: 50));

      stage.trigger(StoryStageInput.celebrate);
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('builtin-stage-celebrate')),
          findsOneWidget);

      stage.trigger(StoryStageInput.collect);
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('builtin-stage-collect')),
          findsOneWidget);
      expect(find.byKey(const ValueKey<String>('builtin-stage-celebrate')),
          findsNothing);

      // Step past the collectible flight (DesignTokens token, 600 ms) in
      // bounded increments; the collect program stays settled after it.
      final flightSteps =
          DesignTokens.collectibleFlightDuration.inMilliseconds ~/ 100 + 2;
      for (var i = 0; i < flightSteps; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(find.byKey(const ValueKey<String>('builtin-stage-collect')),
          findsOneWidget);

      stage.trigger(StoryStageInput.idle);
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('builtin-stage-idle')),
          findsOneWidget);

      await _dismount(tester);
    });

    testWidgets('equal-seed stages render equal scene arrangements',
        (tester) async {
      final a = BuiltInStoryStage(sceneSeed: 21);
      final b = BuiltInStoryStage(sceneSeed: 21);

      await tester.pumpWidget(_host(a));
      await tester.pump(const Duration(milliseconds: 16));
      final painterA = tester
          .widget<CustomPaint>(
              find.byKey(const ValueKey<String>('builtin-stage-idle')))
          .painter! as BuiltInStoryStagePainter;

      await tester.pumpWidget(_host(b));
      await tester.pump(const Duration(milliseconds: 16));
      final painterB = tester
          .widget<CustomPaint>(
              find.byKey(const ValueKey<String>('builtin-stage-idle')))
          .painter! as BuiltInStoryStagePainter;

      expect(painterA.scene, equals(painterB.scene));

      await _dismount(tester);
    });
  });

  group('BuiltInStoryStageView: ticker hygiene', () {
    testWidgets('the idle ambient loop runs while mounted and enabled',
        (tester) async {
      final stage = BuiltInStoryStage();
      await tester.pumpWidget(_host(stage));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
      await _dismount(tester);
    });

    testWidgets('TickerMode(enabled: false) stops the ambient ticker',
        (tester) async {
      final stage = BuiltInStoryStage();
      await tester.pumpWidget(_host(stage));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      await tester.pumpWidget(_host(stage, tickersEnabled: false));
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.binding.transientCallbackCount, 0);

      await _dismount(tester);
    });

    testWidgets('dismounting the view disposes every ticker cleanly',
        (tester) async {
      final stage = BuiltInStoryStage();
      await tester.pumpWidget(_host(stage));
      stage.trigger(StoryStageInput.celebrate);
      await tester.pump(const Duration(milliseconds: 100));

      await _dismount(tester);
      expect(tester.binding.transientCallbackCount, 0);

      // Triggering after dismount must not throw: the view removed its
      // listener on dispose.
      stage.trigger(StoryStageInput.collect);
      expect(stage.activeState, StoryStageInput.collect);
    });
  });
}

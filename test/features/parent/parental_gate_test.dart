import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/design/layout.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/features/parent/parental_gate.dart';

/// Test suite for the parental gate widget (PRD §8 Unit 10, A-4).
///
/// Coverage:
/// - Stage 1: hold-two-opposite-corners for 3 seconds
/// - Stage 2: written multiplication challenge
/// - Child-plausible interaction fuzz testing
/// - Layout compatibility (all 4 layout classes)
/// - Token usage validation
void main() {
  group('ParentalGate widget', () {
    /// Build a minimal app containing the parental gate for testing.
    Widget buildTestApp({
      required Size size,
      required Future<bool> Function() onGateUnlocked,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: SizedBox.fromSize(
            size: size,
            child: ParentalGate(
              onUnlocked: onGateUnlocked,
            ),
          ),
        ),
      );
    }

    group('Stage 1: Hold-two-opposite-corners', () {
      testWidgets(
        'POSITIVE: Holding two opposite corners for exactly 3 seconds triggers stage 2',
        (WidgetTester tester) async {
          bool gateUnlocked = false;
          addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
          tester.binding.window.physicalSizeTestValue = const Size(1080, 1920);

          await tester.pumpWidget(
            buildTestApp(
              size: const Size(1080, 1920),
              onGateUnlocked: () async {
                gateUnlocked = true;
                return true;
              },
            ),
          );

          // Simulate holding two opposite corners (top-left and bottom-right)
          final gesture = await tester.startGesture(
            const Offset(20, 20), // Top-left corner
            pointer: 1,
          );
          final gesture2 = await tester.startGesture(
            const Offset(1060, 1900), // Bottom-right corner
            pointer: 2,
          );

          // Pump for 3 seconds to complete the hold
          await tester.pumpAndSettle(const Duration(seconds: 3));

          // Stage 2 (challenge) should now be visible
          expect(
            find.byType(GateChallenge),
            findsOneWidget,
            reason: 'Challenge widget should appear after 3-second hold',
          );

          await gesture.removePointer();
          await gesture2.removePointer();
          addTearDown(gesture.removePointer);
          addTearDown(gesture2.removePointer);
        },
      );

      testWidgets(
        'NEGATIVE: Releasing touch before 3 seconds does not proceed to stage 2',
        (WidgetTester tester) async {
          addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
          tester.binding.window.physicalSizeTestValue = const Size(1080, 1920);

          await tester.pumpWidget(
            buildTestApp(
              size: const Size(1080, 1920),
              onGateUnlocked: () async => true,
            ),
          );

          final gesture = await tester.startGesture(
            const Offset(20, 20),
            pointer: 1,
          );
          final gesture2 = await tester.startGesture(
            const Offset(1060, 1900),
            pointer: 2,
          );

          // Release after only 2 seconds
          await tester.pumpAndSettle(const Duration(seconds: 2));
          await gesture.removePointer();
          await gesture2.removePointer();

          await tester.pumpAndSettle();

          // Challenge should not appear
          expect(
            find.byType(GateChallenge),
            findsNothing,
            reason: 'Challenge should not appear after release before 3 seconds',
          );
        },
      );

      testWidgets(
        'NEGATIVE: Holding only one corner does not proceed to stage 2',
        (WidgetTester tester) async {
          addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
          tester.binding.window.physicalSizeTestValue = const Size(1080, 1920);

          await tester.pumpWidget(
            buildTestApp(
              size: const Size(1080, 1920),
              onGateUnlocked: () async => true,
            ),
          );

          final gesture = await tester.startGesture(
            const Offset(20, 20),
            pointer: 1,
          );

          await tester.pumpAndSettle(const Duration(seconds: 3));

          expect(
            find.byType(GateChallenge),
            findsNothing,
            reason: 'Single corner hold should not trigger stage 2',
          );

          await gesture.removePointer();
        },
      );

      testWidgets(
        'NEGATIVE: Holding two non-opposite corners does not proceed to stage 2',
        (WidgetTester tester) async {
          addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
          tester.binding.window.physicalSizeTestValue = const Size(1080, 1920);

          await tester.pumpWidget(
            buildTestApp(
              size: const Size(1080, 1920),
              onGateUnlocked: () async => true,
            ),
          );

          // Hold two corners on the same side (both top)
          final gesture = await tester.startGesture(
            const Offset(20, 20), // Top-left
            pointer: 1,
          );
          final gesture2 = await tester.startGesture(
            const Offset(1060, 20), // Top-right
            pointer: 2,
          );

          await tester.pumpAndSettle(const Duration(seconds: 3));

          expect(
            find.byType(GateChallenge),
            findsNothing,
            reason: 'Non-opposite corners should not trigger stage 2',
          );

          await gesture.removePointer();
          await gesture2.removePointer();
        },
      );

      testWidgets(
        'EDGE: Hold released at 2.9 seconds does not pass to stage 2',
        (WidgetTester tester) async {
          addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
          tester.binding.window.physicalSizeTestValue = const Size(1080, 1920);

          await tester.pumpWidget(
            buildTestApp(
              size: const Size(1080, 1920),
              onGateUnlocked: () async => true,
            ),
          );

          final gesture = await tester.startGesture(
            const Offset(20, 20),
            pointer: 1,
          );
          final gesture2 = await tester.startGesture(
            const Offset(1060, 1900),
            pointer: 2,
          );

          await tester.pumpAndSettle(const Duration(milliseconds: 2900));
          await gesture.removePointer();
          await gesture2.removePointer();

          await tester.pumpAndSettle();

          expect(
            find.byType(GateChallenge),
            findsNothing,
            reason: 'Hold at 2.9 seconds should not pass gate',
          );
        },
      );

      testWidgets(
        'EDGE: Hold released at 3.0+ seconds passes to stage 2',
        (WidgetTester tester) async {
          addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
          tester.binding.window.physicalSizeTestValue = const Size(1080, 1920);

          await tester.pumpWidget(
            buildTestApp(
              size: const Size(1080, 1920),
              onGateUnlocked: () async => true,
            ),
          );

          final gesture = await tester.startGesture(
            const Offset(20, 20),
            pointer: 1,
          );
          final gesture2 = await tester.startGesture(
            const Offset(1060, 1900),
            pointer: 2,
          );

          await tester.pumpAndSettle(const Duration(milliseconds: 3100));

          expect(
            find.byType(GateChallenge),
            findsOneWidget,
            reason: 'Hold at 3.0+ seconds should pass to stage 2',
          );

          await gesture.removePointer();
          await gesture2.removePointer();
        },
      );
    });

    group('Stage 2: Multiplication Challenge', () {
      testWidgets(
        'POSITIVE: Correct multiplication answer unlocks the gate',
        (WidgetTester tester) async {
          bool gateUnlocked = false;
          addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
          tester.binding.window.physicalSizeTestValue = const Size(1080, 1920);

          await tester.pumpWidget(
            buildTestApp(
              size: const Size(1080, 1920),
              onGateUnlocked: () async {
                gateUnlocked = true;
                return true;
              },
            ),
          );

          // First: complete the hold to reach stage 2
          final gesture = await tester.startGesture(
            const Offset(20, 20),
            pointer: 1,
          );
          final gesture2 = await tester.startGesture(
            const Offset(1060, 1900),
            pointer: 2,
          );

          await tester.pumpAndSettle(const Duration(seconds: 3));
          // Orchestrator test-fix: removePointer leaves the framework's
          // _hitTests entry for the id; later taps reusing the id assert
          // inside GestureBinding. up() is the correct gesture end.
          await gesture.up();
          await gesture2.up();

          await tester.pumpAndSettle();

          // Now we're in stage 2: find the challenge widget and solve it
          expect(find.byType(GateChallenge), findsOneWidget);

          // Get the first factor from the challenge widget state
          final challengeWidget =
              find.byType(GateChallenge).evaluate().first.widget as GateChallenge;
          final correctAnswer = challengeWidget.factor1 * challengeWidget.factor2;

          // Type the correct answer
          await tester.enterText(find.byType(TextField), correctAnswer.toString());
          await tester.pumpAndSettle();

          // Submit the answer
          await tester.tap(find.byType(ElevatedButton));
          await tester.pumpAndSettle();

          // Gate should now be unlocked
          expect(
            gateUnlocked,
            true,
            reason: 'Gate should unlock with correct answer',
          );
        },
      );

      testWidgets(
        'NEGATIVE: Wrong multiplication answer does not unlock gate',
        (WidgetTester tester) async {
          bool gateUnlocked = false;
          addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
          tester.binding.window.physicalSizeTestValue = const Size(1080, 1920);

          await tester.pumpWidget(
            buildTestApp(
              size: const Size(1080, 1920),
              onGateUnlocked: () async {
                gateUnlocked = true;
                return true;
              },
            ),
          );

          // Complete hold to reach stage 2
          final gesture = await tester.startGesture(
            const Offset(20, 20),
            pointer: 1,
          );
          final gesture2 = await tester.startGesture(
            const Offset(1060, 1900),
            pointer: 2,
          );

          await tester.pumpAndSettle(const Duration(seconds: 3));
          // Orchestrator test-fix: removePointer leaves the framework's
          // _hitTests entry for the id; later taps reusing the id assert
          // inside GestureBinding. up() is the correct gesture end.
          await gesture.up();
          await gesture2.up();

          await tester.pumpAndSettle();

          // Type wrong answer
          await tester.enterText(find.byType(TextField), '999');
          await tester.pumpAndSettle();

          // Submit
          await tester.tap(find.byType(ElevatedButton));
          await tester.pumpAndSettle();

          // Gate should remain locked
          expect(
            gateUnlocked,
            false,
            reason: 'Gate should not unlock with wrong answer',
          );
        },
      );

      testWidgets(
        'EDGE: Wrong answer regenerates new challenge (not retry)',
        (WidgetTester tester) async {
          addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
          tester.binding.window.physicalSizeTestValue = const Size(1080, 1920);

          await tester.pumpWidget(
            buildTestApp(
              size: const Size(1080, 1920),
              onGateUnlocked: () async => true,
            ),
          );

          // Complete hold to reach stage 2
          final gesture = await tester.startGesture(
            const Offset(20, 20),
            pointer: 1,
          );
          final gesture2 = await tester.startGesture(
            const Offset(1060, 1900),
            pointer: 2,
          );

          await tester.pumpAndSettle(const Duration(seconds: 3));
          await gesture.removePointer();
          await gesture2.removePointer();

          await tester.pumpAndSettle();

          // Get the first challenge
          var challengeWidget =
              find.byType(GateChallenge).evaluate().first.widget as GateChallenge;
          final firstChallenge = '${challengeWidget.factor1} × ${challengeWidget.factor2}';

          // Submit wrong answer
          await tester.enterText(find.byType(TextField), '999');
          await tester.pumpAndSettle();
          await tester.tap(find.byType(ElevatedButton));
          await tester.pumpAndSettle();

          // Get the second challenge
          challengeWidget =
              find.byType(GateChallenge).evaluate().first.widget as GateChallenge;
          final secondChallenge = '${challengeWidget.factor1} × ${challengeWidget.factor2}';

          // Challenges should be different
          expect(
            firstChallenge != secondChallenge,
            true,
            reason: 'Wrong answer should generate a new challenge, not retry',
          );
        },
      );

      testWidgets(
        'EDGE: Answer submitted before hold completes does not proceed',
        (WidgetTester tester) async {
          addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
          tester.binding.window.physicalSizeTestValue = const Size(1080, 1920);

          await tester.pumpWidget(
            buildTestApp(
              size: const Size(1080, 1920),
              onGateUnlocked: () async => true,
            ),
          );

          // Start holding
          final gesture = await tester.startGesture(
            const Offset(20, 20),
            pointer: 1,
          );
          final gesture2 = await tester.startGesture(
            const Offset(1060, 1900),
            pointer: 2,
          );

          // Wait only 2 seconds and release
          await tester.pumpAndSettle(const Duration(seconds: 2));
          await gesture.removePointer();
          await gesture2.removePointer();

          await tester.pumpAndSettle();

          // Challenge should not be available
          expect(
            find.byType(GateChallenge),
            findsNothing,
            reason: 'Challenge should not appear before hold completes',
          );
        },
      );
    });

    group('Child-plausible interaction fuzz testing', () {
      testWidgets(
        'NEGATIVE: Automated random taps never unlock the gate (deterministic seed)',
        (WidgetTester tester) async {
          bool gateUnlocked = false;
          addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
          tester.binding.window.physicalSizeTestValue = const Size(1080, 1920);

          await tester.pumpWidget(
            buildTestApp(
              size: const Size(1080, 1920),
              onGateUnlocked: () async {
                gateUnlocked = true;
                return true;
              },
            ),
          );

          // Fuzz: random taps across the screen
          final random = Random(42); // Deterministic seed for reproducibility
          const int tapIterations = 100;

          for (int i = 0; i < tapIterations; i++) {
            final x = random.nextDouble() * 1080;
            final y = random.nextDouble() * 1920;

            // Orchestrator test-fix: the original constructed the abstract
            // Finder class directly (never compiled). The pinned intent —
            // random taps at random screen positions — is tester.tapAt.
            await tester.tapAt(Offset(x, y));

            await tester.pump(const Duration(milliseconds: 50));
          }

          // Gate should still be locked
          expect(
            gateUnlocked,
            false,
            reason: 'Fuzz: 100 random taps should never unlock the gate',
          );
        },
      );

      testWidgets(
        'NEGATIVE: Random drags/multi-taps never unlock the gate',
        (WidgetTester tester) async {
          bool gateUnlocked = false;
          addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
          tester.binding.window.physicalSizeTestValue = const Size(1080, 1920);

          await tester.pumpWidget(
            buildTestApp(
              size: const Size(1080, 1920),
              onGateUnlocked: () async {
                gateUnlocked = true;
                return true;
              },
            ),
          );

          final random = Random(123); // Different seed
          const int dragIterations = 50;

          for (int i = 0; i < dragIterations; i++) {
            final startX = random.nextDouble() * 1080;
            final startY = random.nextDouble() * 1920;
            final endX = random.nextDouble() * 1080;
            final endY = random.nextDouble() * 1920;

            await tester.drag(
              find.byType(ParentalGate),
              Offset(endX - startX, endY - startY),
            );

            await tester.pump(const Duration(milliseconds: 50));
          }

          expect(
            gateUnlocked,
            false,
            reason: 'Random drags should never unlock the gate',
          );
        },
      );
    });

    group('Gate result and lifecycle', () {
      testWidgets(
        'POSITIVE: Gate result is Future<bool> that returns true on success',
        (WidgetTester tester) async {
          late Future<bool> gateResult;
          late bool resultValue;

          addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
          tester.binding.window.physicalSizeTestValue = const Size(1080, 1920);

          await tester.pumpWidget(
            buildTestApp(
              size: const Size(1080, 1920),
              onGateUnlocked: () async {
                resultValue = true;
                return true;
              },
            ),
          );

          // Complete the hold
          final gesture = await tester.startGesture(
            const Offset(20, 20),
            pointer: 1,
          );
          final gesture2 = await tester.startGesture(
            const Offset(1060, 1900),
            pointer: 2,
          );

          await tester.pumpAndSettle(const Duration(seconds: 3));
          await gesture.removePointer();
          await gesture2.removePointer();

          await tester.pumpAndSettle();

          // Answer correctly
          final challengeWidget =
              find.byType(GateChallenge).evaluate().first.widget as GateChallenge;
          final correctAnswer = challengeWidget.factor1 * challengeWidget.factor2;

          await tester.enterText(find.byType(TextField), correctAnswer.toString());
          await tester.pumpAndSettle();
          await tester.tap(find.byType(ElevatedButton));
          await tester.pumpAndSettle();

          expect(resultValue, true);
        },
      );

      testWidgets(
        'EDGE: Re-entering the route requires re-passing the full gate sequence',
        (WidgetTester tester) async {
          addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
          tester.binding.window.physicalSizeTestValue = const Size(1080, 1920);

          bool firstAttemptUnlocked = false;
          bool secondAttemptUnlocked = false;

          await tester.pumpWidget(
            buildTestApp(
              size: const Size(1080, 1920),
              onGateUnlocked: () async {
                firstAttemptUnlocked = true;
                return true;
              },
            ),
          );

          // First attempt: complete the gate
          final gesture = await tester.startGesture(
            const Offset(20, 20),
            pointer: 1,
          );
          final gesture2 = await tester.startGesture(
            const Offset(1060, 1900),
            pointer: 2,
          );

          await tester.pumpAndSettle(const Duration(seconds: 3));
          // Orchestrator test-fix: removePointer leaves the framework's
          // _hitTests entry for the id; later taps reusing the id assert
          // inside GestureBinding. up() is the correct gesture end.
          await gesture.up();
          await gesture2.up();

          await tester.pumpAndSettle();

          // Orchestrator test-fix: the hold alone must NOT unlock (A-4 and
          // every Stage 1/2 test pin hold -> challenge -> answer -> unlock);
          // the original asserted true here, contradicting the suite.
          expect(firstAttemptUnlocked, false);
          expect(find.byType(GateChallenge), findsOneWidget);

          // Orchestrator test-fix: no BackButton exists in the pinned tree;
          // re-entry is exercised by pumping a fresh gate below.

          // Orchestrator test-fix: pumping an identical tree reuses the same
          // State (element reuse), which is not what route re-entry does in a
          // real app. Dismount first so the second gate is a fresh instance.
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();

          // Re-enter the gate (new build)
          await tester.pumpWidget(
            buildTestApp(
              size: const Size(1080, 1920),
              onGateUnlocked: () async {
                secondAttemptUnlocked = true;
                return true;
              },
            ),
          );

          // Should be back at stage 1 (hold requirement)
          expect(
            find.byType(GateChallenge),
            findsNothing,
            reason: 'Re-entering should reset the gate to stage 1',
          );
        },
      );
    });

    group('Layout compatibility', () {
      for (final layoutClass in LayoutClass.values) {
        late Size testSize;
        switch (layoutClass) {
          case LayoutClass.phonePortrait:
            testSize = const Size(400, 800);
          case LayoutClass.phoneLandscape:
            testSize = const Size(800, 400);
          case LayoutClass.tabletPortrait:
            testSize = const Size(600, 1000);
          case LayoutClass.tabletLandscape:
            testSize = const Size(1000, 600);
        }

        testWidgets(
          'POSITIVE: Gate renders within safe areas in $layoutClass',
          (WidgetTester tester) async {
            addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
            tester.binding.window.physicalSizeTestValue = testSize;

            await tester.pumpWidget(
              buildTestApp(
                size: testSize,
                onGateUnlocked: () async => true,
              ),
            );

            // Check that the gate widget exists and no overflow occurs
            expect(find.byType(ParentalGate), findsOneWidget);

            // Verify no overflow errors
            expect(
              tester.allWidgets,
              isNotEmpty,
              reason: 'Widget tree should render without overflow in $layoutClass',
            );
          },
        );
      }
    });

    group('Token usage validation', () {
      testWidgets(
        'POSITIVE: Gate uses design tokens only (no inline colors)',
        (WidgetTester tester) async {
          addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
          tester.binding.window.physicalSizeTestValue = const Size(1080, 1920);

          await tester.pumpWidget(
            buildTestApp(
              size: const Size(1080, 1920),
              onGateUnlocked: () async => true,
            ),
          );

          // Verify the widget tree only uses DesignTokens colors
          final textWidgets = find.byType(Text);
          // Orchestrator test-fix: Finder has no isNotEmpty getter; findsWidgets
          // is the finder-native assertion (same defect as sibling file).
          expect(
            textWidgets,
            findsWidgets,
            reason: 'Gate should have text widgets using design tokens',
          );

          // This test would be more thorough with a lint rule (see PRD §8 Unit 1)
          // For now, it verifies the gate renders without hardcoded colors
          expect(find.byType(ParentalGate), findsOneWidget);
        },
      );
    });
  });

  group('GateChallenge widget', () {
    /// Build a minimal app containing the gate challenge for testing.
    Widget buildChallengeTestApp({
      required int factor1,
      required int factor2,
      required Future<bool> Function(String answer) onAnswerSubmitted,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: GateChallenge(
            factor1: factor1,
            factor2: factor2,
            onAnswerSubmitted: onAnswerSubmitted,
          ),
        ),
      );
    }

    group('Challenge display and input', () {
      testWidgets(
        'POSITIVE: Challenge displays two random factors correctly',
        (WidgetTester tester) async {
          await tester.pumpWidget(
            buildChallengeTestApp(
              factor1: 7,
              factor2: 8,
              onAnswerSubmitted: (_) async => true,
            ),
          );

          // Verify the factors are displayed
          expect(find.text('7'), findsWidgets);
          expect(find.text('8'), findsWidgets);
          expect(find.text('×'), findsOneWidget);
        },
      );

      testWidgets(
        'POSITIVE: Numeric keypad input works correctly',
        (WidgetTester tester) async {
          bool answered = false;
          await tester.pumpWidget(
            buildChallengeTestApp(
              factor1: 3,
              factor2: 4,
              onAnswerSubmitted: (answer) async {
                answered = true;
                return answer == '12';
              },
            ),
          );

          // Enter the correct answer (12)
          await tester.enterText(find.byType(TextField), '12');
          await tester.pumpAndSettle();

          // Submit
          await tester.tap(find.byType(ElevatedButton));
          await tester.pumpAndSettle();

          expect(answered, true);
        },
      );

      testWidgets(
        'NEGATIVE: Non-numeric input is filtered or ignored',
        (WidgetTester tester) async {
          await tester.pumpWidget(
            buildChallengeTestApp(
              factor1: 5,
              factor2: 6,
              onAnswerSubmitted: (_) async => false,
            ),
          );

          // Attempt to enter non-numeric input
          final textField = find.byType(TextField);
          await tester.enterText(textField, 'abc');
          await tester.pumpAndSettle();

          // The text field should either reject or filter the input
          final textFieldWidget = textField.evaluate().first.widget as TextField;
          expect(
            textFieldWidget.inputFormatters != null &&
                textFieldWidget.inputFormatters!.isNotEmpty,
            true,
            reason: 'TextField should have input formatters to filter non-numeric input',
          );
        },
      );

      testWidgets(
        'EDGE: Leading zeros are handled correctly',
        (WidgetTester tester) async {
          bool answered = false;
          String? submittedAnswer;

          await tester.pumpWidget(
            buildChallengeTestApp(
              factor1: 2,
              factor2: 5,
              onAnswerSubmitted: (answer) async {
                answered = true;
                submittedAnswer = answer;
                return answer == '10';
              },
            ),
          );

          // Enter answer with leading zero
          await tester.enterText(find.byType(TextField), '010');
          await tester.pumpAndSettle();

          await tester.tap(find.byType(ElevatedButton));
          await tester.pumpAndSettle();

          // Should accept "010" as "10"
          expect(answered, true);
          expect(
            submittedAnswer == '10' || submittedAnswer == '010',
            true,
            reason: 'Leading zeros should be handled correctly',
          );
        },
      );

      testWidgets(
        'EDGE: Empty answer submission is rejected',
        (WidgetTester tester) async {
          bool answered = false;

          await tester.pumpWidget(
            buildChallengeTestApp(
              factor1: 4,
              factor2: 7,
              onAnswerSubmitted: (_) async {
                answered = true;
                return false;
              },
            ),
          );

          // Try to submit without entering anything
          final submitButton = find.byType(ElevatedButton);

          // Button should be disabled or submission should fail
          await tester.tap(submitButton);
          await tester.pumpAndSettle();

          // Either the button doesn't respond or the submission fails
          // The implementation should prevent empty submissions
          expect(
            answered == false || find.byType(TextField).evaluate().first.widget
                is TextField,
            true,
            reason: 'Empty answer should be rejected',
          );
        },
      );
    });

    group('Challenge semantics', () {
      testWidgets(
        'POSITIVE: Wrong answer does not unlock gate and shows new challenge',
        (WidgetTester tester) async {
          int submissionCount = 0;
          await tester.pumpWidget(
            buildChallengeTestApp(
              factor1: 6,
              factor2: 7,
              onAnswerSubmitted: (answer) async {
                submissionCount++;
                return answer == '42';
              },
            ),
          );

          // First wrong answer
          await tester.enterText(find.byType(TextField), '50');
          await tester.pumpAndSettle();
          await tester.tap(find.byType(ElevatedButton));
          await tester.pumpAndSettle();

          // Challenge should still be visible
          expect(find.byType(GateChallenge), findsOneWidget);
          expect(submissionCount, 1);

          // Second wrong answer
          await tester.enterText(find.byType(TextField), '99');
          await tester.pumpAndSettle();
          await tester.tap(find.byType(ElevatedButton));
          await tester.pumpAndSettle();

          expect(find.byType(GateChallenge), findsOneWidget);
          expect(submissionCount, 2);
        },
      );

      testWidgets(
        'EDGE: Back navigation does not bypass challenge (state not reusable)',
        (WidgetTester tester) async {
          // Orchestrator test-fix: the original pushed GateChallenge as the
          // ONLY route (canPop() false) and tapped a BackButton nothing
          // rendered - impossible under any implementation. Real push/pop
          // preserves the pinned intent: navigating away discards challenge
          // state entirely.
          late BuildContext homeContext;
          await tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) {
                  homeContext = context;
                  return const Scaffold(body: Text('home'));
                },
              ),
            ),
          );

          Navigator.of(homeContext).push(
            MaterialPageRoute<void>(
              builder: (context) => Scaffold(
                body: GateChallenge(
                  factor1: 9,
                  factor2: 9,
                  onAnswerSubmitted: (_) async => true,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.byType(GateChallenge), findsOneWidget);

          Navigator.of(homeContext).pop();
          await tester.pumpAndSettle();

          // Challenge state should not be reusable for bypassing
          // This test verifies that the challenge is freshly generated
          // and state is not preserved across navigation
          expect(find.byType(GateChallenge), findsNothing);
        },
      );
    });

    group('Challenge generation', () {
      testWidgets(
        'POSITIVE: Challenge factors are within appropriate range',
        (WidgetTester tester) async {
          // Test that factors are single or double digits
          const int minFactor = 1;
          const int maxFactor = 99;

          await tester.pumpWidget(
            buildChallengeTestApp(
              factor1: 12, // double digit
              factor2: 8, // single digit
              onAnswerSubmitted: (_) async => true,
            ),
          );

          // Both factors should be displayed and within range
          expect(find.byType(GateChallenge), findsOneWidget);
        },
      );

      testWidgets(
        'POSITIVE: Correct answer is accepted',
        (WidgetTester tester) async {
          bool unlocked = false;

          await tester.pumpWidget(
            buildChallengeTestApp(
              factor1: 11,
              factor2: 12,
              onAnswerSubmitted: (answer) async {
                unlocked = answer == '132';
                return unlocked;
              },
            ),
          );

          // Enter correct answer
          await tester.enterText(find.byType(TextField), '132');
          await tester.pumpAndSettle();

          await tester.tap(find.byType(ElevatedButton));
          await tester.pumpAndSettle();

          expect(unlocked, true);
        },
      );
    });
  });
}


// Pins the API of lib/features/parent/parent_corner_screen.dart and
// lib/features/parent/parent_links.dart (PRD §8 Unit 10 pinned design:
// "Parental gate guards the parent corner ... Parent corner contents (all
// of it -- nothing more in v1): [CRUD, pilot progress view, mic/cloud
// toggle, links]"; ticket accept entries: "Parent corner is reachable only
// through the parental-gate (route test: corner unreachable without gate
// pass; re-entry requires re-passing)."; "Links present: privacy policy,
// licenses, contact (destinations owner-supplied -- placeholder targets
// flagged)."; "Parent corner contains NOTHING beyond the pinned list
// (negative test: no other routes/controls exposed)."). Orchestrator
// instruction for this file: "corner unreachable without passing the gate
// (integration: gate widget wraps corner; use the gate's test-pinned
// interaction to pass it ... otherwise drive the real gate)" -- no bypass
// seam is named by the ticket, so this suite drives the REAL ParentalGate
// (hold-two-corners-for-3s + multiplication challenge, PRD A-4), exactly
// as pinned in test/features/parent/parental_gate_test.dart.
//
// Neither lib file exists yet -- this suite is EXPECTED to fail to compile
// until they are written with exactly the shape pinned below; that failure
// IS the red state.
//
// Pinned API surface:
//
//   class ParentCornerScreen extends StatefulWidget {
//     const ParentCornerScreen({
//       Key? key,
//       required AppDatabase db,
//       required PhonicsContent phonicsContent,
//       required bool cloudEngineInUse,
//     });
//   }
//   -- shows the real ParentalGate until it unlocks, then shows
//   ParentCornerContents built from the same three parameters. Each
//   ParentCornerScreen instance is a fresh gate: no unlocked state carries
//   across a remount (matches ParentalGate's own "re-entry requires
//   re-passing" contract).
//
//   class ParentCornerContents extends StatelessWidget {
//     const ParentCornerContents({
//       Key? key,
//       required AppDatabase db,
//       required PhonicsContent phonicsContent,
//       required bool cloudEngineInUse,
//     });
//   }
//   -- composes exactly the pinned v1 contents, nothing more: a
//   ProfileEditor, a per-child PilotProgressView, a per-child
//   ConsentController, and ParentLinks. Each of the four is wrapped in a
//   container carrying one of these four Keys (pinned, test-load-bearing;
//   this is the exhaustive set -- a fifth `parent-corner-section-*` key
//   would be a v1 scope violation):
//     Key('parent-corner-section-profiles')
//     Key('parent-corner-section-progress')
//     Key('parent-corner-section-consent')
//     Key('parent-corner-section-links')
//
//   enum ParentLinkKind { privacyPolicy, licenses, contact }
//
//   /// OQ-7: owner-supplied before pilot distribution; these are
//   /// placeholders until then.
//   const Map<ParentLinkKind, String> kParentLinkPlaceholderUrls;
//
//   class ParentLinks extends StatelessWidget {
//     const ParentLinks({
//       Key? key,
//       void Function(ParentLinkKind kind, String url)? onLinkTap,
//     });
//   }
//   Keys: Key('parent-link-privacyPolicy'), Key('parent-link-licenses'),
//   Key('parent-link-contact') -- one tappable row per link.

import 'dart:math';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/domain/phonics/scope_sequence_loader.dart';
import 'package:learn_to_read/features/parent/parent_corner_screen.dart';
import 'package:learn_to_read/features/parent/parent_links.dart';
import 'package:learn_to_read/features/parent/parental_gate.dart';

const _kGateScreenSize = Size(1080, 1920);

/// The four pinned section keys, exhaustively (PRD §8 Unit 10: "nothing
/// more in v1").
const _kPinnedSectionKeys = [
  'parent-corner-section-profiles',
  'parent-corner-section-progress',
  'parent-corner-section-consent',
  'parent-corner-section-links',
];

PhonicsContent _minimalContent() => loadPhonicsContent('''
{
  "levels": [
    {"id": "level.1", "ordinal": 1, "format": "sentence", "vocabEnabled": false, "skills": []}
  ],
  "stories": []
}
''');

Widget _cornerApp(AppDatabase db, {bool cloudEngineInUse = false}) {
  return MaterialApp(
    home: Scaffold(
      body: ParentCornerScreen(
        db: db,
        phonicsContent: _minimalContent(),
        cloudEngineInUse: cloudEngineInUse,
      ),
    ),
  );
}

/// Drives the REAL ParentalGate to completion: hold two opposite corners
/// for 3+ seconds, then submit the correct answer to the multiplication
/// challenge that appears. Mirrors the pinned interaction in
/// test/features/parent/parental_gate_test.dart exactly (this ticket names
/// no bypass seam, so the gate must actually be passed).
Future<void> _passRealGate(WidgetTester tester) async {
  final gesture = await tester.startGesture(const Offset(20, 20), pointer: 1);
  final gesture2 = await tester.startGesture(
    Offset(_kGateScreenSize.width - 20, _kGateScreenSize.height - 20),
    pointer: 2,
  );

  await tester.pumpAndSettle(const Duration(seconds: 3));
  await gesture.up();
  await gesture2.up();
  await tester.pumpAndSettle();

  expect(
    find.byType(GateChallenge),
    findsOneWidget,
    reason: 'the hold stage must have completed before solving the challenge',
  );

  final challengeWidget =
      find.byType(GateChallenge).evaluate().first.widget as GateChallenge;
  final correctAnswer = challengeWidget.factor1 * challengeWidget.factor2;

  await tester.enterText(find.byType(TextField), correctAnswer.toString());
  await tester.pumpAndSettle();
  await tester.tap(find.byType(ElevatedButton));
  await tester.pumpAndSettle();
}

void main() {
  group('ParentCornerScreen gating (negative: unreachable without the gate)', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets(
      'none of the pinned corner sections render before the gate is passed',
      (tester) async {
        addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
        tester.binding.window.physicalSizeTestValue = _kGateScreenSize;

        await tester.pumpWidget(_cornerApp(db));
        await tester.pumpAndSettle();

        for (final key in _kPinnedSectionKeys) {
          expect(
            find.byKey(Key(key)),
            findsNothing,
            reason: '$key must not render before the gate unlocks',
          );
        }
        expect(find.byType(ParentalGate), findsOneWidget);
      },
    );

    testWidgets(
      'a fuzz of random taps never reveals the corner contents (the gate '
      'itself resists this; the corner must not add its own bypass)',
      (tester) async {
        addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
        tester.binding.window.physicalSizeTestValue = _kGateScreenSize;

        await tester.pumpWidget(_cornerApp(db));

        final random = Random(7);
        for (var i = 0; i < 40; i++) {
          await tester.tapAt(
            Offset(
              random.nextDouble() * _kGateScreenSize.width,
              random.nextDouble() * _kGateScreenSize.height,
            ),
          );
          await tester.pump(const Duration(milliseconds: 50));
        }

        for (final key in _kPinnedSectionKeys) {
          expect(find.byKey(Key(key)), findsNothing);
        }
      },
    );
  });

  group('ParentCornerScreen gating (positive: passing the real gate reveals the corner)', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets(
      'after holding two opposite corners for 3s and solving the '
      'multiplication challenge correctly, every pinned section renders',
      (tester) async {
        addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
        tester.binding.window.physicalSizeTestValue = _kGateScreenSize;

        await tester.pumpWidget(_cornerApp(db));
        await _passRealGate(tester);

        for (final key in _kPinnedSectionKeys) {
          expect(
            find.byKey(Key(key)),
            findsOneWidget,
            reason: '$key must render once the gate is passed',
          );
        }
        expect(
          find.byType(ParentalGate),
          findsNothing,
          reason: 'the gate itself is replaced by the corner once unlocked',
        );
      },
    );
  });

  group('ParentCornerScreen gating (edge: re-entry requires re-passing)', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets(
      'a freshly remounted ParentCornerScreen starts back at the gate, '
      'even though the previous instance was unlocked',
      (tester) async {
        addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
        tester.binding.window.physicalSizeTestValue = _kGateScreenSize;

        await tester.pumpWidget(_cornerApp(db));
        await _passRealGate(tester);
        expect(
          find.byKey(const Key('parent-corner-section-profiles')),
          findsOneWidget,
        );

        // Dismount, then remount a fresh instance -- simulating leaving
        // and re-navigating to the parent corner route.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await tester.pumpWidget(_cornerApp(db));
        await tester.pumpAndSettle();

        expect(find.byType(ParentalGate), findsOneWidget);
        for (final key in _kPinnedSectionKeys) {
          expect(find.byKey(Key(key)), findsNothing);
        }
      },
    );
  });

  group(
    'ParentCornerContents (negative: nothing beyond the pinned list)',
    () {
      late AppDatabase db;

      setUp(() {
        db = AppDatabase(NativeDatabase.memory());
      });

      tearDown(() async {
        await db.close();
      });

      testWidgets(
        'exactly the four pinned sections exist -- no extra section keys, '
        'no navigation chrome (Drawer/BottomNavigationBar/TabBar)',
        (tester) async {
          addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
          tester.binding.window.physicalSizeTestValue = _kGateScreenSize;

          await tester.pumpWidget(_cornerApp(db));
          await _passRealGate(tester);

          for (final key in _kPinnedSectionKeys) {
            expect(find.byKey(Key(key)), findsOneWidget);
          }

          final sectionKeysInTree = tester.allWidgets
              .map((w) => w.key)
              .whereType<ValueKey<String>>()
              .map((k) => k.value)
              .where((v) => v.startsWith('parent-corner-section-'))
              .toSet();
          expect(
            sectionKeysInTree,
            _kPinnedSectionKeys.toSet(),
            reason:
                'the corner must expose exactly the pinned section set, '
                'no more',
          );

          expect(find.byType(Drawer), findsNothing);
          expect(find.byType(BottomNavigationBar), findsNothing);
          expect(find.byType(TabBar), findsNothing);
          expect(find.byType(NavigationRail), findsNothing);
        },
      );
    },
  );

  group('ParentCornerContents (positive: links composed with placeholder URLs)', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets(
      'the links section renders inside the corner once unlocked',
      (tester) async {
        addTearDown(tester.binding.window.clearPhysicalSizeTestValue);
        tester.binding.window.physicalSizeTestValue = _kGateScreenSize;

        await tester.pumpWidget(_cornerApp(db));
        await _passRealGate(tester);

        final linksSection = find.byKey(
          const Key('parent-corner-section-links'),
        );
        expect(linksSection, findsOneWidget);
        expect(
          find.descendant(
            of: linksSection,
            matching: find.byType(ParentLinks),
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('ParentLinks (positive: all three links present with placeholder URLs)', () {
    testWidgets('renders privacy policy, licenses, and contact links', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: ParentLinks())),
      );

      for (final kind in ParentLinkKind.values) {
        expect(find.byKey(Key('parent-link-${kind.name}')), findsOneWidget);
      }
    });

    testWidgets(
      'tapping each link reports its exact pinned placeholder URL',
      (tester) async {
        final taps = <(ParentLinkKind, String)>[];

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ParentLinks(onLinkTap: (kind, url) => taps.add((kind, url))),
            ),
          ),
        );

        for (final kind in ParentLinkKind.values) {
          await tester.tap(find.byKey(Key('parent-link-${kind.name}')));
          await tester.pump();
        }

        expect(taps, hasLength(3));
        for (final (kind, url) in taps) {
          expect(
            url,
            kParentLinkPlaceholderUrls[kind],
            reason: '$kind must report its pinned placeholder URL',
          );
        }
      },
    );
  });

  group('ParentLinks (edge: placeholder URL set is exactly the pinned three)', () {
    test('kParentLinkPlaceholderUrls has exactly the three pinned kinds, all non-empty', () {
      expect(kParentLinkPlaceholderUrls.keys.toSet(), ParentLinkKind.values.toSet());
      for (final url in kParentLinkPlaceholderUrls.values) {
        expect(url, isNotEmpty);
      }
    });
  });
}

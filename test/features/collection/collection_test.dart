// Test suite for lib/features/collection/collection_screen.dart and
// lib/features/collection/scene_slots.dart (PRD §8 Unit 9 "Collection
// scene"; ticket progress-map-collection accept entries 4, 5, 7).
//
// lib/features/collection/collection_screen.dart and
// lib/features/collection/scene_slots.dart do not exist yet: this file
// fails to compile/analyze until they are created, which is the expected
// red state.
//
// Pinned API surface:
//
//   class SceneSlotLayout {
//     // Parses a "row:col" sceneSlot string -- the pinned addressing scheme
//     // for this ticket (PRD §5 Collectible.sceneSlot leaves the exact
//     // format to content authoring; both row and col are non-negative
//     // integers). Throws FormatException for any other shape.
//     static ({int row, int col}) parseSlot(String sceneSlot);
//     static Offset offsetForSlot(
//       String sceneSlot, {
//       required double cellWidth,
//       required double cellHeight,
//     });
//     // The canvas extent needed to fit every slot in `sceneSlots` without
//     // clipping -- grows in the row (vertical) direction as more slots are
//     // authored; never a fixed cap (PRD §8 Unit 9: "the scene design must
//     // define how it extends for future packs").
//     static Size canvasSizeFor(
//       Iterable<String> sceneSlots, {
//       required double cellWidth,
//       required double cellHeight,
//     });
//   }
//
//   class CollectionScreen extends StatelessWidget {
//     const CollectionScreen({
//       super.key,
//       required Profile profile,
//       required List<Collectible> collectibles,      // full authored catalog
//       required CollectionState collectionState,      // this profile's earned ids
//       required StoryStage Function(String collectibleId) stageFor,
//     });
//   }
//
// Rendering contract (accept 4): CollectionScreen renders exactly the
// collectibles whose id is in `collectionState.earnedCollectibles`, each
// keyed ValueKey('collectible-node-<id>'), positioned per
// SceneSlotLayout.offsetForSlot(collectible.sceneSlot, ...); a collectible
// absent from `earnedCollectibles` renders NO node at all, even though it
// is present in `collectibles` (the full catalog is supplied so the screen
// itself does the earned/unearned filtering, not the caller).
//
// Poke contract (accept 4): tapping a collectible node calls
// `stageFor(collectible.id).trigger(StoryStageInput.collect)` on THAT
// collectible's stage only -- every other collectible's stage
// (FakeStoryStage in tests) records no triggers at all.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/design/fake_rive_stage.dart';
import 'package:learn_to_read/design/rive_stage.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/features/collection/collection_screen.dart';
import 'package:learn_to_read/features/collection/scene_slots.dart';

Profile _fixtureProfile({String localId = 'profile.amara'}) => Profile(
      localId: localId,
      displayName: 'Amara',
      ageBand: AgeBand.fiveToSix,
      currentLevelId: 'level.1',
      micConsent: true,
      cloudAsrConsent: false,
      createdAt: DateTime(2026, 1, 1),
    );

final _catalog = <Collectible>[
  Collectible(id: 'collectible.cat', storyId: 'story.1', riveRef: 'rive/cat.riv', sceneSlot: '0:0'),
  Collectible(id: 'collectible.dog', storyId: 'story.2', riveRef: 'rive/dog.riv', sceneSlot: '0:1'),
  Collectible(id: 'collectible.owl', storyId: 'story.3', riveRef: 'rive/owl.riv', sceneSlot: '1:0'),
];

void main() {
  group('SceneSlotLayout.parseSlot (pinned "row:col" addressing scheme)', () {
    test('POSITIVE: parses a well-formed slot into its row/col', () {
      expect(SceneSlotLayout.parseSlot('2:5'), (row: 2, col: 5));
    });

    test('POSITIVE: "0:0" parses to the origin', () {
      expect(SceneSlotLayout.parseSlot('0:0'), (row: 0, col: 0));
    });

    test('NEGATIVE: a slot missing the separator throws FormatException', () {
      expect(() => SceneSlotLayout.parseSlot('25'), throwsFormatException);
    });

    test('NEGATIVE: a slot with a negative coordinate throws FormatException', () {
      expect(() => SceneSlotLayout.parseSlot('-1:0'), throwsFormatException);
    });

    test('NEGATIVE: a non-numeric slot throws FormatException', () {
      expect(() => SceneSlotLayout.parseSlot('garden:bench'), throwsFormatException);
    });
  });

  group('SceneSlotLayout.offsetForSlot / canvasSizeFor', () {
    test('POSITIVE: offset scales column/row by the given cell size', () {
      final offset = SceneSlotLayout.offsetForSlot('2:3', cellWidth: 100, cellHeight: 80);
      expect(offset.dx, 300);
      expect(offset.dy, 160);
    });

    test(
      'POSITIVE: canvas size covers the highest row/col among the given '
      'slots (extends rather than clipping)',
      () {
        final size = SceneSlotLayout.canvasSizeFor(
          ['0:0', '1:3', '4:1'],
          cellWidth: 100,
          cellHeight: 80,
        );
        // Highest col is 3 -> width covers 4 columns; highest row is 4 -> height covers 5 rows.
        expect(size.width, greaterThanOrEqualTo(400));
        expect(size.height, greaterThanOrEqualTo(400));
      },
    );

    test('EDGE: an empty slot set yields a zero-area canvas', () {
      final size = SceneSlotLayout.canvasSizeFor(const [], cellWidth: 100, cellHeight: 80);
      expect(size.width * size.height, 0);
    });

    test(
      'EDGE: a beyond-launch slot count (40 slots spanning many rows) still '
      'produces a finite canvas that grows linearly with the row count, '
      'never capped',
      () {
        final manySlots = List.generate(40, (i) => '${i ~/ 4}:${i % 4}');
        final size = SceneSlotLayout.canvasSizeFor(manySlots, cellWidth: 50, cellHeight: 50);
        expect(size.height, greaterThanOrEqualTo(10 * 50));
      },
    );
  });

  group('CollectionScreen — earned/unearned rendering (accept 4)', () {
    Widget buildScreen({
      required List<String> earned,
      Map<String, FakeStoryStage>? stages,
    }) {
      final resolvedStages = stages ?? {for (final c in _catalog) c.id: FakeStoryStage()};
      return MaterialApp(
        home: CollectionScreen(
          profile: _fixtureProfile(),
          collectibles: _catalog,
          collectionState: CollectionState(profileId: 'profile.amara', earnedCollectibles: earned),
          stageFor: (id) => resolvedStages[id]!,
        ),
      );
    }

    testWidgets('POSITIVE: an earned collectible renders its node', (tester) async {
      await tester.pumpWidget(buildScreen(earned: const ['collectible.cat']));
      expect(find.byKey(const ValueKey('collectible-node-collectible.cat')), findsOneWidget);
    });

    testWidgets(
      'NEGATIVE: an unearned collectible renders NO node, even though it is '
      'present in the full catalog',
      (tester) async {
        await tester.pumpWidget(buildScreen(earned: const ['collectible.cat']));
        expect(find.byKey(const ValueKey('collectible-node-collectible.dog')), findsNothing);
        expect(find.byKey(const ValueKey('collectible-node-collectible.owl')), findsNothing);
      },
    );

    testWidgets('POSITIVE: every earned collectible renders exactly once', (tester) async {
      await tester.pumpWidget(
        buildScreen(earned: const ['collectible.cat', 'collectible.dog', 'collectible.owl']),
      );
      for (final c in _catalog) {
        expect(find.byKey(ValueKey('collectible-node-${c.id}')), findsOneWidget);
      }
    });

    testWidgets('EDGE: an empty CollectionState renders zero nodes', (tester) async {
      await tester.pumpWidget(buildScreen(earned: const []));
      for (final c in _catalog) {
        expect(find.byKey(ValueKey('collectible-node-${c.id}')), findsNothing);
      }
    });
  });

  group('CollectionScreen — poke tap fires collect on that stage only (accept 4)', () {
    testWidgets(
      'POSITIVE: tapping a collectible node triggers StoryStageInput.collect '
      'on its own FakeStoryStage',
      (tester) async {
        final stages = {for (final c in _catalog) c.id: FakeStoryStage()};
        await tester.pumpWidget(
          MaterialApp(
            home: CollectionScreen(
              profile: _fixtureProfile(),
              collectibles: _catalog,
              collectionState: CollectionState(
                profileId: 'profile.amara',
                earnedCollectibles: _catalog.map((c) => c.id).toList(),
              ),
              stageFor: (id) => stages[id]!,
            ),
          ),
        );

        await tester.tap(find.byKey(const ValueKey('collectible-node-collectible.cat')));
        await tester.pump();

        expect(stages['collectible.cat']!.triggeredInputs, contains(StoryStageInput.collect));
      },
    );

    testWidgets(
      'NEGATIVE: poking one collectible never triggers collect on a '
      'different collectible\'s stage (per-instance isolation)',
      (tester) async {
        final stages = {for (final c in _catalog) c.id: FakeStoryStage()};
        await tester.pumpWidget(
          MaterialApp(
            home: CollectionScreen(
              profile: _fixtureProfile(),
              collectibles: _catalog,
              collectionState: CollectionState(
                profileId: 'profile.amara',
                earnedCollectibles: _catalog.map((c) => c.id).toList(),
              ),
              stageFor: (id) => stages[id]!,
            ),
          ),
        );

        await tester.tap(find.byKey(const ValueKey('collectible-node-collectible.cat')));
        await tester.pump();

        expect(stages['collectible.dog']!.triggeredInputs, isEmpty);
        expect(stages['collectible.owl']!.triggeredInputs, isEmpty);
      },
    );

    testWidgets(
      'POSITIVE: poking a collectible twice records two collect triggers on '
      'its stage (each tap is its own poke reaction)',
      (tester) async {
        final stage = FakeStoryStage();
        await tester.pumpWidget(
          MaterialApp(
            home: CollectionScreen(
              profile: _fixtureProfile(),
              collectibles: _catalog,
              collectionState: CollectionState(
                profileId: 'profile.amara',
                earnedCollectibles: const ['collectible.cat'],
              ),
              stageFor: (_) => stage,
            ),
          ),
        );

        await tester.tap(find.byKey(const ValueKey('collectible-node-collectible.cat')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('collectible-node-collectible.cat')));
        await tester.pump();

        expect(
          stage.triggeredInputs.where((i) => i == StoryStageInput.collect),
          hasLength(2),
        );
      },
    );
  });

  group(
    'CollectionScreen — CollectionState fixtures: first completion vs '
    're-read (accept "adds exactly one collectible ... re-reading adds none")',
    () {
      testWidgets(
        'POSITIVE: a CollectionState reflecting first completion (one '
        'earned entry) renders exactly one node',
        (tester) async {
          final afterFirstCompletion = CollectionState(
            profileId: 'profile.amara',
            earnedCollectibles: const ['collectible.cat'],
          );
          await tester.pumpWidget(
            MaterialApp(
              home: CollectionScreen(
                profile: _fixtureProfile(),
                collectibles: _catalog,
                collectionState: afterFirstCompletion,
                stageFor: (_) => FakeStoryStage(),
              ),
            ),
          );
          expect(
            find.byKey(const ValueKey('collectible-node-collectible.cat')),
            findsOneWidget,
          );
          expect(find.byKey(const ValueKey('collectible-node-collectible.dog')), findsNothing);
          expect(find.byKey(const ValueKey('collectible-node-collectible.owl')), findsNothing);
        },
      );

      testWidgets(
        'NEGATIVE: a CollectionState reflecting a re-read (still exactly one '
        'earned entry -- re-reading a completed story grants no second '
        'collectible) renders the SAME single node, not two',
        (tester) async {
          // Mirrors local-storage's CollectionDao.grantCollectible idempotency
          // (double-grant collapses to one row): the fixture after a re-read
          // is identical to the fixture after first completion.
          final afterReRead = CollectionState(
            profileId: 'profile.amara',
            earnedCollectibles: const ['collectible.cat'],
          );
          await tester.pumpWidget(
            MaterialApp(
              home: CollectionScreen(
                profile: _fixtureProfile(),
                collectibles: _catalog,
                collectionState: afterReRead,
                stageFor: (_) => FakeStoryStage(),
              ),
            ),
          );
          expect(
            find.byKey(const ValueKey('collectible-node-collectible.cat')),
            findsOneWidget,
          );
          expect(find.byKey(const ValueKey('collectible-node-collectible.dog')), findsNothing);
          expect(find.byKey(const ValueKey('collectible-node-collectible.owl')), findsNothing);
        },
      );
    },
  );

  group('CollectionScreen — driven by the in-memory DB (fixture + Drift)', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets(
      'POSITIVE: collectibles granted via CollectionDao (including a '
      'duplicate grant that must not duplicate a node) render exactly the '
      'distinct earned set',
      (tester) async {
        await db.collectionDao.grantCollectible(
          profileId: 'profile.amara',
          collectibleId: 'collectible.cat',
        );
        // Duplicate grant -- must stay idempotent (mirrors local-storage's
        // own pinned CollectionDao contract).
        await db.collectionDao.grantCollectible(
          profileId: 'profile.amara',
          collectibleId: 'collectible.cat',
        );
        await db.collectionDao.grantCollectible(
          profileId: 'profile.amara',
          collectibleId: 'collectible.dog',
        );

        final state = await db.collectionDao.getCollectionState('profile.amara');

        await tester.pumpWidget(
          MaterialApp(
            home: CollectionScreen(
              profile: _fixtureProfile(),
              collectibles: _catalog,
              collectionState: state,
              stageFor: (_) => FakeStoryStage(),
            ),
          ),
        );

        expect(find.byKey(const ValueKey('collectible-node-collectible.cat')), findsOneWidget);
        expect(find.byKey(const ValueKey('collectible-node-collectible.dog')), findsOneWidget);
        expect(find.byKey(const ValueKey('collectible-node-collectible.owl')), findsNothing);
      },
    );
  });
}

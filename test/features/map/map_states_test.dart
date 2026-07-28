// Test suite for lib/features/map/map_node.dart (PRD §8 Unit 9; ticket
// progress-map-collection accept entries 1, 2), plus multi-profile
// StoryProgress-fixture coverage for lib/features/map/progress_map_screen.dart
// (accept entry "locked / available / completed states for fixture
// profiles").
//
// lib/features/map/map_node.dart and lib/features/map/progress_map_screen.dart
// do not exist yet: this file fails to compile/analyze until they are
// created, which is the expected red state.
//
// Pinned API surface (map_node.dart):
//
//   enum MapNodeKind { story, twisterBooster }
//   enum MapNodeVisualState { asleep, awake, completed }
//
//   class MapNode extends StatelessWidget {
//     const MapNode({
//       super.key,
//       required String id,
//       required MapNodeKind kind,
//       required MapNodeVisualState visualState,
//       bool highlighted = false,
//       VoidCallback? onTap,
//     });
//
//     bool get isTappable => visualState != MapNodeVisualState.asleep;
//   }
//
// Tap contract (pinned): MapNode invokes `onTap` on tap ONLY when
// `visualState != MapNodeVisualState.asleep` -- an asleep node swallows the
// tap even if a non-null `onTap` was supplied ("tapping an asleep story does
// nothing" holds at the MapNode level, not just because callers omit the
// callback).
//
// Structural markers (pinned, mutually exclusive per state/kind, all
// findable by Key without depending on paint/pixel output -- these are this
// suite's headless proxy for "awake and gently animated" / "shown by
// thumbnail" / booster nodes' "distinct visual treatment" / the
// return-navigation "highlighted treatment"):
//   - ValueKey('map-node-thumbnail-<id>')        present iff visualState == completed
//   - ValueKey('map-node-awake-animation-<id>')  present iff visualState == awake
//   - ValueKey('map-node-asleep-marker-<id>')    present iff visualState == asleep
//   - ValueKey('map-node-twister-badge-<id>')    present iff kind == twisterBooster
//   - ValueKey('map-node-highlight-<id>')        present iff highlighted == true
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/domain/phonics/scope_sequence_loader.dart';
import 'package:learn_to_read/features/map/map_node.dart';
import 'package:learn_to_read/features/map/progress_map_screen.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('MapNode — visualState field + isTappable (accept 1, 2)', () {
    testWidgets('POSITIVE: asleep node reports isTappable == false', (tester) async {
      const node = MapNode(
        id: 'story.x',
        kind: MapNodeKind.story,
        visualState: MapNodeVisualState.asleep,
      );
      await tester.pumpWidget(_wrap(node));
      expect(node.isTappable, isFalse);
    });

    testWidgets('POSITIVE: awake node reports isTappable == true', (tester) async {
      const node = MapNode(
        id: 'story.x',
        kind: MapNodeKind.story,
        visualState: MapNodeVisualState.awake,
      );
      await tester.pumpWidget(_wrap(node));
      expect(node.isTappable, isTrue);
    });

    testWidgets('POSITIVE: completed node reports isTappable == true', (tester) async {
      const node = MapNode(
        id: 'story.x',
        kind: MapNodeKind.story,
        visualState: MapNodeVisualState.completed,
      );
      await tester.pumpWidget(_wrap(node));
      expect(node.isTappable, isTrue);
    });
  });

  group('MapNode — tap gating (accept 2)', () {
    testWidgets(
      'NEGATIVE: an asleep node with a non-null onTap still swallows the tap',
      (tester) async {
        var fired = false;
        await tester.pumpWidget(
          _wrap(
            MapNode(
              id: 'story.x',
              kind: MapNodeKind.story,
              visualState: MapNodeVisualState.asleep,
              onTap: () => fired = true,
            ),
          ),
        );
        await tester.tap(find.byType(MapNode));
        await tester.pump();
        expect(fired, isFalse);
      },
    );

    testWidgets('POSITIVE: an awake node with onTap fires it on tap', (tester) async {
      var fired = false;
      await tester.pumpWidget(
        _wrap(
          MapNode(
            id: 'story.x',
            kind: MapNodeKind.story,
            visualState: MapNodeVisualState.awake,
            onTap: () => fired = true,
          ),
        ),
      );
      await tester.tap(find.byType(MapNode));
      await tester.pump();
      expect(fired, isTrue);
    });

    testWidgets('POSITIVE: a completed node with onTap fires it on tap', (tester) async {
      var fired = false;
      await tester.pumpWidget(
        _wrap(
          MapNode(
            id: 'story.x',
            kind: MapNodeKind.story,
            visualState: MapNodeVisualState.completed,
            onTap: () => fired = true,
          ),
        ),
      );
      await tester.tap(find.byType(MapNode));
      await tester.pump();
      expect(fired, isTrue);
    });

    testWidgets(
      'EDGE: an awake node with onTap == null does not throw when tapped',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const MapNode(
              id: 'story.x',
              kind: MapNodeKind.story,
              visualState: MapNodeVisualState.awake,
            ),
          ),
        );
        await tester.tap(find.byType(MapNode));
        await tester.pump();
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('MapNode — structural state markers', () {
    testWidgets(
      'POSITIVE: completed renders the thumbnail marker and no other state marker',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const MapNode(
              id: 'story.x',
              kind: MapNodeKind.story,
              visualState: MapNodeVisualState.completed,
            ),
          ),
        );
        expect(find.byKey(const ValueKey('map-node-thumbnail-story.x')), findsOneWidget);
        expect(find.byKey(const ValueKey('map-node-awake-animation-story.x')), findsNothing);
        expect(find.byKey(const ValueKey('map-node-asleep-marker-story.x')), findsNothing);
      },
    );

    testWidgets(
      'POSITIVE: awake renders the gently-animated marker and no other state marker',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const MapNode(
              id: 'story.x',
              kind: MapNodeKind.story,
              visualState: MapNodeVisualState.awake,
            ),
          ),
        );
        expect(find.byKey(const ValueKey('map-node-awake-animation-story.x')), findsOneWidget);
        expect(find.byKey(const ValueKey('map-node-thumbnail-story.x')), findsNothing);
        expect(find.byKey(const ValueKey('map-node-asleep-marker-story.x')), findsNothing);
      },
    );

    testWidgets(
      'POSITIVE: asleep renders the asleep marker and no other state marker',
      (tester) async {
        await tester.pumpWidget(
          _wrap(
            const MapNode(
              id: 'story.x',
              kind: MapNodeKind.story,
              visualState: MapNodeVisualState.asleep,
            ),
          ),
        );
        expect(find.byKey(const ValueKey('map-node-asleep-marker-story.x')), findsOneWidget);
        expect(find.byKey(const ValueKey('map-node-thumbnail-story.x')), findsNothing);
        expect(find.byKey(const ValueKey('map-node-awake-animation-story.x')), findsNothing);
      },
    );

    testWidgets('POSITIVE: highlighted renders the highlight marker', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MapNode(
            id: 'story.x',
            kind: MapNodeKind.story,
            visualState: MapNodeVisualState.awake,
            highlighted: true,
          ),
        ),
      );
      expect(find.byKey(const ValueKey('map-node-highlight-story.x')), findsOneWidget);
    });

    testWidgets('NEGATIVE: non-highlighted renders no highlight marker', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const MapNode(
            id: 'story.x',
            kind: MapNodeKind.story,
            visualState: MapNodeVisualState.awake,
          ),
        ),
      );
      expect(find.byKey(const ValueKey('map-node-highlight-story.x')), findsNothing);
    });
  });

  group('ProgressMapScreen — two fixture profiles, independent StoryProgress', () {
    const stories = <StoryRef>[
      StoryRef(id: 'story.1', levelId: 'level.1'),
      StoryRef(id: 'story.2', levelId: 'level.1'),
      StoryRef(id: 'story.3', levelId: 'level.1'),
    ];

    Widget buildFor(String profileId, Map<String, StoryStatus> statusById) {
      return MaterialApp(
        home: ProgressMapScreen(
          profile: Profile(
            localId: profileId,
            displayName: profileId,
            ageBand: AgeBand.sevenToEight,
            currentLevelId: 'level.1',
            micConsent: true,
            cloudAsrConsent: false,
            createdAt: DateTime(2026, 1, 1),
          ),
          stories: stories,
          storyProgress: {
            for (final entry in statusById.entries)
              entry.key: StoryProgress(
                profileId: profileId,
                storyId: entry.key,
                status: entry.value,
                timesRead: entry.value == StoryStatus.completed ? 1 : 0,
              ),
          },
          twisters: const [],
          unlockedTwisterLevelIds: const {},
          onStartStory: (_) {},
          onReReadStory: (_) {},
          onOpenTwister: (_) {},
        ),
      );
    }

    testWidgets(
      'POSITIVE: profile A (story.1 completed, story.2/3 available) renders '
      'exactly that mix',
      (tester) async {
        await tester.pumpWidget(
          buildFor('profile.A', {
            'story.1': StoryStatus.completed,
            'story.2': StoryStatus.available,
            'story.3': StoryStatus.available,
          }),
        );
        expect(
          tester.widget<MapNode>(find.byKey(const ValueKey('map-node-story-story.1'))).visualState,
          MapNodeVisualState.completed,
        );
        expect(
          tester.widget<MapNode>(find.byKey(const ValueKey('map-node-story-story.2'))).visualState,
          MapNodeVisualState.awake,
        );
      },
    );

    testWidgets(
      'POSITIVE: profile B (nothing touched yet) renders every story asleep, '
      'independent of profile A\'s fixture above',
      (tester) async {
        await tester.pumpWidget(buildFor('profile.B', const {}));
        for (final story in stories) {
          expect(
            tester.widget<MapNode>(find.byKey(ValueKey('map-node-story-${story.id}'))).visualState,
            MapNodeVisualState.asleep,
            reason: '${story.id} must be asleep for profile.B',
          );
        }
      },
    );
  });
}

// Test suite for lib/features/map/progress_map_screen.dart (PRD §8 Unit 9
// "Progress map"; ticket progress-map-collection accept entries 1, 2, 9).
//
// lib/features/map/progress_map_screen.dart (and its sibling
// lib/features/map/map_node.dart) do not exist yet: this file fails to
// compile/analyze until they are created, which is the expected red state.
//
// Pinned API surface this suite transcribes against (see also
// map_states_test.dart and twister_nodes_test.dart, which pin map_node.dart
// and trail_layout.dart in more depth):
//
//   class ProgressMapScreen extends StatelessWidget {
//     const ProgressMapScreen({
//       super.key,
//       required Profile profile,
//       required List<StoryRef> stories,              // full authored trail,
//                                                       // global authored order
//       required Map<String, StoryProgress> storyProgress, // keyed by storyId;
//                                                       // a story absent from
//                                                       // this map is treated
//                                                       // identically to an
//                                                       // explicit `locked` row
//       required List<TongueTwister> twisters,
//       required Set<String> unlockedTwisterLevelIds,
//       required void Function(String storyId) onStartStory,
//       required void Function(String storyId) onReReadStory,
//       required void Function(String twisterId) onOpenTwister,
//       String? highlightedStoryId,
//     });
//   }
//
// Per-story visual state derivation (accept entry 1, "Map reflects
// StoryProgress exactly"): a story's MapNode.visualState is derived SOLELY
// from `storyProgress[story.id]?.status` (asleep when absent or `locked`,
// awake when `available`, completed when `completed`) -- this screen never
// recomputes the rolling window itself (phonics-engine's storiesFor already
// decided `status`; ticket notes: "do not reimplement the rolling window
// here").
//
// Node identity keys (pinned, also used by map_states_test.dart /
// twister_nodes_test.dart):
//   - story node:   ValueKey('map-node-story-<storyId>')
//   - twister node: ValueKey('map-node-twister-<twisterId>')
//
// Tap routing (accept entry 2): a story MapNode's onTap is wired to
// `onReReadStory(id)` when completed, `onStartStory(id)` when awake, and is
// non-functional when asleep (MapNode itself gates this per
// map_states_test.dart's pinned contract, independent of what the screen
// passes as onTap).
//
// Highlight (accept entry 9, Unit 8 "returns to the map with the next story
// highlighted" / validator fix): exactly the story MapNode whose id equals
// `highlightedStoryId` renders with `highlighted: true`; every other node
// (including all twister nodes) is not highlighted. `highlightedStoryId ==
// null`, or referencing an id absent from `stories`, highlights nothing.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/domain/phonics/scope_sequence_loader.dart';
import 'package:learn_to_read/features/map/map_node.dart';
import 'package:learn_to_read/features/map/progress_map_screen.dart';

/// Fixture Profile builder (see also map_states_test.dart / twister_nodes_test.dart
/// / layout_classes_test.dart, which build their own local fixtures the same way).
Profile _fixtureProfile({String localId = 'profile.amara'}) => Profile(
      localId: localId,
      displayName: 'Amara',
      ageBand: AgeBand.fiveToSix,
      currentLevelId: 'level.1',
      micConsent: true,
      cloudAsrConsent: false,
      createdAt: DateTime(2026, 1, 1),
    );

const _stories = <StoryRef>[
  StoryRef(id: 'story.1', levelId: 'level.1'),
  StoryRef(id: 'story.2', levelId: 'level.1'),
  StoryRef(id: 'story.3', levelId: 'level.1'),
  StoryRef(id: 'story.4', levelId: 'level.1'),
  StoryRef(id: 'story.5', levelId: 'level.2'),
];

/// Fixture progress: story.1 completed, story.2/3/4 available (the rolling
/// window of 3), story.5 has no row at all (asleep/untouched).
Map<String, StoryProgress> _fixtureProgress({String profileId = 'profile.amara'}) => {
      'story.1': StoryProgress(
        profileId: profileId,
        storyId: 'story.1',
        status: StoryStatus.completed,
        completedAt: DateTime(2026, 1, 2),
        timesRead: 1,
      ),
      'story.2': StoryProgress(
        profileId: profileId,
        storyId: 'story.2',
        status: StoryStatus.available,
        timesRead: 0,
      ),
      'story.3': StoryProgress(
        profileId: profileId,
        storyId: 'story.3',
        status: StoryStatus.available,
        timesRead: 0,
      ),
      'story.4': StoryProgress(
        profileId: profileId,
        storyId: 'story.4',
        status: StoryStatus.available,
        timesRead: 0,
      ),
      // story.5 intentionally absent: no row yet == asleep.
    };

Widget _buildScreen({
  Profile? profile,
  List<StoryRef>? stories,
  Map<String, StoryProgress>? storyProgress,
  List<TongueTwister> twisters = const [],
  Set<String> unlockedTwisterLevelIds = const {},
  void Function(String storyId)? onStartStory,
  void Function(String storyId)? onReReadStory,
  void Function(String twisterId)? onOpenTwister,
  String? highlightedStoryId,
}) {
  return MaterialApp(
    home: ProgressMapScreen(
      profile: profile ?? _fixtureProfile(),
      stories: stories ?? _stories,
      storyProgress: storyProgress ?? _fixtureProgress(),
      twisters: twisters,
      unlockedTwisterLevelIds: unlockedTwisterLevelIds,
      onStartStory: onStartStory ?? (_) {},
      onReReadStory: onReReadStory ?? (_) {},
      onOpenTwister: onOpenTwister ?? (_) {},
      highlightedStoryId: highlightedStoryId,
    ),
  );
}

MapNode _node(WidgetTester tester, String storyId) =>
    tester.widget<MapNode>(find.byKey(ValueKey('map-node-story-$storyId')));

void main() {
  group('ProgressMapScreen — reflects StoryProgress exactly (accept 1)', () {
    testWidgets(
      'POSITIVE: completed story renders MapNode.visualState == completed',
      (tester) async {
        await tester.pumpWidget(_buildScreen());
        expect(_node(tester, 'story.1').visualState, MapNodeVisualState.completed);
      },
    );

    testWidgets(
      'POSITIVE: the rolling window (status == available) stories render '
      'MapNode.visualState == awake',
      (tester) async {
        await tester.pumpWidget(_buildScreen());
        expect(_node(tester, 'story.2').visualState, MapNodeVisualState.awake);
        expect(_node(tester, 'story.3').visualState, MapNodeVisualState.awake);
        expect(_node(tester, 'story.4').visualState, MapNodeVisualState.awake);
      },
    );

    testWidgets(
      'POSITIVE: exactly 3 nodes are awake, matching the rolling-window-of-3 '
      'size (not the count of rendered nodes overall)',
      (tester) async {
        await tester.pumpWidget(_buildScreen());
        final awake = tester
            .widgetList<MapNode>(find.byType(MapNode))
            .where((n) => n.visualState == MapNodeVisualState.awake);
        expect(awake.length, 3);
      },
    );

    testWidgets(
      'POSITIVE: a future story with no StoryProgress row renders '
      'MapNode.visualState == asleep (visible but not yet reached)',
      (tester) async {
        await tester.pumpWidget(_buildScreen());
        expect(_node(tester, 'story.5').visualState, MapNodeVisualState.asleep);
        // Still present in the tree ("visible but visually asleep").
        expect(find.byKey(const ValueKey('map-node-story-story.5')), findsOneWidget);
      },
    );

    testWidgets(
      'EDGE: an explicit StoryStatus.locked row is treated identically to a '
      'missing row (asleep)',
      (tester) async {
        final progress = {
          ..._fixtureProgress(),
          'story.5': const StoryProgress(
            profileId: 'profile.amara',
            storyId: 'story.5',
            status: StoryStatus.locked,
            timesRead: 0,
          ),
        };
        await tester.pumpWidget(_buildScreen(storyProgress: progress));
        expect(_node(tester, 'story.5').visualState, MapNodeVisualState.asleep);
      },
    );

    testWidgets(
      'NEGATIVE: every authored story renders exactly one node -- the trail '
      'never drops or duplicates a story',
      (tester) async {
        await tester.pumpWidget(_buildScreen());
        for (final story in _stories) {
          expect(find.byKey(ValueKey('map-node-story-${story.id}')), findsOneWidget);
        }
      },
    );
  });

  group('ProgressMapScreen — tap routing (accept 2)', () {
    testWidgets(
      'POSITIVE: tapping a completed story fires onReReadStory with its id',
      (tester) async {
        String? reRead;
        await tester.pumpWidget(_buildScreen(onReReadStory: (id) => reRead = id));
        await tester.tap(find.byKey(const ValueKey('map-node-story-story.1')));
        await tester.pump();
        expect(reRead, 'story.1');
      },
    );

    testWidgets(
      'POSITIVE: tapping an awake story fires onStartStory with its id',
      (tester) async {
        String? started;
        await tester.pumpWidget(_buildScreen(onStartStory: (id) => started = id));
        await tester.tap(find.byKey(const ValueKey('map-node-story-story.3')));
        await tester.pump();
        expect(started, 'story.3');
      },
    );

    testWidgets(
      'NEGATIVE: tapping an asleep story fires neither callback',
      (tester) async {
        String? started;
        String? reRead;
        await tester.pumpWidget(
          _buildScreen(
            onStartStory: (id) => started = id,
            onReReadStory: (id) => reRead = id,
          ),
        );
        await tester.tap(find.byKey(const ValueKey('map-node-story-story.5')));
        await tester.pump();
        expect(started, isNull);
        expect(reRead, isNull);
      },
    );

    testWidgets(
      'NEGATIVE: tapping a completed story never fires onStartStory',
      (tester) async {
        String? started;
        await tester.pumpWidget(_buildScreen(onStartStory: (id) => started = id));
        await tester.tap(find.byKey(const ValueKey('map-node-story-story.1')));
        await tester.pump();
        expect(started, isNull);
      },
    );

    testWidgets(
      'NEGATIVE: tapping an awake story never fires onReReadStory',
      (tester) async {
        String? reRead;
        await tester.pumpWidget(_buildScreen(onReReadStory: (id) => reRead = id));
        await tester.tap(find.byKey(const ValueKey('map-node-story-story.2')));
        await tester.pump();
        expect(reRead, isNull);
      },
    );
  });

  group('ProgressMapScreen — return-navigation highlight (accept 9)', () {
    testWidgets(
      'POSITIVE: the story id from the return-navigation payload renders '
      'highlighted, and only that story',
      (tester) async {
        await tester.pumpWidget(_buildScreen(highlightedStoryId: 'story.3'));
        expect(_node(tester, 'story.3').highlighted, isTrue);
        for (final id in ['story.1', 'story.2', 'story.4', 'story.5']) {
          expect(_node(tester, id).highlighted, isFalse, reason: '$id must not be highlighted');
        }
      },
    );

    testWidgets(
      'EDGE: highlightedStoryId == null highlights no node',
      (tester) async {
        await tester.pumpWidget(_buildScreen(highlightedStoryId: null));
        for (final story in _stories) {
          expect(_node(tester, story.id).highlighted, isFalse);
        }
      },
    );

    testWidgets(
      'EDGE: highlightedStoryId referencing an id absent from stories '
      'highlights nothing and does not crash',
      (tester) async {
        await tester.pumpWidget(_buildScreen(highlightedStoryId: 'story.does-not-exist'));
        expect(tester.takeException(), isNull);
        for (final story in _stories) {
          expect(_node(tester, story.id).highlighted, isFalse);
        }
      },
    );
  });

  group('ProgressMapScreen — driven by the in-memory DB (fixture + Drift)', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets(
      'POSITIVE: StoryProgress rows written via StoryProgressDao and read '
      'back drive the exact same node states as the in-memory fixture',
      (tester) async {
        for (final entry in _fixtureProgress().values) {
          await db.storyProgressDao.upsertProgress(entry);
        }
        final rows = await db.storyProgressDao.allForProfile('profile.amara');
        final progressById = {for (final r in rows) r.storyId: r};

        await tester.pumpWidget(_buildScreen(storyProgress: progressById));

        expect(_node(tester, 'story.1').visualState, MapNodeVisualState.completed);
        expect(_node(tester, 'story.2').visualState, MapNodeVisualState.awake);
        expect(_node(tester, 'story.5').visualState, MapNodeVisualState.asleep);
      },
    );
  });
}

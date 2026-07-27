// Test suite for lib/features/map/trail_layout.dart's booster-node
// interleaving (PRD §8 Unit 9 + Unit 14, "Tongue-twister booster nodes
// interleave the trail with a distinct visual treatment") and
// lib/features/map/progress_map_screen.dart's rendering/tap-routing of
// those nodes (ticket progress-map-collection accept entry 3).
//
// lib/features/map/trail_layout.dart, lib/features/map/map_node.dart and
// lib/features/map/progress_map_screen.dart do not exist yet: this file
// fails to compile/analyze until they are created, which is the expected
// red state.
//
// Pinned API surface (trail_layout.dart):
//
//   enum TrailEntryKind { story, twisterBooster }
//
//   class TrailEntry {
//     const TrailEntry.story(StoryRef storyRef);
//     const TrailEntry.twister(TongueTwister twister);
//     TrailEntryKind get kind;
//     StoryRef? get storyRef;   // non-null iff kind == story
//     TongueTwister? get twister; // non-null iff kind == twisterBooster
//   }
//
//   List<TrailEntry> buildTrail({
//     required List<StoryRef> stories,
//     required List<TongueTwister> twisters,
//   });
//
// Interleave rule (pinned by this ticket -- PRD only pins a density
// guideline, "~1 per 3 stories", not an exact placement algorithm): each
// twister is inserted immediately after the LAST story entry sharing its
// `levelId` (scanning `stories` in authored order); a twister whose
// `levelId` matches no story in `stories` is appended at the trail's end.
// Twisters sharing a levelId with each other preserve their relative
// `twisters` input order, all placed immediately after that level's last
// story.
//
// ProgressMapScreen renders one MapNode(kind: MapNodeKind.twisterBooster)
// per twister, keyed ValueKey('map-node-twister-<twisterId>'), positioned
// per buildTrail's order. A twister's node is awake (tappable, fires
// onOpenTwister(id)) iff its levelId is in `unlockedTwisterLevelIds`;
// otherwise it is asleep (non-tappable), matching "unlocked with [its]
// level" and MapNode's asleep tap-gating pinned in map_states_test.dart.
// Twisters are "always replayable" once unlocked -- there is no `completed`
// state for a twister node.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/domain/phonics/scope_sequence_loader.dart';
import 'package:learn_to_read/features/map/map_node.dart';
import 'package:learn_to_read/features/map/progress_map_screen.dart';
import 'package:learn_to_read/features/map/trail_layout.dart';

TongueTwister _twister({required String id, required String levelId}) => TongueTwister(
      id: id,
      levelId: levelId,
      words: const [],
      targetPhonemeId: 'SH',
      narrationAudioRef: 'audio/twisters/$id.mp3',
      packId: 'pack.starter',
    );

const _stories = <StoryRef>[
  StoryRef(id: 'story.1', levelId: 'level.1'),
  StoryRef(id: 'story.2', levelId: 'level.1'),
  StoryRef(id: 'story.3', levelId: 'level.2'),
  StoryRef(id: 'story.4', levelId: 'level.2'),
  StoryRef(id: 'story.5', levelId: 'level.3'),
];

void main() {
  group('buildTrail — booster interleave rule (accept 3)', () {
    test(
      'POSITIVE: a twister is inserted immediately after the last story of '
      'its level',
      () {
        final twisterA = _twister(id: 'twister.a', levelId: 'level.1');
        final twisterB = _twister(id: 'twister.b', levelId: 'level.2');

        final trail = buildTrail(stories: _stories, twisters: [twisterA, twisterB]);
        final ids = trail
            .map((e) => e.kind == TrailEntryKind.story ? e.storyRef!.id : e.twister!.id)
            .toList();

        expect(ids, [
          'story.1',
          'story.2',
          'twister.a',
          'story.3',
          'story.4',
          'twister.b',
          'story.5',
        ]);
      },
    );

    test(
      'POSITIVE: every entry carries its expected kind and non-null payload',
      () {
        final twisterA = _twister(id: 'twister.a', levelId: 'level.1');
        final trail = buildTrail(stories: _stories, twisters: [twisterA]);

        for (final entry in trail) {
          if (entry.kind == TrailEntryKind.story) {
            expect(entry.storyRef, isNotNull);
            expect(entry.twister, isNull);
          } else {
            expect(entry.twister, isNotNull);
            expect(entry.storyRef, isNull);
          }
        }
      },
    );

    test(
      'EDGE: a twister whose levelId matches no story is appended at the '
      'trail\'s end, not dropped',
      () {
        final orphan = _twister(id: 'twister.orphan', levelId: 'level.99');
        final trail = buildTrail(stories: _stories, twisters: [orphan]);

        expect(trail.last.kind, TrailEntryKind.twisterBooster);
        expect(trail.last.twister!.id, 'twister.orphan');
        expect(trail.length, _stories.length + 1);
      },
    );

    test(
      'POSITIVE: two twisters sharing a level preserve their relative input '
      'order, both placed after that level\'s last story',
      () {
        final a1 = _twister(id: 'twister.a1', levelId: 'level.1');
        final a2 = _twister(id: 'twister.a2', levelId: 'level.1');
        final trail = buildTrail(stories: _stories, twisters: [a1, a2]);
        final ids = trail
            .map((e) => e.kind == TrailEntryKind.story ? e.storyRef!.id : e.twister!.id)
            .toList();

        expect(ids, [
          'story.1',
          'story.2',
          'twister.a1',
          'twister.a2',
          'story.3',
          'story.4',
          'story.5',
        ]);
      },
    );

    test('EDGE: no twisters produces a trail identical to the story list', () {
      final trail = buildTrail(stories: _stories, twisters: const []);
      expect(trail.length, _stories.length);
      expect(trail.every((e) => e.kind == TrailEntryKind.story), isTrue);
    });

    test('EDGE: no stories places every twister at the (empty) trail end', () {
      final onlyTwister = _twister(id: 'twister.solo', levelId: 'level.1');
      final trail = buildTrail(stories: const [], twisters: [onlyTwister]);
      expect(trail, hasLength(1));
      expect(trail.single.twister!.id, 'twister.solo');
    });
  });

  group('ProgressMapScreen — booster nodes render distinct + tap-navigable', () {
    Widget buildScreen({
      List<TongueTwister> twisters = const [],
      Set<String> unlockedTwisterLevelIds = const {},
      void Function(String twisterId)? onOpenTwister,
    }) {
      return MaterialApp(
        home: ProgressMapScreen(
          profile: Profile(
            localId: 'profile.amara',
            displayName: 'Amara',
            ageBand: AgeBand.fiveToSix,
            currentLevelId: 'level.1',
            micConsent: true,
            cloudAsrConsent: false,
            createdAt: DateTime(2026, 1, 1),
          ),
          stories: _stories,
          storyProgress: const {},
          twisters: twisters,
          unlockedTwisterLevelIds: unlockedTwisterLevelIds,
          onStartStory: (_) {},
          onReReadStory: (_) {},
          onOpenTwister: onOpenTwister ?? (_) {},
        ),
      );
    }

    testWidgets(
      'POSITIVE: a twister node renders MapNodeKind.twisterBooster and its '
      'distinct-treatment badge marker, unlike story nodes',
      (tester) async {
        final twisterA = _twister(id: 'twister.a', levelId: 'level.1');
        await tester.pumpWidget(buildScreen(twisters: [twisterA]));

        final node = tester.widget<MapNode>(find.byKey(const ValueKey('map-node-twister-twister.a')));
        expect(node.kind, MapNodeKind.twisterBooster);
        expect(find.byKey(const ValueKey('map-node-twister-badge-twister.a')), findsOneWidget);

        final storyNode = tester.widget<MapNode>(find.byKey(const ValueKey('map-node-story-story.1')));
        expect(storyNode.kind, MapNodeKind.story);
        expect(find.byKey(const ValueKey('map-node-twister-badge-story.1')), findsNothing);
      },
    );

    testWidgets(
      'POSITIVE: booster nodes render at their level position -- immediately '
      'after that level\'s last story, in overall trail render order',
      (tester) async {
        final twisterB = _twister(id: 'twister.b', levelId: 'level.2');
        await tester.pumpWidget(buildScreen(twisters: [twisterB]));

        final order = tester
            .widgetList<MapNode>(find.byType(MapNode))
            .map((n) => n.id)
            .toList();
        expect(order.indexOf('twister.b'), order.indexOf('story.4') + 1);
        expect(order.indexOf('twister.b'), lessThan(order.indexOf('story.5')));
      },
    );

    testWidgets(
      'POSITIVE: an unlocked (level-reached) twister node is tap-navigable, '
      'firing onOpenTwister with its id',
      (tester) async {
        String? opened;
        final twisterA = _twister(id: 'twister.a', levelId: 'level.1');
        await tester.pumpWidget(
          buildScreen(
            twisters: [twisterA],
            unlockedTwisterLevelIds: const {'level.1'},
            onOpenTwister: (id) => opened = id,
          ),
        );

        await tester.tap(find.byKey(const ValueKey('map-node-twister-twister.a')));
        await tester.pump();
        expect(opened, 'twister.a');
      },
    );

    testWidgets(
      'NEGATIVE: a locked (level not yet reached) twister node is asleep '
      'and non-tappable',
      (tester) async {
        String? opened;
        final twisterC = _twister(id: 'twister.c', levelId: 'level.3');
        await tester.pumpWidget(
          buildScreen(
            twisters: [twisterC],
            unlockedTwisterLevelIds: const {'level.1'},
            onOpenTwister: (id) => opened = id,
          ),
        );

        final node = tester.widget<MapNode>(find.byKey(const ValueKey('map-node-twister-twister.c')));
        expect(node.visualState, MapNodeVisualState.asleep);

        await tester.tap(find.byKey(const ValueKey('map-node-twister-twister.c')));
        await tester.pump();
        expect(opened, isNull);
      },
    );

    testWidgets(
      'POSITIVE: an unlocked twister remains tap-navigable regardless of how '
      'many times it has already been completed -- always replayable, no '
      '"completed"/thumbnail state exists for a twister node',
      (tester) async {
        var openCount = 0;
        final twisterA = _twister(id: 'twister.a', levelId: 'level.1');
        await tester.pumpWidget(
          buildScreen(
            twisters: [twisterA],
            unlockedTwisterLevelIds: const {'level.1'},
            onOpenTwister: (_) => openCount++,
          ),
        );

        await tester.tap(find.byKey(const ValueKey('map-node-twister-twister.a')));
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('map-node-twister-twister.a')));
        await tester.pump();

        expect(openCount, 2);
        expect(find.byKey(const ValueKey('map-node-thumbnail-twister.a')), findsNothing);
      },
    );
  });

  group('[DEVICE] pixel golden — not testable headlessly, skipped with reason', () {
    test(
      'booster node golden shows a distinct visual treatment from a story node',
      () {},
      skip: '[DEVICE] ticket accept 3: real trail illustrations (including the '
          'booster-node style) are owner-commissioned (PRD §10 OQ-4); this '
          'container only has token-styled placeholder painting, so a pixel '
          'golden here would pin placeholder art, not the shipped distinct '
          'treatment. The headless proxy above ("booster nodes present at '
          'their level positions with the booster node type/style token": '
          'MapNodeKind.twisterBooster + the map-node-twister-badge-<id> '
          'marker, both asserted distinct from story nodes) is the '
          'compile-time stand-in pinned by this suite.',
    );
  });
}

// Integration test: profile switch swaps ProgressMapScreen + CollectionScreen
// state completely, with zero cross-profile leakage (PRD §8 Unit 9 "Both
// screens are per-profile. No global/comparative elements"; ticket
// progress-map-collection accept entry "Profile switch swaps map +
// collection state completely (integration test with two fixture profiles)").
//
// Exercises the real in-memory Drift DB (local-storage's StoryProgressDao /
// CollectionDao) end-to-end into both screens, standing in for the
// provider-level wiring app-shell owns later: this test loads each
// profile's rows directly from the DAOs and feeds them into the screens,
// the same shape of data flow app-shell's providers will perform.
//
// lib/features/map/progress_map_screen.dart and
// lib/features/collection/collection_screen.dart do not exist yet: this
// file fails to compile/analyze until they (and their siblings map_node.dart,
// trail_layout.dart, scene_slots.dart) are created, which is the expected
// red state.
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/design/fake_rive_stage.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/domain/phonics/scope_sequence_loader.dart';
import 'package:learn_to_read/features/collection/collection_screen.dart';
import 'package:learn_to_read/features/map/map_node.dart';
import 'package:learn_to_read/features/map/progress_map_screen.dart';

const _profileA = 'profile.A';
const _profileB = 'profile.B';

const _stories = <StoryRef>[
  StoryRef(id: 'story.1', levelId: 'level.1'),
  StoryRef(id: 'story.2', levelId: 'level.1'),
  StoryRef(id: 'story.3', levelId: 'level.1'),
];

final _catalog = <Collectible>[
  Collectible(id: 'collectible.cat', storyId: 'story.1', riveRef: 'rive/cat.riv', sceneSlot: '0:0'),
  Collectible(id: 'collectible.owl', storyId: 'story.2', riveRef: 'rive/owl.riv', sceneSlot: '0:1'),
];

Profile _profile(String localId) => Profile(
      localId: localId,
      displayName: localId,
      ageBand: AgeBand.sevenToEight,
      currentLevelId: 'level.1',
      micConsent: true,
      cloudAsrConsent: false,
      createdAt: DateTime(2026, 1, 1),
    );

Widget _mapScreenFor(String profileId, Map<String, StoryProgress> progress) => MaterialApp(
      home: ProgressMapScreen(
        profile: _profile(profileId),
        stories: _stories,
        storyProgress: progress,
        twisters: const [],
        unlockedTwisterLevelIds: const {},
        onStartStory: (_) {},
        onReReadStory: (_) {},
        onOpenTwister: (_) {},
      ),
    );

Widget _collectionScreenFor(String profileId, CollectionState state) => MaterialApp(
      home: CollectionScreen(
        profile: _profile(profileId),
        collectibles: _catalog,
        collectionState: state,
        stageFor: (_) => FakeStoryStage(),
      ),
    );

void main() {
  group('Profile switch — StoryProgress isolation via the real in-memory DB', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      // Profile A: story.1 completed, story.2 available, story.3 untouched.
      await db.storyProgressDao.upsertProgress(
        const StoryProgress(
          profileId: _profileA,
          storyId: 'story.1',
          status: StoryStatus.completed,
          timesRead: 1,
        ),
      );
      await db.storyProgressDao.upsertProgress(
        const StoryProgress(
          profileId: _profileA,
          storyId: 'story.2',
          status: StoryStatus.available,
          timesRead: 0,
        ),
      );
      // Profile B: nothing completed; story.3 (not story.1!) is B's window story.
      await db.storyProgressDao.upsertProgress(
        const StoryProgress(
          profileId: _profileB,
          storyId: 'story.3',
          status: StoryStatus.available,
          timesRead: 0,
        ),
      );

      await db.collectionDao.grantCollectible(profileId: _profileA, collectibleId: 'collectible.cat');
      await db.collectionDao.grantCollectible(profileId: _profileB, collectibleId: 'collectible.owl');
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets(
      'POSITIVE: profile A\'s map shows A\'s own StoryProgress (story.1 '
      'completed, story.2 awake, story.3 asleep)',
      (tester) async {
        final rows = await db.storyProgressDao.allForProfile(_profileA);
        final progress = {for (final r in rows) r.storyId: r};

        await tester.pumpWidget(_mapScreenFor(_profileA, progress));

        expect(
          tester.widget<MapNode>(find.byKey(const ValueKey('map-node-story-story.1'))).visualState,
          MapNodeVisualState.completed,
        );
        expect(
          tester.widget<MapNode>(find.byKey(const ValueKey('map-node-story-story.2'))).visualState,
          MapNodeVisualState.awake,
        );
        expect(
          tester.widget<MapNode>(find.byKey(const ValueKey('map-node-story-story.3'))).visualState,
          MapNodeVisualState.asleep,
        );
      },
    );

    testWidgets(
      'NEGATIVE: switching to profile B\'s map does NOT retain profile A\'s '
      'completion of story.1 -- story.1 renders asleep for B, and B\'s own '
      'window story (story.3) is awake instead',
      (tester) async {
        // First render A (as the child would have been looking at before the
        // switch), then swap the whole tree to B -- simulating the app-shell
        // navigation that happens on profile switch.
        final aRows = await db.storyProgressDao.allForProfile(_profileA);
        await tester.pumpWidget(_mapScreenFor(_profileA, {for (final r in aRows) r.storyId: r}));
        expect(
          tester.widget<MapNode>(find.byKey(const ValueKey('map-node-story-story.1'))).visualState,
          MapNodeVisualState.completed,
        );

        final bRows = await db.storyProgressDao.allForProfile(_profileB);
        await tester.pumpWidget(_mapScreenFor(_profileB, {for (final r in bRows) r.storyId: r}));

        expect(
          tester.widget<MapNode>(find.byKey(const ValueKey('map-node-story-story.1'))).visualState,
          MapNodeVisualState.asleep,
          reason: 'profile A\'s completion of story.1 must not leak into profile B\'s map',
        );
        expect(
          tester.widget<MapNode>(find.byKey(const ValueKey('map-node-story-story.3'))).visualState,
          MapNodeVisualState.awake,
        );
      },
    );
  });

  group('Profile switch — CollectionState isolation via the real in-memory DB', () {
    late AppDatabase db;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      await db.collectionDao.grantCollectible(profileId: _profileA, collectibleId: 'collectible.cat');
      await db.collectionDao.grantCollectible(profileId: _profileB, collectibleId: 'collectible.owl');
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets(
      'POSITIVE: profile A\'s collection shows only collectible.cat, never '
      'collectible.owl (B\'s earn)',
      (tester) async {
        final state = await db.collectionDao.getCollectionState(_profileA);
        await tester.pumpWidget(_collectionScreenFor(_profileA, state));

        expect(find.byKey(const ValueKey('collectible-node-collectible.cat')), findsOneWidget);
        expect(find.byKey(const ValueKey('collectible-node-collectible.owl')), findsNothing);
      },
    );

    testWidgets(
      'NEGATIVE: switching the collection screen to profile B removes A\'s '
      'collectible.cat entirely and shows only B\'s collectible.owl -- no '
      'residual node from A\'s tree survives the swap',
      (tester) async {
        final aState = await db.collectionDao.getCollectionState(_profileA);
        await tester.pumpWidget(_collectionScreenFor(_profileA, aState));
        expect(find.byKey(const ValueKey('collectible-node-collectible.cat')), findsOneWidget);

        final bState = await db.collectionDao.getCollectionState(_profileB);
        await tester.pumpWidget(_collectionScreenFor(_profileB, bState));

        expect(
          find.byKey(const ValueKey('collectible-node-collectible.cat')),
          findsNothing,
          reason: 'profile A\'s earned collectible must not leak into profile B\'s collection',
        );
        expect(find.byKey(const ValueKey('collectible-node-collectible.owl')), findsOneWidget);
      },
    );
  });

  group('Profile isolation — the screens carry no comparative/global elements', () {
    testWidgets(
      'NEGATIVE: neither screen accepts or renders a second profile\'s data '
      'in the same instance -- each screen is constructed for exactly one '
      '`profile` (structural: the widget API has no multi-profile input, so '
      'no leaderboard/comparison surface exists to render)',
      (tester) async {
        await tester.pumpWidget(
          _mapScreenFor(_profileA, const {
            'story.1': StoryProgress(
              profileId: _profileA,
              storyId: 'story.1',
              status: StoryStatus.completed,
              timesRead: 1,
            ),
          }),
        );
        final screen = tester.widget<ProgressMapScreen>(find.byType(ProgressMapScreen));
        expect(screen.profile.localId, _profileA);
        // No text anywhere in the tree names the other fixture profile.
        expect(find.textContaining(_profileB), findsNothing);
      },
    );
  });
}

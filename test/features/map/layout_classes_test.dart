// Headless layout-class coverage for lib/features/map/progress_map_screen.dart
// and lib/features/collection/collection_screen.dart (PRD §8 Unit 9 accept
// "Golden tests, four layout classes, for both screens"; ticket
// progress-map-collection accept entry 8: "All four layout classes render
// without overflow (headless layout tests; [DEVICE] goldens for both screens
// routed to owner)").
//
// None of lib/features/map/progress_map_screen.dart,
// lib/features/map/map_node.dart, lib/features/collection/collection_screen.dart,
// or lib/features/collection/scene_slots.dart exist yet: this file fails to
// compile/analyze until they are created, which is the expected red state.
//
// This suite is the headless proxy for the [DEVICE] golden acceptance: it
// pumps both screens at all four [LayoutClass] sizes with a representative
// fixture (including twister nodes and a beyond-launch collectible count)
// and asserts no overflow/render exception is thrown
// (`tester.takeException() == null`). The actual pixel-level goldens are a
// [DEVICE]/owner task, explicitly skip-marked below per the ticket's
// "skipped-with-reason" convention (see test/spike/spike_channel_test.dart
// and test/features/audio/phoneme_sequencer_test.dart for the established
// pattern in this repo).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/design/fake_rive_stage.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/domain/phonics/scope_sequence_loader.dart';
import 'package:learn_to_read/features/collection/collection_screen.dart';
import 'package:learn_to_read/features/map/progress_map_screen.dart';

/// Resizes the actual test viewport (not just an ambient MediaQuery) so the
/// screen lays out exactly as it would at a real device size of [size] --
/// mirrors test/design/layout_test.dart's `_pumpAt` helper (private there,
/// so redefined locally per-file, same behavior).
Future<void> _pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(child);
}

const _phonePortrait = Size(375, 812);
const _phoneLandscape = Size(812, 375);
const _tabletPortrait = Size(768, 1024);
const _tabletLandscape = Size(1024, 768);

const _layoutSizes = <String, Size>{
  'phonePortrait': _phonePortrait,
  'phoneLandscape': _phoneLandscape,
  'tabletPortrait': _tabletPortrait,
  'tabletLandscape': _tabletLandscape,
};

TongueTwister _twister(String id, String levelId) => TongueTwister(
      id: id,
      levelId: levelId,
      words: const [],
      targetPhonemeId: 'SH',
      narrationAudioRef: 'audio/twisters/$id.mp3',
      packId: 'pack.starter',
    );

Widget _buildProgressMap() {
  final stories = List.generate(
    8,
    (i) => StoryRef(id: 'story.$i', levelId: 'level.${i ~/ 3}'),
  );
  final progress = <String, StoryProgress>{
    for (var i = 0; i < 8; i++)
      'story.$i': StoryProgress(
        profileId: 'profile.amara',
        storyId: 'story.$i',
        status: i < 2
            ? StoryStatus.completed
            : (i < 5 ? StoryStatus.available : StoryStatus.locked),
        timesRead: i < 2 ? 1 : 0,
      ),
  };
  return MaterialApp(
    home: ProgressMapScreen(
      profile: Profile(
        localId: 'profile.amara',
        displayName: 'Amara',
        ageBand: AgeBand.fiveToSix,
        currentLevelId: 'level.0',
        micConsent: true,
        cloudAsrConsent: false,
        createdAt: DateTime(2026, 1, 1),
      ),
      stories: stories,
      storyProgress: progress,
      twisters: [_twister('twister.a', 'level.0'), _twister('twister.b', 'level.1')],
      unlockedTwisterLevelIds: const {'level.0', 'level.1'},
      onStartStory: (_) {},
      onReReadStory: (_) {},
      onOpenTwister: (_) {},
      highlightedStoryId: 'story.2',
    ),
  );
}

Widget _buildCollectionScreen({int collectibleCount = 6}) {
  final collectibles = List.generate(
    collectibleCount,
    (i) => Collectible(
      id: 'collectible.$i',
      storyId: 'story.$i',
      riveRef: 'rive/collectibles/$i.riv',
      sceneSlot: '${i ~/ 4}:${i % 4}',
    ),
  );
  final stages = <String, FakeStoryStage>{
    for (final c in collectibles) c.id: FakeStoryStage(),
  };
  return MaterialApp(
    home: CollectionScreen(
      profile: Profile(
        localId: 'profile.amara',
        displayName: 'Amara',
        ageBand: AgeBand.fiveToSix,
        currentLevelId: 'level.0',
        micConsent: true,
        cloudAsrConsent: false,
        createdAt: DateTime(2026, 1, 1),
      ),
      collectibles: collectibles,
      collectionState: CollectionState(
        profileId: 'profile.amara',
        earnedCollectibles: collectibles.map((c) => c.id).toList(),
      ),
      stageFor: (id) => stages[id]!,
    ),
  );
}

void main() {
  group('ProgressMapScreen — all four layout classes, no overflow', () {
    for (final entry in _layoutSizes.entries) {
      testWidgets('POSITIVE: ${entry.key} (${entry.value}) renders without overflow', (tester) async {
        await _pumpAt(tester, entry.value, _buildProgressMap());
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('CollectionScreen — all four layout classes, no overflow', () {
    for (final entry in _layoutSizes.entries) {
      testWidgets('POSITIVE: ${entry.key} (${entry.value}) renders without overflow', (tester) async {
        await _pumpAt(tester, entry.value, _buildCollectionScreen());
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('CollectionScreen — beyond-launch collectible count, four layout classes', () {
    for (final entry in _layoutSizes.entries) {
      testWidgets(
        'EDGE: ${entry.key} with 40 collectibles (well beyond the ~launch '
        'catalog) still renders without overflow, by extending the scene',
        (tester) async {
          await _pumpAt(tester, entry.value, _buildCollectionScreen(collectibleCount: 40));
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  group('[DEVICE] pixel goldens — not testable headlessly, skipped with reason', () {
    for (final layoutClassName in _layoutSizes.keys) {
      test(
        'ProgressMapScreen golden at $layoutClassName matches the illustrated '
        'trail style guide',
        () {},
        skip: '[DEVICE] Real trail illustrations are owner-commissioned (PRD §10 '
            'OQ-4); this container has only token-styled placeholder painting, '
            'so a pixel golden here would pin placeholder art, not the shipped '
            'design. Routed to the owner once the illustrated trail assets and '
            'style-guide sign-off land. The headless proxy above (no-overflow '
            'assertion at this exact layout class) is the compile-time stand-in.',
      );
    }

    for (final layoutClassName in _layoutSizes.keys) {
      test(
        'CollectionScreen golden at $layoutClassName matches the illustrated '
        'scene style guide',
        () {},
        skip: '[DEVICE] Real collection-scene illustration (e.g. the garden) is '
            'owner-commissioned (PRD §10 OQ-4); this container has only '
            'token-styled placeholder painting. Routed to the owner once the '
            'illustrated scene assets and style-guide sign-off land. The '
            'headless proxy above (no-overflow assertion at this exact layout '
            'class) is the compile-time stand-in.',
      );
    }
  });
}

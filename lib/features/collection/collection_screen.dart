/// The collection scene: one persistent illustrated scene (e.g. a garden)
/// where every earned collectible lives at its authored `sceneSlot` (PRD
/// §8 Unit 9; ticket progress-map-collection accept entries 4, 5, 7).
///
/// This screen does its own earned/unearned filtering: callers supply the
/// full authored catalog plus this profile's [CollectionState], and only
/// collectibles named in `collectionState.earnedCollectibles` render at all.
/// Real scene/collectible illustrations are owner-commissioned (PRD §10
/// OQ-4); this screen paints token-styled placeholder shapes at each slot.
library;

import 'package:flutter/material.dart';
import 'package:learn_to_read/design/rive_stage.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/features/collection/scene_slots.dart';

/// One persistent illustrated scene, strictly per-profile (PRD §8 Unit 9:
/// "No global/comparative elements") -- there is no multi-profile input on
/// this widget's API.
class CollectionScreen extends StatelessWidget {
  const CollectionScreen({
    super.key,
    required this.profile,
    required this.collectibles,
    required this.collectionState,
    required this.stageFor,
  });

  /// The profile this collection belongs to.
  final Profile profile;

  /// The full authored collectible catalog. Filtered down to
  /// `collectionState.earnedCollectibles` by this screen -- callers do not
  /// pre-filter.
  final List<Collectible> collectibles;

  /// This profile's earned collectibles.
  final CollectionState collectionState;

  /// Resolves the [StoryStage] a given collectible's poke reaction (Rive
  /// collect/poke, `StoryStageInput.collect`) should fire on.
  final StoryStage Function(String collectibleId) stageFor;

  static const double _cellWidth = 88.0;
  static const double _cellHeight = 88.0;

  @override
  Widget build(BuildContext context) {
    final earnedIds = collectionState.earnedCollectibles.toSet();
    final earned = [
      for (final collectible in collectibles)
        if (earnedIds.contains(collectible.id)) collectible,
    ];
    final canvasSize = SceneSlotLayout.canvasSizeFor(
      earned.map((c) => c.sceneSlot),
      cellWidth: _cellWidth,
      cellHeight: _cellHeight,
    );

    return Scaffold(
      backgroundColor: DesignTokens.surfaceBackground,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.spacingLg,
                DesignTokens.spacingMd,
                DesignTokens.spacingLg,
                DesignTokens.spacingSm,
              ),
              child: Text(
                'My Garden',
                style: const TextStyle(
                  fontFamily: DesignTokens.displayFontFamily,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: DesignTokens.wordUnreadInk,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(DesignTokens.spacingLg),
                child: SizedBox(
                  width: canvasSize.width,
                  height: canvasSize.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (final collectible in earned) _buildCollectibleNode(collectible),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCollectibleNode(Collectible collectible) {
    final offset = SceneSlotLayout.offsetForSlot(
      collectible.sceneSlot,
      cellWidth: _cellWidth,
      cellHeight: _cellHeight,
    );
    return Positioned(
      left: offset.dx,
      top: offset.dy,
      width: _cellWidth,
      height: _cellHeight,
      child: GestureDetector(
        key: ValueKey('collectible-node-${collectible.id}'),
        onTap: () => stageFor(collectible.id).trigger(StoryStageInput.collect),
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spacingXs),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: DesignTokens.readingBackground,
              shape: BoxShape.circle,
              border: Border.all(color: DesignTokens.wordUnreadInk.withAlpha(60), width: 2),
            ),
            child: const Icon(Icons.pets, color: DesignTokens.wordUnreadInk),
          ),
        ),
      ),
    );
  }
}

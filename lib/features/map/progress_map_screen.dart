/// The child home screen: an illustrated trail of the reading level path
/// (PRD §8 Unit 9; ticket progress-map-collection accept entries 1, 2, 3, 9).
///
/// This screen never recomputes story availability itself -- the rolling
/// window is phonics-engine's decision (PRD §8 Unit 2), already baked into
/// each `StoryProgress.status` by the time it reaches [storyProgress]. A
/// story's [MapNode] visual state is derived *solely* from
/// `storyProgress[story.id]?.status`: absent or `locked` -> asleep,
/// `available` -> awake, `completed` -> completed.
library;

import 'package:flutter/material.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/domain/phonics/scope_sequence_loader.dart';
import 'package:learn_to_read/features/map/map_node.dart';
import 'package:learn_to_read/features/map/trail_layout.dart';

/// The progress map: this profile's illustrated trail of stories and
/// tongue-twister boosters.
///
/// Strictly per-profile (PRD §8 Unit 9: "No global/comparative elements") --
/// there is no multi-profile input on this widget's API, so no
/// leaderboard/comparison surface can exist to render.
class ProgressMapScreen extends StatelessWidget {
  const ProgressMapScreen({
    super.key,
    required this.profile,
    required this.stories,
    required this.storyProgress,
    required this.twisters,
    required this.unlockedTwisterLevelIds,
    required this.onStartStory,
    required this.onReReadStory,
    required this.onOpenTwister,
    this.highlightedStoryId,
  });

  /// The profile this map belongs to.
  final Profile profile;

  /// The full authored trail, in global authored order.
  final List<StoryRef> stories;

  /// This profile's progress, keyed by `storyId`. A story absent from this
  /// map is treated identically to an explicit `locked` row.
  final Map<String, StoryProgress> storyProgress;

  /// Tongue-twister boosters (Unit 14), interleaved into the trail via
  /// [buildTrail].
  final List<TongueTwister> twisters;

  /// Levels whose twister booster is unlocked (reached) for this profile.
  final Set<String> unlockedTwisterLevelIds;

  /// Fired with a story id when an awake story is tapped.
  final void Function(String storyId) onStartStory;

  /// Fired with a story id when a completed story is tapped (re-read).
  final void Function(String storyId) onReReadStory;

  /// Fired with a twister id when an unlocked booster node is tapped.
  final void Function(String twisterId) onOpenTwister;

  /// The story id to render highlighted (e.g. the "next story" payload
  /// returned from the celebration sequence, PRD §8 Unit 8). `null`, or an
  /// id absent from [stories], highlights nothing.
  final String? highlightedStoryId;

  MapNodeVisualState _storyVisualState(StoryRef story) {
    final status = storyProgress[story.id]?.status;
    switch (status) {
      case StoryStatus.completed:
        return MapNodeVisualState.completed;
      case StoryStatus.available:
        return MapNodeVisualState.awake;
      case StoryStatus.locked:
      case null:
        return MapNodeVisualState.asleep;
    }
  }

  Widget _buildStoryNode(StoryRef story) {
    final visualState = _storyVisualState(story);
    VoidCallback? onTap;
    switch (visualState) {
      case MapNodeVisualState.completed:
        onTap = () => onReReadStory(story.id);
      case MapNodeVisualState.awake:
        onTap = () => onStartStory(story.id);
      case MapNodeVisualState.asleep:
        onTap = null;
    }
    return MapNode(
      key: ValueKey('map-node-story-${story.id}'),
      id: story.id,
      kind: MapNodeKind.story,
      visualState: visualState,
      highlighted: story.id == highlightedStoryId,
      onTap: onTap,
    );
  }

  Widget _buildTwisterNode(TongueTwister twister) {
    final unlocked = unlockedTwisterLevelIds.contains(twister.levelId);
    return MapNode(
      key: ValueKey('map-node-twister-${twister.id}'),
      id: twister.id,
      kind: MapNodeKind.twisterBooster,
      visualState: unlocked ? MapNodeVisualState.awake : MapNodeVisualState.asleep,
      onTap: unlocked ? () => onOpenTwister(twister.id) : null,
    );
  }

  Widget _buildEntry(TrailEntry entry) {
    return switch (entry.kind) {
      TrailEntryKind.story => _buildStoryNode(entry.storyRef!),
      TrailEntryKind.twisterBooster => _buildTwisterNode(entry.twister!),
    };
  }

  @override
  Widget build(BuildContext context) {
    final trail = buildTrail(stories: stories, twisters: twisters);

    return Scaffold(
      backgroundColor: DesignTokens.screenBackground,
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
                'Hi, ${profile.displayName}!',
                style: const TextStyle(
                  fontFamily: DesignTokens.displayFontFamily,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: DesignTokens.wordUnreadInk,
                ),
              ),
            ),
            Expanded(
              child: trail.isEmpty
                  ? const SizedBox.shrink()
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.spacingLg,
                        vertical: DesignTokens.spacingMd,
                      ),
                      itemCount: trail.length,
                      separatorBuilder: (_, __) => const SizedBox(height: DesignTokens.spacingMd),
                      itemBuilder: (context, index) {
                        final alignment = index.isEven ? Alignment.centerLeft : Alignment.centerRight;
                        return Align(alignment: alignment, child: _buildEntry(trail[index]));
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Interleaves tongue-twister booster nodes (Unit 14) into the story trail
/// (PRD §8 Unit 9 + Unit 14; ticket progress-map-collection accept entry 3).
///
/// The PRD only pins a density guideline for boosters ("~1 per 3 stories"),
/// not an exact placement algorithm; this ticket pins the placement rule
/// itself: each twister is inserted immediately after the last story entry
/// sharing its `levelId`, scanning `stories` in authored order. A twister
/// whose `levelId` matches no story in `stories` is appended at the trail's
/// end rather than dropped. Twisters sharing a `levelId` preserve their
/// relative `twisters` input order.
library;

import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/phonics/scope_sequence_loader.dart';

/// What one [TrailEntry] represents.
enum TrailEntryKind { story, twisterBooster }

/// One position on the rendered trail: either an authored story or a
/// tongue-twister booster, never both.
class TrailEntry {
  const TrailEntry.story(this.storyRef)
      : twister = null,
        kind = TrailEntryKind.story;

  const TrailEntry.twister(this.twister)
      : storyRef = null,
        kind = TrailEntryKind.twisterBooster;

  final TrailEntryKind kind;

  /// Non-null iff [kind] == [TrailEntryKind.story].
  final StoryRef? storyRef;

  /// Non-null iff [kind] == [TrailEntryKind.twisterBooster].
  final TongueTwister? twister;
}

/// Builds the rendered trail from the authored [stories] (global authored
/// order, per phonics-engine) and [twisters] (Unit 14 boosters), applying
/// the pinned interleave rule described in this file's doc comment.
List<TrailEntry> buildTrail({
  required List<StoryRef> stories,
  required List<TongueTwister> twisters,
}) {
  final twistersByLevel = <String, List<TongueTwister>>{};
  for (final twister in twisters) {
    twistersByLevel.putIfAbsent(twister.levelId, () => []).add(twister);
  }

  final lastStoryIndexForLevel = <String, int>{};
  for (var i = 0; i < stories.length; i++) {
    lastStoryIndexForLevel[stories[i].levelId] = i;
  }

  final placedLevelIds = <String>{};
  final trail = <TrailEntry>[];
  for (var i = 0; i < stories.length; i++) {
    final story = stories[i];
    trail.add(TrailEntry.story(story));

    final isLastStoryOfLevel = lastStoryIndexForLevel[story.levelId] == i;
    final levelTwisters = twistersByLevel[story.levelId];
    if (isLastStoryOfLevel && levelTwisters != null) {
      trail.addAll(levelTwisters.map(TrailEntry.twister));
      placedLevelIds.add(story.levelId);
    }
  }

  // Orphans: twisters whose levelId matched no story, appended at the end
  // in original relative `twisters` input order.
  for (final twister in twisters) {
    if (!placedLevelIds.contains(twister.levelId)) {
      trail.add(TrailEntry.twister(twister));
    }
  }

  return trail;
}

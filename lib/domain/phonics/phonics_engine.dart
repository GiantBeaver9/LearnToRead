/// Phonics engine: rolling-window story unlocking and level advancement
/// (PRD §8 Unit 2 pinned design, "Unlock rule (ratified)": "rolling window
/// of 3 -- the child always has the next 3 uncompleted stories in global
/// authored order (which is level-ordered) and picks freely among them;
/// completing one pulls the next authored story into the window, and
/// unchosen stories remain offered until read ('no strict block': when
/// fewer than 3 uncompleted stories remain at the current level, the window
/// back-fills from the next level's authored order). `currentLevelId` still
/// advances only when the level's full story set is completed -- it gates
/// vocab enablement and twister tagging, not story availability. Earlier
/// stories remain replayable forever.").
///
/// Every function here is pure: `storiesFor`, `isUnlocked`, and `advance`
/// take a [Profile], a loaded [PhonicsContent], and a `completedStoryIds`
/// snapshot as plain inputs and return plain outputs -- no I/O, no mutation
/// of their inputs, no hidden state. Persisting `completedStoryIds` and the
/// returned [Profile] between calls is the caller's job (local-storage
/// ticket).
library;

import '../models/user_models.dart';
import 'scope_sequence_loader.dart';

/// The rolling-window size (PRD: "rolling window of 3").
const int kRollingWindowSize = 3;

/// Returns the stories currently available to `profile`: every entry of
/// `content.stories`, in that same relative (global authored) order, that
/// is either
///  - already completed (present in `completedStoryIds`) -- completed
///    stories are replayable forever, or
///  - among the first [kRollingWindowSize] entries of `content.stories`
///    (in `content.stories` order) that are NOT in `completedStoryIds` --
///    the rolling window itself, which naturally back-fills across level
///    boundaries because `content.stories` is one flat, level-ordered,
///    global list.
///
/// Never consults `profile.currentLevelId`: level advancement gates vocab
/// enablement and twister tagging only, never story availability (PRD,
/// ticket accept entry 4).
///
/// Pure: does not mutate `completedStoryIds`, and returns an equal result
/// for equal inputs no matter how many times it is called.
List<StoryRef> storiesFor(
  Profile profile,
  PhonicsContent content,
  Set<String> completedStoryIds,
) {
  final result = <StoryRef>[];
  var windowSlotsLeft = kRollingWindowSize;
  for (final story in content.stories) {
    if (completedStoryIds.contains(story.id)) {
      result.add(story);
    } else if (windowSlotsLeft > 0) {
      result.add(story);
      windowSlotsLeft--;
    }
  }
  return List.unmodifiable(result);
}

/// Whether `story` is currently available to `profile`. Equivalent to
/// `storiesFor(profile, content, completedStoryIds).any((s) => s.id ==
/// story.id)`.
bool isUnlocked(
  Profile profile,
  StoryRef story,
  PhonicsContent content,
  Set<String> completedStoryIds,
) =>
    storiesFor(profile, content, completedStoryIds).any((s) => s.id == story.id);

/// The result of a successful [advance] call: a new completed-story-id set
/// and a new [Profile] (identical to the input profile except possibly for
/// `currentLevelId`).
class AdvanceResult {
  const AdvanceResult({required this.profile, required this.completedStoryIds});

  final Profile profile;
  final Set<String> completedStoryIds;
}

/// Records `profile` completing `story`.
///
/// Throws [ArgumentError] if
/// `!isUnlocked(profile, story, content, completedStoryIds)` -- a locked
/// story can never be completed out of order. On a failed call,
/// `completedStoryIds` is left untouched (no partial mutation).
///
/// On success, returns a NEW completed set (`{...completedStoryIds,
/// story.id}`; the input set is left unmutated) and a NEW [Profile]
/// identical to `profile` except `currentLevelId`, recomputed by: while the
/// level in `content.levels` whose id == `currentLevelId` has a non-empty
/// story set (within `content.stories`) that is now fully contained in the
/// new completed set, AND a next level (next entry by ascending ordinal in
/// `content.levels`) exists, move `currentLevelId` to that next level's id;
/// repeat. `currentLevelId` therefore advances only on full-level
/// completion, and a single `advance()` call may skip forward more than one
/// level if it pushes multiple already-fully-completed levels' boundary at
/// once.
AdvanceResult advance(
  Profile profile,
  StoryRef story,
  PhonicsContent content,
  Set<String> completedStoryIds,
) {
  if (!isUnlocked(profile, story, content, completedStoryIds)) {
    throw ArgumentError.value(
      story.id,
      'story',
      'is locked for this profile and cannot be completed',
    );
  }

  final newCompletedStoryIds = {...completedStoryIds, story.id};

  var currentLevelId = profile.currentLevelId;
  while (true) {
    final levelIndex = content.levels.indexWhere((l) => l.id == currentLevelId);
    if (levelIndex == -1) break;

    final levelStoryIds = content.stories
        .where((s) => s.levelId == content.levels[levelIndex].id)
        .map((s) => s.id);
    if (levelStoryIds.isEmpty) break;

    final levelFullyComplete = levelStoryIds.every(newCompletedStoryIds.contains);
    if (!levelFullyComplete) break;

    final nextLevelIndex = levelIndex + 1;
    if (nextLevelIndex >= content.levels.length) break;

    currentLevelId = content.levels[nextLevelIndex].id;
  }

  final newProfile = Profile(
    localId: profile.localId,
    displayName: profile.displayName,
    ageBand: profile.ageBand,
    currentLevelId: currentLevelId,
    micConsent: profile.micConsent,
    cloudAsrConsent: profile.cloudAsrConsent,
    createdAt: profile.createdAt,
  );

  return AdvanceResult(profile: newProfile, completedStoryIds: newCompletedStoryIds);
}

/// Device-local user domain models (PRD §5 "Device-local user models").
///
/// All models here are local-first: no server holds user data. They are
/// pure, immutable Dart value types: no Flutter imports, no persistence
/// annotations (Drift/local-storage owns persistence in its own ticket).
///
/// No JSON (de)serialization is defined here -- per the domain-models
/// ticket's pinned design, "No JSON for user models is needed beyond what
/// Drift/analytics tickets do themselves."
library;

/// Compares two lists for deep (element-by-element) equality.
bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A profile's reading age band, set at profile creation and used to pick
/// the profile's starting level (A-9).
enum AgeBand {
  fiveToSix('5-6'),
  sevenToEight('7-8'),
  nineToTen('9-10');

  const AgeBand(this.label);

  /// Human-readable band label, e.g. `'5-6'`.
  final String label;
}

/// Max profiles allowed per device. The constant lives here per the
/// domain-models ticket's pinned design; enforcement is local-storage/UI.
const int kMaxProfilesPerDevice = 4;

/// A device-local child profile.
class Profile {
  const Profile({
    required this.localId,
    required this.displayName,
    required this.ageBand,
    required this.currentLevelId,
    required this.micConsent,
    required this.cloudAsrConsent,
    required this.createdAt,
  });

  final String localId;
  final String displayName;
  final AgeBand ageBand;
  final String currentLevelId;
  final bool micConsent;
  final bool cloudAsrConsent;
  final DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Profile &&
          other.localId == localId &&
          other.displayName == displayName &&
          other.ageBand == ageBand &&
          other.currentLevelId == currentLevelId &&
          other.micConsent == micConsent &&
          other.cloudAsrConsent == cloudAsrConsent &&
          other.createdAt == createdAt);

  @override
  int get hashCode => Object.hash(
        localId,
        displayName,
        ageBand,
        currentLevelId,
        micConsent,
        cloudAsrConsent,
        createdAt,
      );
}

/// A story's completion state for a given profile.
enum StoryStatus { locked, available, completed }

/// Per-profile, per-story progress.
class StoryProgress {
  const StoryProgress({
    required this.profileId,
    required this.storyId,
    required this.status,
    this.completedAt,
    required this.timesRead,
  });

  final String profileId;
  final String storyId;
  final StoryStatus status;

  /// Null for locked/available stories; set the first time the story is
  /// completed.
  final DateTime? completedAt;
  final int timesRead;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoryProgress &&
          other.profileId == profileId &&
          other.storyId == storyId &&
          other.status == status &&
          other.completedAt == completedAt &&
          other.timesRead == timesRead);

  @override
  int get hashCode =>
      Object.hash(profileId, storyId, status, completedAt, timesRead);
}

/// Tier of help most recently given for a word (Unit 6 stuck-word scaffold).
enum HelpLevel { none, soundOut, modeled }

/// Per-profile, per-word help/read signal, powering the learning signal
/// (§4.3) and the parent pilot view (Unit 10).
class WordHelpRecord {
  const WordHelpRecord({
    required this.profileId,
    required this.wordText,
    required this.encounterCount,
    required this.helpCount,
    required this.lastHelpLevel,
  });

  final String profileId;
  final String wordText;
  final int encounterCount;
  final int helpCount;
  final HelpLevel lastHelpLevel;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WordHelpRecord &&
          other.profileId == profileId &&
          other.wordText == wordText &&
          other.encounterCount == encounterCount &&
          other.helpCount == helpCount &&
          other.lastHelpLevel == lastHelpLevel);

  @override
  int get hashCode => Object.hash(
        profileId,
        wordText,
        encounterCount,
        helpCount,
        lastHelpLevel,
      );
}

/// Per-profile, per-twister completion count (Unit 14).
class TwisterProgress {
  const TwisterProgress({
    required this.profileId,
    required this.twisterId,
    required this.timesCompleted,
  });

  final String profileId;
  final String twisterId;
  final int timesCompleted;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TwisterProgress &&
          other.profileId == profileId &&
          other.twisterId == twisterId &&
          other.timesCompleted == timesCompleted);

  @override
  int get hashCode => Object.hash(profileId, twisterId, timesCompleted);
}

/// Per-profile set of earned `Collectible.id`s (Unit 9).
class CollectionState {
  CollectionState({
    required this.profileId,
    required List<String> earnedCollectibles,
  }) : earnedCollectibles = List.unmodifiable(earnedCollectibles);

  final String profileId;
  final List<String> earnedCollectibles;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CollectionState &&
          other.profileId == profileId &&
          _listEquals(other.earnedCollectibles, earnedCollectibles));

  @override
  int get hashCode =>
      Object.hash(profileId, Object.hashAll(earnedCollectibles));
}

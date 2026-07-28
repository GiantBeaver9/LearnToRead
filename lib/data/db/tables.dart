/// Drift table definitions for the device-local user models (PRD §5
/// "Device-local user models"; ticket local-storage).
///
/// Every table is keyed so it can be scoped and erased per-profile (PRD §8
/// Unit 10: "deleting a profile erases all its local data ... irreversibly").
/// Enum-typed domain fields (`AgeBand`, `StoryStatus`, `HelpLevel`) are
/// stored as `INTEGER` via `TypeConverter`s keyed to `enum.index`, so every
/// Drift-generated row class field is already the domain enum type -- DAOs
/// never hand-roll the int<->enum mapping.
library;

import 'package:drift/drift.dart';
import 'package:learn_to_read/domain/models/user_models.dart';

/// Converts [AgeBand] <-> its `enum.index` for storage.
class AgeBandConverter extends TypeConverter<AgeBand, int> {
  const AgeBandConverter();

  @override
  AgeBand fromSql(int fromDb) => AgeBand.values[fromDb];

  @override
  int toSql(AgeBand value) => value.index;
}

/// Converts [StoryStatus] <-> its `enum.index` for storage.
class StoryStatusConverter extends TypeConverter<StoryStatus, int> {
  const StoryStatusConverter();

  @override
  StoryStatus fromSql(int fromDb) => StoryStatus.values[fromDb];

  @override
  int toSql(StoryStatus value) => value.index;
}

/// Converts [HelpLevel] <-> its `enum.index` for storage.
class HelpLevelConverter extends TypeConverter<HelpLevel, int> {
  const HelpLevelConverter();

  @override
  HelpLevel fromSql(int fromDb) => HelpLevel.values[fromDb];

  @override
  int toSql(HelpLevel value) => value.index;
}

/// Device-local child profiles (PRD §5 Profile; §8 Unit 10 "up to 4 local
/// profiles"). The generated row class is named `ProfileRow` (not
/// `Profile`) so it never collides with `domain.Profile` in DAO imports.
@DataClassName('ProfileRow')
class Profiles extends Table {
  TextColumn get localId => text()();
  TextColumn get displayName => text()();
  IntColumn get ageBand => integer().map(const AgeBandConverter())();
  TextColumn get currentLevelId => text()();
  BoolColumn get micConsent => boolean()();
  BoolColumn get cloudAsrConsent => boolean()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column> get primaryKey => {localId};
}

/// Per-profile, per-story progress (PRD §5 StoryProgress; §8 Unit 2 status
/// lifecycle). Keyed by `(profileId, storyId)` so `upsertProgress` /
/// `recordCompletion` never duplicate a row for the same story.
@DataClassName('StoryProgressRow')
class StoryProgressEntries extends Table {
  TextColumn get profileId => text()();
  TextColumn get storyId => text()();
  IntColumn get status => integer().map(const StoryStatusConverter())();

  /// Null until the story is first completed; never moves after that.
  DateTimeColumn get completedAt => dateTime().nullable()();
  IntColumn get timesRead => integer()();

  @override
  Set<Column> get primaryKey => {profileId, storyId};
}

/// Per-profile, per-word help/read signal (PRD §5 WordHelpRecord; §4.3
/// learning signal; §8 Unit 6 tiered help). Keyed by `(profileId,
/// wordText)` so encounters/help for the same word accumulate on one row.
@DataClassName('WordHelpRow')
class WordHelpRecords extends Table {
  TextColumn get profileId => text()();
  TextColumn get wordText => text()();
  IntColumn get encounterCount => integer()();
  IntColumn get helpCount => integer()();
  IntColumn get lastHelpLevel => integer().map(const HelpLevelConverter())();

  @override
  Set<Column> get primaryKey => {profileId, wordText};
}

/// Per-profile, per-twister completion count (PRD §5 TwisterProgress; §8
/// Unit 14). Keyed by `(profileId, twisterId)`.
@DataClassName('TwisterProgressRow')
class TwisterProgressEntries extends Table {
  TextColumn get profileId => text()();
  TextColumn get twisterId => text()();
  IntColumn get timesCompleted => integer()();

  @override
  Set<Column> get primaryKey => {profileId, twisterId};
}

/// Per-profile earned collectibles (PRD §5 CollectionState; §8 Unit 8
/// "collectible granted only on first completion"; §8 Unit 9 collection
/// scene). Keyed by `(profileId, collectibleId)` so granting the same
/// collectible twice is a no-op at the storage layer -- the primary key
/// itself makes double-grant impossible, independent of caller discipline.
@DataClassName('CollectionEntryRow')
class CollectionEntries extends Table {
  TextColumn get profileId => text()();
  TextColumn get collectibleId => text()();

  @override
  Set<Column> get primaryKey => {profileId, collectibleId};
}

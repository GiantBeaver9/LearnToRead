/// The device-local Drift database (PRD §5 device-local user models; §9
/// A-2 "local storage is Drift (SQLite)"; ticket local-storage; PRD §8
/// Unit 16 flashcard persistence).
///
/// Owns the six device-local user model tables -- Profiles, StoryProgress,
/// WordHelpRecord, TwisterProgress, CollectionState (schema v1), and
/// FlashcardProgress (added by the v1->v2 migration, Unit 16) -- and
/// exposes one DAO per table. Content models are never stored here (they
/// are file-based story packs, owned by content-delivery); analytics has
/// its own queue persistence, kept disjoint from this DB.
///
/// Consumers (Riverpod providers in UI tickets) construct `AppDatabase`
/// with a real `QueryExecutor` (e.g. `NativeDatabase` backed by
/// `path_provider`'s app-documents directory) in production, and with
/// `NativeDatabase.memory()` in tests -- this file has no path_provider or
/// platform-channel dependency itself, so it is headlessly testable.
library;

import 'package:drift/drift.dart';
import 'package:learn_to_read/domain/models/user_models.dart';

import 'daos/collection_dao.dart';
import 'daos/flashcards_dao.dart';
import 'daos/profiles_dao.dart';
import 'daos/story_progress_dao.dart';
import 'daos/twister_progress_dao.dart';
import 'daos/word_help_dao.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// Per-profile, per-card Leitner flashcard state (PRD §8 Unit 16
/// "Persistence: per-profile `FlashcardProgress` (Drift; card key =
/// A-14-style word hash, box, dueAt) -- schema migration v1->v2").
///
/// Defined here rather than in `tables.dart` because it is the one v2
/// table: `tables.dart` holds the five original v1 tables, and the v1->v2
/// migration in [AppDatabase.migration] creates exactly this table.
/// Keyed by `(profileId, cardKey)` so grading upserts never duplicate a
/// row for the same card.
@DataClassName('FlashcardProgressRow')
class FlashcardProgressRows extends Table {
  TextColumn get profileId => text()();

  /// The A-14-style word hash (16 lowercase hex chars -- `hashWord` of the
  /// lowercased word text). Word text itself is never stored here.
  TextColumn get cardKey => text()();

  /// Leitner box, 1..kFlashcardMaxBox (see lib/domain/tuning.dart).
  IntColumn get box => integer()();

  /// When the card next becomes due (whole-second precision).
  DateTimeColumn get dueAt => dateTime()();

  @override
  Set<Column> get primaryKey => {profileId, cardKey};
}

/// The app's single Drift database.
///
/// Schema history:
///  - v1: Profiles, StoryProgress, WordHelpRecord, TwisterProgress,
///    CollectionState (ticket local-storage).
///  - v2: adds FlashcardProgress (PRD §8 Unit 16 phonics flashcards).
@DriftDatabase(
  tables: [
    Profiles,
    StoryProgressEntries,
    WordHelpRecords,
    TwisterProgressEntries,
    CollectionEntries,
    FlashcardProgressRows,
  ],
  daos: [
    ProfilesDao,
    StoryProgressDao,
    WordHelpDao,
    TwisterProgressDao,
    CollectionDao,
    FlashcardsDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v1 -> v2 (PRD §8 Unit 16): adds the FlashcardProgress table.
            // Purely additive -- every v1 table and its rows are untouched
            // (pinned by test/data/db/schema_migration_test.dart).
            await m.createTable(flashcardProgressRows);
          }
        },
      );
}

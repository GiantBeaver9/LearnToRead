/// The device-local Drift database (PRD §5 device-local user models; §9
/// A-2 "local storage is Drift (SQLite)"; ticket local-storage).
///
/// Owns exactly the five device-local user model tables -- Profiles,
/// StoryProgress, WordHelpRecord, TwisterProgress, CollectionState -- and
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
import 'daos/profiles_dao.dart';
import 'daos/story_progress_dao.dart';
import 'daos/twister_progress_dao.dart';
import 'daos/word_help_dao.dart';
import 'tables.dart';

part 'app_database.g.dart';

/// The app's single Drift database. Schema version is pinned to `1` --
/// there is no shipped prior version to migrate from yet.
@DriftDatabase(
  tables: [
    Profiles,
    StoryProgressEntries,
    WordHelpRecords,
    TwisterProgressEntries,
    CollectionEntries,
  ],
  daos: [
    ProfilesDao,
    StoryProgressDao,
    WordHelpDao,
    TwisterProgressDao,
    CollectionDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;
}

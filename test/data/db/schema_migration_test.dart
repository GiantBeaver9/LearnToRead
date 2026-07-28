// Schema migration test: v1 -> v2 (PRD §8 Unit 16 acceptance "Schema
// migration v1->v2 preserves existing rows of every v1 table").
//
// Approach (pragmatic user_version path, headless like the sibling db
// suites): a file-backed database is first created AT SCHEMA v1 by a test
// subclass that overrides `schemaVersion` to 1 and creates exactly the
// five v1 tables (so sqlite's user_version lands at 1, and the flashcard
// table genuinely does not exist yet). Every v1 table is populated through
// the real DAOs. The file is then re-opened as the real AppDatabase
// (schemaVersion 2), which runs `onUpgrade(from: 1, to: 2)` — and the test
// asserts:
//   * every v1 row in every v1 table survives byte-for-byte (via DAO
//     round-trips),
//   * the new FlashcardProgress table exists and is usable,
//   * user_version is now 2 (a third open runs no migration).

import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/features/flashcards/flashcard_progress.dart';

/// Opens the SAME schema as [AppDatabase] but pinned at v1: onCreate makes
/// only the five original tables, so a fresh file ends up exactly as a
/// v1 install left it (user_version = 1, no flashcard table).
class _V1Database extends AppDatabase {
  _V1Database(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createTable(profiles);
          await m.createTable(storyProgressEntries);
          await m.createTable(wordHelpRecords);
          await m.createTable(twisterProgressEntries);
          await m.createTable(collectionEntries);
        },
      );
}

Profile _profile(String id) => Profile(
      localId: id,
      displayName: 'Kid $id',
      ageBand: AgeBand.sevenToEight,
      currentLevelId: 'level.2',
      micConsent: true,
      cloudAsrConsent: false,
      createdAt: DateTime(2026, 1, 1, 9, 30),
    );

/// Populates every v1 table for [profileId] through the real DAOs.
Future<void> _populateV1Tables(AppDatabase db, String profileId) async {
  await db.profilesDao.insertProfile(_profile(profileId));
  await db.storyProgressDao.upsertProgress(
    StoryProgress(
      profileId: profileId,
      storyId: 'story.1',
      status: StoryStatus.available,
      timesRead: 0,
    ),
  );
  await db.storyProgressDao
      .recordCompletion(profileId: profileId, storyId: 'story.2');
  await db.wordHelpDao.recordEncounter(profileId: profileId, wordText: 'cat');
  await db.wordHelpDao.recordHelp(
    profileId: profileId,
    wordText: 'cat',
    tier: HelpLevel.soundOut,
  );
  await db.twisterProgressDao
      .recordCompletion(profileId: profileId, twisterId: 'twister.1');
  await db.collectionDao.grantCollectible(
    profileId: profileId,
    collectibleId: 'collectible.cat',
  );
}

Future<int> _userVersion(AppDatabase db) async {
  final row = await db.customSelect('PRAGMA user_version').getSingle();
  return row.data.values.single as int;
}

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('schema_migration_test_');
    dbFile = File('${tempDir.path}/app.sqlite');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  Future<void> createPopulatedV1Database() async {
    final v1 = _V1Database(NativeDatabase(dbFile));
    await _populateV1Tables(v1, 'profile.old');
    expect(await _userVersion(v1), 1,
        reason: 'the fixture must genuinely be a v1 database');
    await v1.close();
  }

  test('v1 -> v2 upgrade preserves every v1 row and adds a usable '
      'FlashcardProgress table', () async {
    await createPopulatedV1Database();

    final db = AppDatabase(NativeDatabase(dbFile));
    addTearDown(db.close);

    // --- every v1 table's rows are intact, via full DAO round-trips.
    expect(await db.profilesDao.getProfile('profile.old'),
        equals(_profile('profile.old')));

    final story1 = await db.storyProgressDao
        .getProgress(profileId: 'profile.old', storyId: 'story.1');
    expect(story1?.status, StoryStatus.available);
    final story2 = await db.storyProgressDao
        .getProgress(profileId: 'profile.old', storyId: 'story.2');
    expect(story2?.status, StoryStatus.completed);

    final help = await db.wordHelpDao
        .getRecord(profileId: 'profile.old', wordText: 'cat');
    expect(help?.encounterCount, 1);
    expect(help?.helpCount, 1);

    final twister = await db.twisterProgressDao
        .getProgress(profileId: 'profile.old', twisterId: 'twister.1');
    expect(twister?.timesCompleted, 1);

    final collection =
        await db.collectionDao.getCollectionState('profile.old');
    expect(collection.earnedCollectibles, ['collectible.cat']);

    // --- the new table exists and is usable.
    final progress = FlashcardProgress(
      profileId: 'profile.old',
      cardKey: '77af778b51abd4a3',
      box: 2,
      dueAt: DateTime(2026, 7, 29, 9, 0, 0),
    );
    await db.flashcardsDao.upsertProgress(progress);
    expect(
      await db.flashcardsDao
          .getProgress(profileId: 'profile.old', cardKey: '77af778b51abd4a3'),
      equals(progress),
    );

    // --- and the file is now stamped v2.
    expect(await _userVersion(db), 2);
  });

  test('re-opening an already-migrated file runs no further migration and '
      'keeps both v1 and v2 data', () async {
    await createPopulatedV1Database();

    // First open: migrates, writes one flashcard row.
    final first = AppDatabase(NativeDatabase(dbFile));
    await first.flashcardsDao.upsertProgress(FlashcardProgress(
      profileId: 'profile.old',
      cardKey: 'b9776d7ddf459c9a',
      box: 3,
      dueAt: DateTime(2026, 8, 4, 9, 0, 0),
    ));
    await first.close();

    // Second open: no migration to run; everything still there.
    final second = AppDatabase(NativeDatabase(dbFile));
    addTearDown(second.close);
    expect(await second.profilesDao.getProfile('profile.old'), isNotNull);
    expect(await second.flashcardsDao.rowCountForProfile('profile.old'), 1);
    expect(await _userVersion(second), 2);
  });

  test('a FRESH v2 database (onCreate path) also gets the flashcard table',
      () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    await db.flashcardsDao.upsertProgress(FlashcardProgress(
      profileId: 'p1',
      cardKey: 'k1',
      box: 1,
      dueAt: DateTime(2026, 7, 28),
    ));
    expect(await db.flashcardsDao.rowCountForProfile('p1'), 1);
    expect(await _userVersion(db), 2);
  });
}

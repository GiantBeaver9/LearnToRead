// PRD §8 Unit 10 pinned guarantee: "Deleting a profile erases all its local
// data (progress, help records, collection) -- irreversibly, with a plain
// confirmation" / acceptance: "Profile CRUD + data erasure verified (deleted
// profile leaves zero rows)". Ticket local-storage accept entry: "Deleting a
// profile erases ALL its local data -- progress, help records, twister
// progress, collection -- irreversibly; erasure_test verifies a deleted
// profile leaves zero rows in every table."
//
// This suite populates every table this unit owns (Profiles, StoryProgress,
// WordHelpRecord, TwisterProgress, CollectionState) for two profiles, then
// deletes one via ProfilesDao.deleteProfile and asserts:
//   * the deleted profile leaves zero rows in EVERY table (via
//     ProfilesDao.getProfile + each other DAO's rowCountForProfile), and
//   * the surviving profile's data in every table is completely untouched
//     -- proving this is a scoped per-profile erasure, not a full-database
//     wipe.
//
// Exercises the same DAO API pinned in the sibling *_dao_test.dart files in
// this directory; see those files' header comments for the full pinned
// surface.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/domain/models/user_models.dart';

Profile _profile(String id) {
  return Profile(
    localId: id,
    displayName: 'Kid $id',
    ageBand: AgeBand.sevenToEight,
    currentLevelId: 'level.1',
    micConsent: false,
    cloudAsrConsent: false,
    createdAt: DateTime(2026, 1, 1),
  );
}

Future<void> _populateAllTablesFor(AppDatabase db, String profileId) async {
  await db.profilesDao.insertProfile(_profile(profileId));

  await db.storyProgressDao.upsertProgress(
    StoryProgress(
      profileId: profileId,
      storyId: 'story.1',
      status: StoryStatus.available,
      timesRead: 0,
    ),
  );
  await db.storyProgressDao.recordCompletion(
    profileId: profileId,
    storyId: 'story.2',
  );

  await db.wordHelpDao.recordEncounter(profileId: profileId, wordText: 'cat');
  await db.wordHelpDao.recordHelp(
    profileId: profileId,
    wordText: 'cat',
    tier: HelpLevel.soundOut,
  );
  await db.wordHelpDao.recordEncounter(profileId: profileId, wordText: 'dog');

  await db.twisterProgressDao.recordCompletion(
    profileId: profileId,
    twisterId: 'twister.1',
  );
  await db.twisterProgressDao.recordCompletion(
    profileId: profileId,
    twisterId: 'twister.1',
  );

  await db.collectionDao.grantCollectible(
    profileId: profileId,
    collectibleId: 'collectible.cat',
  );
  await db.collectionDao.grantCollectible(
    profileId: profileId,
    collectibleId: 'collectible.dog',
  );
}

Future<void> _expectZeroRowsEverywhere(AppDatabase db, String profileId) async {
  expect(
    await db.profilesDao.getProfile(profileId),
    isNull,
    reason: 'Profiles table',
  );
  expect(
    await db.storyProgressDao.rowCountForProfile(profileId),
    0,
    reason: 'StoryProgress table',
  );
  expect(
    await db.wordHelpDao.rowCountForProfile(profileId),
    0,
    reason: 'WordHelpRecord table',
  );
  expect(
    await db.twisterProgressDao.rowCountForProfile(profileId),
    0,
    reason: 'TwisterProgress table',
  );
  expect(
    await db.collectionDao.rowCountForProfile(profileId),
    0,
    reason: 'CollectionState table',
  );
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group(
    'Profile erasure (positive: zero rows everywhere for the deleted profile)',
    () {
      test(
        'deleting a profile with data in every table leaves zero rows in every table',
        () async {
          await _populateAllTablesFor(db, 'profile.doomed');

          // Sanity: confirm data actually landed before deleting, otherwise a
          // trivially-empty DB would make this test meaningless.
          expect(await db.profilesDao.getProfile('profile.doomed'), isNotNull);
          expect(
            await db.storyProgressDao.rowCountForProfile('profile.doomed'),
            greaterThan(0),
          );
          expect(
            await db.wordHelpDao.rowCountForProfile('profile.doomed'),
            greaterThan(0),
          );
          expect(
            await db.twisterProgressDao.rowCountForProfile('profile.doomed'),
            greaterThan(0),
          );
          expect(
            await db.collectionDao.rowCountForProfile('profile.doomed'),
            greaterThan(0),
          );

          await db.profilesDao.deleteProfile('profile.doomed');

          await _expectZeroRowsEverywhere(db, 'profile.doomed');
        },
      );

      test(
        'erasing one profile does not touch a second profile\'s data in any table',
        () async {
          await _populateAllTablesFor(db, 'profile.doomed');
          await _populateAllTablesFor(db, 'profile.survivor');

          await db.profilesDao.deleteProfile('profile.doomed');

          // The deleted profile: zero rows everywhere.
          await _expectZeroRowsEverywhere(db, 'profile.doomed');

          // The surviving profile: every table still fully populated.
          expect(
            await db.profilesDao.getProfile('profile.survivor'),
            isNotNull,
          );
          expect(
            await db.storyProgressDao.rowCountForProfile('profile.survivor'),
            2,
          );
          expect(
            await db.wordHelpDao.rowCountForProfile('profile.survivor'),
            2,
          );
          expect(
            await db.twisterProgressDao.rowCountForProfile('profile.survivor'),
            1,
          );
          expect(
            await db.collectionDao.rowCountForProfile('profile.survivor'),
            2,
          );

          final survivorCollection = await db.collectionDao.getCollectionState(
            'profile.survivor',
          );
          expect(survivorCollection.earnedCollectibles.toSet(), {
            'collectible.cat',
            'collectible.dog',
          });
        },
      );
    },
  );

  group('Profile erasure (edge: deleting an empty profile)', () {
    test(
      'a profile with no progress/help/twister/collection data still deletes cleanly to zero rows',
      () async {
        await db.profilesDao.insertProfile(_profile('profile.empty'));

        await db.profilesDao.deleteProfile('profile.empty');

        await _expectZeroRowsEverywhere(db, 'profile.empty');
      },
    );
  });
}

// Unit 10 erasure cascade × Unit 16 flashcards (schema v2): deleting a
// profile irreversibly erases its FlashcardProgress rows along with every
// other per-profile table, and leaves other profiles' rows untouched.
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/features/flashcards/flashcard_progress.dart';
import 'package:learn_to_read/domain/models/user_models.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Profile profileNamed(String id) => Profile(
        localId: id,
        displayName: id,
        ageBand: AgeBand.fiveToSix,
        currentLevelId: 'level.demo.1',
        micConsent: true,
        cloudAsrConsent: false,
        createdAt: DateTime.utc(2026, 7, 28),
      );

  FlashcardProgress progressFor(String profileId, {int box = 2}) =>
      FlashcardProgress(
        profileId: profileId,
        cardKey: 'cardkey000000001',
        box: box,
        dueAt: DateTime.utc(2026, 7, 28),
      );

  test(
      'POSITIVE: deleteProfile erases that profile\'s flashcard progress '
      'and keeps the other profile\'s rows', () async {
    await db.profilesDao.insertProfile(profileNamed('erased'));
    await db.profilesDao.insertProfile(profileNamed('kept'));
    await db.flashcardsDao.upsertProgress(progressFor('erased'));
    await db.flashcardsDao.upsertProgress(progressFor('kept', box: 3));

    await db.profilesDao.deleteProfile('erased');

    expect(await db.flashcardsDao.rowCountForProfile('erased'), 0);
    expect(await db.flashcardsDao.rowCountForProfile('kept'), 1);
  });

  test(
      'NEGATIVE: deleting an unknown profile id is a no-op and throws '
      'nothing', () async {
    await db.profilesDao.insertProfile(profileNamed('kept'));
    await db.flashcardsDao.upsertProgress(progressFor('kept', box: 1));

    await db.profilesDao.deleteProfile('no-such-profile');

    expect(await db.flashcardsDao.rowCountForProfile('kept'), 1);
  });
}

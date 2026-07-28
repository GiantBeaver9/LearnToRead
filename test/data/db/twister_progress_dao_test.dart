// Pins the API of lib/data/db/daos/twister_progress_dao.dart (PRD §5
// TwisterProgress; §8 Unit 14 tongue-twister boosters; ticket local-storage
// accept entry "TwisterProgress increments").
//
// Pinned API surface:
//   class TwisterProgressDao {
//     Future<void> recordCompletion({
//       required String profileId,
//       required String twisterId,
//     }); // creates the row on first completion (timesCompleted=1) or
//         // increments timesCompleted on an existing row; never duplicates
//         // rows for the same (profileId, twisterId)
//     Future<TwisterProgress?> getProgress({
//       required String profileId,
//       required String twisterId,
//     });
//     Future<List<TwisterProgress>> allForProfile(String profileId);
//     Future<int> rowCountForProfile(String profileId);
//   }
//
// Round trips go through the domain TwisterProgress type, never a
// Drift-generated row class.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/domain/models/user_models.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('TwisterProgressDao recordCompletion (positive)', () {
    test('first completion creates a row with timesCompleted=1', () async {
      await db.twisterProgressDao.recordCompletion(
        profileId: 'profile.1',
        twisterId: 'twister.1',
      );

      final progress = await db.twisterProgressDao.getProgress(
        profileId: 'profile.1',
        twisterId: 'twister.1',
      );
      expect(progress, isNotNull);
      expect(progress!.timesCompleted, 1);
    });

    test(
      'repeated completions increment timesCompleted without duplicating the row',
      () async {
        await db.twisterProgressDao.recordCompletion(
          profileId: 'profile.1',
          twisterId: 'twister.1',
        );
        await db.twisterProgressDao.recordCompletion(
          profileId: 'profile.1',
          twisterId: 'twister.1',
        );
        await db.twisterProgressDao.recordCompletion(
          profileId: 'profile.1',
          twisterId: 'twister.1',
        );

        final progress = await db.twisterProgressDao.getProgress(
          profileId: 'profile.1',
          twisterId: 'twister.1',
        );
        expect(progress!.timesCompleted, 3);
        expect(await db.twisterProgressDao.rowCountForProfile('profile.1'), 1);
      },
    );

    test(
      'two distinct twisters for the same profile track independently',
      () async {
        await db.twisterProgressDao.recordCompletion(
          profileId: 'profile.1',
          twisterId: 'twister.a',
        );
        await db.twisterProgressDao.recordCompletion(
          profileId: 'profile.1',
          twisterId: 'twister.a',
        );
        await db.twisterProgressDao.recordCompletion(
          profileId: 'profile.1',
          twisterId: 'twister.b',
        );

        final a = await db.twisterProgressDao.getProgress(
          profileId: 'profile.1',
          twisterId: 'twister.a',
        );
        final b = await db.twisterProgressDao.getProgress(
          profileId: 'profile.1',
          twisterId: 'twister.b',
        );
        expect(a!.timesCompleted, 2);
        expect(b!.timesCompleted, 1);
        expect(await db.twisterProgressDao.rowCountForProfile('profile.1'), 2);
      },
    );

    test(
      'allForProfile lists all completed twisters for a profile only',
      () async {
        await db.twisterProgressDao.recordCompletion(
          profileId: 'profile.1',
          twisterId: 'twister.a',
        );
        await db.twisterProgressDao.recordCompletion(
          profileId: 'profile.2',
          twisterId: 'twister.a',
        );

        final profile1 = await db.twisterProgressDao.allForProfile('profile.1');
        expect(profile1.map((t) => t.twisterId).toSet(), {'twister.a'});
        expect(profile1.every((t) => t.profileId == 'profile.1'), isTrue);
      },
    );
  });

  group('TwisterProgressDao getProgress / rowCountForProfile (edge)', () {
    test('getProgress returns null for a twister never attempted', () async {
      expect(
        await db.twisterProgressDao.getProgress(
          profileId: 'profile.1',
          twisterId: 'never',
        ),
        isNull,
      );
    });

    test(
      'rowCountForProfile is 0 for a profile with no twister history',
      () async {
        expect(
          await db.twisterProgressDao.rowCountForProfile('profile.nobody'),
          0,
        );
      },
    );
  });
}

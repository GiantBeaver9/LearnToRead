// Pins the API of lib/data/db/daos/story_progress_dao.dart (PRD §5
// StoryProgress; §8 Unit 2 status lifecycle; §8 Unit 9 "map reflects
// StoryProgress exactly"; ticket local-storage accept entry 5).
//
// Pinned API surface:
//   class StoryProgressDao {
//     Future<void> upsertProgress(StoryProgress progress); // full write,
//         keyed by (profileId, storyId); used to set up arbitrary fixture
//         states including status transitions (locked/available/completed)
//     Future<void> recordCompletion({
//       required String profileId,
//       required String storyId,
//       DateTime? completedAt, // defaults to DateTime.now() if omitted
//     }); // sets status=completed, increments timesRead, sets completedAt
//         // only the FIRST time a story is completed (re-reads leave the
//         // original completedAt untouched per the domain model's "set the
//         // first time the story is completed" contract)
//     Future<StoryProgress?> getProgress({
//       required String profileId,
//       required String storyId,
//     });
//     Future<List<StoryProgress>> allForProfile(String profileId);
//     Future<int> rowCountForProfile(String profileId);
//   }
//
// Round trips go through the domain StoryProgress type, never a
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

  group('StoryProgressDao CRUD / round-trip (positive)', () {
    test(
      'upsertProgress then getProgress round-trips every pinned field',
      () async {
        final progress = StoryProgress(
          profileId: 'profile.1',
          storyId: 'story.1',
          status: StoryStatus.available,
          timesRead: 0,
        );

        await db.storyProgressDao.upsertProgress(progress);
        final fetched = await db.storyProgressDao.getProgress(
          profileId: 'profile.1',
          storyId: 'story.1',
        );

        expect(fetched, equals(progress));
      },
    );

    test(
      'allForProfile reflects fixture StoryProgress exactly for locked/available/completed',
      () async {
        final completedAt = DateTime(2026, 2, 1, 8);
        final locked = StoryProgress(
          profileId: 'profile.1',
          storyId: 'story.locked',
          status: StoryStatus.locked,
          timesRead: 0,
        );
        final available = StoryProgress(
          profileId: 'profile.1',
          storyId: 'story.available',
          status: StoryStatus.available,
          timesRead: 0,
        );
        final completed = StoryProgress(
          profileId: 'profile.1',
          storyId: 'story.completed',
          status: StoryStatus.completed,
          completedAt: completedAt,
          timesRead: 2,
        );

        await db.storyProgressDao.upsertProgress(locked);
        await db.storyProgressDao.upsertProgress(available);
        await db.storyProgressDao.upsertProgress(completed);

        final all = await db.storyProgressDao.allForProfile('profile.1');
        expect(all.toSet(), {locked, available, completed});
      },
    );
  });

  group('StoryProgressDao status transitions (positive)', () {
    test(
      'locked -> available -> completed via upsertProgress does not duplicate the row',
      () async {
        const profileId = 'profile.1';
        const storyId = 'story.1';

        await db.storyProgressDao.upsertProgress(
          const StoryProgress(
            profileId: profileId,
            storyId: storyId,
            status: StoryStatus.locked,
            timesRead: 0,
          ),
        );
        expect(
          (await db.storyProgressDao.getProgress(
            profileId: profileId,
            storyId: storyId,
          ))!.status,
          StoryStatus.locked,
        );

        await db.storyProgressDao.upsertProgress(
          const StoryProgress(
            profileId: profileId,
            storyId: storyId,
            status: StoryStatus.available,
            timesRead: 0,
          ),
        );
        expect(
          (await db.storyProgressDao.getProgress(
            profileId: profileId,
            storyId: storyId,
          ))!.status,
          StoryStatus.available,
        );

        final completedAt = DateTime(2026, 3, 1);
        await db.storyProgressDao.upsertProgress(
          StoryProgress(
            profileId: profileId,
            storyId: storyId,
            status: StoryStatus.completed,
            completedAt: completedAt,
            timesRead: 1,
          ),
        );
        final fetched = await db.storyProgressDao.getProgress(
          profileId: profileId,
          storyId: storyId,
        );
        expect(fetched!.status, StoryStatus.completed);
        expect(fetched.completedAt, completedAt);

        expect(await db.storyProgressDao.rowCountForProfile(profileId), 1);
      },
    );
  });

  group('StoryProgressDao recordCompletion semantics (positive)', () {
    test('first completion sets completedAt and timesRead=1', () async {
      final completedAt = DateTime(2026, 4, 1, 10);
      await db.storyProgressDao.recordCompletion(
        profileId: 'profile.1',
        storyId: 'story.1',
        completedAt: completedAt,
      );

      final fetched = await db.storyProgressDao.getProgress(
        profileId: 'profile.1',
        storyId: 'story.1',
      );
      expect(fetched!.status, StoryStatus.completed);
      expect(fetched.timesRead, 1);
      expect(fetched.completedAt, completedAt);
    });

    test(
      're-reading increments timesRead without duplicating the row or moving completedAt',
      () async {
        final firstCompletedAt = DateTime(2026, 4, 1, 10);
        final secondReadAt = DateTime(2026, 4, 5, 10);

        await db.storyProgressDao.recordCompletion(
          profileId: 'profile.1',
          storyId: 'story.1',
          completedAt: firstCompletedAt,
        );
        await db.storyProgressDao.recordCompletion(
          profileId: 'profile.1',
          storyId: 'story.1',
          completedAt: secondReadAt,
        );

        final fetched = await db.storyProgressDao.getProgress(
          profileId: 'profile.1',
          storyId: 'story.1',
        );
        expect(fetched!.timesRead, 2);
        expect(
          fetched.completedAt,
          firstCompletedAt,
          reason: 'completedAt is set the first time only',
        );
        expect(await db.storyProgressDao.rowCountForProfile('profile.1'), 1);
      },
    );

    test(
      'three reads accumulate timesRead=3 with a single underlying row',
      () async {
        for (var i = 0; i < 3; i++) {
          await db.storyProgressDao.recordCompletion(
            profileId: 'profile.1',
            storyId: 'story.1',
          );
        }

        final fetched = await db.storyProgressDao.getProgress(
          profileId: 'profile.1',
          storyId: 'story.1',
        );
        expect(fetched!.timesRead, 3);
        expect(await db.storyProgressDao.rowCountForProfile('profile.1'), 1);
      },
    );

    test(
      'different stories for the same profile track timesRead independently',
      () async {
        await db.storyProgressDao.recordCompletion(
          profileId: 'profile.1',
          storyId: 'story.a',
        );
        await db.storyProgressDao.recordCompletion(
          profileId: 'profile.1',
          storyId: 'story.a',
        );
        await db.storyProgressDao.recordCompletion(
          profileId: 'profile.1',
          storyId: 'story.b',
        );

        final a = await db.storyProgressDao.getProgress(
          profileId: 'profile.1',
          storyId: 'story.a',
        );
        final b = await db.storyProgressDao.getProgress(
          profileId: 'profile.1',
          storyId: 'story.b',
        );
        expect(a!.timesRead, 2);
        expect(b!.timesRead, 1);
        expect(await db.storyProgressDao.rowCountForProfile('profile.1'), 2);
      },
    );
  });

  group('StoryProgressDao getProgress / rowCountForProfile (edge)', () {
    test('getProgress returns null for a story never touched', () async {
      expect(
        await db.storyProgressDao.getProgress(
          profileId: 'profile.1',
          storyId: 'never',
        ),
        isNull,
      );
    });

    test(
      'rowCountForProfile is 0 for a profile with no story progress',
      () async {
        expect(
          await db.storyProgressDao.rowCountForProfile('profile.nobody'),
          0,
        );
      },
    );
  });
}

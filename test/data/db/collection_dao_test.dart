// Pins the API of lib/data/db/daos/collection_dao.dart (PRD §5
// CollectionState; §8 Unit 8 "collectible granted only on first completion";
// §8 Unit 9 collection scene; ticket local-storage accept entry
// "CollectionState uniqueness").
//
// Pinned API surface:
//   class CollectionDao {
//     Future<void> grantCollectible({
//       required String profileId,
//       required String collectibleId,
//     }); // idempotent per (profileId, collectibleId): granting the same
//         // collectible twice stores exactly one row -- this is what makes
//         // Unit 8's "collectible granted only on first completion" rule
//         // safe even if the caller double-invokes it
//     Future<CollectionState> getCollectionState(String profileId);
//         // never null; a profile with nothing earned yet has an empty
//         // earnedCollectibles list
//     Future<int> rowCountForProfile(String profileId);
//   }
//
// Reads return the domain CollectionState type, never a Drift-generated row
// class or raw list.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/db/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('CollectionDao grantCollectible (positive)', () {
    test(
      'granting a collectible makes it appear in the profile collection state',
      () async {
        await db.collectionDao.grantCollectible(
          profileId: 'profile.1',
          collectibleId: 'collectible.cat',
        );

        final state = await db.collectionDao.getCollectionState('profile.1');
        expect(state.profileId, 'profile.1');
        expect(state.earnedCollectibles, ['collectible.cat']);
      },
    );

    test(
      'granting multiple distinct collectibles accumulates all of them',
      () async {
        await db.collectionDao.grantCollectible(
          profileId: 'profile.1',
          collectibleId: 'collectible.cat',
        );
        await db.collectionDao.grantCollectible(
          profileId: 'profile.1',
          collectibleId: 'collectible.dog',
        );
        await db.collectionDao.grantCollectible(
          profileId: 'profile.1',
          collectibleId: 'collectible.owl',
        );

        final state = await db.collectionDao.getCollectionState('profile.1');
        expect(state.earnedCollectibles.toSet(), {
          'collectible.cat',
          'collectible.dog',
          'collectible.owl',
        });
        expect(await db.collectionDao.rowCountForProfile('profile.1'), 3);
      },
    );
  });

  group(
    'CollectionDao idempotent double-grant (positive: Unit 8 first-completion-only rule)',
    () {
      test(
        'granting the same collectible twice stores exactly one row',
        () async {
          await db.collectionDao.grantCollectible(
            profileId: 'profile.1',
            collectibleId: 'collectible.cat',
          );
          await db.collectionDao.grantCollectible(
            profileId: 'profile.1',
            collectibleId: 'collectible.cat',
          );

          final state = await db.collectionDao.getCollectionState('profile.1');
          expect(state.earnedCollectibles, ['collectible.cat']);
          expect(await db.collectionDao.rowCountForProfile('profile.1'), 1);
        },
      );

      test(
        're-granting one collectible does not affect counts of others already earned',
        () async {
          await db.collectionDao.grantCollectible(
            profileId: 'profile.1',
            collectibleId: 'collectible.cat',
          );
          await db.collectionDao.grantCollectible(
            profileId: 'profile.1',
            collectibleId: 'collectible.dog',
          );
          await db.collectionDao.grantCollectible(
            profileId: 'profile.1',
            collectibleId: 'collectible.cat',
          );
          await db.collectionDao.grantCollectible(
            profileId: 'profile.1',
            collectibleId: 'collectible.cat',
          );

          expect(await db.collectionDao.rowCountForProfile('profile.1'), 2);
          final state = await db.collectionDao.getCollectionState('profile.1');
          expect(state.earnedCollectibles.toSet(), {
            'collectible.cat',
            'collectible.dog',
          });
        },
      );
    },
  );

  group('CollectionDao per-profile scoping (positive)', () {
    test(
      'the same collectibleId can be earned independently by two different profiles',
      () async {
        await db.collectionDao.grantCollectible(
          profileId: 'profile.1',
          collectibleId: 'collectible.cat',
        );
        await db.collectionDao.grantCollectible(
          profileId: 'profile.2',
          collectibleId: 'collectible.cat',
        );

        expect(
          (await db.collectionDao.getCollectionState(
            'profile.1',
          )).earnedCollectibles,
          ['collectible.cat'],
        );
        expect(
          (await db.collectionDao.getCollectionState(
            'profile.2',
          )).earnedCollectibles,
          ['collectible.cat'],
        );
        expect(await db.collectionDao.rowCountForProfile('profile.1'), 1);
        expect(await db.collectionDao.rowCountForProfile('profile.2'), 1);
      },
    );
  });

  group('CollectionDao getCollectionState / rowCountForProfile (edge)', () {
    test(
      'a brand-new profile has an empty (non-null) collection state',
      () async {
        final state = await db.collectionDao.getCollectionState(
          'profile.nobody',
        );
        expect(state.profileId, 'profile.nobody');
        expect(state.earnedCollectibles, isEmpty);
      },
    );

    test('rowCountForProfile is 0 for a profile with nothing earned', () async {
      expect(await db.collectionDao.rowCountForProfile('profile.nobody'), 0);
    });
  });
}

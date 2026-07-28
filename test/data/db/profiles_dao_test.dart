// Pins the API of lib/data/db/app_database.dart and
// lib/data/db/daos/profiles_dao.dart (PRD §5 "Device-local user models" /
// Profile; §8 Unit 10 "up to 4 local profiles"; ticket local-storage accept
// entries 1 + 2).
//
// Pinned API surface exercised here (implementation does not exist yet --
// this suite is expected to fail to compile until it does; that failure IS
// the red state that pins the shape below):
//   class AppDatabase extends _$AppDatabase {
//     AppDatabase(QueryExecutor executor);
//     int get schemaVersion; // pinned to 2 (AMENDED 2026-07-28: Unit 16
//         flashcards (PRD §8) — schema v2 adds FlashcardProgress)
//     ProfilesDao get profilesDao;
//     StoryProgressDao get storyProgressDao;
//     WordHelpDao get wordHelpDao;
//     TwisterProgressDao get twisterProgressDao;
//     CollectionDao get collectionDao;
//     Future<void> close(); // inherited from drift's GeneratedDatabase
//   }
//   class ProfilesDao {
//     Future<void> insertProfile(Profile profile); // throws
//         MaxProfilesExceededException once 4 profiles already exist
//     Future<Profile?> getProfile(String localId);
//     Future<List<Profile>> allProfiles();
//     Stream<List<Profile>> watchAllProfiles();
//     Future<void> updateProfile(Profile profile); // mutates by localId;
//         localId/createdAt are identity/audit fields and are not mutated
//     Future<void> deleteProfile(String localId); // cascades erasure
//         (see erasure_test.dart); no-op if localId does not exist
//   }
//   class MaxProfilesExceededException implements Exception {
//     final int max;
//   }
//
// Round trips go through the domain types from domain-models
// (package:learn_to_read/domain/models/user_models.dart) -- DAOs return
// Profile, never a Drift-generated row class.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/data/db/daos/profiles_dao.dart';
import 'package:learn_to_read/domain/models/user_models.dart';

Profile _profile(
  String id, {
  String displayName = 'Ada',
  AgeBand ageBand = AgeBand.fiveToSix,
  String currentLevelId = 'level.1',
  bool micConsent = false,
  bool cloudAsrConsent = false,
  DateTime? createdAt,
}) {
  return Profile(
    localId: id,
    displayName: displayName,
    ageBand: ageBand,
    currentLevelId: currentLevelId,
    micConsent: micConsent,
    cloudAsrConsent: cloudAsrConsent,
    createdAt: createdAt ?? DateTime(2026, 1, 1, 9, 30),
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

  group('AppDatabase (positive: schema sanity)', () {
    // AMENDED 2026-07-28: Unit 16 flashcards (PRD §8) — schema v2 adds
    // FlashcardProgress (see test/data/db/schema_migration_test.dart for
    // the v1->v2 migration coverage).
    test('schemaVersion is pinned to 2', () {
      expect(db.schemaVersion, 2);
    });
  });

  group('ProfilesDao CRUD (positive)', () {
    test(
      'insertProfile then getProfile round-trips every pinned field exactly',
      () async {
        final createdAt = DateTime(2026, 1, 1, 9, 30);
        final profile = Profile(
          localId: 'profile.1',
          displayName: 'Ada',
          ageBand: AgeBand.sevenToEight,
          currentLevelId: 'level.3',
          micConsent: true,
          cloudAsrConsent: false,
          createdAt: createdAt,
        );

        await db.profilesDao.insertProfile(profile);
        final fetched = await db.profilesDao.getProfile('profile.1');

        expect(fetched, equals(profile));
      },
    );

    test('round-trips all three AgeBand values distinctly', () async {
      final p1 = _profile('p1', ageBand: AgeBand.fiveToSix);
      final p2 = _profile('p2', ageBand: AgeBand.sevenToEight);
      final p3 = _profile('p3', ageBand: AgeBand.nineToTen);

      await db.profilesDao.insertProfile(p1);
      await db.profilesDao.insertProfile(p2);
      await db.profilesDao.insertProfile(p3);

      expect(
        (await db.profilesDao.getProfile('p1'))!.ageBand,
        AgeBand.fiveToSix,
      );
      expect(
        (await db.profilesDao.getProfile('p2'))!.ageBand,
        AgeBand.sevenToEight,
      );
      expect(
        (await db.profilesDao.getProfile('p3'))!.ageBand,
        AgeBand.nineToTen,
      );
    });

    test('allProfiles returns every inserted profile', () async {
      final p1 = _profile('p1');
      final p2 = _profile('p2');

      await db.profilesDao.insertProfile(p1);
      await db.profilesDao.insertProfile(p2);

      final all = await db.profilesDao.allProfiles();
      expect(all.toSet(), {p1, p2});
    });

    test(
      'updateProfile changes mutable fields and preserves identity/audit fields',
      () async {
        final createdAt = DateTime(2026, 1, 1, 9, 30);
        final original = _profile(
          'p1',
          displayName: 'Ada',
          ageBand: AgeBand.fiveToSix,
          currentLevelId: 'level.1',
          micConsent: false,
          cloudAsrConsent: false,
          createdAt: createdAt,
        );
        await db.profilesDao.insertProfile(original);

        final updated = Profile(
          localId: 'p1',
          displayName: 'Adaeze',
          ageBand: AgeBand.sevenToEight,
          currentLevelId: 'level.4',
          micConsent: true,
          cloudAsrConsent: true,
          createdAt: createdAt,
        );
        await db.profilesDao.updateProfile(updated);

        final fetched = await db.profilesDao.getProfile('p1');
        expect(fetched!.displayName, 'Adaeze');
        expect(fetched.ageBand, AgeBand.sevenToEight);
        expect(fetched.currentLevelId, 'level.4');
        expect(fetched.micConsent, isTrue);
        expect(fetched.cloudAsrConsent, isTrue);
        expect(fetched.localId, 'p1');
        expect(fetched.createdAt, createdAt);
      },
    );
  });

  group('ProfilesDao getProfile (edge)', () {
    test('returns null for an id that was never inserted', () async {
      expect(await db.profilesDao.getProfile('nope'), isNull);
    });
  });

  group('ProfilesDao max-4-profiles cap (edge + negative)', () {
    test('inserting exactly 4 profiles succeeds (boundary)', () async {
      for (final id in ['p1', 'p2', 'p3', 'p4']) {
        await db.profilesDao.insertProfile(_profile(id));
      }
      expect(await db.profilesDao.allProfiles(), hasLength(4));
    });

    test(
      'inserting a 5th profile throws MaxProfilesExceededException',
      () async {
        for (final id in ['p1', 'p2', 'p3', 'p4']) {
          await db.profilesDao.insertProfile(_profile(id));
        }

        await expectLater(
          () => db.profilesDao.insertProfile(_profile('p5')),
          throwsA(isA<MaxProfilesExceededException>()),
        );
      },
    );

    test(
      'a failed 5th insert leaves the existing 4 profiles unchanged',
      () async {
        for (final id in ['p1', 'p2', 'p3', 'p4']) {
          await db.profilesDao.insertProfile(_profile(id));
        }
        try {
          await db.profilesDao.insertProfile(_profile('p5'));
        } catch (_) {
          // expected
        }

        final all = await db.profilesDao.allProfiles();
        expect(all, hasLength(4));
        expect(all.map((p) => p.localId).toSet(), {'p1', 'p2', 'p3', 'p4'});
      },
    );

    test(
      'deleting one of 4 profiles re-opens capacity for a new insert',
      () async {
        for (final id in ['p1', 'p2', 'p3', 'p4']) {
          await db.profilesDao.insertProfile(_profile(id));
        }
        await db.profilesDao.deleteProfile('p1');

        await db.profilesDao.insertProfile(_profile('p5'));

        expect(await db.profilesDao.allProfiles(), hasLength(4));
        expect((await db.profilesDao.getProfile('p5')), isNotNull);
      },
    );
  });

  group('ProfilesDao deleteProfile (positive + edge)', () {
    test('removes the profile and leaves other profiles untouched', () async {
      final p1 = _profile('p1');
      final p2 = _profile('p2');
      await db.profilesDao.insertProfile(p1);
      await db.profilesDao.insertProfile(p2);

      await db.profilesDao.deleteProfile('p1');

      expect(await db.profilesDao.getProfile('p1'), isNull);
      expect(await db.profilesDao.getProfile('p2'), equals(p2));
      expect(await db.profilesDao.allProfiles(), [p2]);
    });

    test(
      'deleting a non-existent localId is a no-op and does not throw',
      () async {
        await db.profilesDao.insertProfile(_profile('p1'));

        await db.profilesDao.deleteProfile('does-not-exist');

        expect(await db.profilesDao.allProfiles(), hasLength(1));
      },
    );
  });

  group(
    'ProfilesDao watchAllProfiles (positive: stream for Riverpod providers)',
    () {
      test('emits an updated list after a profile is inserted', () async {
        final emissions = <List<Profile>>[];
        final sub = db.profilesDao.watchAllProfiles().listen(emissions.add);
        await Future<void>.delayed(Duration.zero);
        expect(emissions, hasLength(1));
        expect(emissions.single, isEmpty);

        final p1 = _profile('p1');
        await db.profilesDao.insertProfile(p1);
        await Future<void>.delayed(Duration.zero);

        await sub.cancel();
        expect(emissions.last, [p1]);
      });
    },
  );
}

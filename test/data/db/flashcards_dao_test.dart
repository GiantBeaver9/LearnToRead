// Tests for lib/data/db/daos/flashcards_dao.dart (PRD §8 Unit 16
// "Persistence: per-profile FlashcardProgress (Drift; card key =
// A-14-style word hash, box, dueAt)").
//
// Same idioms as the sibling *_dao_test.dart suites: NativeDatabase.memory,
// DAOs round-trip the pure domain value type (FlashcardProgress), the
// composite primary key makes upserts duplicate-proof. All DateTimes are
// whole-second (Drift's dateTime() column stores unix seconds).

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/features/flashcards/flashcard_progress.dart';

final DateTime _t0 = DateTime(2026, 7, 28, 9, 0, 0);

FlashcardProgress _progress(
  String profileId,
  String cardKey, {
  int box = 1,
  DateTime? dueAt,
}) =>
    FlashcardProgress(
      profileId: profileId,
      cardKey: cardKey,
      box: box,
      dueAt: dueAt ?? _t0,
    );

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('FlashcardsDao upsert + get (positive)', () {
    test('upsertProgress then getProgress round-trips every field', () async {
      final progress = _progress('p1', 'aaaa111122223333', box: 2);

      await db.flashcardsDao.upsertProgress(progress);
      final fetched = await db.flashcardsDao
          .getProgress(profileId: 'p1', cardKey: 'aaaa111122223333');

      expect(fetched, equals(progress));
    });

    test('a second upsert for the same (profile, cardKey) REPLACES the row '
        '(no duplicates — grading moves the box/dueAt)', () async {
      await db.flashcardsDao.upsertProgress(_progress('p1', 'k1', box: 1));
      await db.flashcardsDao.upsertProgress(_progress(
        'p1',
        'k1',
        box: 2,
        dueAt: _t0.add(const Duration(days: 1)),
      ));

      expect(await db.flashcardsDao.rowCountForProfile('p1'), 1);
      final fetched =
          await db.flashcardsDao.getProgress(profileId: 'p1', cardKey: 'k1');
      expect(fetched?.box, 2);
      expect(fetched?.dueAt, _t0.add(const Duration(days: 1)));
    });

    test('the same cardKey is independent per profile', () async {
      await db.flashcardsDao.upsertProgress(_progress('p1', 'k1', box: 3));
      await db.flashcardsDao.upsertProgress(_progress('p2', 'k1', box: 1));

      final p1 =
          await db.flashcardsDao.getProgress(profileId: 'p1', cardKey: 'k1');
      final p2 =
          await db.flashcardsDao.getProgress(profileId: 'p2', cardKey: 'k1');
      expect(p1?.box, 3);
      expect(p2?.box, 1);
    });
  });

  group('FlashcardsDao getProgress (edge)', () {
    test('returns null for a never-graded card', () async {
      expect(
        await db.flashcardsDao.getProgress(profileId: 'p1', cardKey: 'nope'),
        isNull,
      );
    });
  });

  group('FlashcardsDao dueForProfile — due filtering at t', () {
    test('returns rows with dueAt <= t only, scoped to the profile', () async {
      await db.flashcardsDao.upsertProgress(
          _progress('p1', 'past', dueAt: _t0.subtract(const Duration(hours: 2))));
      await db.flashcardsDao.upsertProgress(_progress('p1', 'exact', dueAt: _t0));
      await db.flashcardsDao.upsertProgress(_progress('p1', 'future',
          dueAt: _t0.add(const Duration(seconds: 1))));
      await db.flashcardsDao.upsertProgress(
          _progress('p2', 'other-profile', dueAt: _t0.subtract(const Duration(days: 1))));

      final due =
          await db.flashcardsDao.dueForProfile(profileId: 'p1', at: _t0);

      expect(due.map((p) => p.cardKey).toSet(), {'past', 'exact'},
          reason: 'boundary inclusive; future and other-profile rows excluded');
    });

    test('advancing t brings future rows due (fake-clock progression)', () async {
      await db.flashcardsDao.upsertProgress(
          _progress('p1', 'k1', dueAt: _t0.add(const Duration(days: 1))));

      expect(
        await db.flashcardsDao.dueForProfile(profileId: 'p1', at: _t0),
        isEmpty,
      );
      expect(
        await db.flashcardsDao.dueForProfile(
          profileId: 'p1',
          at: _t0.add(const Duration(days: 1)),
        ),
        hasLength(1),
      );
    });
  });

  group('FlashcardsDao allForProfile + eraseProfile', () {
    test('allForProfile returns only that profile\'s rows', () async {
      await db.flashcardsDao.upsertProgress(_progress('p1', 'k1'));
      await db.flashcardsDao.upsertProgress(_progress('p1', 'k2'));
      await db.flashcardsDao.upsertProgress(_progress('p2', 'k1'));

      final rows = await db.flashcardsDao.allForProfile('p1');

      expect(rows.map((p) => p.cardKey).toSet(), {'k1', 'k2'});
    });

    test('eraseProfile removes every row for the profile and no others '
        '(the Unit 10 erasure hook)', () async {
      await db.flashcardsDao.upsertProgress(_progress('p1', 'k1'));
      await db.flashcardsDao.upsertProgress(_progress('p1', 'k2'));
      await db.flashcardsDao.upsertProgress(_progress('p2', 'k1'));

      await db.flashcardsDao.eraseProfile('p1');

      expect(await db.flashcardsDao.rowCountForProfile('p1'), 0);
      expect(await db.flashcardsDao.rowCountForProfile('p2'), 1);
    });
  });
}

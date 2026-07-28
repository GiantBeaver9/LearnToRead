/// DAO for the per-profile `FlashcardProgress` model (PRD §8 Unit 16
/// "Persistence: per-profile `FlashcardProgress` (Drift; card key =
/// A-14-style word hash, box, dueAt)" -- the one table the v1->v2 schema
/// migration adds).
///
/// Returns the pure `FlashcardProgress` value type from
/// `lib/features/flashcards/flashcard_progress.dart`, never a generated
/// row class (repo convention pinned by the local-storage suites). A card
/// with NO row is implicitly box 1 / due now, so "due" queries here only
/// answer for STORED progress -- the deck-side helper `dueCardsAt`
/// (lib/features/flashcards/leitner_scheduler.dart) combines this with the
/// deck to include never-graded cards.
///
/// NOTE for the erasure cascade (PRD §8 Unit 10 "deleting a profile erases
/// all its local data"): `ProfilesDao.deleteProfile` must also clear this
/// table; that DAO is owned by another work stream right now, so the hook
/// is [eraseProfile] here, plus the cascade amendment called out in the
/// flashcards screen's WIRING block.
library;

import 'package:drift/drift.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/features/flashcards/flashcard_progress.dart';

part 'flashcards_dao.g.dart';

@DriftAccessor(tables: [FlashcardProgressRows])
class FlashcardsDao extends DatabaseAccessor<AppDatabase>
    with _$FlashcardsDaoMixin {
  FlashcardsDao(super.db);

  /// Inserts or replaces the `(profileId, cardKey)` row -- grading writes
  /// the post-grade `(box, dueAt)` through this, and the primary key makes
  /// duplicate rows impossible at the storage layer.
  Future<void> upsertProgress(FlashcardProgress progress) async {
    await into(flashcardProgressRows).insertOnConflictUpdate(
      FlashcardProgressRowsCompanion.insert(
        profileId: progress.profileId,
        cardKey: progress.cardKey,
        box: progress.box,
        dueAt: progress.dueAt,
      ),
    );
  }

  /// Returns the stored progress for `(profileId, cardKey)`, or null if
  /// the card has never been graded (implicitly box 1, due now).
  Future<FlashcardProgress?> getProgress({
    required String profileId,
    required String cardKey,
  }) async {
    final row = await (select(flashcardProgressRows)
          ..where(
            (t) => t.profileId.equals(profileId) & t.cardKey.equals(cardKey),
          ))
        .getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  /// Every stored progress row for [profileId], keyed by nothing --
  /// callers index by `cardKey` as needed.
  Future<List<FlashcardProgress>> allForProfile(String profileId) async {
    final rows = await (select(
      flashcardProgressRows,
    )..where((t) => t.profileId.equals(profileId))).get();
    return rows.map(_toDomain).toList();
  }

  /// The stored rows for [profileId] that are due at [at] (boundary
  /// inclusive: `dueAt <= at`). Never-graded cards have no row and are due
  /// by definition -- combine with the deck via `dueCardsAt` for the full
  /// session queue.
  Future<List<FlashcardProgress>> dueForProfile({
    required String profileId,
    required DateTime at,
  }) async {
    final rows = await (select(flashcardProgressRows)
          ..where(
            (t) =>
                t.profileId.equals(profileId) &
                t.dueAt.isSmallerOrEqualValue(at),
          ))
        .get();
    return rows.map(_toDomain).toList();
  }

  /// Returns the number of progress rows stored for [profileId] (mirrors
  /// the sibling DAOs' `rowCountForProfile`, used by erasure checks).
  Future<int> rowCountForProfile(String profileId) async {
    final rows = await (select(
      flashcardProgressRows,
    )..where((t) => t.profileId.equals(profileId))).get();
    return rows.length;
  }

  /// Deletes every row for [profileId] -- the Unit 10 erasure hook for
  /// this table (see the library doc comment).
  Future<void> eraseProfile(String profileId) async {
    await (delete(
      flashcardProgressRows,
    )..where((t) => t.profileId.equals(profileId))).go();
  }

  FlashcardProgress _toDomain(FlashcardProgressRow row) => FlashcardProgress(
        profileId: row.profileId,
        cardKey: row.cardKey,
        box: row.box,
        dueAt: row.dueAt,
      );
}

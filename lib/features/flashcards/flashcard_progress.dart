/// The per-profile Leitner state of one flashcard (PRD §8 Unit 16
/// "Persistence: per-profile `FlashcardProgress` (Drift; card key =
/// A-14-style word hash, box, dueAt)").
///
/// A pure, immutable value type in the style of the device-local user
/// models (`lib/domain/models/user_models.dart`): no Flutter imports, no
/// persistence annotations; equal constructor arguments give `==` instances.
/// `FlashcardsDao` maps its Drift rows to and from this type — DAOs return
/// domain values, never generated row classes (repo convention pinned by
/// the local-storage suites).
library;

/// One `(profileId, cardKey)`'s Leitner box and next-due time.
///
/// A card with NO stored `FlashcardProgress` row is implicitly in box 1 and
/// due immediately — box 1 is "due now" (PRD §8 Unit 16), so absence of a
/// row and a box-1 row behave identically for due-queue purposes.
class FlashcardProgress {
  const FlashcardProgress({
    required this.profileId,
    required this.cardKey,
    required this.box,
    required this.dueAt,
  });

  /// `Profile.localId` this progress belongs to.
  final String profileId;

  /// The A-14-style word hash identifying the card (see
  /// `FlashcardCard.cardKey` / `hashWord`).
  final String cardKey;

  /// Leitner box, `1..kFlashcardMaxBox`.
  final int box;

  /// When the card next becomes due. Stored via Drift's `dateTime()`
  /// column (whole-second precision).
  final DateTime dueAt;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FlashcardProgress &&
          other.profileId == profileId &&
          other.cardKey == cardKey &&
          other.box == box &&
          other.dueAt == dueAt);

  @override
  int get hashCode => Object.hash(profileId, cardKey, box, dueAt);

  @override
  String toString() =>
      'FlashcardProgress($profileId, $cardKey, box $box, due $dueAt)';
}

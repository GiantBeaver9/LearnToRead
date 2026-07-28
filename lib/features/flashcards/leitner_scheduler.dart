/// The MVP Leitner scheduler (PRD §8 Unit 16 "Scheduling (MVP Leitner,
/// consts in the tuning file): 3 boxes").
///
/// Pure grade-transition and due-filtering logic over `(box, now)`:
///  - "practice again" -> box 1, due immediately (the session additionally
///    re-queues the card after the remaining due cards — that ordering is
///    `FlashcardSession`'s job in `flashcard_session.dart`, not this
///    file's);
///  - "got it" -> next box, capped at `kFlashcardMaxBox`; dues:
///    box 2 = +`kFlashcardBox2Due` (1 day), box 3 = +`kFlashcardBox3Due`
///    (3 days), then +`kFlashcardBox3Redue` (7 days) re-dues while the card
///    stays in box 3.
///
/// The clock is injected (`DateTime Function() now`) — nothing here calls
/// `DateTime.now()` inline, per the repo convention pinned by
/// `lib/features/analytics/event_schema.dart`'s `Clock`.
library;

import 'package:learn_to_read/domain/tuning.dart';
import 'package:learn_to_read/features/flashcards/flashcard_deck.dart';
import 'package:learn_to_read/features/flashcards/flashcard_progress.dart';
import 'package:learn_to_read/features/flashcards/phonics_first_order.dart';

/// The exactly-two grades a child can give a card (PRD §8 Unit 16
/// "Grading: exactly two buttons" — amber "practice again", green "got
/// it"; Anki's four are too many for the age band).
enum FlashcardGrade { practiceAgain, gotIt }

/// Applies Unit 16's Leitner transitions with an injected clock.
class LeitnerScheduler {
  const LeitnerScheduler({required this.now});

  /// The injected clock — never `DateTime.now()` inline.
  final DateTime Function() now;

  /// Returns the `(box, dueAt)` a card in [box] moves to when graded
  /// [grade], evaluated at `now()`.
  ///
  /// Throws [ArgumentError] for a box outside `1..kFlashcardMaxBox` — a
  /// storage-corruption signal, not a runtime state.
  ({int box, DateTime dueAt}) applyGrade({
    required int box,
    required FlashcardGrade grade,
  }) {
    if (box < 1 || box > kFlashcardMaxBox) {
      throw ArgumentError.value(
        box,
        'box',
        'must be 1..$kFlashcardMaxBox (kFlashcardMaxBox)',
      );
    }
    final at = now();
    switch (grade) {
      case FlashcardGrade.practiceAgain:
        // Box 1 is "due now": the card is immediately due again, and the
        // session re-queues it after the remaining due cards.
        return (box: 1, dueAt: at);
      case FlashcardGrade.gotIt:
        if (box >= kFlashcardMaxBox) {
          // Stays in the top box with the 7-day re-due.
          return (box: kFlashcardMaxBox, dueAt: at.add(kFlashcardBox3Redue));
        }
        final nextBox = box + 1;
        return (
          box: nextBox,
          dueAt: at.add(nextBox == 2 ? kFlashcardBox2Due : kFlashcardBox3Due),
        );
    }
  }

  /// Whether a card with [progress] is due at `now()`. A card with no
  /// stored progress (`null`) is implicitly box 1, due immediately.
  bool isDue(FlashcardProgress? progress) => isDueAt(progress, now());
}

/// Pure due filter: due iff no progress row exists (implicit box 1, due
/// now) or `dueAt` is at or before [at] (boundary inclusive: a card due
/// exactly at [at] IS due).
bool isDueAt(FlashcardProgress? progress, DateTime at) =>
    progress == null || !progress.dueAt.isAfter(at);

/// Builds the session queue: every card of [deck] due at [at] per
/// [isDueAt], in deck (first-appearance) order. [progressByKey] maps
/// `cardKey` -> stored progress; cards absent from it are new (box 1, due
/// now).
///
/// [cumulativeGraphemes] is the OPTIONAL phonics-first ordering input (PRD
/// §8 Unit 16 speech-first layer): when non-null, the due cards are
/// reordered by [phonicsFirstOrder] — decodable-at-level first,
/// ahead-of-level after, stable within each group. When null the deck
/// order stands unchanged (the committed scaffold behavior).
List<FlashcardCard> dueCardsAt({
  required FlashcardDeck deck,
  required Map<String, FlashcardProgress> progressByKey,
  required DateTime at,
  Set<String>? cumulativeGraphemes,
}) {
  final due = [
    for (final card in deck.cards)
      if (isDueAt(progressByKey[card.cardKey], at)) card,
  ];
  if (cumulativeGraphemes == null) return due;
  return phonicsFirstOrder(due, cumulativeGraphemes);
}

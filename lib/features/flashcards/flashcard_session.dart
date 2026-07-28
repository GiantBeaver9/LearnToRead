/// One flashcard session's queue (PRD §8 Unit 16 "Session = all due
/// cards"): the due cards at session start, graded front-to-back.
///
/// "practice again" re-queues the card at the END of the queue — after the
/// remaining due cards this session (PRD §8 Unit 16) — so it reappears
/// before the session can end. "got it" simply removes it. The session is
/// complete when the queue is empty; persistence (box/dueAt writes) is the
/// screen's job via `LeitnerScheduler` + `FlashcardsDao`, not this class's.
library;

import 'package:learn_to_read/features/flashcards/flashcard_deck.dart';
import 'package:learn_to_read/features/flashcards/leitner_scheduler.dart';

/// A mutable in-memory queue over the session's due cards.
class FlashcardSession {
  /// Creates a session over [queue] (typically `dueCardsAt(...)`'s result).
  /// The list is copied; the caller's list is never mutated.
  FlashcardSession({required List<FlashcardCard> queue})
      : _queue = List.of(queue);

  final List<FlashcardCard> _queue;

  /// The card currently facing the child, or null when the session is
  /// complete.
  FlashcardCard? get current => _queue.isEmpty ? null : _queue.first;

  /// True once every card has been graded "got it" (the queue is cleared).
  bool get isComplete => _queue.isEmpty;

  /// How many cards remain in the queue (re-queued cards count once per
  /// queue position).
  int get remaining => _queue.length;

  /// The remaining queue, front first. Unmodifiable snapshot.
  List<FlashcardCard> get queue => List.unmodifiable(_queue);

  /// Grades [current]: removes it from the front and, for
  /// [FlashcardGrade.practiceAgain], re-queues it at the end — after every
  /// remaining due card. Throws [StateError] if the session is already
  /// complete.
  void gradeCurrent(FlashcardGrade grade) {
    if (_queue.isEmpty) {
      throw StateError('gradeCurrent called on a completed session');
    }
    final card = _queue.removeAt(0);
    if (grade == FlashcardGrade.practiceAgain) {
      _queue.add(card);
    }
  }
}

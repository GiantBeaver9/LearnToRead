// Tests for lib/features/flashcards/flashcard_session.dart (PRD §8 Unit 16
// "Session = all due cards"; "'practice again' -> ... re-queued after the
// remaining due cards this session"): same-session re-queue ordering and
// completion semantics.

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/features/flashcards/flashcard_deck.dart';
import 'package:learn_to_read/features/flashcards/flashcard_session.dart';
import 'package:learn_to_read/features/flashcards/leitner_scheduler.dart';

List<FlashcardCard> _cards(List<String> words) =>
    FlashcardDeck.fromWordTokens([
      for (final word in words)
        WordToken(
          text: word,
          graphemePhonemeMap: [(graphemes: word, phonemeId: 'AH')],
          pronunciationAudioRef: 'audio/words/$word.mp3',
        ),
    ]).cards;

void main() {
  group('FlashcardSession — "got it" walks the queue (positive)', () {
    test('cards present front-to-back and the session completes when the '
        'last is graded', () {
      final session = FlashcardSession(queue: _cards(['a', 'b', 'c']));

      expect(session.current?.wordText, 'a');
      session.gradeCurrent(FlashcardGrade.gotIt);
      expect(session.current?.wordText, 'b');
      session.gradeCurrent(FlashcardGrade.gotIt);
      expect(session.current?.wordText, 'c');
      expect(session.isComplete, isFalse);
      session.gradeCurrent(FlashcardGrade.gotIt);

      expect(session.isComplete, isTrue);
      expect(session.current, isNull);
      expect(session.remaining, 0);
    });
  });

  group('FlashcardSession — "practice again" re-queue ordering (positive)', () {
    test('the card moves to the END, after every remaining due card', () {
      final session = FlashcardSession(queue: _cards(['a', 'b', 'c']));

      session.gradeCurrent(FlashcardGrade.practiceAgain);

      expect(
        session.queue.map((c) => c.wordText).toList(),
        ['b', 'c', 'a'],
        reason: '"a" reappears only after the remaining due cards',
      );
    });

    test('a practice-again card reappears before the session can end', () {
      final session = FlashcardSession(queue: _cards(['a', 'b']));

      session.gradeCurrent(FlashcardGrade.practiceAgain); // a -> end
      session.gradeCurrent(FlashcardGrade.gotIt); // b done

      expect(session.isComplete, isFalse,
          reason: 'the re-queued card still owes a rep');
      expect(session.current?.wordText, 'a');

      session.gradeCurrent(FlashcardGrade.gotIt);
      expect(session.isComplete, isTrue);
    });

    test('repeated practice-again keeps re-queuing (the card repeats until '
        'graded "got it")', () {
      final session = FlashcardSession(queue: _cards(['a']));

      for (var i = 0; i < 3; i++) {
        expect(session.current?.wordText, 'a');
        session.gradeCurrent(FlashcardGrade.practiceAgain);
        expect(session.isComplete, isFalse);
      }
      session.gradeCurrent(FlashcardGrade.gotIt);

      expect(session.isComplete, isTrue);
    });
  });

  group('FlashcardSession (edge + negative)', () {
    test('an empty queue is complete from the start', () {
      final session = FlashcardSession(queue: const []);

      expect(session.isComplete, isTrue);
      expect(session.current, isNull);
    });

    test('grading a completed session throws StateError', () {
      final session = FlashcardSession(queue: const []);

      expect(
        () => session.gradeCurrent(FlashcardGrade.gotIt),
        throwsStateError,
      );
    });

    test('the constructor copies the caller\'s list', () {
      final source = List.of(_cards(['a', 'b']));
      final session = FlashcardSession(queue: source);

      source.clear();

      expect(session.remaining, 2);
    });
  });
}

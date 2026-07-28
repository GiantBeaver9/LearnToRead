// Tests for lib/features/flashcards/leitner_scheduler.dart (PRD §8 Unit 16
// "Scheduling (MVP Leitner, consts in the tuning file)"): grade
// transitions, the box-3 cap, due filtering at a time t, and the tuning
// consts themselves. All time flows through the injected clock — no test
// here ever sleeps or reads the wall clock.

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/tuning.dart';
import 'package:learn_to_read/features/flashcards/flashcard_deck.dart';
import 'package:learn_to_read/features/flashcards/flashcard_progress.dart';
import 'package:learn_to_read/features/flashcards/leitner_scheduler.dart';

final DateTime _t0 = DateTime(2026, 7, 28, 9, 0, 0);

LeitnerScheduler _schedulerAt(DateTime at) => LeitnerScheduler(now: () => at);

FlashcardProgress _progress(String key, int box, DateTime dueAt) =>
    FlashcardProgress(
      profileId: 'profile.1',
      cardKey: key,
      box: box,
      dueAt: dueAt,
    );

WordToken _token(String text) => WordToken(
      text: text,
      graphemePhonemeMap: [(graphemes: text, phonemeId: 'AH')],
      pronunciationAudioRef: 'audio/words/$text.mp3',
    );

void main() {
  group('tuning consts (PRD §8 Unit 16 pinned values)', () {
    test('box dues are 1 day / 3 days / 7-day re-dues, 3 boxes', () {
      expect(kFlashcardMaxBox, 3);
      expect(kFlashcardBox2Due, const Duration(days: 1));
      expect(kFlashcardBox3Due, const Duration(days: 3));
      expect(kFlashcardBox3Redue, const Duration(days: 7));
    });
  });

  group('applyGrade — "got it" promotions (positive)', () {
    test('box 1 -> box 2, due +1 day (kFlashcardBox2Due)', () {
      final next = _schedulerAt(_t0)
          .applyGrade(box: 1, grade: FlashcardGrade.gotIt);

      expect(next.box, 2);
      expect(next.dueAt, _t0.add(kFlashcardBox2Due));
    });

    test('box 2 -> box 3, due +3 days (kFlashcardBox3Due)', () {
      final next = _schedulerAt(_t0)
          .applyGrade(box: 2, grade: FlashcardGrade.gotIt);

      expect(next.box, 3);
      expect(next.dueAt, _t0.add(kFlashcardBox3Due));
    });

    test('box 3 stays box 3 (capped), due +7 days (kFlashcardBox3Redue)', () {
      final next = _schedulerAt(_t0)
          .applyGrade(box: 3, grade: FlashcardGrade.gotIt);

      expect(next.box, 3);
      expect(next.dueAt, _t0.add(kFlashcardBox3Redue));
    });
  });

  group('applyGrade — "practice again" (positive)', () {
    for (final box in [1, 2, 3]) {
      test('box $box -> box 1, due immediately (now)', () {
        final next = _schedulerAt(_t0)
            .applyGrade(box: box, grade: FlashcardGrade.practiceAgain);

        expect(next.box, 1);
        expect(next.dueAt, _t0, reason: 'box 1 is "due now"');
      });
    }
  });

  group('applyGrade — the injected clock is the only time source', () {
    test('two different clock values produce two different dueAts from the '
        'same transition', () {
      final later = _t0.add(const Duration(hours: 5));

      final a = _schedulerAt(_t0).applyGrade(box: 1, grade: FlashcardGrade.gotIt);
      final b =
          _schedulerAt(later).applyGrade(box: 1, grade: FlashcardGrade.gotIt);

      expect(a.dueAt, _t0.add(kFlashcardBox2Due));
      expect(b.dueAt, later.add(kFlashcardBox2Due));
    });
  });

  group('applyGrade — invalid box (negative)', () {
    for (final badBox in [0, -1, 4]) {
      test('box $badBox throws ArgumentError', () {
        expect(
          () => _schedulerAt(_t0)
              .applyGrade(box: badBox, grade: FlashcardGrade.gotIt),
          throwsArgumentError,
        );
      });
    }
  });

  group('due filtering at t (isDueAt / isDue)', () {
    test('no stored progress => due (implicit box 1, due now)', () {
      expect(isDueAt(null, _t0), isTrue);
      expect(_schedulerAt(_t0).isDue(null), isTrue);
    });

    test('dueAt before t => due', () {
      final p = _progress('k', 2, _t0.subtract(const Duration(minutes: 1)));
      expect(isDueAt(p, _t0), isTrue);
    });

    test('dueAt exactly at t => due (boundary inclusive)', () {
      expect(isDueAt(_progress('k', 2, _t0), _t0), isTrue);
    });

    test('dueAt after t => not due', () {
      final p = _progress('k', 2, _t0.add(const Duration(seconds: 1)));
      expect(isDueAt(p, _t0), isFalse);
      expect(_schedulerAt(_t0).isDue(p), isFalse);
    });
  });

  group('dueCardsAt — session queue building', () {
    test('returns exactly the due cards, preserving deck order', () {
      final deck = FlashcardDeck.fromWordTokens([
        _token('one'),
        _token('two'),
        _token('three'),
      ]);
      final progress = {
        // 'one': graded yesterday into box 2, due today -> due.
        deck.cards[0].cardKey:
            _progress(deck.cards[0].cardKey, 2, _t0.subtract(const Duration(hours: 1))),
        // 'two': promoted, due in 3 days -> not due.
        deck.cards[1].cardKey:
            _progress(deck.cards[1].cardKey, 3, _t0.add(kFlashcardBox3Due)),
        // 'three': no row -> new, due now.
      };

      final due = dueCardsAt(deck: deck, progressByKey: progress, at: _t0);

      expect(due.map((c) => c.wordText).toList(), ['one', 'three']);
    });

    test('an entirely new deck is entirely due', () {
      final deck = FlashcardDeck.fromWordTokens([_token('a'), _token('b')]);

      final due = dueCardsAt(deck: deck, progressByKey: const {}, at: _t0);

      expect(due, hasLength(2));
    });

    test('nothing due -> empty queue', () {
      final deck = FlashcardDeck.fromWordTokens([_token('a')]);
      final progress = {
        deck.cards.single.cardKey: _progress(
          deck.cards.single.cardKey,
          2,
          _t0.add(const Duration(days: 1)),
        ),
      };

      expect(
        dueCardsAt(deck: deck, progressByKey: progress, at: _t0),
        isEmpty,
      );
    });
  });
}

// Tests for lib/features/flashcards/flashcard_deck.dart (PRD §8 Unit 16
// "Deck source (MVP): the unique WordTokens across installed packs";
// acceptance "Deck builds from installed-pack fixtures: unique words,
// stable card keys").
//
// Card key = the A-14 word hash (event_schema.dart hashWord: SHA-256 of
// the LOWERCASED word text, truncated to 16 hex chars) — pinned here both
// via hashWord itself and via an externally-computed vector, so the deck
// can never drift from the analytics hash.

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/flashcards/flashcard_deck.dart';

WordToken _token(
  String text, {
  List<({String graphemes, String phonemeId})>? map,
  String? pronunciationAudioRef,
}) {
  return WordToken(
    text: text,
    graphemePhonemeMap: map ??
        [
          for (var i = 0; i < text.length; i++)
            (graphemes: text[i], phonemeId: 'AH'),
        ],
    pronunciationAudioRef:
        pronunciationAudioRef ?? 'audio/words/${text.toLowerCase()}.mp3',
  );
}

void main() {
  group('FlashcardDeck.fromWordTokens — dedupe (positive)', () {
    test('unique words become one card each, in first-appearance order', () {
      final deck = FlashcardDeck.fromWordTokens([
        _token('the'),
        _token('cat'),
        _token('sat'),
      ]);

      expect(deck.cards, hasLength(3));
      expect(deck.cards.map((c) => c.wordText).toList(), ['the', 'cat', 'sat']);
    });

    test('repeated words collapse to a single card', () {
      final deck = FlashcardDeck.fromWordTokens([
        _token('the'),
        _token('cat'),
        _token('the'),
        _token('the'),
      ]);

      expect(deck.cards, hasLength(2));
      expect(deck.cards.map((c) => c.wordText).toList(), ['the', 'cat']);
    });

    test('dedupe is by LOWERCASED text: "The", "THE", "the" are one card, '
        'keeping the first occurrence\'s casing', () {
      final deck = FlashcardDeck.fromWordTokens([
        _token('The'),
        _token('THE'),
        _token('the'),
      ]);

      expect(deck.cards, hasLength(1));
      expect(deck.cards.single.wordText, 'The');
    });

    test('the FIRST occurrence\'s graphemePhonemeMap and '
        'pronunciationAudioRef win over later duplicates', () {
      final first = _token(
        'cake',
        map: [
          (graphemes: 'c', phonemeId: 'K'),
          (graphemes: 'a', phonemeId: 'EY'),
          (graphemes: 'k', phonemeId: 'K'),
          (graphemes: 'e', phonemeId: ''),
        ],
        pronunciationAudioRef: 'audio/words/cake-pack1.mp3',
      );
      final later = _token(
        'Cake',
        map: [(graphemes: 'cake', phonemeId: 'K')],
        pronunciationAudioRef: 'audio/words/cake-pack2.mp3',
      );

      final deck = FlashcardDeck.fromWordTokens([first, later]);

      expect(deck.cards, hasLength(1));
      final card = deck.cards.single;
      expect(card.token, equals(first));
      expect(card.graphemePhonemeMap, hasLength(4));
      expect(card.graphemePhonemeMap[0].graphemes, 'c');
      expect(card.pronunciationAudioRef, 'audio/words/cake-pack1.mp3');
    });
  });

  group('FlashcardDeck — card keys (positive: A-14 stability)', () {
    test('card key equals hashWord of the word text', () {
      final deck = FlashcardDeck.fromWordTokens([_token('cat'), _token('the')]);

      expect(deck.cards[0].cardKey, hashWord('cat'));
      expect(deck.cards[1].cardKey, hashWord('the'));
    });

    test('card key matches the externally-computed A-14 vector for "cat" '
        '(16 lowercase hex chars)', () {
      final deck = FlashcardDeck.fromWordTokens([_token('cat')]);

      // Same vector event_schema_test.dart pins for hashWord('cat').
      expect(deck.cards.single.cardKey, '77af778b51abd4a3');
      expect(deck.cards.single.cardKey, hasLength(16));
    });

    test('differently-cased occurrences of the same word share one stable '
        'key (hashWord lowercases)', () {
      final deckA = FlashcardDeck.fromWordTokens([_token('Cat')]);
      final deckB = FlashcardDeck.fromWordTokens([_token('CAT')]);
      final deckC = FlashcardDeck.fromWordTokens([_token('cat')]);

      expect(deckA.cards.single.cardKey, deckB.cards.single.cardKey);
      expect(deckB.cards.single.cardKey, deckC.cards.single.cardKey);
    });

    test('keys are stable across deck rebuilds from equal fixtures', () {
      List<WordToken> fixture() => [_token('ship'), _token('cake')];

      final keys1 =
          FlashcardDeck.fromWordTokens(fixture()).cards.map((c) => c.cardKey);
      final keys2 =
          FlashcardDeck.fromWordTokens(fixture()).cards.map((c) => c.cardKey);

      expect(keys1.toList(), keys2.toList());
    });
  });

  group('FlashcardDeck.cardByKey (positive + edge)', () {
    test('finds a card by its key', () {
      final deck = FlashcardDeck.fromWordTokens([_token('cat'), _token('the')]);

      expect(deck.cardByKey(hashWord('the'))?.wordText, 'the');
    });

    test('returns null for an unknown key', () {
      final deck = FlashcardDeck.fromWordTokens([_token('cat')]);

      expect(deck.cardByKey('0000000000000000'), isNull);
    });
  });

  group('FlashcardDeck (edge)', () {
    test('an empty token list builds an empty deck', () {
      expect(FlashcardDeck.fromWordTokens(const []).cards, isEmpty);
    });

    test('cards list is unmodifiable', () {
      final deck = FlashcardDeck.fromWordTokens([_token('cat')]);

      expect(() => deck.cards.clear(), throwsUnsupportedError);
    });
  });
}

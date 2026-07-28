/// The MVP flashcard deck builder (PRD §8 Unit 16 "Deck source (MVP): the
/// unique `WordToken`s across installed packs").
///
/// Explicitly a seam: owner-curated decks arrive LATER as a different way
/// of producing the same [FlashcardDeck]; nothing downstream (session,
/// scheduler, screen) knows where the cards came from.
library;

import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';

/// One flashcard: a unique word plus its stable card key.
///
/// Wraps the FIRST-encountered [WordToken] for the word, so the card
/// carries that occurrence's `graphemePhonemeMap` and
/// `pronunciationAudioRef` (PRD §8 Unit 16 — every card is about how to
/// sound the word out, and `PhonemeSequencer.playSequence` takes the token
/// directly).
class FlashcardCard {
  const FlashcardCard({required this.cardKey, required this.token});

  /// The A-14-style word hash (PRD §8 Unit 16 "card key = A-14-style word
  /// hash"): [hashWord] of the word text, which SHA-256 hashes the
  /// LOWERCASED text truncated to 16 hex chars — so "Cat" and "cat" share
  /// one card key, matching the deck's case-insensitive dedupe.
  final String cardKey;

  /// The first-encountered token for this word.
  final WordToken token;

  /// The word as first encountered (original casing preserved for display).
  String get wordText => token.text;

  /// Ordered `(graphemes, phonemeId)` pairs driving the back-side chips and
  /// the front-side sound-out.
  List<({String graphemes, String phonemeId})> get graphemePhonemeMap =>
      token.graphemePhonemeMap;

  /// The whole-word pronunciation clip for the back-side play button.
  String get pronunciationAudioRef => token.pronunciationAudioRef;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FlashcardCard &&
          other.cardKey == cardKey &&
          other.token == token);

  @override
  int get hashCode => Object.hash(cardKey, token);
}

/// An ordered deck of unique-word flashcards.
class FlashcardDeck {
  /// Builds the deck from [tokens], deduplicating by LOWERCASED word text
  /// and keeping the first occurrence of each word (its
  /// `graphemePhonemeMap` + `pronunciationAudioRef` win). Card order is
  /// first-appearance order, so the deck is deterministic for a given
  /// token list.
  factory FlashcardDeck.fromWordTokens(Iterable<WordToken> tokens) {
    final seen = <String>{};
    final cards = <FlashcardCard>[];
    for (final token in tokens) {
      final lowered = token.text.toLowerCase();
      if (!seen.add(lowered)) continue;
      cards.add(FlashcardCard(cardKey: hashWord(token.text), token: token));
    }
    return FlashcardDeck._(cards);
  }

  FlashcardDeck._(List<FlashcardCard> cards)
      : cards = List.unmodifiable(cards);

  /// The unique-word cards, in first-appearance order. Unmodifiable.
  final List<FlashcardCard> cards;

  /// Looks a card up by its A-14 card key; null if the deck has no such
  /// word.
  FlashcardCard? cardByKey(String cardKey) {
    for (final card in cards) {
      if (card.cardKey == cardKey) return card;
    }
    return null;
  }
}

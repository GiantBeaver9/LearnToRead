/// Phonics-first deck ordering (PRD §8 Unit 16 speech-first layer, ratified
/// 2026-07-28: "Deck ordering is phonics-first: words decodable at the
/// profile's current level come before ahead-of-level words";
/// docs/design/mockup-spec.md §10b).
///
/// Pure functions over [FlashcardCard] + a cumulative grapheme set (the
/// `Set<String>` produced by `cumulativeGraphemeSet` in
/// lib/pipeline/cumulative_grapheme_set.dart). Deliberately decoupled: the
/// SET is the input, never a `Profile` or `Level` — the orchestrator's
/// wiring derives the set and hands it in, so this feature knows nothing
/// about levels.
library;

import 'package:learn_to_read/features/flashcards/flashcard_deck.dart';

/// Whether [card] is decodable with [cumulativeGraphemes]: EVERY
/// `graphemePhonemeMap` graphemes entry is in the set — including silent
/// letters' graphemes (an entry with an empty phonemeId still names a
/// grapheme the child must recognize on the page).
///
/// Grapheme units are opaque strings, matching the cumulative set's
/// convention: a digraph ("sh") or a silent-e pattern ("a_e") is one
/// element, never decomposed.
bool isDecodableWith(FlashcardCard card, Set<String> cumulativeGraphemes) {
  for (final entry in card.graphemePhonemeMap) {
    if (!cumulativeGraphemes.contains(entry.graphemes)) return false;
  }
  return true;
}

/// Orders [cards] phonics-first: every card decodable with
/// [cumulativeGraphemes] (per [isDecodableWith]) comes before every card
/// that is ahead of level, and WITHIN each group the cards keep their
/// relative order from [cards] (stable). Returns a new list; [cards] is
/// never mutated.
List<FlashcardCard> phonicsFirstOrder(
  List<FlashcardCard> cards,
  Set<String> cumulativeGraphemes,
) {
  final inLevel = <FlashcardCard>[];
  final aheadOfLevel = <FlashcardCard>[];
  for (final card in cards) {
    (isDecodableWith(card, cumulativeGraphemes) ? inLevel : aheadOfLevel)
        .add(card);
  }
  return [...inLevel, ...aheadOfLevel];
}

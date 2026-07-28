// Tests for lib/features/flashcards/phonics_first_order.dart and its
// wire-through (PRD §8 Unit 16 speech-first layer, ratified 2026-07-28:
// "Deck ordering is phonics-first: words decodable at the profile's
// current level come before ahead-of-level words"; the ordering input is
// the cumulative grapheme SET itself — the feature stays decoupled from
// Profile/Level).
//
// The committed scaffold tests are frozen; everything here is additive.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/flashcards/flashcard_deck.dart';
import 'package:learn_to_read/features/flashcards/flashcard_progress.dart';
import 'package:learn_to_read/features/flashcards/flashcards_screen.dart';
import 'package:learn_to_read/features/flashcards/leitner_scheduler.dart';
import 'package:learn_to_read/features/flashcards/phonics_first_order.dart';

final DateTime _t0 = DateTime(2026, 7, 28, 9, 0, 0);

WordToken _token(String text, List<({String graphemes, String phonemeId})> map,
        {String audioRef = ''}) =>
    WordToken(
      text: text,
      graphemePhonemeMap: map,
      pronunciationAudioRef:
          audioRef.isEmpty ? 'audio/words/$text.mp3' : audioRef,
    );

WordToken _cat() => _token('cat', [
      (graphemes: 'c', phonemeId: 'K'),
      (graphemes: 'a', phonemeId: 'AE'),
      (graphemes: 't', phonemeId: 'T'),
    ]);

WordToken _sat() => _token('sat', [
      (graphemes: 's', phonemeId: 'S'),
      (graphemes: 'a', phonemeId: 'AE'),
      (graphemes: 't', phonemeId: 'T'),
    ]);

WordToken _ship() => _token('ship', [
      (graphemes: 'sh', phonemeId: 'SH'),
      (graphemes: 'i', phonemeId: 'IH'),
      (graphemes: 'p', phonemeId: 'P'),
    ]);

WordToken _cake() => _token('cake', [
      (graphemes: 'c', phonemeId: 'K'),
      (graphemes: 'a_e', phonemeId: 'EY'),
      (graphemes: 'k', phonemeId: 'K'),
      (graphemes: 'e', phonemeId: ''), // silent letter
    ]);

FlashcardCard _card(WordToken token) =>
    FlashcardCard(cardKey: hashWord(token.text), token: token);

/// Base early-level set: single letters only — no digraph 'sh', no
/// silent-e pattern 'a_e'.
const Set<String> _earlySet = {'c', 'a', 't', 's', 'i', 'p'};

void main() {
  group('isDecodableWith — every graphemePhonemeMap graphemes entry ∈ set',
      () {
    test('POSITIVE: a word whose every grapheme is in the set is decodable',
        () {
      expect(isDecodableWith(_card(_cat()), _earlySet), isTrue);
    });

    test('NEGATIVE: one out-of-set grapheme (the digraph "sh") makes the '
        'word ahead-of-level', () {
      expect(isDecodableWith(_card(_ship()), _earlySet), isFalse);
    });

    test('EDGE: grapheme units are opaque — having "s" and "h" does NOT '
        'cover the digraph "sh"', () {
      expect(
        isDecodableWith(_card(_ship()), const {'s', 'h', 'i', 'p'}),
        isFalse,
      );
    });

    test('EDGE: a silent letter\'s graphemes entry counts too — "cake" '
        'needs BOTH the a_e pattern and the trailing "e" entry in the set',
        () {
      expect(
        isDecodableWith(_card(_cake()), const {'c', 'a_e', 'k'}),
        isFalse,
        reason: 'the silent "e" entry is still a graphemes entry',
      );
      expect(
        isDecodableWith(_card(_cake()), const {'c', 'a_e', 'k', 'e'}),
        isTrue,
      );
    });
  });

  group('phonicsFirstOrder — decodable first, stable within groups', () {
    test('POSITIVE: in-level cards come before ahead-of-level cards', () {
      final cards = [_card(_ship()), _card(_cat()), _card(_cake())];
      final ordered = phonicsFirstOrder(cards, _earlySet);
      expect(
        [for (final c in ordered) c.wordText],
        ['cat', 'ship', 'cake'],
        reason: 'cat is decodable with the early set; ship (sh) and cake '
            '(a_e) are ahead of level and keep their relative order',
      );
    });

    test('POSITIVE: ordering is STABLE within both groups', () {
      // Interleaved: ahead, in, ahead, in — relative order inside each
      // group must survive.
      final cards = [
        _card(_ship()), // ahead
        _card(_cat()), // in
        _card(_cake()), // ahead
        _card(_sat()), // in
      ];
      final ordered = phonicsFirstOrder(cards, _earlySet);
      expect(
        [for (final c in ordered) c.wordText],
        ['cat', 'sat', 'ship', 'cake'],
      );
    });

    test('EDGE: with every card decodable the order is unchanged', () {
      final cards = [_card(_sat()), _card(_cat())];
      final ordered = phonicsFirstOrder(cards, _earlySet);
      expect([for (final c in ordered) c.wordText], ['sat', 'cat']);
    });

    test('EDGE: with an empty set nothing is decodable and the order is '
        'unchanged', () {
      final cards = [_card(_cat()), _card(_ship())];
      final ordered = phonicsFirstOrder(cards, const {});
      expect([for (final c in ordered) c.wordText], ['cat', 'ship']);
    });

    test('EDGE: empty input gives empty output; the input list is never '
        'mutated', () {
      expect(phonicsFirstOrder(const [], _earlySet), isEmpty);
      final cards = [_card(_ship()), _card(_cat())];
      phonicsFirstOrder(cards, _earlySet);
      expect([for (final c in cards) c.wordText], ['ship', 'cat']);
    });
  });

  group('dueCardsAt wire-through — the ordering input is optional', () {
    final deck = FlashcardDeck.fromWordTokens([_ship(), _cat(), _sat()]);

    test('POSITIVE: passing cumulativeGraphemes orders the due queue '
        'phonics-first', () {
      final due = dueCardsAt(
        deck: deck,
        progressByKey: const {},
        at: _t0,
        cumulativeGraphemes: _earlySet,
      );
      expect([for (final c in due) c.wordText], ['cat', 'sat', 'ship']);
    });

    test('NEGATIVE: omitting it keeps the committed deck order (scaffold '
        'behavior unchanged)', () {
      final due = dueCardsAt(deck: deck, progressByKey: const {}, at: _t0);
      expect([for (final c in due) c.wordText], ['ship', 'cat', 'sat']);
    });

    test('POSITIVE: due filtering still applies before ordering', () {
      final due = dueCardsAt(
        deck: deck,
        progressByKey: {
          hashWord('cat'): FlashcardProgress(
            profileId: 'p',
            cardKey: hashWord('cat'),
            box: 2,
            dueAt: _t0.add(const Duration(days: 1)), // not due
          ),
        },
        at: _t0,
        cumulativeGraphemes: _earlySet,
      );
      expect([for (final c in due) c.wordText], ['sat', 'ship']);
    });
  });

  group('FlashcardsScreen wire-through (optional cumulativeGraphemes param)',
      () {
    testWidgets('POSITIVE: with the set provided, the first card facing the '
        'child is the decodable-at-level one', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      await tester.pumpWidget(MaterialApp(
        home: FlashcardsScreen(
          profileId: 'profile.amara',
          deck: FlashcardDeck.fromWordTokens([_ship(), _cat()]),
          audioService: FakeAudioService(),
          phonemeAudioRefs: const {},
          dao: db.flashcardsDao,
          now: () => _t0,
          confettiSeed: 7,
          cumulativeGraphemes: _earlySet,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.text('cat'), findsOneWidget,
          reason: 'cat is decodable with the early set, so it leads even '
              'though ship comes first in the deck');
      expect(find.text('ship'), findsNothing);
    });
  });
}

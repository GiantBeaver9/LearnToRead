// Widget tests for the tappable back-side grapheme chips (owner direction
// 2026-07-29: "sounding out the phonics of everything" — every chip plays
// its own sound).
//
// Pinned contract this suite locks in (additive to the frozen flashcards
// suites, which must keep passing untouched):
//  - tapping ONE chip on the card's back plays exactly THAT cluster's
//    phoneme clip — a single clip on the help channel, never the whole
//    sound-out sequence;
//  - the tap then continues into the card's flip toggle, exactly the
//    observable behavior a chip tap has always had (the frozen
//    speech-first suite pins that a chip tap reaches the flip detector);
//  - a silent-letter chip (empty phonemeId, the "e" in "cake") plays
//    nothing — no audio call, no crash;
//  - a phoneme with no shipped clip plays nothing and never throws.
//
// Harness mirrors test/features/flashcards/no_negative_state_test.dart:
// real FlashcardsDao over NativeDatabase.memory(), fixed clock, stepped
// pumps only (the idle sway repeats forever — never pumpAndSettle).

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/flashcards/flashcard_deck.dart';
import 'package:learn_to_read/features/flashcards/flashcards_screen.dart';
import 'package:learn_to_read/features/flashcards/flip_card.dart';

WordToken _ship() => WordToken(
      text: 'ship',
      graphemePhonemeMap: const [
        (graphemes: 'sh', phonemeId: 'SH'),
        (graphemes: 'i', phonemeId: 'IH'),
        (graphemes: 'p', phonemeId: 'P'),
      ],
      pronunciationAudioRef: 'audio/words/ship.mp3',
    );

WordToken _cake() => WordToken(
      text: 'cake',
      graphemePhonemeMap: const [
        (graphemes: 'c', phonemeId: 'K'),
        (graphemes: 'a', phonemeId: 'EY'),
        (graphemes: 'k', phonemeId: 'K'),
        (graphemes: 'e', phonemeId: ''), // silent letter
      ],
      pronunciationAudioRef: 'audio/words/cake.mp3',
    );

const Map<String, AudioRef> _phonemeRefs = {
  'SH': 'audio/phonemes/SH.mp3',
  'IH': 'audio/phonemes/IH.mp3',
  'P': 'audio/phonemes/P.mp3',
  'K': 'audio/phonemes/K.mp3',
  'EY': 'audio/phonemes/EY.mp3',
};

List<PlayLogEntry> _plays(FakeAudioService audio) =>
    audio.callLog.whereType<PlayLogEntry>().toList();

void main() {
  late AppDatabase db;
  late FakeAudioService audio;
  final clock = DateTime(2026, 7, 29, 9, 0, 0);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    audio = FakeAudioService();
  });

  tearDown(() async {
    await db.close();
  });

  Widget screen({
    List<WordToken>? tokens,
    Map<String, AudioRef> phonemeAudioRefs = _phonemeRefs,
  }) {
    return MaterialApp(
      home: FlashcardsScreen(
        profileId: 'profile.amara',
        deck: FlashcardDeck.fromWordTokens(tokens ?? [_ship()]),
        audioService: audio,
        phonemeAudioRefs: phonemeAudioRefs,
        dao: db.flashcardsDao,
        now: () => clock,
        confettiSeed: 7,
      ),
    );
  }

  /// Pumps past load, then flips the current card to its back.
  Future<void> flipToBack(WidgetTester tester, String cardKey) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(ValueKey('flashcard-flip-$cardKey')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  bool showBack(WidgetTester tester) =>
      tester.widget<FlipCard>(find.byType(FlipCard)).showBack;

  testWidgets('POSITIVE: tapping one chip plays exactly that cluster\'s '
      'phoneme clip on the help channel, and the tap still flips the card '
      '(the pinned chip-tap-reaches-the-flip behavior)', (tester) async {
    await tester.pumpWidget(screen());
    final cardKey = hashWord('ship');
    await flipToBack(tester, cardKey);
    expect(showBack(tester), isTrue);
    expect(_plays(audio), isEmpty, reason: 'flipping plays nothing');

    await tester.tap(find.byKey(ValueKey('flashcard-chip-tap-$cardKey-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(_plays(audio).map((e) => e.ref).toList(), ['audio/phonemes/IH.mp3'],
        reason: 'exactly the tapped chip\'s clip — one clip, no sequence');
    expect(_plays(audio).single.channel, AudioChannel.help);
    expect(showBack(tester), isFalse,
        reason: 'a chip tap has always reached the flip toggle');

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('POSITIVE: a different chip plays its own clip — the digraph '
      'chip is one unit', (tester) async {
    await tester.pumpWidget(screen());
    final cardKey = hashWord('ship');
    await flipToBack(tester, cardKey);

    await tester.tap(find.byKey(ValueKey('flashcard-chip-tap-$cardKey-0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(_plays(audio).map((e) => e.ref).toList(), ['audio/phonemes/SH.mp3']);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('NEGATIVE: a silent-letter chip plays nothing — no audio '
      'call, no crash (the flip continues as any card tap would)',
      (tester) async {
    await tester.pumpWidget(screen(tokens: [_cake()]));
    final cardKey = hashWord('cake');
    await flipToBack(tester, cardKey);

    await tester.tap(find.byKey(ValueKey('flashcard-chip-tap-$cardKey-3')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(_plays(audio), isEmpty);
    expect(tester.takeException(), isNull);
    expect(showBack(tester), isFalse);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('NEGATIVE: a phoneme with no shipped clip plays nothing and '
      'never throws', (tester) async {
    await tester.pumpWidget(screen(phonemeAudioRefs: const {}));
    final cardKey = hashWord('ship');
    await flipToBack(tester, cardKey);

    await tester.tap(find.byKey(ValueKey('flashcard-chip-tap-$cardKey-0')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(_plays(audio), isEmpty);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 2));
  });
}

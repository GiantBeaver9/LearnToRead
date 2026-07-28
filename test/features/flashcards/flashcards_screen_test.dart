// Widget tests for lib/features/flashcards/flashcards_screen.dart (PRD §8
// Unit 16 acceptance: "Front->flip->grade cycle: front sound-out plays the
// mapped phoneme refs in order; flip reveals exactly the word's
// graphemePhonemeMap chips; each grade button moves the box and
// reschedules per the Leitner consts"; "'practice again' cards reappear
// later in the same session; cleared queue -> confetti once + all-done").
//
// Harness notes (repo conventions):
//  * FakeAudioService drain pattern copied from
//    sound_garden_screen_test.dart — completing each play handle in turn
//    proves gapless sequencing as a side effect.
//  * Stepped pump for the flip/entrance animations (FlipCard 420ms, FadeUp
//    380ms) — never pumpAndSettle while confetti might be mounted; the
//    confetti overlay is finite (<= 5.3s), so pumping 6s is always past
//    its end (see test/design/confetti_test.dart's bound).
//  * Persistence is the REAL FlashcardsDao over NativeDatabase.memory();
//    the clock is a mutable fake — no wall-clock time anywhere.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/design/confetti.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/tuning.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/flashcards/flashcard_deck.dart';
import 'package:learn_to_read/features/flashcards/flashcard_progress.dart';
import 'package:learn_to_read/features/flashcards/flashcards_screen.dart';

const _profileId = 'profile.amara';

final DateTime _t0 = DateTime(2026, 7, 28, 9, 0, 0);

WordToken _ship() => WordToken(
      text: 'ship',
      graphemePhonemeMap: [
        (graphemes: 'sh', phonemeId: 'SH'),
        (graphemes: 'i', phonemeId: 'IH'),
        (graphemes: 'p', phonemeId: 'P'),
      ],
      pronunciationAudioRef: 'audio/words/ship.mp3',
    );

WordToken _cake() => WordToken(
      text: 'cake',
      graphemePhonemeMap: [
        (graphemes: 'c', phonemeId: 'K'),
        (graphemes: 'a', phonemeId: 'EY'),
        (graphemes: 'k', phonemeId: 'K'),
        (graphemes: 'e', phonemeId: ''), // silent letter
      ],
      pronunciationAudioRef: 'audio/words/cake.mp3',
    );

WordToken _cat() => WordToken(
      text: 'cat',
      graphemePhonemeMap: [
        (graphemes: 'c', phonemeId: 'K'),
        (graphemes: 'a', phonemeId: 'AE'),
        (graphemes: 't', phonemeId: 'T'),
      ],
      pronunciationAudioRef: 'audio/words/cat.mp3',
    );

Map<String, AudioRef> _phonemeAudioRefs() => const {
      'SH': 'audio/phonemes/SH.mp3',
      'IH': 'audio/phonemes/IH.mp3',
      'P': 'audio/phonemes/P.mp3',
      'K': 'audio/phonemes/K.mp3',
      'EY': 'audio/phonemes/EY.mp3',
      'AE': 'audio/phonemes/AE.mp3',
      'T': 'audio/phonemes/T.mp3',
    };

Widget _wrap(Widget child) => MaterialApp(home: child);

/// Pumps past the load future plus the flip/entrance animations.
Future<void> _settleShortAnimations(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));
}

/// Taps the flip affordance (a tap anywhere on the card outside the word
/// flips; the affordance key is a reliable such spot — the card's CENTER
/// is the word, whose own tap is the sound-out) and pumps through the
/// 420ms flip in fixed steps.
Future<void> _flip(WidgetTester tester, String cardKey) async {
  await tester.tap(find.byKey(ValueKey('flashcard-flip-$cardKey')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));
}

/// Flips the current card and presses a grade pill, pumping through the
/// dao write and the next card's entrance.
Future<void> _flipAndGrade(
  WidgetTester tester,
  String cardKey,
  String gradeKey,
) async {
  await _flip(tester, cardKey);
  await tester.tap(find.byKey(ValueKey(gradeKey)));
  await tester.pump(); // dao write resolves
  await tester.pump(); // setState -> next card / all-done
  await _settleShortAnimations(tester);
}

void main() {
  late AppDatabase db;
  late FakeAudioService audioService;
  late DateTime clock;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    audioService = FakeAudioService();
    clock = _t0;
  });

  tearDown(() async {
    await db.close();
  });

  Widget screen({List<WordToken>? tokens, int confettiSeed = 424242}) {
    return _wrap(FlashcardsScreen(
      profileId: _profileId,
      deck: FlashcardDeck.fromWordTokens(tokens ?? [_ship(), _cake(), _cat()]),
      audioService: audioService,
      phonemeAudioRefs: _phonemeAudioRefs(),
      dao: db.flashcardsDao,
      now: () => clock,
      confettiSeed: confettiSeed,
    ));
  }

  group('front face (PRD §8 Unit 16 "the word large in the reading '
      'typeface")', () {
    testWidgets('POSITIVE: the first due card renders its word in the '
        'reading font, ink color', (tester) async {
      await tester.pumpWidget(screen());
      await _settleShortAnimations(tester);

      final wordFinder = find.text('ship');
      expect(wordFinder, findsOneWidget);
      final text = tester.widget<Text>(wordFinder);
      expect(text.style?.fontFamily, DesignTokens.readingFontFamily);
      expect(text.style?.color, DesignTokens.wordUnreadInk);
    });

    testWidgets('POSITIVE: tapping the word plays the mapped phoneme refs '
        'in graphemePhonemeMap order, gaplessly', (tester) async {
      await tester.pumpWidget(screen());
      await _settleShortAnimations(tester);
      final cardKey = hashWord('ship');

      await tester.tap(find.byKey(ValueKey('flashcard-word-$cardKey')));
      await tester.pump();

      // Sequential: only the first phoneme so far.
      var plays = audioService.callLog.whereType<PlayLogEntry>().toList();
      expect(plays, hasLength(1));
      expect(plays[0].ref, 'audio/phonemes/SH.mp3');
      expect(plays[0].channel, AudioChannel.help);

      audioService.completePlayback(plays[0].handle);
      await tester.pump();
      plays = audioService.callLog.whereType<PlayLogEntry>().toList();
      expect(plays, hasLength(2), reason: 'IH only after SH completes');
      expect(plays[1].ref, 'audio/phonemes/IH.mp3');

      audioService.completePlayback(plays[1].handle);
      await tester.pump();
      plays = audioService.callLog.whereType<PlayLogEntry>().toList();
      expect(plays, hasLength(3));
      expect(plays[2].ref, 'audio/phonemes/P.mp3');

      audioService.completePlayback(plays[2].handle);
      await tester.pump();
      expect(
        audioService.callLog.whereType<PlayLogEntry>().toList(),
        hasLength(3),
        reason: 'no further phonemes to play',
      );
    });

    testWidgets('NEGATIVE: grade buttons are NOT present on the front', (tester) async {
      await tester.pumpWidget(screen());
      await _settleShortAnimations(tester);

      expect(find.byKey(const ValueKey('flashcard-grade-practice-again')),
          findsNothing);
      expect(find.byKey(const ValueKey('flashcard-grade-got-it')), findsNothing);
    });
  });

  group('flip -> back face (grapheme chips + pronunciation)', () {
    testWidgets('POSITIVE: flip reveals EXACTLY the word\'s '
        'graphemePhonemeMap chips, phoneme ids in mono type, and the grade '
        'bar', (tester) async {
      await tester.pumpWidget(screen());
      await _settleShortAnimations(tester);
      final cardKey = hashWord('ship');

      await _flip(tester, cardKey);

      final map = _ship().graphemePhonemeMap;
      for (var i = 0; i < map.length; i++) {
        expect(find.byKey(ValueKey('flashcard-chip-$cardKey-$i')),
            findsOneWidget);
        final grapheme = tester.widget<Text>(
            find.byKey(ValueKey('flashcard-chip-graphemes-$cardKey-$i')));
        expect(grapheme.data, map[i].graphemes);
        final phoneme = tester.widget<Text>(
            find.byKey(ValueKey('flashcard-chip-phoneme-$cardKey-$i')));
        expect(phoneme.data, map[i].phonemeId);
        expect(phoneme.style?.fontFamily, DesignTokens.monoFontFamily);
      }
      // EXACTLY the map's chips: no extra chip index exists.
      expect(find.byKey(ValueKey('flashcard-chip-$cardKey-${map.length}')),
          findsNothing);

      expect(find.byKey(const ValueKey('flashcard-grade-practice-again')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('flashcard-grade-got-it')), findsOneWidget);
    });

    testWidgets('EDGE: a silent letter (empty phonemeId) keeps its chip but '
        'carries no phoneme label', (tester) async {
      await tester.pumpWidget(screen(tokens: [_cake()]));
      await _settleShortAnimations(tester);
      final cardKey = hashWord('cake');

      await _flip(tester, cardKey);

      expect(find.byKey(ValueKey('flashcard-chip-$cardKey-3')), findsOneWidget);
      expect(find.byKey(ValueKey('flashcard-chip-phoneme-$cardKey-3')),
          findsNothing, reason: 'the silent "e" plays/labels no phoneme');
    });

    testWidgets('POSITIVE: the pronunciation button plays the whole-word '
        'clip', (tester) async {
      await tester.pumpWidget(screen());
      await _settleShortAnimations(tester);
      final cardKey = hashWord('ship');
      await _flip(tester, cardKey);

      await tester.tap(find.byKey(ValueKey('flashcard-pronounce-$cardKey')));
      await tester.pump();

      final plays = audioService.callLog.whereType<PlayLogEntry>().toList();
      expect(plays, hasLength(1));
      expect(plays.single.ref, 'audio/words/ship.mp3');
      expect(plays.single.channel, AudioChannel.help);
    });
  });

  group('grading moves the box and reschedules (fake clock)', () {
    testWidgets('POSITIVE: "got it" on a new card writes box 2, due '
        '+kFlashcardBox2Due, and advances to the next due card', (tester) async {
      await tester.pumpWidget(screen());
      await _settleShortAnimations(tester);
      final cardKey = hashWord('ship');

      await _flipAndGrade(tester, cardKey, 'flashcard-grade-got-it');

      final stored = await db.flashcardsDao
          .getProgress(profileId: _profileId, cardKey: cardKey);
      expect(stored?.box, 2);
      expect(stored?.dueAt, _t0.add(kFlashcardBox2Due));

      expect(find.text('cake'), findsOneWidget,
          reason: 'the next due card takes the front');
      expect(find.text('ship'), findsNothing);
    });

    testWidgets('POSITIVE: "practice again" writes box 1, due now', (tester) async {
      await tester.pumpWidget(screen());
      await _settleShortAnimations(tester);
      final cardKey = hashWord('ship');

      await _flipAndGrade(tester, cardKey, 'flashcard-grade-practice-again');

      final stored = await db.flashcardsDao
          .getProgress(profileId: _profileId, cardKey: cardKey);
      expect(stored?.box, 1);
      expect(stored?.dueAt, _t0);
    });

    testWidgets('POSITIVE: a stored box-2 card graded "got it" moves to '
        'box 3 with the +3 day due', (tester) async {
      await db.flashcardsDao.upsertProgress(FlashcardProgress(
        profileId: _profileId,
        cardKey: hashWord('ship'),
        box: 2,
        dueAt: _t0, // due exactly now
      ));
      await tester.pumpWidget(screen(tokens: [_ship()]));
      await _settleShortAnimations(tester);

      await _flipAndGrade(tester, hashWord('ship'), 'flashcard-grade-got-it');

      final stored = await db.flashcardsDao
          .getProgress(profileId: _profileId, cardKey: hashWord('ship'));
      expect(stored?.box, 3);
      expect(stored?.dueAt, _t0.add(kFlashcardBox3Due));
    });
  });

  group('session queue (due filtering + same-session re-queue)', () {
    testWidgets('NEGATIVE: a card whose dueAt is in the future never enters '
        'the session', (tester) async {
      // 'cake' was promoted yesterday and is not due until tomorrow.
      await db.flashcardsDao.upsertProgress(FlashcardProgress(
        profileId: _profileId,
        cardKey: hashWord('cake'),
        box: 2,
        dueAt: _t0.add(const Duration(days: 1)),
      ));
      await tester.pumpWidget(screen());
      await _settleShortAnimations(tester);

      // Session: ship then cat; cake never appears.
      expect(find.text('ship'), findsOneWidget);
      await _flipAndGrade(tester, hashWord('ship'), 'flashcard-grade-got-it');
      expect(find.text('cake'), findsNothing);
      expect(find.text('cat'), findsOneWidget);
      await _flipAndGrade(tester, hashWord('cat'), 'flashcard-grade-got-it');

      expect(find.text('cake'), findsNothing);
      expect(find.byKey(const ValueKey('flashcards-all-done')), findsOneWidget);
    });

    testWidgets('POSITIVE: a practice-again card reappears AFTER the '
        'remaining due cards and BEFORE the session can end', (tester) async {
      await tester.pumpWidget(screen(tokens: [_ship(), _cat()]));
      await _settleShortAnimations(tester);

      await _flipAndGrade(tester, hashWord('ship'), 'flashcard-grade-practice-again');
      expect(find.text('cat'), findsOneWidget,
          reason: 'the remaining due card comes first');

      await _flipAndGrade(tester, hashWord('cat'), 'flashcard-grade-got-it');
      expect(find.byKey(const ValueKey('flashcards-all-done')), findsNothing,
          reason: 'the re-queued card still owes a rep');
      expect(find.text('ship'), findsOneWidget);

      await _flipAndGrade(tester, hashWord('ship'), 'flashcard-grade-got-it');
      expect(find.byKey(const ValueKey('flashcards-all-done')), findsOneWidget);
    });
  });

  group('cleared queue -> all-done + confetti exactly once', () {
    testWidgets('POSITIVE: clearing the queue shows the warm all-done state '
        'with ONE intensity-1 confetti overlay, which never returns after '
        'finishing', (tester) async {
      await tester.pumpWidget(screen(tokens: [_ship()]));
      await _settleShortAnimations(tester);

      await _flipAndGrade(tester, hashWord('ship'), 'flashcard-grade-got-it');

      expect(find.byKey(const ValueKey('flashcards-all-done')), findsOneWidget);
      final confettiFinder = find.byType(ConfettiOverlay);
      expect(confettiFinder, findsOneWidget);
      final confetti = tester.widget<ConfettiOverlay>(confettiFinder);
      expect(confetti.intensity, 1);
      expect(confetti.seed, 424242, reason: 'seed stable per session');

      // The overlay is finite: pump past its longest possible runtime.
      await tester.pump(const Duration(seconds: 6));
      await tester.pump();
      expect(find.byType(ConfettiOverlay), findsNothing,
          reason: 'confetti plays exactly once');
      expect(find.byKey(const ValueKey('flashcards-all-done')), findsOneWidget,
          reason: 'the all-done state stays');

      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(ConfettiOverlay), findsNothing);
    });

    testWidgets('EDGE: opening with nothing due shows the calm all-done '
        'state WITHOUT confetti (nothing was cleared)', (tester) async {
      for (final word in ['ship', 'cake', 'cat']) {
        await db.flashcardsDao.upsertProgress(FlashcardProgress(
          profileId: _profileId,
          cardKey: hashWord(word),
          box: 3,
          dueAt: _t0.add(const Duration(days: 7)),
        ));
      }
      await tester.pumpWidget(screen());
      await _settleShortAnimations(tester);

      expect(find.byKey(const ValueKey('flashcards-all-done')), findsOneWidget);
      expect(find.byType(ConfettiOverlay), findsNothing);
    });
  });
}

// Tests for the §10b swipe advance and swipe cues (PRD §8 Unit 16
// speech-first layer + swipe-affordance refinement, ratified 2026-07-28):
//
//  * a horizontal swipe advances to the next card at ANY time — front or
//    back, accepted or not, engine or no engine; success never gates;
//  * advancing without a grade writes NO progress (the card stays due and
//    rotates to the end of the session queue) and stops a live attempt;
//  * the card is never static: idle sway (~6 px horizontal, repeating) +
//    a faint trailing-edge chevron, both suppressed during the impress
//    hold, and neither blocks gestures.
//
// Harness: gestures end with .up() (tester.drag does); stepped pumps
// everywhere — the sway repeats forever, so pumpAndSettle would never
// return while a card is front-up. Tests that arm engine timers dismount
// and flush at the end.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/design/confetti.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/flashcards/flashcard_deck.dart';
import 'package:learn_to_read/features/flashcards/flashcard_session.dart';
import 'package:learn_to_read/features/flashcards/flashcards_screen.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/contracts/fake_asr_engine.dart';
import 'package:learn_to_read/features/listening/matcher/sound_mode_scorer.dart';
import 'package:learn_to_read/features/sound_garden/echo_session.dart';

const _profileId = 'profile.amara';

final DateTime _t0 = DateTime(2026, 7, 28, 9, 0, 0);

WordToken _word(String text, List<({String graphemes, String phonemeId})> map) =>
    WordToken(
      text: text,
      graphemePhonemeMap: map,
      pronunciationAudioRef: 'audio/words/$text.mp3',
    );

WordToken _ship() => _word('ship', [
      (graphemes: 'sh', phonemeId: 'SH'),
      (graphemes: 'i', phonemeId: 'IH'),
      (graphemes: 'p', phonemeId: 'P'),
    ]);

WordToken _cake() => _word('cake', [
      (graphemes: 'c', phonemeId: 'K'),
      (graphemes: 'a', phonemeId: 'EY'),
      (graphemes: 'k', phonemeId: 'K'),
      (graphemes: 'e', phonemeId: ''),
    ]);

WordToken _cat() => _word('cat', [
      (graphemes: 'c', phonemeId: 'K'),
      (graphemes: 'a', phonemeId: 'AE'),
      (graphemes: 't', phonemeId: 'T'),
    ]);

Map<String, AudioRef> _phonemeAudioRefs() => const {
      'SH': 'audio/phonemes/SH.mp3',
      'IH': 'audio/phonemes/IH.mp3',
      'P': 'audio/phonemes/P.mp3',
      'K': 'audio/phonemes/K.mp3',
      'EY': 'audio/phonemes/EY.mp3',
      'AE': 'audio/phonemes/AE.mp3',
      'T': 'audio/phonemes/T.mp3',
    };

Hypothesis _phones(List<String> phones) =>
    Hypothesis(wordHypotheses: const ['<phones>'], phoneHypotheses: phones);

class _CountingEngine extends FakeAsrEngine {
  _CountingEngine({required super.script, super.delayBetweenHypotheses});

  int startCalls = 0;
  int stopCalls = 0;

  @override
  void start(List<String> biasingContext) {
    startCalls++;
    super.start(biasingContext);
  }

  @override
  void stop() {
    stopCalls++;
    super.stop();
  }
}

FlashcardEchoAttemptBuilder _echoBuilder() =>
    (engine, phonemeSequence, targetPhonemeId) => EchoSession(
          engine: engine,
          scorer: SoundModeScorer(
            targetPhonemeSequence: phonemeSequence,
            targetPhonemeId: targetPhonemeId,
          ),
        );

Future<void> _settleShortAnimations(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));
}

Future<void> _swipe(WidgetTester tester, String cardKey,
    {double dx = -200}) async {
  await tester.drag(
    find.byKey(ValueKey('flashcard-card-$cardKey')),
    Offset(dx, 0),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _teardownTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 12));
}

void main() {
  late AppDatabase db;
  late FakeAudioService audioService;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    audioService = FakeAudioService();
  });

  tearDown(() async {
    await db.close();
  });

  Widget screen({List<WordToken>? tokens, AsrEngine? engine}) {
    return MaterialApp(
      home: FlashcardsScreen(
        profileId: _profileId,
        deck: FlashcardDeck.fromWordTokens(
            tokens ?? [_ship(), _cake(), _cat()]),
        audioService: audioService,
        phonemeAudioRefs: _phonemeAudioRefs(),
        dao: db.flashcardsDao,
        now: () => _t0,
        confettiSeed: 424242,
        echoEngine: engine,
        buildEchoAttempt: engine == null ? null : _echoBuilder(),
      ),
    );
  }

  group('FlashcardSession.skipCurrent (no-grade advance)', () {
    test('POSITIVE: rotates the current card to the END of the queue', () {
      final session = FlashcardSession(queue: [
        FlashcardCard(cardKey: hashWord('ship'), token: _ship()),
        FlashcardCard(cardKey: hashWord('cake'), token: _cake()),
        FlashcardCard(cardKey: hashWord('cat'), token: _cat()),
      ]);
      session.skipCurrent();
      expect([for (final c in session.queue) c.wordText],
          ['cake', 'cat', 'ship']);
      expect(session.remaining, 3,
          reason: 'no card leaves the session without a grade');
    });

    test('EDGE: with a single card the "next" card is the same card', () {
      final session = FlashcardSession(queue: [
        FlashcardCard(cardKey: hashWord('ship'), token: _ship()),
      ]);
      session.skipCurrent();
      expect(session.current?.wordText, 'ship');
    });

    test('EDGE: a completed session is a safe no-op (never a StateError)',
        () {
      final session = FlashcardSession(queue: const []);
      expect(session.skipCurrent, returnsNormally);
      expect(session.isComplete, isTrue);
    });
  });

  group('swipe advances — success never gates, nothing is written', () {
    testWidgets('POSITIVE: mid-attempt swipe stops the live attempt, '
        'advances with NO progress write, and the card stays in the '
        'session (rotates to the end)', (tester) async {
      final engine = _CountingEngine(
        script: [_phones(const ['SH', 'IH', 'P'])],
        delayBetweenHypotheses: const Duration(seconds: 10),
      );
      await tester.pumpWidget(screen(engine: engine));
      await _settleShortAnimations(tester);
      expect(engine.startCalls, 1);

      await _swipe(tester, hashWord('ship'));
      await _settleShortAnimations(tester);

      expect(find.text('cake'), findsOneWidget);
      expect(find.text('ship'), findsNothing);
      expect(engine.stopCalls, 1,
          reason: 'the live attempt is stopped cleanly on swipe');
      expect(engine.startCalls, 2,
          reason: 'the next card visit listens afresh');
      expect(
        await db.flashcardsDao
            .getProgress(profileId: _profileId, cardKey: hashWord('ship')),
        isNull,
        reason: 'advancing without a grade writes nothing — the card '
            'stays due',
      );

      // The swiped card is still owed this session: two more swipes bring
      // it back around (rotation, not removal).
      await _swipe(tester, hashWord('cake'));
      await _settleShortAnimations(tester);
      expect(find.text('cat'), findsOneWidget);
      await _swipe(tester, hashWord('cat'));
      await _settleShortAnimations(tester);
      expect(find.text('ship'), findsOneWidget);
      expect(find.byKey(const ValueKey('flashcards-all-done')), findsNothing,
          reason: 'swiping can never complete the session');

      await _teardownTimers(tester);
    });

    testWidgets('POSITIVE: swipe works with NO engine, in either direction',
        (tester) async {
      await tester.pumpWidget(screen(tokens: [_ship(), _cake()]));
      await _settleShortAnimations(tester);

      // Rightward swipe advances too.
      await _swipe(tester, hashWord('ship'), dx: 200);
      await _settleShortAnimations(tester);
      expect(find.text('cake'), findsOneWidget);
      expect(
        await db.flashcardsDao.rowCountForProfile(_profileId),
        0,
        reason: 'no grade, no write',
      );
    });

    testWidgets('POSITIVE: swipe advances from the BACK side as well, and '
        'the next card arrives front-up', (tester) async {
      await tester.pumpWidget(screen(tokens: [_ship(), _cake()]));
      await _settleShortAnimations(tester);
      final shipKey = hashWord('ship');

      await tester.tap(find.byKey(ValueKey('flashcard-flip-$shipKey')));
      await _settleShortAnimations(tester);
      expect(find.byKey(const ValueKey('flashcard-grade-got-it')),
          findsOneWidget, reason: 'back side is up');

      await _swipe(tester, shipKey);
      await _settleShortAnimations(tester);

      expect(find.text('cake'), findsOneWidget);
      expect(find.byKey(const ValueKey('flashcard-grade-got-it')),
          findsNothing, reason: 'the next card starts on its front');
      expect(await db.flashcardsDao.rowCountForProfile(_profileId), 0);
    });

    testWidgets('NEGATIVE: a drag below the advance threshold does not '
        'advance', (tester) async {
      await tester.pumpWidget(screen(tokens: [_ship(), _cake()]));
      await _settleShortAnimations(tester);

      await tester.drag(
        find.byKey(ValueKey('flashcard-card-${hashWord('ship')}')),
        const Offset(-30, 0),
      );
      await _settleShortAnimations(tester);

      expect(find.text('ship'), findsOneWidget);
      expect(find.text('cake'), findsNothing);
    });
  });

  group('swipe cues — the card is never static (§10b refinement)', () {
    testWidgets('POSITIVE: the idle front shows the trailing-edge chevron '
        'and sways horizontally', (tester) async {
      await tester.pumpWidget(screen(tokens: [_ship()]));
      await _settleShortAnimations(tester);
      final cardKey = hashWord('ship');

      expect(find.byKey(ValueKey('flashcard-swipe-cue-$cardKey')),
          findsOneWidget);

      final cardFinder = find.byKey(ValueKey('flashcard-card-$cardKey'));
      final before = tester.getTopLeft(cardFinder);
      await tester.pump(const Duration(milliseconds: 400));
      final after = tester.getTopLeft(cardFinder);
      expect(after.dx, isNot(closeTo(before.dx, 0.01)),
          reason: 'the sway keeps the card moving horizontally');
      expect(after.dy, closeTo(before.dy, 0.01),
          reason: 'the sway is horizontal only');
      expect((after.dx - before.dx).abs(), lessThanOrEqualTo(12.0),
          reason: 'gentle: within the ±6 px swing');
    });

    testWidgets('POSITIVE: both cues are suppressed during the impress '
        'hold, and return on the next card', (tester) async {
      final engine = _CountingEngine(
        script: [_phones(const ['SH', 'IH', 'P'])],
        delayBetweenHypotheses: const Duration(milliseconds: 50),
      );
      await tester.pumpWidget(screen(tokens: [_ship(), _cake()], engine: engine));
      await tester.pump();
      await tester.pump();
      final shipKey = hashWord('ship');

      // Deliver + accept.
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('flashcard-impress-confetti')),
          findsOneWidget, reason: 'in the impress hold');

      expect(find.byKey(ValueKey('flashcard-swipe-cue-$shipKey')),
          findsNothing, reason: 'chevron suppressed during the hold');

      // Sway suppressed: the card holds still. Measure past the 160 ms
      // swell AND the 380 ms FadeUp entrance (which translates
      // vertically), so the only motion left would be the sway.
      await tester.pump(const Duration(milliseconds: 400)); // hold t≈450ms
      final cardFinder = find.byKey(ValueKey('flashcard-card-$shipKey'));
      final p1 = tester.getTopLeft(cardFinder);
      await tester.pump(const Duration(milliseconds: 200)); // hold t≈650ms
      final p2 = tester.getTopLeft(cardFinder);
      expect(p2.dx, closeTo(p1.dx, 0.001));
      expect(p2.dy, closeTo(p1.dy, 0.001));

      // Hold over -> next card, cues back.
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      await _settleShortAnimations(tester);
      expect(find.text('cake'), findsOneWidget);
      expect(
        find.byKey(ValueKey('flashcard-swipe-cue-${hashWord('cake')}')),
        findsOneWidget,
      );

      await _teardownTimers(tester);
    });

    testWidgets('POSITIVE: the sway never blocks gestures — word tap '
        '(sound-out) and flip both work mid-sway', (tester) async {
      await tester.pumpWidget(screen(tokens: [_ship()]));
      await _settleShortAnimations(tester);
      final cardKey = hashWord('ship');

      await tester.tap(find.byKey(ValueKey('flashcard-word-$cardKey')));
      await tester.pump();
      final plays = audioService.callLog.whereType<PlayLogEntry>().toList();
      expect(plays, hasLength(1));
      expect(plays.single.ref, 'audio/phonemes/SH.mp3');

      await tester.tap(find.byKey(ValueKey('flashcard-flip-$cardKey')));
      await _settleShortAnimations(tester);
      expect(find.byKey(const ValueKey('flashcard-grade-got-it')),
          findsOneWidget);
    });
  });

  group('no-engine construction stays the committed scaffold', () {
    testWidgets('NEGATIVE: without an engine no confetti/impress state ever '
        'appears on its own', (tester) async {
      await tester.pumpWidget(screen(tokens: [_ship()]));
      await _settleShortAnimations(tester);
      await tester.pump(const Duration(seconds: 2));

      expect(find.byType(ConfettiOverlay), findsNothing);
      expect(find.byKey(const ValueKey('flashcard-impress-confetti')),
          findsNothing);
      expect(await db.flashcardsDao.rowCountForProfile(_profileId), 0);
    });
  });
}

// Widget tests for the flashcards speech-first layer (PRD §8 Unit 16
// "Speech-first", RATIFIED 2026-07-28; docs/design/mockup-spec.md §10b):
// the front card listens; on accept the word impresses (read-green +
// intensity-1 seeded confetti), a got-it grade is auto-recorded through
// the existing dao/scheduler path, and after the kSoundGardenGreenHold
// window the session auto-advances. Non-matching sound changes nothing.
//
// Harness notes (copied from the frozen scaffold suite + the sound-garden
// echo suite):
//  * FakeAsrEngine delivers on its own delayBetweenHypotheses timer —
//    with zero delay the hypothesis resolves in the same microtask flush
//    as engine.start, making the pre-accept state unobservable. Stepped
//    pumps advance to delivery; NEVER pumpAndSettle while a card is
//    front-up (the §10b idle sway repeats forever) or while confetti is
//    mounted.
//  * Every test ends by dismounting the tree and flushing a couple of
//    seconds so no scripted-delivery or hold timer leaks past the test.
//  * Persistence is the REAL FlashcardsDao over NativeDatabase.memory();
//    the clock is fixed — no wall-clock time anywhere.

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
import 'package:learn_to_read/features/flashcards/flashcards_screen.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/contracts/fake_asr_engine.dart';
import 'package:learn_to_read/features/listening/matcher/sound_mode_scorer.dart';
import 'package:learn_to_read/features/sound_garden/echo_session.dart';

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

Map<String, AudioRef> _phonemeAudioRefs() => const {
      'SH': 'audio/phonemes/SH.mp3',
      'IH': 'audio/phonemes/IH.mp3',
      'P': 'audio/phonemes/P.mp3',
      'K': 'audio/phonemes/K.mp3',
      'EY': 'audio/phonemes/EY.mp3',
    };

Hypothesis _phones(List<String> phones) =>
    Hypothesis(wordHypotheses: const ['<phones>'], phoneHypotheses: phones);

/// FakeAsrEngine that additionally counts lifecycle calls, so the tests
/// can pin "the attempt was stopped cleanly" / "a fresh attempt started".
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

/// The wiring's attempt builder: EchoSession over the injected engine and
/// a fresh sound-mode SoundModeScorer for the card's sequence/target —
/// exactly the construction the WIRING block in flashcards_screen.dart
/// describes (and sound_garden_screen_test.dart uses).
FlashcardEchoAttemptBuilder _echoBuilder() =>
    (engine, phonemeSequence, targetPhonemeId) => EchoSession(
          engine: engine,
          scorer: SoundModeScorer(
            targetPhonemeSequence: phonemeSequence,
            targetPhonemeId: targetPhonemeId,
          ),
        );

/// Dismounts the tree and flushes any scripted-delivery / hold timers.
Future<void> _teardownTimers(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 8));
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

  Widget screen({
    List<WordToken>? tokens,
    AsrEngine? engine,
    int confettiSeed = 424242,
  }) {
    return MaterialApp(
      home: FlashcardsScreen(
        profileId: _profileId,
        deck: FlashcardDeck.fromWordTokens(tokens ?? [_ship(), _cake()]),
        audioService: audioService,
        phonemeAudioRefs: _phonemeAudioRefs(),
        dao: db.flashcardsDao,
        now: () => _t0,
        confettiSeed: confettiSeed,
        echoEngine: engine,
        buildEchoAttempt: engine == null ? null : _echoBuilder(),
      ),
    );
  }

  /// Pumps past the load future and the first frame (entrance animations
  /// keep running; finders and gestures work regardless).
  Future<void> pumpLoaded(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  /// Advances to the fake engine's delivery moment and flushes the accept
  /// path (hypothesis -> matcher -> dao write -> setState).
  Future<void> pumpDelivery(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  group('accept -> impress + auto got-it + auto-advance (PRD §8 Unit 16)',
      () {
    testWidgets('POSITIVE: a matching echo turns the word read-green with '
        'the scale swell, mounts the seeded intensity-1 confetti, records '
        'got-it through the dao/scheduler path, stops the attempt, and '
        'advances after the kSoundGardenGreenHold window', (tester) async {
      final engine = _CountingEngine(
        script: [_phones(const ['SH', 'IH', 'P'])],
        delayBetweenHypotheses: const Duration(milliseconds: 50),
      );
      await tester.pumpWidget(screen(engine: engine));
      await pumpLoaded(tester);
      final cardKey = hashWord('ship');

      expect(engine.startCalls, 1,
          reason: 'the front card listens as soon as it takes the queue');
      expect(engine.recordedBiasingContext, isNotNull);
      // Pre-accept: ink word, no confetti, nothing written.
      expect(tester.widget<Text>(find.text('ship')).style?.color,
          DesignTokens.wordUnreadInk);
      expect(find.byType(ConfettiOverlay), findsNothing);

      await pumpDelivery(tester);

      // Impress: read-green word + swell.
      final wordText = tester.widget<Text>(find.text('ship'));
      expect(wordText.style?.color, DesignTokens.wordReadGreen);
      final swell = tester.widget<AnimatedScale>(find.ancestor(
        of: find.text('ship'),
        matching: find.byType(AnimatedScale),
      ));
      expect(swell.scale, greaterThan(1.0));

      // Confetti: intensity 1, deterministic per-visit seed (first visit).
      final confettiFinder =
          find.byKey(const ValueKey('flashcard-impress-confetti'));
      expect(confettiFinder, findsOneWidget);
      final confetti = tester.widget<ConfettiOverlay>(confettiFinder);
      expect(confetti.intensity, 1);
      expect(confetti.seed, flashcardConfettiSeed(cardKey, 0));

      // Got-it already recorded, same path as the green button: box 2,
      // due +kFlashcardBox2Due.
      final stored = await db.flashcardsDao
          .getProgress(profileId: _profileId, cardKey: cardKey);
      expect(stored?.box, 2);
      expect(stored?.dueAt, _t0.add(kFlashcardBox2Due));

      // The attempt was stopped cleanly the moment it accepted.
      expect(engine.stopCalls, 1);

      // Hold window: the impressed card stays front for the whole hold.
      await tester.pump(kSoundGardenGreenHold - const Duration(milliseconds: 100));
      expect(find.text('ship'), findsOneWidget);

      // Hold over -> the existing advance path: next card, fresh attempt.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      expect(find.text('ship'), findsNothing);
      expect(find.text('cake'), findsOneWidget);
      expect(find.byKey(const ValueKey('flashcard-impress-confetti')),
          findsNothing, reason: 'the impress burst lives only in the hold');
      expect(engine.startCalls, 2,
          reason: 'the next card visit starts its own fresh attempt');

      await _teardownTimers(tester);
    });

    testWidgets('POSITIVE: accepting the LAST due card auto-advances into '
        'the existing completion path (all-done + the session confetti)',
        (tester) async {
      final engine = _CountingEngine(
        script: [_phones(const ['SH', 'IH', 'P'])],
        delayBetweenHypotheses: const Duration(milliseconds: 50),
      );
      await tester.pumpWidget(screen(tokens: [_ship()], engine: engine));
      await pumpLoaded(tester);

      await pumpDelivery(tester);
      await tester.pump(kSoundGardenGreenHold);
      await tester.pump();

      expect(find.byKey(const ValueKey('flashcards-all-done')), findsOneWidget);
      final confettiFinder = find.byType(ConfettiOverlay);
      expect(confettiFinder, findsOneWidget);
      expect(tester.widget<ConfettiOverlay>(confettiFinder).seed, 424242,
          reason: 'the completion burst is the session-seeded one; the '
              'impress burst is already dismounted');

      await _teardownTimers(tester);
    });
  });

  group('non-matching / no speech -> nothing changes, still listening', () {
    testWidgets('NEGATIVE: clearly different sounds earn nothing: word '
        'stays ink, no confetti, no write, the attempt keeps listening',
        (tester) async {
      final engine = _CountingEngine(
        script: [_phones(const ['M', 'M'])],
        delayBetweenHypotheses: const Duration(milliseconds: 50),
      );
      await tester.pumpWidget(screen(tokens: [_ship()], engine: engine));
      await pumpLoaded(tester);

      await pumpDelivery(tester);
      await tester.pump(const Duration(milliseconds: 300));

      expect(tester.widget<Text>(find.text('ship')).style?.color,
          DesignTokens.wordUnreadInk);
      expect(find.byType(ConfettiOverlay), findsNothing);
      expect(
        await db.flashcardsDao
            .getProgress(profileId: _profileId, cardKey: hashWord('ship')),
        isNull,
      );
      expect(engine.stopCalls, 0,
          reason: 'no accept, no advance: the attempt is never stopped — '
              'the card simply keeps listening');

      await _teardownTimers(tester);
    });

    testWidgets('EDGE: silence (an empty script) changes nothing either',
        (tester) async {
      final engine = _CountingEngine(script: const []);
      await tester.pumpWidget(screen(tokens: [_ship()], engine: engine));
      await pumpLoaded(tester);
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.widget<Text>(find.text('ship')).style?.color,
          DesignTokens.wordUnreadInk);
      expect(find.byType(ConfettiOverlay), findsNothing);
      expect(engine.startCalls, 1);
      expect(engine.stopCalls, 0);

      await _teardownTimers(tester);
    });
  });

  group('listening is a front-side behavior', () {
    testWidgets('POSITIVE: flipping to the back stops the attempt; flipping '
        'home starts a FRESH one', (tester) async {
      // The delivery delay only needs to outlast the test body; it must
      // stay inside the teardown flush so no timer outlives the test.
      final engine = _CountingEngine(
        script: [_phones(const ['M'])],
        delayBetweenHypotheses: const Duration(seconds: 5),
      );
      await tester.pumpWidget(screen(tokens: [_ship()], engine: engine));
      await pumpLoaded(tester);
      final cardKey = hashWord('ship');

      expect(engine.startCalls, 1);
      await tester.tap(find.byKey(ValueKey('flashcard-flip-$cardKey')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
      expect(engine.stopCalls, 1,
          reason: 'the card listens while the FRONT is showing');

      // Flip home (tap a chip — it carries no gesture of its own, so the
      // tap falls through to the card's flip detector, clear of the
      // pronunciation button): a fresh attempt (never a reused one).
      await tester.tap(find.byKey(ValueKey('flashcard-chip-$cardKey-0')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));
      expect(engine.startCalls, 2);

      await _teardownTimers(tester);
    });
  });

  group('confetti seed varies between visits', () {
    test('POSITIVE: flashcardConfettiSeed is deterministic per (card, '
        'visit) and differs across visits and cards', () {
      final key = hashWord('ship');
      expect(flashcardConfettiSeed(key, 0), flashcardConfettiSeed(key, 0));
      expect(flashcardConfettiSeed(key, 0),
          isNot(flashcardConfettiSeed(key, 1)));
      expect(flashcardConfettiSeed(key, 0),
          isNot(flashcardConfettiSeed(hashWord('cake'), 0)));
    });

    testWidgets('POSITIVE: a card accepted on its SECOND visit (after a '
        'swipe-away and return) bursts with the visit-1 seed, not the '
        'visit-0 seed', (tester) async {
      final engine = _CountingEngine(
        script: [_phones(const ['SH', 'IH', 'P'])],
        delayBetweenHypotheses: const Duration(milliseconds: 50),
      );
      await tester.pumpWidget(screen(tokens: [_ship()], engine: engine));
      await pumpLoaded(tester);
      final cardKey = hashWord('ship');

      // Swipe away BEFORE the 50 ms delivery: visit 1 ends unaccepted;
      // with a single-card queue the "next" card is the same card, and a
      // second visit (fresh attempt) begins.
      await tester.drag(
        find.byKey(ValueKey('flashcard-card-$cardKey')),
        const Offset(-200, 0),
      );
      await tester.pump();
      expect(engine.startCalls, 2);
      expect(engine.stopCalls, 1);

      await pumpDelivery(tester);

      final confetti = tester.widget<ConfettiOverlay>(
          find.byKey(const ValueKey('flashcard-impress-confetti')));
      expect(confetti.seed, flashcardConfettiSeed(cardKey, 1));
      expect(confetti.seed, isNot(flashcardConfettiSeed(cardKey, 0)));

      await _teardownTimers(tester);
    });
  });
}

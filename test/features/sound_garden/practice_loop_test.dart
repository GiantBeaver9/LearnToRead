// Test suite for the Sound Garden PRACTICE LOOP (docs/design/mockup-spec.md
// §10a, ratified 2026-07-28; PRD §8 Unit 15 "Practice loop" bullet), the
// ruling that supersedes the one-shot "accept is terminal" semantics:
//
//   - while a card listens, the grapheme renders amber
//     (DesignTokens.wordCurrentInk);
//   - on scorer accept it turns read-green (DesignTokens.wordReadGreen) and
//     a ConfettiOverlay burst plays (intensity 1, seed = confettiSeedFor(
//     card id, rep) — deterministic, different every rep);
//   - after the pinned 1000 ms green hold (kSoundGardenGreenHold) the card
//     resets to amber with a FRESH EchoSession (never a reused one) and the
//     rep counter increments — unlimited reps;
//   - the practice card carries the §8 PageCurlCorner dog-ear, ALWAYS
//     enabled; turning advances through the inventory order, wrapping, never
//     requires an accepted rep, and stops a live session cleanly mid-attempt.
//
// HARNESS NOTES: ConfettiOverlay mounts only during the green hold, so this
// suite drives time with stepped pump(duration) calls and NEVER
// pumpAndSettle while confetti is live; hypothesis delivery uses a
// hand-controlled broadcast engine (add + pump); every test ends with a
// pumpWidget(SizedBox()) dismount so no loop timer leaks past the test.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/design/confetti.dart';
import 'package:learn_to_read/design/page_curl.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/domain/tuning.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/matcher/sound_mode_scorer.dart';
import 'package:learn_to_read/features/sound_garden/sound_garden_screen.dart';

const _installId = 'a1b2c3d4-1234-4abc-8def-0123456789ab';

/// A hand-controlled AsrEngine: hypotheses are pushed explicitly via
/// [add], and every start/stop is counted so tests can assert the exact
/// per-rep engine lifecycle the practice loop drives. Broadcast, so each
/// rep's fresh EchoSession can subscribe in turn.
class _ControlledAsrEngine implements AsrEngine {
  final StreamController<Hypothesis> controller =
      StreamController<Hypothesis>.broadcast();
  int startCount = 0;
  int stopCount = 0;

  @override
  void start(List<String> biasingContext) => startCount++;

  @override
  void stop() => stopCount++;

  @override
  Stream<Hypothesis> get hypothesesStream => controller.stream;

  void add(List<String> phones) => controller.add(
      Hypothesis(wordHypotheses: const ['<phones>'], phoneHypotheses: phones));

  Future<void> close() => controller.close();
}

List<Level> _levels() => [
      for (var i = 1; i <= 5; i++)
        Level(
          id: 'level.$i',
          ordinal: i,
          newSkills: const [],
          format: LevelFormat.sentence,
          vocabEnabled: false,
        ),
    ];

GraphemeSound _card(String id, String grapheme, List<String> phonemeIds) =>
    GraphemeSound(
      id: id,
      grapheme: grapheme,
      phonemeIds: phonemeIds,
      introducedAtLevelId: 'level.1',
      exampleWords: const [],
    );

/// Three cards in a pinned order — the §10a curl walks (and wraps) exactly
/// this order.
List<GraphemeSound> _inventory() => [
      _card('gs.a', 'a', const ['AE']),
      _card('gs.sh', 'sh', const ['SH']),
      _card('gs.oi', 'oi', const ['OI']),
    ];

Profile _profile() => Profile(
      localId: 'profile.amara',
      displayName: 'Amara',
      ageBand: AgeBand.fiveToSix,
      currentLevelId: 'level.3',
      micConsent: true,
      cloudAsrConsent: false,
      createdAt: DateTime(2026, 1, 1),
    );

Widget _screen({
  required _ControlledAsrEngine engine,
  required FakeAudioService audioService,
  List<GraphemeSound>? inventory,
  void Function(AnalyticsEvent event)? onAnalyticsEvent,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SoundGardenScreen(
        profile: _profile(),
        profileOrdinal: 1,
        levelOrdinal: 3,
        installId: _installId,
        inventory: inventory ?? _inventory(),
        levels: _levels(),
        audioService: audioService,
        phonemeAudioRefs: const {
          'AE': 'audio/phonemes/AE.mp3',
          'SH': 'audio/phonemes/SH.mp3',
          'OI': 'audio/phonemes/OI.mp3',
        },
        downloadedExampleWordAudioRefs: const {},
        echoEngine: engine,
        buildScorer: (card) => SoundModeScorer(
          targetPhonemeSequence: card.phonemeIds,
          targetPhonemeId: card.phonemeIds.first,
        ),
        onAnalyticsEvent: onAnalyticsEvent ?? (_) {},
      ),
    ),
  );
}

/// Taps a card into its listening state: tap the grapheme text (its center
/// is never under the curl's corner hit region), then drain the single
/// phoneme playback (completing each play() in order, pumping between —
/// same mechanism as the canonical suite's `_drainSequentialPlayback`).
Future<void> _tapIntoListening(
  WidgetTester tester,
  FakeAudioService audioService,
  String cardId, {
  int alreadyPlayed = 0,
}) async {
  await tester.tap(find.byKey(ValueKey('sound-card-text-$cardId')));
  var drained = alreadyPlayed;
  while (drained < alreadyPlayed + 1) {
    await tester.pump();
    final plays = audioService.callLog.whereType<PlayLogEntry>().toList();
    expect(plays.length, greaterThan(drained));
    audioService.completePlayback(plays[drained].handle);
    drained++;
  }
  await tester.pump();
  await tester.pump();
}

Color? _graphemeColor(WidgetTester tester, String cardId) =>
    tester.widget<Text>(find.byKey(ValueKey('sound-card-text-$cardId'))).style?.color;

/// Pushes a hypothesis and pumps twice: the broadcast stream delivers in a
/// microtask after the first pump's frame, so the resulting setState needs a
/// second pump to render.
Future<void> _deliver(
  WidgetTester tester,
  _ControlledAsrEngine engine,
  List<String> phones,
) async {
  engine.add(phones);
  await tester.pump();
  await tester.pump();
}

/// Turns the practice card's page curl by tapping its bottom-right corner,
/// then pumps through the settle animation to the advance.
Future<void> _turnByTap(WidgetTester tester) async {
  final corner =
      tester.getBottomRight(find.byType(PageCurlCorner)) - const Offset(8, 8);
  await tester.tapAt(corner);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump();
}

void main() {
  group('§10a practice loop — accept → green + confetti → 1 s reset', () {
    testWidgets(
        'POSITIVE: amber while listening; accept turns the grapheme green '
        'with a ConfettiOverlay; after kSoundGardenGreenHold the card '
        'resets to amber with a FRESH echo attempt that can match again',
        (tester) async {
      final engine = _ControlledAsrEngine();
      final audioService = FakeAudioService();
      await tester.pumpWidget(_screen(engine: engine, audioService: audioService));
      await tester.pump();

      await _tapIntoListening(tester, audioService, 'gs.a');

      // Live/awaiting: amber grapheme, listening prompt, engine started.
      expect(find.byKey(const ValueKey('sound-card-echo-prompt-gs.a')), findsOneWidget);
      expect(_graphemeColor(tester, 'gs.a'), DesignTokens.wordCurrentInk);
      expect(engine.startCount, 1);
      expect(find.byType(ConfettiOverlay), findsNothing);

      // Accept: green hold + confetti burst; the used session is stopped.
      await _deliver(tester, engine, const ['AE']);
      expect(find.byKey(const ValueKey('sound-card-sparkle-gs.a')), findsOneWidget);
      expect(_graphemeColor(tester, 'gs.a'), DesignTokens.wordReadGreen);
      final confetti = tester.widget<ConfettiOverlay>(find.byType(ConfettiOverlay));
      expect(confetti.intensity, 1);
      expect(engine.stopCount, 1);

      // Still green just before the pinned 1000 ms elapses...
      await tester.pump(kSoundGardenGreenHold - const Duration(milliseconds: 1));
      expect(find.byKey(const ValueKey('sound-card-sparkle-gs.a')), findsOneWidget);

      // ...and reset to amber with a fresh attempt right after: confetti
      // unmounted, prompt back, a NEW session started (a used EchoSession
      // can never restart, so startCount == 2 proves a fresh instance).
      await tester.pump(const Duration(milliseconds: 2));
      expect(find.byKey(const ValueKey('sound-card-sparkle-gs.a')), findsNothing);
      expect(find.byKey(const ValueKey('sound-card-echo-prompt-gs.a')), findsOneWidget);
      expect(_graphemeColor(tester, 'gs.a'), DesignTokens.wordCurrentInk);
      expect(find.byType(ConfettiOverlay), findsNothing);
      expect(engine.startCount, 2);

      // Unlimited reps: the fresh attempt accepts again.
      await _deliver(tester, engine, const ['AE']);
      expect(find.byKey(const ValueKey('sound-card-sparkle-gs.a')), findsOneWidget);
      expect(engine.stopCount, 2);

      await tester.pumpWidget(const SizedBox());
      await engine.close();
    });

    testWidgets(
        'POSITIVE: the rep counter increments across resets — each rep\'s '
        'confetti seed is confettiSeedFor(card id, rep) for rep 0, then '
        'rep 1', (tester) async {
      final engine = _ControlledAsrEngine();
      final audioService = FakeAudioService();
      await tester.pumpWidget(_screen(engine: engine, audioService: audioService));
      await tester.pump();

      await _tapIntoListening(tester, audioService, 'gs.a');

      await _deliver(tester, engine, const ['AE']);
      final firstSeed =
          tester.widget<ConfettiOverlay>(find.byType(ConfettiOverlay)).seed;
      expect(firstSeed, confettiSeedFor('gs.a', 0),
          reason: 'first rep seeds from rep count 0');

      await tester.pump(kSoundGardenGreenHold + const Duration(milliseconds: 1));
      await _deliver(tester, engine, const ['AE']);
      final secondSeed =
          tester.widget<ConfettiOverlay>(find.byType(ConfettiOverlay)).seed;
      expect(secondSeed, confettiSeedFor('gs.a', 1),
          reason: 'the reset must have incremented the rep counter');

      await tester.pumpWidget(const SizedBox());
      await engine.close();
    });

    testWidgets(
        'POSITIVE: confetti seeds differ between reps of the same card, '
        'deterministically', (tester) async {
      final engine = _ControlledAsrEngine();
      final audioService = FakeAudioService();
      await tester.pumpWidget(_screen(engine: engine, audioService: audioService));
      await tester.pump();

      await _tapIntoListening(tester, audioService, 'gs.a');

      final seeds = <int>[];
      for (var rep = 0; rep < 2; rep++) {
        await _deliver(tester, engine, const ['AE']);
        seeds.add(
            tester.widget<ConfettiOverlay>(find.byType(ConfettiOverlay)).seed);
        await tester
            .pump(kSoundGardenGreenHold + const Duration(milliseconds: 1));
      }

      expect(seeds[0], isNot(seeds[1]),
          reason: 'each rep\'s confetti must differ');
      // Deterministic: the same (card, rep) pair always yields the same seed.
      expect(seeds[0], confettiSeedFor('gs.a', 0));
      expect(seeds[1], confettiSeedFor('gs.a', 1));

      await tester.pumpWidget(const SizedBox());
      await engine.close();
    });
  });

  group('§10a page curl — always enabled, advances and wraps', () {
    testWidgets(
        'POSITIVE: the practice card carries an ENABLED PageCurlCorner from '
        'the first frame — no accepted rep (or any echo attempt) required',
        (tester) async {
      final engine = _ControlledAsrEngine();
      await tester.pumpWidget(
          _screen(engine: engine, audioService: FakeAudioService()));
      await tester.pump();

      final curlFinder = find.byType(PageCurlCorner);
      expect(curlFinder, findsOneWidget);
      expect(tester.widget<PageCurlCorner>(curlFinder).enabled, isTrue,
          reason: '§10a: always enabled — never gated on success');
      // It wraps the first card in the inventory order...
      expect(
        find.descendant(
            of: curlFinder, matching: find.byKey(const ValueKey('sound-card-gs.a'))),
        findsOneWidget,
      );
      // ...and its underleaf is the plain themed preview, not a second
      // (key-colliding) real card face.
      expect(
        find.descendant(
            of: curlFinder,
            matching: find.byKey(const ValueKey('sound-garden-next-card-preview'))),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox());
      await engine.close();
    });

    testWidgets(
        'POSITIVE: turning (tap or drag past threshold, released with '
        '.up()) advances through the garden\'s existing card order and '
        'wraps past the end; the curl stays enabled on every card',
        (tester) async {
      final engine = _ControlledAsrEngine();
      await tester.pumpWidget(
          _screen(engine: engine, audioService: FakeAudioService()));
      await tester.pump();

      Finder curl() => find.byType(PageCurlCorner);
      void expectPracticeCard(String cardId) {
        expect(
          find.descendant(
              of: curl(), matching: find.byKey(ValueKey('sound-card-$cardId'))),
          findsOneWidget,
          reason: 'the dog-ear must sit on $cardId now',
        );
        expect(tester.widget<PageCurlCorner>(curl()).enabled, isTrue);
      }

      expectPracticeCard('gs.a');

      // Turn 1 — tap the dog-ear.
      await _turnByTap(tester);
      expectPracticeCard('gs.sh');

      // Turn 2 — drag the corner past the ~40% threshold and release.
      final corner =
          tester.getBottomRight(curl()) - const Offset(8, 8);
      final gesture = await tester.startGesture(corner);
      for (var i = 0; i < 8; i++) {
        await gesture.moveBy(const Offset(-20, -20));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expectPracticeCard('gs.oi');

      // Turn 3 — wraps past the end back to the first card.
      await _turnByTap(tester);
      expectPracticeCard('gs.a');

      await tester.pumpWidget(const SizedBox());
      await engine.close();
    });

    testWidgets(
        'POSITIVE: turning MID-ATTEMPT stops the live session cleanly '
        '(engine.stop called once), clears the loop state, and still '
        'advances — success is never required', (tester) async {
      final engine = _ControlledAsrEngine();
      final audioService = FakeAudioService();
      await tester.pumpWidget(_screen(engine: engine, audioService: audioService));
      await tester.pump();

      await _tapIntoListening(tester, audioService, 'gs.a');
      expect(find.byKey(const ValueKey('sound-card-echo-prompt-gs.a')), findsOneWidget);
      expect(engine.startCount, 1);
      expect(engine.stopCount, 0);

      await _turnByTap(tester);

      expect(engine.stopCount, 1,
          reason: 'the live attempt must be stopped via EchoSession.stop');
      expect(find.byKey(const ValueKey('sound-card-echo-prompt-gs.a')), findsNothing,
          reason: 'the turned-away card\'s loop state is cleared');
      expect(find.byKey(const ValueKey('sound-card-sparkle-gs.a')), findsNothing);
      expect(
        find.descendant(
            of: find.byType(PageCurlCorner),
            matching: find.byKey(const ValueKey('sound-card-gs.sh'))),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await engine.close();
    });

    testWidgets(
        'EDGE: turning during a green hold cancels the reset — no sparkle, '
        'no confetti, no fresh attempt for the turned-away card',
        (tester) async {
      final engine = _ControlledAsrEngine();
      final audioService = FakeAudioService();
      await tester.pumpWidget(_screen(engine: engine, audioService: audioService));
      await tester.pump();

      await _tapIntoListening(tester, audioService, 'gs.a');
      await _deliver(tester, engine, const ['AE']);
      expect(find.byType(ConfettiOverlay), findsOneWidget);

      await _turnByTap(tester);

      expect(find.byType(ConfettiOverlay), findsNothing);
      expect(find.byKey(const ValueKey('sound-card-sparkle-gs.a')), findsNothing);
      expect(find.byKey(const ValueKey('sound-card-echo-prompt-gs.a')), findsNothing);

      // Past where the hold would have reset: no fresh attempt starts for
      // the turned-away card.
      await tester.pump(kSoundGardenGreenHold + const Duration(milliseconds: 10));
      expect(engine.startCount, 1);
      expect(find.byKey(const ValueKey('sound-card-echo-prompt-gs.a')), findsNothing);

      await tester.pumpWidget(const SizedBox());
      await engine.close();
    });
  });

  group('§10a — no failure state, unchanged invariant', () {
    testWidgets(
        'NEGATIVE: wrong sound keeps the card listening in amber — no '
        'reset, no confetti, no extra engine cycles, and the tree settles',
        (tester) async {
      final engine = _ControlledAsrEngine();
      final audioService = FakeAudioService();
      await tester.pumpWidget(_screen(engine: engine, audioService: audioService));
      await tester.pump();

      await _tapIntoListening(tester, audioService, 'gs.a');

      await _deliver(tester, engine, const ['Z']);
      await _deliver(tester, engine, const ['Z']);

      expect(find.byKey(const ValueKey('sound-card-echo-prompt-gs.a')), findsOneWidget);
      expect(_graphemeColor(tester, 'gs.a'), DesignTokens.wordCurrentInk);
      expect(find.byKey(const ValueKey('sound-card-sparkle-gs.a')), findsNothing);
      expect(find.byType(ConfettiOverlay), findsNothing);
      expect(engine.startCount, 1);
      expect(engine.stopCount, 0);

      // No confetti mounted -> a settle is safe and proves nothing loops.
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sound-card-echo-prompt-gs.a')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await engine.close();
    });
  });
}

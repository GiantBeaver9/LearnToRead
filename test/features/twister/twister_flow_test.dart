// Test suite for lib/features/twister/twister_controller.dart and
// lib/features/twister/sparkle_celebration.dart (PRD §8 Unit 14
// "Tongue-twister boosters"; §5 TongueTwister / TwisterProgress; §9 A-13;
// ticket twister-flow). Neither implementation file exists yet: every
// import below fails to resolve, which is the expected red state.
//
// This file is the CANONICAL pinned API for the twister-flow unit; the
// sibling files (sound_mode_config_test.dart, faster_pass_test.dart,
// no_collectible_test.dart) restate only the slice they exercise.
//
// Pinned API surface this suite requires:
//
//   lib/features/twister/twister_controller.dart:
//     class TwisterController {
//       TwisterController({
//         required TongueTwister twister,
//         required AsrEngine engine,
//         required AudioService audioService,
//         required TwisterProgressDao twisterProgressDao,
//         required String profileId,
//         required bool micConsent,
//         required String installId,
//         required int profileOrdinal,
//         required int levelOrdinal,
//         required void Function(AnalyticsEvent event) onAnalyticsEvent,
//         void Function()? onCelebrate,
//         double matchThreshold = kSoundModeMatchThreshold,
//         int perPhonemeMaxDistance = kSoundModePerPhonemeMaxDistance,
//         int targetPhonemeWeight = kSoundModeTargetPhonemeWeight,
//       });
//
//       // Sound-mode progress (backed by one SoundModeScorer over the
//       // whole twister's concatenated phoneme sequence -- PRD's "the
//       // twister's phoneme sequence... is the target", A-13).
//       double get matchedFraction;
//       bool get accepted;
//
//       // Session state.
//       bool get isListening;   // mic/engine actively open right now
//       bool get isTapMode;     // degraded to listen-then-tap
//       bool get isComplete;    // node done (either path)
//
//       // Tap-fallback progress.
//       int get tappedWordCount;
//       int get totalWordCount; // == twister.words.length
//
//       // Tunables actually in effect (mirrors ReadingTracker's exposed
//       // tunable getters) -- proves config injection, not hardcoding.
//       double get matchThreshold;
//       int get perPhonemeMaxDistance;
//       int get targetPhonemeWeight;
//
//       Future<void> start();
//       void tapWord();  // listen-then-tap manual advance; always available
//       void stop();
//     }
//
//   lib/features/twister/sparkle_celebration.dart:
//     const Duration kSparkleCelebrationDuration = Duration(seconds: 2);
//     class SparkleCelebration extends StatelessWidget {
//       const SparkleCelebration({
//         super.key,
//         required VoidCallback onFinished,
//         Duration duration = kSparkleCelebrationDuration,
//       });
//     }
//
// Contract this suite locks in (builder-mechanical design choices the
// ticket leaves to the builder; behavior is pinned by the PRD/ticket, exact
// shapes are pinned by this suite):
//
//  - start()'s synchronous prefix (the same event-loop turn as the call,
//    before its first `await` suspends it) is, in order:
//      1. onAnalyticsEvent(twister_started)
//      2. audioService.play(twister.narrationAudioRef, channel:
//         AudioChannel.narration)  -- the owner-supplied recording models
//         the twister BEFORE listening begins.
//    Listening (or, absent consent/a healthy engine, tap mode) begins only
//    once the narration's `completionOf(handle)` resolves -- this is the
//    "narration-before-listening" ordering the ticket names.
//  - biasingContext passed to `engine.start` is `twister.words.map((w) =>
//    w.text)`, in order (expected-text hybridization stays on, even though
//    sound mode does not grade on word identity).
//  - micConsent == false: engine.start is NEVER called (recordedBiasingContext
//    stays null) -- the controller enters tap mode directly once narration
//    ends. micConsent == true with a failing engine (hypothesesStream
//    throws synchronously, as `FakeAsrEngine(shouldFail: true)` does):
//    engine.start IS called (an attempt is recorded) but the controller
//    still falls back to tap mode -- both are distinguishable via
//    `engine.recordedBiasingContext`, and both land in `isTapMode`.
//  - While listening, every finalized hypothesis is fed to one internal
//    `SoundModeScorer(targetPhonemeSequence: <twister's words' authored
//    phonemes, concatenated in word order>, targetPhonemeId:
//    twister.targetPhonemeId, matchThreshold:, perPhonemeMaxDistance:,
//    targetPhonemeWeight:)` -- reused, never forked, and NOT WordMatcher
//    (see sound_mode_config_test.dart for the "twister set, not story set"
//    proof). The moment `accepted` transitions to true, the controller
//    completes (see below). Producing the right SOUNDS advances/accepts
//    this even when the hypothesis's word text is nonsense (PRD ratified).
//  - `tapWord()` is available in every mode. It advances `tappedWordCount`
//    by one (a no-op past `totalWordCount` or after `isComplete`); once
//    `tappedWordCount == totalWordCount` the controller completes via the
//    SAME completion path below, independent of `accepted`.
//  - Completion (from either path): the engine/mic session ends
//    (isListening -> false), `twisterProgressDao.recordCompletion(profileId:,
//    twisterId:)` is awaited, `onAnalyticsEvent(twister_completed)` fires,
//    `onCelebrate` fires (if given), and `isComplete` becomes true. There is
//    deliberately no CollectionDao anywhere in this constructor -- see
//    no_collectible_test.dart.
//  - The controller takes `engine: AsrEngine` directly and runs its own
//    engine+SoundModeScorer loop -- there is no `ReadingTracker` in this
//    constructor's dependencies (accept: "does NOT depend on
//    listening-tracker").
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rive/rive.dart' as rive;

import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/domain/tuning.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/analytics/events.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/contracts/fake_asr_engine.dart';
import 'package:learn_to_read/features/twister/sparkle_celebration.dart';
import 'package:learn_to_read/features/twister/twister_controller.dart';

const _installId = 'a1b2c3d4-1234-4abc-8def-0123456789ab';

// ---------------------------------------------------------------------------
// Fixtures.
// ---------------------------------------------------------------------------

WordToken _tok(String text, List<({String graphemes, String phonemeId})> map) =>
    WordToken(text: text, graphemePhonemeMap: map, pronunciationAudioRef: 'audio/$text.wav');

/// "sassy" -- authored to match graphemesToPhonemes('sassy') exactly
/// (s->S, a->AE, s->S, s->S, y->Y), so a correctly-spelled word-only
/// hypothesis exercises the approximation path predictably.
WordToken get _sassy => _tok('sassy', const [
      (graphemes: 's', phonemeId: 'S'),
      (graphemes: 'a', phonemeId: 'AE'),
      (graphemes: 's', phonemeId: 'S'),
      (graphemes: 's', phonemeId: 'S'),
      (graphemes: 'y', phonemeId: 'Y'),
    ]);

/// "sam" -- likewise matches graphemesToPhonemes('sam') exactly.
WordToken get _sam => _tok('sam', const [
      (graphemes: 's', phonemeId: 'S'),
      (graphemes: 'a', phonemeId: 'AE'),
      (graphemes: 'm', phonemeId: 'M'),
    ]);

/// The main 2-word, 8-phoneme fixture twister: target sequence
/// S,AE,S,S,Y,S,AE,M -- drills 'S' (four of the eight positions).
TongueTwister _mainTwister({String id = 'twister.sassy_sam'}) => TongueTwister(
      id: id,
      levelId: 'level.1',
      words: [_sassy, _sam],
      targetPhonemeId: 'S',
      narrationAudioRef: 'audio/twister/narration/$id.wav',
      packId: 'pack.starter',
    );

/// The full correct phoneme sequence for [_mainTwister], for scripting a
/// "produces every sound" hypothesis burst directly (bypassing G2P).
const List<String> _mainSequence = ['S', 'AE', 'S', 'S', 'Y', 'S', 'AE', 'M'];

/// A minimal 2-word, 4-phoneme fixture built ONLY to make the A-13
/// weighting-flip arithmetic exact: target sequence S,S,T,T, drilling 'S'
/// (positions 0 and 1 -- deliberately the FIRST two positions).
///
/// [SoundModeScorer]'s greedy in-order alignment (pinned by its library
/// doc) claims the first still-unmatched position for EVERY produced
/// phoneme once the per-phoneme distance is within [perPhonemeMaxDistance]
/// -- and since the uniform default distance metric only ever returns 0
/// (identical) or 1 (different), and the A-13 default
/// [kSoundModePerPhonemeMaxDistance] is itself 1, any two-phoneme
/// production claims the sequence's first two positions regardless of
/// which phonemes were produced. Placing the drilled phoneme's two
/// instances first (rather than scattering them) is what makes "producing
/// exactly two sounds" a clean, content-independent proxy for "credits
/// positions 0 and 1" -- see sound_mode_scorer_test.dart's own fixture-
/// design note for the same constraint. Word text/graphemes are otherwise
/// irrelevant: every scripted hypothesis in the weighting tests supplies
/// phoneHypotheses directly.
TongueTwister _weightFlipTwister() => TongueTwister(
      id: 'twister.weight_flip',
      levelId: 'level.1',
      words: [
        _tok('worda', const [(graphemes: 'w', phonemeId: 'S'), (graphemes: 'o', phonemeId: 'S')]),
        _tok('wordb', const [(graphemes: 'w', phonemeId: 'T'), (graphemes: 'o', phonemeId: 'T')]),
      ],
      targetPhonemeId: 'S',
      narrationAudioRef: 'audio/twister/narration/weight_flip.wav',
      packId: 'pack.starter',
    );

Hypothesis _phones(List<String> phones, {String word = '<phones>'}) =>
    Hypothesis(wordHypotheses: [word], phoneHypotheses: phones);

Hypothesis _wordOnly(String w) => Hypothesis(wordHypotheses: [w], phoneHypotheses: null);

/// Test harness: an in-memory DB, fake audio, and recorded analytics/
/// celebration callbacks, with a factory for constructing a
/// TwisterController wired to them.
class _Harness {
  _Harness()
      : db = AppDatabase(NativeDatabase.memory()),
        audio = FakeAudioService(clock: () => Duration.zero);

  final AppDatabase db;
  final FakeAudioService audio;
  final List<AnalyticsEvent> events = [];
  int celebrateCount = 0;

  Future<void> close() => db.close();

  TwisterController controller({
    required TongueTwister twister,
    required AsrEngine engine,
    bool micConsent = true,
    String profileId = 'profile.1',
    int profileOrdinal = 1,
    int levelOrdinal = 1,
    double? matchThreshold,
    int? perPhonemeMaxDistance,
    int? targetPhonemeWeight,
  }) =>
      TwisterController(
        twister: twister,
        engine: engine,
        audioService: audio,
        twisterProgressDao: db.twisterProgressDao,
        profileId: profileId,
        micConsent: micConsent,
        installId: _installId,
        profileOrdinal: profileOrdinal,
        levelOrdinal: levelOrdinal,
        onAnalyticsEvent: events.add,
        onCelebrate: () => celebrateCount += 1,
        matchThreshold: matchThreshold ?? kSoundModeMatchThreshold,
        perPhonemeMaxDistance: perPhonemeMaxDistance ?? kSoundModePerPhonemeMaxDistance,
        targetPhonemeWeight: targetPhonemeWeight ?? kSoundModeTargetPhonemeWeight,
      );
}

/// Drives [controller] past its narration beat: starts it, lets the
/// synchronous prefix run, plays the narration out to completion, and
/// flushes the microtasks that carry `start()` on into listening/tap mode.
/// Leaves any scripted engine hypotheses to be flushed by the caller.
void _passNarration(_Harness h, TwisterController controller, FakeAsync async) {
  unawaited(controller.start());
  async.flushMicrotasks();
  final handle = h.audio.callLog.whereType<PlayLogEntry>().first.handle;
  h.audio.completePlayback(handle);
  async.flushMicrotasks();
  async.flushMicrotasks();
}

void main() {
  group('POSITIVE: narration models the twister before listening begins', () {
    test('twister_started fires and narration plays synchronously in '
        'start(), before the engine is ever touched', () {
      fakeAsync((async) {
        final h = _Harness();
        final engine = FakeAsrEngine(script: const []);
        final twister = _mainTwister();
        final controller = h.controller(twister: twister, engine: engine);

        unawaited(controller.start());

        // Synchronous prefix: analytics + narration play, zero fake-clock
        // time elapsed, before any `await` inside start() suspends it.
        expect(async.elapsed, Duration.zero);
        expect(h.events.map((e) => e.name), contains(AnalyticsEventName.twisterStarted));
        final playLogs = h.audio.callLog.whereType<PlayLogEntry>().toList();
        expect(playLogs, hasLength(1));
        expect(playLogs.single.ref, twister.narrationAudioRef);
        expect(playLogs.single.channel, AudioChannel.narration);

        // Listening has not begun: the engine has not even been started.
        expect(engine.recordedBiasingContext, isNull);
        expect(controller.isListening, isFalse);

        unawaited(h.close());
      });
    });

    test('listening begins only after the narration finishes playing '
        '(FakeAudioService completionOf ordering)', () {
      fakeAsync((async) {
        final h = _Harness();
        final engine = FakeAsrEngine(script: const []);
        final twister = _mainTwister();
        final controller = h.controller(twister: twister, engine: engine);

        unawaited(controller.start());
        async.flushMicrotasks();
        // Still waiting on narration: no engine interaction yet.
        expect(engine.recordedBiasingContext, isNull);

        final handle = h.audio.callLog.whereType<PlayLogEntry>().first.handle;
        h.audio.completePlayback(handle);
        async.flushMicrotasks();
        async.flushMicrotasks();

        expect(engine.recordedBiasingContext, ['sassy', 'sam']);
        expect(controller.isListening, isTrue);

        unawaited(h.close());
      });
    });
  });

  group('POSITIVE: mic indicator reflects isListening across the session', () {
    test('false before narration ends, true once listening starts, false '
        'again once the twister completes', () {
      fakeAsync((async) {
        final h = _Harness();
        final engine = FakeAsrEngine(script: [_phones(_mainSequence)]);
        final controller = h.controller(twister: _mainTwister(), engine: engine);

        unawaited(controller.start());
        async.flushMicrotasks();
        expect(controller.isListening, isFalse, reason: 'narration still playing');

        final handle = h.audio.callLog.whereType<PlayLogEntry>().first.handle;
        h.audio.completePlayback(handle);
        async.flushMicrotasks();
        async.flushMicrotasks();
        expect(controller.isListening, isTrue, reason: 'engine now listening');

        // The scripted burst carries the full sequence -- accepted, so the
        // controller auto-completes and stops listening.
        async.flushMicrotasks();
        expect(controller.isComplete, isTrue);
        expect(controller.isListening, isFalse, reason: 'session ended on completion');

        unawaited(h.close());
      });
    });
  });

  group('POSITIVE: sound-level tracking advances even when word recognition '
      'would fail', () {
    test('a single burst producing the full correct phoneme sequence '
        'accepts and completes, despite nonsense word text', () {
      fakeAsync((async) {
        final h = _Harness();
        // Word text 'xyzxyz' would never match "sassy" or "sam" textually or
        // phonetically -- only the phones drive acceptance.
        final engine = FakeAsrEngine(
          script: [_phones(_mainSequence, word: 'xyzxyz')],
        );
        final controller = h.controller(twister: _mainTwister(), engine: engine);
        _passNarration(h, controller, async);

        expect(controller.matchedFraction, 1.0);
        expect(controller.accepted, isTrue);
        expect(controller.isComplete, isTrue);

        unawaited(h.close());
      });
    });

    test('a partial burst raises matchedFraction without yet accepting', () {
      fakeAsync((async) {
        final h = _Harness();
        // Three produced phonemes credit only the sequence's first three
        // (of eight) positions -- nowhere near the 60% (A-13) floor.
        final engine = FakeAsrEngine(script: [_phones(['S', 'AE', 'S'])]);
        final controller = h.controller(twister: _mainTwister(), engine: engine);
        _passNarration(h, controller, async);

        expect(controller.matchedFraction, greaterThan(0.0));
        expect(controller.accepted, isFalse);
        expect(controller.isComplete, isFalse);
        expect(controller.isListening, isTrue, reason: 'still mid-attempt');

        unawaited(h.close());
      });
    });
  });

  group('POSITIVE: word-hypothesis-only engines are approximated by '
      'phonetic-distance scoring (no phone-level detail)', () {
    test('correctly-spelled word-only hypotheses (phoneHypotheses: null) '
        'still accept via the G2P approximation path', () {
      fakeAsync((async) {
        final h = _Harness();
        final engine = FakeAsrEngine(script: [_wordOnly('sassy'), _wordOnly('sam')]);
        final controller = h.controller(twister: _mainTwister(), engine: engine);
        _passNarration(h, controller, async);

        expect(controller.matchedFraction, 1.0);
        expect(controller.accepted, isTrue);
        expect(controller.isComplete, isTrue);

        unawaited(h.close());
      });
    });
  });

  group('POSITIVE: the target phoneme is weighted most (A-13) -- a case '
      'where the weight flips the verdict', () {
    test('producing just the twister\'s first two sounds -- both instances '
        'of the drilled S -- accepts under the default double weight', () {
      fakeAsync((async) {
        final h = _Harness();
        final engine = FakeAsrEngine(script: [_phones(['S', 'S'])]);
        final controller = h.controller(twister: _weightFlipTwister(), engine: engine);
        _passNarration(h, controller, async);

        expect(controller.targetPhonemeWeight, kSoundModeTargetPhonemeWeight);
        // Positions 0,1 (both S, the drilled phoneme) are credited; weight
        // 2*2=4 over total weight 2*2+2*1=6 -> 0.667 >= 0.60.
        expect(controller.matchedFraction, closeTo(4 / 6, 1e-9));
        expect(controller.accepted, isTrue);
        expect(controller.isComplete, isTrue);

        unawaited(h.close());
      });
    });

    test('the identical production does NOT accept with an explicit '
        'weight-1 override -- the weight is genuinely consulted, not '
        'hardcoded', () {
      fakeAsync((async) {
        final h = _Harness();
        final engine = FakeAsrEngine(script: [_phones(['S', 'S'])]);
        final controller = h.controller(
          twister: _weightFlipTwister(),
          engine: engine,
          targetPhonemeWeight: 1,
        );
        _passNarration(h, controller, async);

        // matched 2 over total 4 -> 0.5 < 0.60.
        expect(controller.matchedFraction, closeTo(0.5, 1e-9));
        expect(controller.accepted, isFalse);
        expect(controller.isComplete, isFalse);

        unawaited(h.close());
      });
    });
  });

  group('POSITIVE: completion effects (mic path)', () {
    test('writes TwisterProgress, emits twister_completed, and celebrates '
        'exactly once', () {
      fakeAsync((async) {
        final h = _Harness();
        final engine = FakeAsrEngine(script: [_phones(_mainSequence)]);
        final controller = h.controller(
          twister: _mainTwister(id: 'twister.complete.1'),
          engine: engine,
          profileId: 'profile.amara',
          profileOrdinal: 2,
          levelOrdinal: 3,
        );
        _passNarration(h, controller, async);

        expect(controller.isComplete, isTrue);
        expect(h.celebrateCount, 1);
        expect(h.events.map((e) => e.name), containsAll(<AnalyticsEventName>[
          AnalyticsEventName.twisterStarted,
          AnalyticsEventName.twisterCompleted,
        ]));
        for (final event in h.events) {
          expect(() => validateEventPayload(event.toPayload()), returnsNormally);
          expect(event.storyId, isNull, reason: 'twister events never carry a storyId');
          expect(event.profileOrdinal, 2);
          expect(event.levelOrdinal, 3);
        }

        TwisterProgress? progress;
        h.db.twisterProgressDao
            .getProgress(profileId: 'profile.amara', twisterId: 'twister.complete.1')
            .then((p) => progress = p);
        async.flushMicrotasks();
        expect(progress, isNotNull);
        expect(progress!.timesCompleted, 1);

        unawaited(h.close());
      });
    });
  });

  group('NEGATIVE/EDGE: never hard-blocked -- micConsent off falls back to '
      'listen-then-tap', () {
    test('with micConsent false, the engine is never touched and the '
        'controller enters tap mode directly once narration ends', () {
      fakeAsync((async) {
        final h = _Harness();
        final engine = FakeAsrEngine(script: [_phones(_mainSequence)]);
        final controller = h.controller(
          twister: _mainTwister(),
          engine: engine,
          micConsent: false,
        );
        _passNarration(h, controller, async);

        expect(engine.recordedBiasingContext, isNull,
            reason: 'no consent -> the engine must never be started at all');
        expect(controller.isTapMode, isTrue);
        expect(controller.isListening, isFalse);
        expect(controller.isComplete, isFalse, reason: 'not yet tapped through');

        unawaited(h.close());
      });
    });

    test('tapping through every word completes the node -- TwisterProgress, '
        'twister_completed and the celebration all still fire', () {
      fakeAsync((async) {
        final h = _Harness();
        final engine = FakeAsrEngine(script: const []);
        final twister = _mainTwister(id: 'twister.tap.consent_off');
        final controller = h.controller(twister: twister, engine: engine, micConsent: false);
        _passNarration(h, controller, async);

        expect(controller.totalWordCount, 2);
        controller.tapWord();
        expect(controller.tappedWordCount, 1);
        expect(controller.isComplete, isFalse);
        controller.tapWord();
        async.flushMicrotasks();

        expect(controller.tappedWordCount, 2);
        expect(controller.isComplete, isTrue);
        expect(h.celebrateCount, 1);
        expect(h.events.map((e) => e.name), contains(AnalyticsEventName.twisterCompleted));

        TwisterProgress? progress;
        h.db.twisterProgressDao
            .getProgress(profileId: 'profile.1', twisterId: 'twister.tap.consent_off')
            .then((p) => progress = p);
        async.flushMicrotasks();
        expect(progress?.timesCompleted, 1);

        unawaited(h.close());
      });
    });
  });

  group('NEGATIVE/EDGE: never hard-blocked -- engine failure falls back to '
      'listen-then-tap', () {
    test('with a failing engine, start IS attempted (biasing recorded) but '
        'the controller still falls into tap mode', () {
      fakeAsync((async) {
        final h = _Harness();
        final engine = FakeAsrEngine(script: const [], shouldFail: true);
        final controller = h.controller(twister: _mainTwister(), engine: engine);
        _passNarration(h, controller, async);

        expect(engine.recordedBiasingContext, ['sassy', 'sam'],
            reason: 'an attempt to start the real engine is made');
        expect(controller.isTapMode, isTrue);
        expect(controller.isListening, isFalse);

        unawaited(h.close());
      });
    });

    test('tapping through every word completes the node on engine failure '
        'too', () {
      fakeAsync((async) {
        final h = _Harness();
        final engine = FakeAsrEngine(script: const [], shouldFail: true);
        final twister = _mainTwister(id: 'twister.tap.engine_failure');
        final controller = h.controller(twister: twister, engine: engine);
        _passNarration(h, controller, async);

        controller.tapWord();
        controller.tapWord();
        async.flushMicrotasks();

        expect(controller.isComplete, isTrue);
        expect(h.celebrateCount, 1);

        unawaited(h.close());
      });
    });
  });

  group('EDGE: twisters are always replayable', () {
    test('re-entry after completion is a fresh, un-done controller, and '
        'timesCompleted increments across runs', () {
      fakeAsync((async) {
        final h = _Harness();
        final twister = _mainTwister(id: 'twister.replay');

        final firstEngine = FakeAsrEngine(script: [_phones(_mainSequence)]);
        final first = h.controller(twister: twister, engine: firstEngine);
        _passNarration(h, first, async);
        expect(first.isComplete, isTrue);

        // Re-entry: a brand-new controller for the same twister/profile.
        final secondEngine = FakeAsrEngine(script: [_phones(_mainSequence)]);
        final second = h.controller(twister: twister, engine: secondEngine);
        expect(second.isComplete, isFalse,
            reason: 'a fresh controller carries no completed-lock from before');

        _passNarration(h, second, async);
        expect(second.isComplete, isTrue);

        TwisterProgress? progress;
        h.db.twisterProgressDao
            .getProgress(profileId: 'profile.1', twisterId: 'twister.replay')
            .then((p) => progress = p);
        async.flushMicrotasks();
        expect(progress?.timesCompleted, 2);

        unawaited(h.close());
      });
    });
  });

  group('POSITIVE: sparkle celebration is distinct from story celebration '
      '(widget test)', () {
    testWidgets('renders no rive.RiveAnimation (no story artboard)', (tester) async {
      var finished = false;
      await tester.pumpWidget(MaterialApp(
        home: SparkleCelebration(onFinished: () => finished = true),
      ));

      expect(find.byType(rive.RiveAnimation), findsNothing);

      await tester.pump(kSparkleCelebrationDuration);
      expect(finished, isTrue);
    });

    testWidgets('finishes at exactly its own duration -- no additional '
        "collectible-flight beat tacked on", (tester) async {
      var finished = false;
      await tester.pumpWidget(MaterialApp(
        home: SparkleCelebration(onFinished: () => finished = true),
      ));

      await tester.pump(kSparkleCelebrationDuration - const Duration(milliseconds: 1));
      expect(finished, isFalse);

      await tester.pump(const Duration(milliseconds: 1));
      expect(finished, isTrue);
    });

    testWidgets('a custom duration is honored (constructor takes no '
        'StoryStage / collectible ref -- only onFinished and duration)', (tester) async {
      var finished = false;
      await tester.pumpWidget(MaterialApp(
        home: SparkleCelebration(
          onFinished: () => finished = true,
          duration: const Duration(milliseconds: 500),
        ),
      ));

      await tester.pump(const Duration(milliseconds: 499));
      expect(finished, isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      expect(finished, isTrue);
    });
  });

  group('[DEVICE] pixel golden -- not testable headlessly, skipped with reason', () {
    test(
      'sparkle celebration reads as visually playful and distinct from the '
      'story celebration',
      () {},
      skip: '[DEVICE] the actual sparkle illustration/motion is '
          'owner-commissioned art (PRD §8 Unit 1 storybook-illustrated '
          'direction); this container has no shipped sparkle asset, so a '
          'pixel golden here would pin placeholder painting, not the real '
          'treatment. The headless proxies above (no rive.RiveAnimation in '
          'the tree, no collectible-flight beat, distinct default duration '
          'from kCelebrationDefaultAnimationDuration) are the structural '
          'stand-in this suite pins instead.',
    );
  });
}

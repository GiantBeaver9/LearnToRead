// Test suite for the "twister threshold set, not the story set" acceptance
// (PRD §8 Unit 14 accept: "word tracking uses the twister threshold set,
// not the story set — asserted via matcher config injection"; §9 A-13;
// ticket twister-flow). Pinned API under test: see twister_flow_test.dart
// (canonical) for TwisterController's full shape. This file additionally
// pins that the A-13 sound-mode tunables actually reach the controller's
// internal `SoundModeScorer` (config injection), rather than the word-mode
// `WordMatcher` thresholds in lib/domain/tuning.dart
// (kWordModeShortWordMaxPhonemes / kWordModeMaxSubstitutedPhonemesShortWord
// / kWordModeMaxSubstitutedPhonemesLongWord) ever being consulted.
//
// lib/features/twister/twister_controller.dart does not exist yet: every
// import below fails to resolve, which is the expected red state.
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/tuning.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/analytics/events.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/contracts/fake_asr_engine.dart';
import 'package:learn_to_read/features/twister/twister_controller.dart';

const _installId = 'a1b2c3d4-1234-4abc-8def-0123456789ab';

WordToken _tok(String text, List<({String graphemes, String phonemeId})> map) =>
    WordToken(text: text, graphemePhonemeMap: map, pronunciationAudioRef: 'audio/$text.wav');

/// The same 2-word, 8-phoneme fixture as twister_flow_test.dart's
/// `_mainTwister` (target sequence S,AE,S,S,Y,S,AE,M, drilling 'S').
TongueTwister _mainTwister() => TongueTwister(
      id: 'twister.sassy_sam',
      levelId: 'level.1',
      words: [
        _tok('sassy', const [
          (graphemes: 's', phonemeId: 'S'),
          (graphemes: 'a', phonemeId: 'AE'),
          (graphemes: 's', phonemeId: 'S'),
          (graphemes: 's', phonemeId: 'S'),
          (graphemes: 'y', phonemeId: 'Y'),
        ]),
        _tok('sam', const [
          (graphemes: 's', phonemeId: 'S'),
          (graphemes: 'a', phonemeId: 'AE'),
          (graphemes: 'm', phonemeId: 'M'),
        ]),
      ],
      targetPhonemeId: 'S',
      narrationAudioRef: 'audio/twister/narration/sassy_sam.wav',
      packId: 'pack.starter',
    );

Hypothesis _phones(List<String> phones) =>
    Hypothesis(wordHypotheses: const ['<phones>'], phoneHypotheses: phones);

class _Harness {
  _Harness()
      : db = AppDatabase(NativeDatabase.memory()),
        audio = FakeAudioService(clock: () => Duration.zero);

  final AppDatabase db;
  final FakeAudioService audio;
  final List<AnalyticsEvent> events = [];

  Future<void> close() => db.close();

  TwisterController controller({
    required TongueTwister twister,
    required AsrEngine engine,
    double? matchThreshold,
    int? perPhonemeMaxDistance,
    int? targetPhonemeWeight,
  }) =>
      TwisterController(
        twister: twister,
        engine: engine,
        audioService: audio,
        twisterProgressDao: db.twisterProgressDao,
        profileId: 'profile.1',
        micConsent: true,
        installId: _installId,
        profileOrdinal: 1,
        levelOrdinal: 1,
        onAnalyticsEvent: events.add,
        matchThreshold: matchThreshold ?? kSoundModeMatchThreshold,
        perPhonemeMaxDistance: perPhonemeMaxDistance ?? kSoundModePerPhonemeMaxDistance,
        targetPhonemeWeight: targetPhonemeWeight ?? kSoundModeTargetPhonemeWeight,
      );
}

void _passNarration(_Harness h, TwisterController controller, FakeAsync async) {
  unawaited(controller.start());
  async.flushMicrotasks();
  final handle = h.audio.callLog.whereType<PlayLogEntry>().first.handle;
  h.audio.completePlayback(handle);
  async.flushMicrotasks();
  async.flushMicrotasks();
}

void main() {
  group('fixture premise — pinned A-13 tuning defaults', () {
    test('POSITIVE: the sound-mode constants this suite derives its exact '
        'fractions from hold their pinned values', () {
      expect(kSoundModeMatchThreshold, 0.60);
      expect(kSoundModePerPhonemeMaxDistance, 1);
      expect(kSoundModeTargetPhonemeWeight, 2);
    });
  });

  group('POSITIVE: an unconfigured controller uses the A-13 defaults, not '
      'hardcoded literals', () {
    test('matchThreshold / perPhonemeMaxDistance / targetPhonemeWeight '
        'getters mirror lib/domain/tuning.dart exactly when no override is '
        'given', () {
      final h = _Harness();
      final controller = h.controller(
        twister: _mainTwister(),
        engine: FakeAsrEngine(script: const []),
      );

      expect(controller.matchThreshold, kSoundModeMatchThreshold);
      expect(controller.perPhonemeMaxDistance, kSoundModePerPhonemeMaxDistance);
      expect(controller.targetPhonemeWeight, kSoundModeTargetPhonemeWeight);

      unawaited(h.close());
    });
  });

  group('POSITIVE: threshold overrides are genuinely consulted (config '
      'injection), not ignored', () {
    test('a burst that accepts at the default 0.60 threshold does NOT '
        'accept once matchThreshold is raised past its matchedFraction', () {
      fakeAsync((async) {
        // Five of eight positions credited -> weighted fraction 8/12 ≈
        // 0.667 (see twister_flow_test.dart's "partial burst" derivation).
        final defaultHarness = _Harness();
        // Orchestrator test-fix (A-13 metric clarification, PRD c2d9e9e): the
        // original burst used arbitrary symbols ('A'..'E'), which only earned
        // position credit under the since-corrected any-phoneme metric. Real
        // target phonemes preserve the identical weighted fractions.
        final defaultEngine = FakeAsrEngine(script: [_phones(['S', 'AE', 'S', 'S', 'Y'])]);
        final defaultController =
            defaultHarness.controller(twister: _mainTwister(), engine: defaultEngine);
        _passNarration(defaultHarness, defaultController, async);
        expect(defaultController.matchedFraction, closeTo(8 / 12, 1e-9));
        expect(defaultController.accepted, isTrue);
        expect(defaultController.isComplete, isTrue);
        unawaited(defaultHarness.close());

        final strictHarness = _Harness();
        final strictEngine = FakeAsrEngine(script: [_phones(['S', 'AE', 'S', 'S', 'Y'])]);
        final strictController = strictHarness.controller(
          twister: _mainTwister(),
          engine: strictEngine,
          matchThreshold: 0.90,
        );
        _passNarration(strictHarness, strictController, async);
        expect(strictController.matchThreshold, 0.90);
        expect(strictController.matchedFraction, closeTo(8 / 12, 1e-9));
        expect(strictController.accepted, isFalse,
            reason: 'same production, stricter injected threshold');
        expect(strictController.isComplete, isFalse);
        unawaited(strictHarness.close());
      });
    });

    test('lowering matchThreshold accepts a burst the A-13 default would '
        'reject', () {
      fakeAsync((async) {
        // Two of eight positions credited -> weighted fraction 3/12 = 0.25,
        // well under the A-13 default floor.
        final h = _Harness();
        final engine = FakeAsrEngine(script: [_phones(['S', 'AE'])]);
        final controller = h.controller(
          twister: _mainTwister(),
          engine: engine,
          matchThreshold: 0.20,
        );
        _passNarration(h, controller, async);

        expect(controller.matchedFraction, closeTo(3 / 12, 1e-9));
        expect(controller.accepted, isTrue);
        expect(controller.isComplete, isTrue);

        unawaited(h.close());
      });
    });
  });

  group('POSITIVE: the twister/sound-mode set is looser than the story/'
      'word-mode set (proof the wrong config is not silently in effect)', () {
    test('a burst missing three of eight sequence positions -- more '
        'omissions than word-mode\'s near-miss tolerance for a word this '
        'long would ever accept -- still accepts under the twister/A-13 '
        'set', () {
      fakeAsync((async) {
        // word-mode's near-miss ceiling for a long word tolerates at most
        // kWordModeMaxSubstitutedPhonemesLongWord (2) wrong phonemes before
        // rejecting outright; this burst leaves THREE of the twister's
        // eight target positions completely uncovered and still accepts,
        // because sound mode grades against A-13's 60%-of-sequence floor,
        // not the story engine's near-miss policy.
        expect(kWordModeMaxSubstitutedPhonemesLongWord, lessThan(3));

        final h = _Harness();
        final engine = FakeAsrEngine(script: [_phones(['S', 'AE', 'S', 'S', 'Y'])]);
        final controller = h.controller(twister: _mainTwister(), engine: engine);
        _passNarration(h, controller, async);

        expect(controller.matchedFraction, closeTo(8 / 12, 1e-9));
        expect(controller.accepted, isTrue,
            reason: 'A-13\'s looser sound-mode floor, not the story near-miss '
                'policy, governs twister acceptance');

        unawaited(h.close());
      });
    });
  });
}

// Test suite for the "no collectible" acceptance (PRD §8 Unit 14 pinned:
// "No collectible (collectibles remain story-tied)"; ticket twister-flow
// accept: "Completion writes TwisterProgress (timesCompleted incremented)
// and grants NO collectible... no_collectible_test asserts CollectionState
// untouched"). Pinned API under test: see twister_flow_test.dart
// (canonical) for TwisterController's full shape.
//
// lib/features/twister/twister_controller.dart does not exist yet: every
// import below fails to resolve, which is the expected red state.
//
// Structural note this suite leans on: TwisterController's constructor
// (see twister_flow_test.dart's pinned header) takes a TwisterProgressDao
// but deliberately NO CollectionDao at all -- there is nowhere for a
// collectible grant to come from. Every test below is the behavioral
// confirmation that this holds across every completion path (mic-accepted,
// listen-then-tap, and repeated replays).
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/analytics/events.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/contracts/fake_asr_engine.dart';
import 'package:learn_to_read/features/twister/twister_controller.dart';

const _installId = 'a1b2c3d4-1234-4abc-8def-0123456789ab';

WordToken _tok(String text, List<({String graphemes, String phonemeId})> map) =>
    WordToken(text: text, graphemePhonemeMap: map, pronunciationAudioRef: 'audio/$text.wav');

TongueTwister _mainTwister({String id = 'twister.sassy_sam'}) => TongueTwister(
      id: id,
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
      narrationAudioRef: 'audio/twister/narration/$id.wav',
      packId: 'pack.starter',
    );

const List<String> _fullSequence = ['S', 'AE', 'S', 'S', 'Y', 'S', 'AE', 'M'];

Hypothesis _fullMatch() =>
    Hypothesis(wordHypotheses: const ['<phones>'], phoneHypotheses: _fullSequence);

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
    bool micConsent = true,
    String profileId = 'profile.1',
  }) =>
      TwisterController(
        twister: twister,
        engine: engine,
        audioService: audio,
        twisterProgressDao: db.twisterProgressDao,
        profileId: profileId,
        micConsent: micConsent,
        installId: _installId,
        profileOrdinal: 1,
        levelOrdinal: 1,
        onAnalyticsEvent: events.add,
      );

  void passNarration(TwisterController controller, FakeAsync async) {
    unawaited(controller.start());
    async.flushMicrotasks();
    // Orchestrator test-fix: on replay the shared FakeAudioService still
    // holds run 1's finished handle; .first re-completed that no-op and
    // run 2+'s narration never resolved. Complete the most recent play.
    final handle = audio.callLog.whereType<PlayLogEntry>().last.handle;
    audio.completePlayback(handle);
    async.flushMicrotasks();
    async.flushMicrotasks();
  }

  /// Reads back [CollectionState] for [profileId] synchronously from the
  /// caller's point of view: issues the DAO call then drains exactly the
  /// microtasks an in-memory Drift query needs to resolve.
  CollectionState collectionState(String profileId, FakeAsync async) {
    CollectionState? state;
    db.collectionDao.getCollectionState(profileId).then((s) => state = s);
    async.flushMicrotasks();
    return state!;
  }

  int collectionRowCount(String profileId, FakeAsync async) {
    int? count;
    db.collectionDao.rowCountForProfile(profileId).then((c) => count = c);
    async.flushMicrotasks();
    return count!;
  }

  TwisterProgress? twisterProgress(String profileId, String twisterId, FakeAsync async) {
    TwisterProgress? progress;
    db.twisterProgressDao
        .getProgress(profileId: profileId, twisterId: twisterId)
        .then((p) => progress = p);
    async.flushMicrotasks();
    return progress;
  }
}

void main() {
  group('POSITIVE: mic-path completion writes TwisterProgress and leaves '
      'CollectionState untouched', () {
    test('a fully-matched sound-mode completion increments '
        'timesCompleted but earns nothing in CollectionState', () {
      fakeAsync((async) {
        final h = _Harness();
        final engine = FakeAsrEngine(script: [_fullMatch()]);
        final controller = h.controller(
          twister: _mainTwister(id: 'twister.mic'),
          engine: engine,
          profileId: 'profile.no_collectible.mic',
        );
        h.passNarration(controller, async);

        expect(controller.isComplete, isTrue);
        expect(h.events.map((e) => e.name), contains(AnalyticsEventName.twisterCompleted));

        final progress = h.twisterProgress('profile.no_collectible.mic', 'twister.mic', async);
        expect(progress, isNotNull);
        expect(progress!.timesCompleted, 1);

        final state = h.collectionState('profile.no_collectible.mic', async);
        expect(state.earnedCollectibles, isEmpty);
        expect(h.collectionRowCount('profile.no_collectible.mic', async), 0);

        unawaited(h.close());
      });
    });
  });

  group('POSITIVE: listen-then-tap completion also writes TwisterProgress '
      'and leaves CollectionState untouched', () {
    test('a consent-off, fully-tapped completion increments '
        'timesCompleted but earns nothing in CollectionState', () {
      fakeAsync((async) {
        final h = _Harness();
        final engine = FakeAsrEngine(script: const []);
        final controller = h.controller(
          twister: _mainTwister(id: 'twister.tap'),
          engine: engine,
          micConsent: false,
          profileId: 'profile.no_collectible.tap',
        );
        h.passNarration(controller, async);

        expect(controller.isTapMode, isTrue);
        controller.tapWord();
        controller.tapWord();
        async.flushMicrotasks();

        expect(controller.isComplete, isTrue);

        final progress = h.twisterProgress('profile.no_collectible.tap', 'twister.tap', async);
        expect(progress?.timesCompleted, 1);

        final state = h.collectionState('profile.no_collectible.tap', async);
        expect(state.earnedCollectibles, isEmpty);

        unawaited(h.close());
      });
    });
  });

  group('POSITIVE: CollectionState remains empty across repeated replays, '
      'even as TwisterProgress keeps incrementing', () {
    test('three completions of the same twister leave CollectionState '
        'empty throughout, with timesCompleted reaching 3', () {
      fakeAsync((async) {
        final h = _Harness();
        final twister = _mainTwister(id: 'twister.replay');
        const profileId = 'profile.no_collectible.replay';

        for (var i = 0; i < 3; i++) {
          final engine = FakeAsrEngine(script: [_fullMatch()]);
          final controller = h.controller(
            twister: twister,
            engine: engine,
            profileId: profileId,
          );
          h.passNarration(controller, async);
          expect(controller.isComplete, isTrue);

          expect(h.collectionRowCount(profileId, async), 0, reason: 'run ${i + 1}: still no collectible');
        }

        final progress = h.twisterProgress(profileId, 'twister.replay', async);
        expect(progress?.timesCompleted, 3);

        unawaited(h.close());
      });
    });
  });
}

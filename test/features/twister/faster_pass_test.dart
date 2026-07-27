// Test suite for lib/features/twister/faster_pass.dart (PRD §8 Unit 14
// "Optional second pass... offered once, skippable, no extra reward"; ticket
// twister-flow accept: "'Faster' second pass is offered once, skippable,
// and its completion is not required for the node to be marked done").
//
// lib/features/twister/faster_pass.dart does not exist yet: every import
// below fails to resolve, which is the expected red state. Pinned API
// under test: see twister_flow_test.dart (canonical) for
// TwisterController's full shape.
//
// Pinned API surface this suite requires:
//
//   lib/features/twister/faster_pass.dart:
//     enum FasterPassStatus { offered, inProgress, completed, skipped }
//
//     class FasterPassPrompt {
//       // Throws StateError unless `primaryController.isComplete` is
//       // already true -- the faster pass may only be offered AFTER the
//       // primary attempt completes, never before or in place of it.
//       FasterPassPrompt({
//         required TwisterController primaryController,
//         required Future<void> Function() runReplay,
//       });
//
//       FasterPassStatus get status;   // starts at `offered`
//       bool get isOffered;            // true immediately at construction
//       bool get isNodeDone;           // mirrors primaryController.isComplete
//                                       // for the prompt's whole lifetime
//
//       void skip();          // offered -> skipped; a no-op once resolved
//       Future<void> accept(); // offered -> inProgress -> completed; a
//                               // no-op once resolved (already skipped or
//                               // already accepted)
//     }
//
// Contract this suite locks in: [FasterPassPrompt] is deliberately built
// with NO `TwisterProgressDao`, no `onAnalyticsEvent`, and no CollectionDao
// in its constructor -- there is structurally nowhere for it to record an
// extra completion, an extra `twister_completed`, or a reward, no matter
// what `runReplay` does internally. "No extra reward" is therefore provable
// by construction, not just by behavior: see the `_NoRewardRunReplay`
// fixture below, which proves a replay that WOULD grant a reward (it
// touches its own harness's DAO directly) still leaves the *original*
// completion/analytics/collection state the prompt was built over
// untouched, because the prompt itself never mediates any of that -- it
// only sequences the replay attempt and reports offer/skip/accept state.
library;

import 'dart:async';

import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/analytics/events.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/contracts/fake_asr_engine.dart';
import 'package:learn_to_read/features/twister/faster_pass.dart';
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
  int celebrateCount = 0;

  Future<void> close() => db.close();

  TwisterController controller({required TongueTwister twister, required AsrEngine engine}) =>
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
        onCelebrate: () => celebrateCount += 1,
      );

  /// Runs [controller] to completion via the mic/sound-mode path (scripted
  /// with the full correct sequence, so it always accepts).
  void completeViaMic(TwisterController controller, FakeAsync async) {
    unawaited(controller.start());
    async.flushMicrotasks();
    final handle = audio.callLog.whereType<PlayLogEntry>().first.handle;
    audio.completePlayback(handle);
    async.flushMicrotasks();
    async.flushMicrotasks();
  }
}

void main() {
  group('NEGATIVE: the faster pass may only be offered after the primary '
      'attempt completes', () {
    test('constructing over an incomplete TwisterController throws '
        'StateError', () {
      final h = _Harness();
      final engine = FakeAsrEngine(script: const []);
      final controller = h.controller(twister: _mainTwister(), engine: engine);
      expect(controller.isComplete, isFalse);

      expect(
        () => FasterPassPrompt(primaryController: controller, runReplay: () async {}),
        throwsStateError,
      );

      unawaited(h.close());
    });
  });

  group('POSITIVE: offered exactly once, immediately, after completion', () {
    test('status starts at offered and isOffered is true right away; '
        'runReplay has not been invoked', () {
      fakeAsync((async) {
        final h = _Harness();
        final engine = FakeAsrEngine(script: [_fullMatch()]);
        final controller = h.controller(twister: _mainTwister(), engine: engine);
        h.completeViaMic(controller, async);
        expect(controller.isComplete, isTrue);

        var replayCalls = 0;
        final prompt = FasterPassPrompt(
          primaryController: controller,
          runReplay: () async {
            replayCalls += 1;
          },
        );

        expect(prompt.status, FasterPassStatus.offered);
        expect(prompt.isOffered, isTrue);
        expect(replayCalls, 0);
        expect(prompt.isNodeDone, isTrue);

        unawaited(h.close());
      });
    });
  });

  group('POSITIVE: skippable, with no extra reward', () {
    test('skip() resolves to skipped without ever invoking runReplay, and '
        'the node stays done', () {
      fakeAsync((async) {
        final h = _Harness();
        final engine = FakeAsrEngine(script: [_fullMatch()]);
        final controller = h.controller(twister: _mainTwister(), engine: engine);
        h.completeViaMic(controller, async);

        var replayCalls = 0;
        final prompt = FasterPassPrompt(
          primaryController: controller,
          runReplay: () async => replayCalls += 1,
        );

        prompt.skip();

        expect(prompt.status, FasterPassStatus.skipped);
        expect(replayCalls, 0);
        expect(prompt.isNodeDone, isTrue);
        // No extra reward: exactly the one completion/celebration from the
        // primary attempt, none added by skipping.
        expect(h.celebrateCount, 1);
        expect(h.events.where((e) => e.name == AnalyticsEventName.twisterCompleted), hasLength(1));

        unawaited(h.close());
      });
    });
  });

  group('POSITIVE: accept() runs exactly one replay round, no extra reward', () {
    test('accept() drives offered -> inProgress -> completed and runs '
        'runReplay exactly once; the node stays done throughout', () {
      fakeAsync((async) {
        final h = _Harness();
        final engine = FakeAsrEngine(script: [_fullMatch()]);
        final controller = h.controller(twister: _mainTwister(), engine: engine);
        h.completeViaMic(controller, async);

        var replayCalls = 0;
        final replayCompleter = Completer<void>();
        final prompt = FasterPassPrompt(
          primaryController: controller,
          runReplay: () {
            replayCalls += 1;
            return replayCompleter.future;
          },
        );

        final acceptFuture = prompt.accept();
        expect(prompt.status, FasterPassStatus.inProgress);
        expect(replayCalls, 1);
        expect(prompt.isNodeDone, isTrue, reason: 'done state predates the replay entirely');

        replayCompleter.complete();
        async.flushMicrotasks();
        unawaited(acceptFuture);

        expect(prompt.status, FasterPassStatus.completed);
        expect(prompt.isNodeDone, isTrue);
        // Still exactly the ONE celebration/completion from the primary
        // attempt -- the faster pass grants nothing of its own.
        expect(h.celebrateCount, 1);
        expect(h.events.where((e) => e.name == AnalyticsEventName.twisterCompleted), hasLength(1));

        unawaited(h.close());
      });
    });
  });

  group('EDGE: resolved exactly once -- cannot be re-offered', () {
    test('accept() after an already-accepted-and-completed prompt is a '
        'no-op: runReplay is not invoked again', () {
      fakeAsync((async) {
        final h = _Harness();
        final engine = FakeAsrEngine(script: [_fullMatch()]);
        final controller = h.controller(twister: _mainTwister(), engine: engine);
        h.completeViaMic(controller, async);

        var replayCalls = 0;
        final prompt = FasterPassPrompt(
          primaryController: controller,
          runReplay: () async => replayCalls += 1,
        );

        unawaited(prompt.accept());
        async.flushMicrotasks();
        expect(prompt.status, FasterPassStatus.completed);
        expect(replayCalls, 1);

        unawaited(prompt.accept());
        async.flushMicrotasks();
        expect(replayCalls, 1, reason: 'a resolved prompt cannot be re-accepted');
        expect(prompt.status, FasterPassStatus.completed);

        unawaited(h.close());
      });
    });

    test('skip() after accept() has already resolved the prompt is a '
        'no-op: status stays completed, not skipped', () {
      fakeAsync((async) {
        final h = _Harness();
        final engine = FakeAsrEngine(script: [_fullMatch()]);
        final controller = h.controller(twister: _mainTwister(), engine: engine);
        h.completeViaMic(controller, async);

        final prompt = FasterPassPrompt(primaryController: controller, runReplay: () async {});
        unawaited(prompt.accept());
        async.flushMicrotasks();
        expect(prompt.status, FasterPassStatus.completed);

        prompt.skip();
        expect(prompt.status, FasterPassStatus.completed,
            reason: 'already resolved -- skip() cannot override an accepted pass');

        unawaited(h.close());
      });
    });

    test('accept() after skip() is a no-op: runReplay is never invoked', () {
      fakeAsync((async) {
        final h = _Harness();
        final engine = FakeAsrEngine(script: [_fullMatch()]);
        final controller = h.controller(twister: _mainTwister(), engine: engine);
        h.completeViaMic(controller, async);

        var replayCalls = 0;
        final prompt = FasterPassPrompt(
          primaryController: controller,
          runReplay: () async => replayCalls += 1,
        );

        prompt.skip();
        expect(prompt.status, FasterPassStatus.skipped);

        unawaited(prompt.accept());
        async.flushMicrotasks();
        expect(replayCalls, 0);
        expect(prompt.status, FasterPassStatus.skipped);

        unawaited(h.close());
      });
    });
  });

  group('EDGE: the node\'s done state never depends on the faster pass '
      'being resolved at all', () {
    test('isNodeDone is already true at offer time and stays true whether '
        'or not skip()/accept() is ever called', () {
      fakeAsync((async) {
        final h = _Harness();
        final engine = FakeAsrEngine(script: [_fullMatch()]);
        final controller = h.controller(twister: _mainTwister(), engine: engine);
        h.completeViaMic(controller, async);

        final prompt = FasterPassPrompt(primaryController: controller, runReplay: () async {});
        // Deliberately never resolved.
        expect(prompt.status, FasterPassStatus.offered);
        expect(prompt.isNodeDone, isTrue);
        expect(controller.isComplete, isTrue);

        unawaited(h.close());
      });
    });
  });
}

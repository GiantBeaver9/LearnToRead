// Test suite for lib/features/sound_garden/echo_session.dart (PRD §8 Unit
// 15 "a gentle prompt invites the child to say it back, scored with
// sound-level matching"; §8 Unit 4 sound mode; §9 A-13; ticket sound-garden
// accept entry 4).
//
// lib/features/sound_garden/echo_session.dart does not exist yet: every
// import below fails to resolve, which is the expected red state.
//
// See sound_garden_screen_test.dart for the canonical pinned API. This file
// restates and is the authority for EchoSession's own contract:
//
//   class EchoResult {
//     const EchoResult({required bool matched, required double matchedFraction});
//     final bool matched;
//     final double matchedFraction;
//   }
//
//   class EchoSession {
//     EchoSession({
//       required AsrEngine engine,
//       required SoundModeScorer scorer,
//       List<String> biasingContext = const [],
//     });
//     bool get isListening;   // true from start() until stop()
//     bool get matched;       // mirrors scorer.accepted, monotone
//     double get matchedFraction; // mirrors scorer.matchedFraction
//     void start({void Function()? onMatch});
//       // -- calls engine.start(biasingContext), then subscribes to
//       //    engine.hypothesesStream, feeding every hypothesis to
//       //    scorer.onHypothesis. The FIRST time scorer.accepted flips from
//       //    false to true, `onMatch` fires exactly once (never again for
//       //    this session, even if more hypotheses arrive).
//     EchoResult stop();
//       // -- cancels the hypothesis subscription, calls engine.stop(),
//       //    sets isListening false, and returns the final EchoResult.
//       //    Idempotent: calling stop() again is a safe no-op returning the
//       //    same result.
//   }
//
// This is deliberately a lightweight engine+scorer loop (ticket note: "do
// NOT pull in listening-tracker (no words, no silence/struggle/tap
// semantics here)") -- EchoSession has no notion of a word, a silence
// timer, a struggle counter, or a tap fallback; it exists purely to wire
// one AsrEngine to one SoundModeScorer for one echo attempt. The "asserted
// via matcher config injection" acceptance is satisfied by every test below
// constructing its SoundModeScorer explicitly from lib/domain/tuning.dart's
// A-13 constants (never hardcoded numbers) and handing that scorer to
// EchoSession -- proving the session routes hypotheses through whatever
// scorer configuration it is given.
library;

import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/tuning.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/contracts/fake_asr_engine.dart';
import 'package:learn_to_read/features/listening/matcher/sound_mode_scorer.dart';
import 'package:learn_to_read/features/sound_garden/echo_session.dart';

Hypothesis _phones(List<String> phones) =>
    Hypothesis(wordHypotheses: const ['<phones>'], phoneHypotheses: phones);

/// A hand-controlled AsrEngine double (mirrors reading_tracker_test.dart's
/// `_ControlledAsrEngine`): records every start/stop call so tests can
/// assert the exact engine lifecycle EchoSession drives, independent of
/// FakeAsrEngine's scripted-stream mechanics.
class _RecordingAsrEngine implements AsrEngine {
  final List<List<String>> startCalls = [];
  int stopCallCount = 0;

  @override
  void start(List<String> biasingContext) => startCalls.add(biasingContext);

  @override
  void stop() => stopCallCount += 1;

  @override
  Stream<Hypothesis> get hypothesesStream => const Stream.empty();
}

/// A single-grapheme scorer (digraph "sh" -> one phoneme 'SH'), configured
/// from the A-13 tuning constants -- never hardcoded.
SoundModeScorer _shScorer() => SoundModeScorer(
      targetPhonemeSequence: const ['SH'],
      targetPhonemeId: 'SH',
      matchThreshold: kSoundModeMatchThreshold,
      perPhonemeMaxDistance: kSoundModePerPhonemeMaxDistance,
      targetPhonemeWeight: kSoundModeTargetPhonemeWeight,
    );

/// A multi-phoneme scorer (blend "bl" -> ['B', 'L']), same A-13 constants.
SoundModeScorer _blScorer() => SoundModeScorer(
      targetPhonemeSequence: const ['B', 'L'],
      targetPhonemeId: 'B',
      matchThreshold: kSoundModeMatchThreshold,
      perPhonemeMaxDistance: kSoundModePerPhonemeMaxDistance,
      targetPhonemeWeight: kSoundModeTargetPhonemeWeight,
    );

void main() {
  group('EchoSession — engine lifecycle', () {
    test('POSITIVE: start() calls engine.start exactly once', () {
      final engine = _RecordingAsrEngine();
      final session = EchoSession(engine: engine, scorer: _shScorer());

      session.start();

      expect(engine.startCalls, hasLength(1));
      expect(session.isListening, isTrue);
    });

    test('POSITIVE: stop() calls engine.stop exactly once and flips '
        'isListening false', () {
      final engine = _RecordingAsrEngine();
      final session = EchoSession(engine: engine, scorer: _shScorer());

      session.start();
      session.stop();

      expect(engine.stopCallCount, 1);
      expect(session.isListening, isFalse);
    });

    test('EDGE: calling stop() twice is a safe no-op the second time -- '
        'engine.stop is not called again', () {
      final engine = _RecordingAsrEngine();
      final session = EchoSession(engine: engine, scorer: _shScorer());

      session.start();
      final first = session.stop();
      final second = session.stop();

      expect(engine.stopCallCount, 1);
      expect(second.matched, first.matched);
      expect(second.matchedFraction, first.matchedFraction);
    });
  });

  group('EchoSession — sparkle on match (single-phoneme card, accept 4)', () {
    test('POSITIVE: a matching hypothesis flips matched to true and fires '
        'onMatch exactly once', () {
      fakeAsync((async) {
        final engine = FakeAsrEngine(script: [_phones(const ['SH'])]);
        final session = EchoSession(engine: engine, scorer: _shScorer());
        var matchCount = 0;

        session.start(onMatch: () => matchCount++);
        async.flushMicrotasks();

        expect(session.matched, isTrue);
        expect(matchCount, 1);
        expect(session.matchedFraction, closeTo(1.0, 1e-9));
      });
    });

    test('POSITIVE: stop() after a match returns EchoResult(matched: '
        'true, matchedFraction: 1.0)', () {
      fakeAsync((async) {
        final engine = FakeAsrEngine(script: [_phones(const ['SH'])]);
        final session = EchoSession(engine: engine, scorer: _shScorer());

        session.start();
        async.flushMicrotasks();
        final result = session.stop();

        expect(result.matched, isTrue);
        expect(result.matchedFraction, closeTo(1.0, 1e-9));
      });
    });

    test('POSITIVE: onMatch never fires a second time even if more '
        'hypotheses arrive after the match', () {
      fakeAsync((async) {
        final engine = FakeAsrEngine(script: [
          _phones(const ['SH']),
          _phones(const ['SH']),
          _phones(const ['SH']),
        ]);
        final session = EchoSession(engine: engine, scorer: _shScorer());
        var matchCount = 0;

        session.start(onMatch: () => matchCount++);
        async.flushMicrotasks();

        expect(matchCount, 1);
      });
    });
  });

  group('EchoSession — no negative state on a non-match (accept 4, 5)', () {
    test('NEGATIVE: a hypothesis that never covers the target sequence '
        'leaves matched false and never fires onMatch', () {
      fakeAsync((async) {
        final engine = FakeAsrEngine(script: [_phones(const ['Z'])]);
        final session = EchoSession(engine: engine, scorer: _shScorer());
        var matchCount = 0;

        session.start(onMatch: () => matchCount++);
        async.flushMicrotasks();

        expect(session.matched, isFalse);
        expect(matchCount, 0);
      });
    });

    test('NEGATIVE: silence (no hypotheses at all) leaves matched false '
        'and stop() reports matchedFraction 0.0 -- no error, no exception',
        () {
      fakeAsync((async) {
        final engine = FakeAsrEngine(script: const []);
        final session = EchoSession(engine: engine, scorer: _shScorer());

        session.start();
        async.flushMicrotasks();
        final result = session.stop();

        expect(result.matched, isFalse);
        expect(result.matchedFraction, 0.0);
      });
    });
  });

  group('EchoSession — multi-phoneme grapheme order (accept 3, 4)', () {
    test('POSITIVE: a blend ("bl" -> B, L) matches only once both '
        'phonemes are produced in order', () {
      fakeAsync((async) {
        final engine = FakeAsrEngine(script: [_phones(const ['B', 'L'])]);
        final session = EchoSession(engine: engine, scorer: _blScorer());

        session.start();
        async.flushMicrotasks();

        expect(session.matched, isTrue);
      });
    });

    test('NEGATIVE: producing only the non-drilled phoneme of a blend '
        '("L" alone, weight 1 of 3 total) does not cross the A-13 0.60 '
        'threshold', () {
      fakeAsync((async) {
        final engine = FakeAsrEngine(script: [_phones(const ['L'])]);
        final session = EchoSession(engine: engine, scorer: _blScorer());

        session.start();
        async.flushMicrotasks();

        expect(session.matched, isFalse);
        expect(session.matchedFraction, lessThan(kSoundModeMatchThreshold));
      });
    });

    test('POSITIVE: producing only the drilled phoneme of a blend '
        '("B" alone, weight 2 of 3 total = 0.667) crosses the A-13 0.60 '
        'threshold by itself', () {
      fakeAsync((async) {
        final engine = FakeAsrEngine(script: [_phones(const ['B'])]);
        final session = EchoSession(engine: engine, scorer: _blScorer());

        session.start();
        async.flushMicrotasks();

        expect(session.matched, isTrue);
        expect(session.matchedFraction, closeTo(2 / 3, 1e-9));
      });
    });
  });

  group('lightweight engine+scorer loop -- no listening-tracker pulled in '
      '(ticket note, static check)', () {
    test(
      'NEGATIVE: echo_session.dart does not import any listening-tracker '
      'module (no words, no silence/struggle/tap semantics belong here)',
      () {
        final file = File('lib/features/sound_garden/echo_session.dart');
        if (!file.existsSync()) {
          // Vacuously true before the implementation lands -- this becomes
          // a real gate the moment echo_session.dart is created.
          return;
        }
        final source = file.readAsStringSync();
        const bannedImports = [
          'tracker/reading_tracker.dart',
          'tracker/silence_detector.dart',
          'tracker/tap_engine.dart',
          'tracker/cloud_minute_cap.dart',
          'tracker/mic_session.dart',
          'help/stuck_word_controller.dart',
        ];
        for (final banned in bannedImports) {
          expect(
            source.contains(banned),
            isFalse,
            reason: 'echo_session.dart must not import $banned -- ticket '
                'note: "do NOT pull in listening-tracker (no words, no '
                'silence/struggle/tap semantics here)"',
          );
        }
      },
    );
  });
}

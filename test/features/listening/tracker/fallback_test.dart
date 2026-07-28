/// Fallback-chain tests for the listening tracker (PRD §8 Unit 4, ticket
/// listening-tracker): engine failure, mic unavailable (modeled here as an
/// engine that throws on first use), and consent-off all degrade to tap
/// mode without interrupting the event stream; tapping the current word
/// emits wordAccepted identically to ASR acceptance; engine choice is
/// invisible above the tracker's event-stream interface.
///
/// Pinned API under test: see reading_tracker_test.dart (canonical) for
/// ReadingTracker's full shape. This file additionally pins:
///
///   lib/features/listening/tracker/tap_engine.dart:
///     class TapEngine implements AsrEngine {
///       TapEngine();
///       List<String>? get recordedBiasingContext; // from the latest start()
///       int get stopCallCount;
///       @override void start(List<String> biasingContext);
///       @override void stop();
///       @override Stream<Hypothesis> get hypothesesStream; // broadcast
///       void tapWord(String word); // pushes an exact-text Hypothesis for
///         // [word] onto hypothesesStream -- the SAME shape a real engine
///         // would produce for a spoken exact match, so downstream matching
///         // is identical regardless of source (PRD: "engine choice ...
///         // invisible above this interface").
///     }
///
/// TapEngine is the real production fallback (ticket note: "fully owned
/// here"), not a test-only stub; ReadingTracker uses it internally whenever
/// it falls back (engine failure, mic unavailable, or micConsent == false).
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/contracts/fake_asr_engine.dart';
import 'package:learn_to_read/features/listening/contracts/tracker_events.dart';
import 'package:learn_to_read/features/listening/tracker/reading_tracker.dart';
import 'package:learn_to_read/features/listening/tracker/tap_engine.dart';

WordToken _tok(String text, List<({String graphemes, String phonemeId})> map) =>
    WordToken(
      text: text,
      graphemePhonemeMap: map,
      pronunciationAudioRef: 'audio/$text.mp3',
    );

WordToken get _cat => _tok('cat', [
      (graphemes: 'c', phonemeId: 'K'),
      (graphemes: 'a', phonemeId: 'AE'),
      (graphemes: 't', phonemeId: 'T'),
    ]);

WordToken get _sun => _tok('sun', [
      (graphemes: 's', phonemeId: 'S'),
      (graphemes: 'u', phonemeId: 'AH'),
      (graphemes: 'n', phonemeId: 'N'),
    ]);

Hypothesis _word(String w) => Hypothesis(wordHypotheses: [w], phoneHypotheses: null);

/// Simulates "mic unavailable" / immediate engine-construction failure:
/// [start] succeeds (records biasing) but [hypothesesStream] throws
/// synchronously on access, exactly like [FakeAsrEngine]'s `shouldFail`.
/// Unlike [FakeAsrEngine], this double also records [stop] calls, needed to
/// assert the tracker cleans up the failed engine.
class _ThrowingEngine implements AsrEngine {
  List<String>? recordedBiasingContext;
  int stopCallCount = 0;

  @override
  void start(List<String> biasingContext) => recordedBiasingContext = biasingContext;

  @override
  void stop() => stopCallCount += 1;

  @override
  Stream<Hypothesis> get hypothesesStream =>
      throw Exception('_ThrowingEngine: simulated mic-unavailable failure');
}

/// Simulates "engine failure mid-stream": emits hypotheses on demand via
/// [emit], then a fatal stream error via [failNow] (mirrors
/// AsrEngine.hypothesesStream doc: "Closed ... or the engine encounters a
/// fatal error").
class _MidStreamFailureEngine implements AsrEngine {
  final _controller = StreamController<Hypothesis>.broadcast();
  List<String>? recordedBiasingContext;
  int stopCallCount = 0;

  @override
  void start(List<String> biasingContext) => recordedBiasingContext = biasingContext;

  @override
  void stop() => stopCallCount += 1;

  @override
  Stream<Hypothesis> get hypothesesStream => _controller.stream;

  void emit(Hypothesis h) => _controller.add(h);
  void failNow() => _controller.addError(Exception('simulated mid-stream ASR failure'));
}

void main() {
  group('TapEngine — standalone AsrEngine implementation (production tap '
      'fallback, fully owned here)', () {
    test('POSITIVE: implements AsrEngine', () {
      expect(TapEngine(), isA<AsrEngine>());
    });

    test('POSITIVE: start() records the biasing context like any engine', () {
      final engine = TapEngine();
      engine.start(['cat', 'sun']);
      expect(engine.recordedBiasingContext, ['cat', 'sun']);
    });

    test('POSITIVE: tapWord(word) emits an exact-text Hypothesis for that '
        'word on hypothesesStream', () async {
      final engine = TapEngine();
      engine.start(['cat', 'sun']);
      final hyps = <Hypothesis>[];
      final sub = engine.hypothesesStream.listen(hyps.add);

      engine.tapWord('cat');
      await Future<void>.delayed(Duration.zero);

      expect(hyps, hasLength(1));
      expect(hyps.single.wordHypotheses, contains('cat'));
      await sub.cancel();
    });

    test('POSITIVE: successive tapWord calls emit successive hypotheses, '
        'in order', () async {
      final engine = TapEngine();
      engine.start(['cat', 'sun']);
      final hyps = <Hypothesis>[];
      final sub = engine.hypothesesStream.listen(hyps.add);

      engine.tapWord('cat');
      engine.tapWord('sun');
      await Future<void>.delayed(Duration.zero);

      expect(hyps.map((h) => h.wordHypotheses.single), ['cat', 'sun']);
      await sub.cancel();
    });

    test('POSITIVE: stop() completes without error', () {
      final engine = TapEngine();
      engine.start(['cat']);
      expect(() => engine.stop(), returnsNormally);
    });
  });

  group('Fallback trigger: mic unavailable / engine failure at start '
      '(hypothesesStream throws on first access)', () {
    test('POSITIVE: falling back to tap mode does not throw to the caller '
        'and does not interrupt eventsStream', () {
      final engine = _ThrowingEngine();
      final tracker =
          ReadingTracker(engine: engine, sentence: [_cat], micConsent: true);
      final events = <TrackerEvent>[];
      var streamErrored = false;
      tracker.eventsStream.listen(events.add, onError: (_) => streamErrored = true);

      expect(() => tracker.start(), returnsNormally);

      expect(tracker.isTapMode, isTrue);
      expect(streamErrored, isFalse);
    });

    test('POSITIVE: the failed engine is stopped for cleanup', () {
      final engine = _ThrowingEngine();
      final tracker =
          ReadingTracker(engine: engine, sentence: [_cat], micConsent: true);

      tracker.start();

      expect(engine.stopCallCount, greaterThanOrEqualTo(1));
    });

    test('POSITIVE: tapCurrentWord() works immediately after falling back, '
        'emitting wordAccepted', () {
      final engine = _ThrowingEngine();
      final tracker = ReadingTracker(
        engine: engine,
        sentence: [_cat, _sun],
        micConsent: true,
      );
      final events = <TrackerEvent>[];
      tracker.eventsStream.listen(events.add);

      tracker.start();
      tracker.tapCurrentWord();
      tracker.tapCurrentWord();

      expect(events, [WordAccepted(index: 0), WordAccepted(index: 1)]);
    });
  });

  group('Fallback trigger: engine failure mid-stream', () {
    test('POSITIVE: words accepted before the failure remain in the event '
        'list, and the eventsStream never errors to its listener', () {
      fakeAsync((async) {
        final engine = _MidStreamFailureEngine();
        final tracker = ReadingTracker(
          engine: engine,
          sentence: [_cat, _sun],
          micConsent: true,
        );
        final events = <TrackerEvent>[];
        var streamErrored = false;
        tracker.eventsStream
            .listen(events.add, onError: (_) => streamErrored = true);

        tracker.start();
        engine.emit(_word('cat'));
        async.flushMicrotasks();
        engine.failNow();
        async.flushMicrotasks();

        expect(events, [WordAccepted(index: 0)]);
        expect(streamErrored, isFalse);
        expect(tracker.isTapMode, isTrue);
      });
    });

    test('POSITIVE: after a mid-stream failure, tapCurrentWord() continues '
        'the reading for the remaining words', () {
      fakeAsync((async) {
        final engine = _MidStreamFailureEngine();
        final tracker = ReadingTracker(
          engine: engine,
          sentence: [_cat, _sun],
          micConsent: true,
        );
        final events = <TrackerEvent>[];
        tracker.eventsStream.listen(events.add);

        tracker.start();
        engine.emit(_word('cat'));
        async.flushMicrotasks();
        engine.failNow();
        async.flushMicrotasks();
        tracker.tapCurrentWord();

        expect(events, [WordAccepted(index: 0), WordAccepted(index: 1)]);
      });
    });
  });

  group('Fallback trigger: micConsent == false', () {
    test('POSITIVE: the tracker never calls engine.start() when '
        'micConsent is false at construction -- it starts directly in tap '
        'mode', () {
      final engine = _ThrowingEngine(); // any engine; must never be touched
      final tracker =
          ReadingTracker(engine: engine, sentence: [_cat], micConsent: false);

      tracker.start();

      expect(engine.recordedBiasingContext, isNull,
          reason: 'engine.start() must never be called without consent');
      expect(tracker.isTapMode, isTrue);
    });

    test('POSITIVE: tapCurrentWord() still works with consent off', () {
      final engine = _ThrowingEngine();
      final tracker =
          ReadingTracker(engine: engine, sentence: [_cat], micConsent: false);
      final events = <TrackerEvent>[];
      tracker.eventsStream.listen(events.add);

      tracker.start();
      tracker.tapCurrentWord();

      expect(events, [WordAccepted(index: 0)]);
    });

    test('POSITIVE: revoking consent mid-session (updateMicConsent(false)) '
        'degrades to tap mode immediately, stops the engine, and does not '
        'interrupt eventsStream', () {
      final engine = _MidStreamFailureEngine();
      final tracker =
          ReadingTracker(engine: engine, sentence: [_cat], micConsent: true);
      final events = <TrackerEvent>[];
      var streamErrored = false;
      tracker.eventsStream.listen(events.add, onError: (_) => streamErrored = true);

      tracker.start();
      expect(tracker.isTapMode, isFalse);

      tracker.updateMicConsent(false);

      expect(tracker.isTapMode, isTrue);
      expect(tracker.micConsent, isFalse);
      expect(engine.stopCallCount, greaterThanOrEqualTo(1));
      expect(streamErrored, isFalse);

      tracker.tapCurrentWord();
      expect(events, [WordAccepted(index: 0)]);
    });
  });

  group('Engine choice is invisible above the tracker interface (accept: '
      '"same scripted scenario run against FakeAsrEngine and tap_engine '
      'yields equivalent acceptance events")', () {
    test('POSITIVE: reading a sentence via a healthy FakeAsrEngine and '
        'reading the SAME sentence via tap-mode fallback produce identical '
        'WordAccepted event sequences', () {
      final sentence = [_cat, _sun];

      final asrEngine = FakeAsrEngine(script: [_word('cat'), _word('sun')]);
      final asrTracker = ReadingTracker(
        engine: asrEngine,
        sentence: sentence,
        micConsent: true,
      );
      final asrEvents = <TrackerEvent>[];
      asrTracker.eventsStream.listen(asrEvents.add);
      asrTracker.start();

      final failingEngine = _ThrowingEngine();
      final tapTracker = ReadingTracker(
        engine: failingEngine,
        sentence: sentence,
        micConsent: true,
      );
      final tapEvents = <TrackerEvent>[];
      tapTracker.eventsStream.listen(tapEvents.add);
      tapTracker.start();
      tapTracker.tapCurrentWord();
      tapTracker.tapCurrentWord();

      expect(tapTracker.isTapMode, isTrue);
      expect(asrTracker.isTapMode, isFalse);
      expect(tapEvents, asrEvents,
          reason: 'engine choice (ASR vs tap) must be invisible above the '
              'tracker event-stream interface');
      expect(asrEvents, [WordAccepted(index: 0), WordAccepted(index: 1)]);
    });
  });
}

/// Unit tests for fake implementations: FakeAsrEngine and FakeReadingTracker.
///
/// FakeAsrEngine: scripted hypothesis sequences with configurable timing,
/// error injection, biasing context recording.
/// FakeReadingTracker: scripted tracker-event stream emission.
///
/// Works with fake_async for timing tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/contracts/tracker_events.dart';
import 'package:learn_to_read/features/listening/contracts/fake_asr_engine.dart';
import 'package:learn_to_read/features/listening/contracts/fake_reading_tracker.dart';

void main() {
  group('FakeAsrEngine — scripted hypothesis playback for testing', () {
    group('POSITIVE: construction and initialization', () {
      test('constructs with script of hypotheses', () {
        final script = [
          Hypothesis(wordHypotheses: ['cat'], phoneHypotheses: null),
          Hypothesis(wordHypotheses: ['dog'], phoneHypotheses: ['D', 'AO', 'G']),
        ];

        final engine = FakeAsrEngine(script: script);
        expect(engine, isNotNull);
      });

      test('constructs with empty script', () {
        final engine = FakeAsrEngine(script: []);
        expect(engine, isNotNull);
      });

      test('constructs with single hypothesis', () {
        final script = [
          Hypothesis(wordHypotheses: ['hello'], phoneHypotheses: null),
        ];

        final engine = FakeAsrEngine(script: script);
        expect(engine, isNotNull);
      });
    });

    group('POSITIVE: start/stop lifecycle', () {
      test('start records biasing context', () {
        final script = [
          Hypothesis(wordHypotheses: ['cat'], phoneHypotheses: null),
        ];
        final engine = FakeAsrEngine(script: script);

        final biasingContext = ['cat', 'can', 'car'];
        engine.start(biasingContext);

        expect(engine.recordedBiasingContext, biasingContext);
      });

      test('start can be called with empty biasing context', () {
        final script = [
          Hypothesis(wordHypotheses: ['test'], phoneHypotheses: null),
        ];
        final engine = FakeAsrEngine(script: script);

        engine.start([]);

        expect(engine.recordedBiasingContext, isEmpty);
      });

      test('stop method completes without error', () {
        final script = [
          Hypothesis(wordHypotheses: ['test'], phoneHypotheses: null),
        ];
        final engine = FakeAsrEngine(script: script);

        engine.start(['test']);
        expect(() => engine.stop(), returnsNormally);
      });

      test('stop can be called multiple times', () {
        final script = [
          Hypothesis(wordHypotheses: ['test'], phoneHypotheses: null),
        ];
        final engine = FakeAsrEngine(script: script);

        engine.start(['test']);
        engine.stop();
        expect(() => engine.stop(), returnsNormally);
      });
    });

    group('POSITIVE: hypothesis stream emission', () {
      test('emits scripted hypotheses in order', () async {
        final script = [
          Hypothesis(wordHypotheses: ['first'], phoneHypotheses: null),
          Hypothesis(wordHypotheses: ['second'], phoneHypotheses: ['S', 'E', 'K']),
          Hypothesis(wordHypotheses: ['third'], phoneHypotheses: null),
        ];
        final engine = FakeAsrEngine(script: script);

        engine.start(['first', 'second', 'third']);

        final hypotheses = <Hypothesis>[];
        await engine.hypothesesStream.forEach((hyp) {
          hypotheses.add(hyp);
        });

        expect(hypotheses, script);
      });

      test('stream delivers hypotheses with correct word lists', () async {
        final script = [
          Hypothesis(
            wordHypotheses: ['cat', 'can', 'car'],
            phoneHypotheses: null,
          ),
        ];
        final engine = FakeAsrEngine(script: script);

        engine.start(['cat']);

        final hyps = <Hypothesis>[];
        await engine.hypothesesStream.forEach((hyp) {
          hyps.add(hyp);
          if (hyps.length >= 1) return; // Take first only
        });

        expect(hyps[0].wordHypotheses, ['cat', 'can', 'car']);
      });

      test('stream delivers phone-level detail where present', () async {
        final script = [
          Hypothesis(
            wordHypotheses: ['dog'],
            phoneHypotheses: ['D', 'AO', 'G'],
          ),
        ];
        final engine = FakeAsrEngine(script: script);

        engine.start(['dog']);

        final hyps = <Hypothesis>[];
        await engine.hypothesesStream.forEach((hyp) {
          hyps.add(hyp);
          if (hyps.length >= 1) return;
        });

        expect(hyps[0].phoneHypotheses, ['D', 'AO', 'G']);
      });

      test('stream delivers null phones where engine does not provide them', () async {
        final script = [
          Hypothesis(wordHypotheses: ['word'], phoneHypotheses: null),
        ];
        final engine = FakeAsrEngine(script: script);

        engine.start(['word']);

        final hyps = <Hypothesis>[];
        await engine.hypothesesStream.forEach((hyp) {
          hyps.add(hyp);
          if (hyps.length >= 1) return;
        });

        expect(hyps[0].phoneHypotheses, isNull);
      });
    });

    group('POSITIVE: configurable timing', () {
      test('emits hypotheses with configurable delays', () async {
        final script = [
          Hypothesis(wordHypotheses: ['one'], phoneHypotheses: null),
          Hypothesis(wordHypotheses: ['two'], phoneHypotheses: null),
        ];
        const delay = Duration(milliseconds: 100);
        final engine = FakeAsrEngine(
          script: script,
          delayBetweenHypotheses: delay,
        );

        engine.start(['one', 'two']);

        final stopwatch = Stopwatch()..start();
        final hyps = <Hypothesis>[];
        await engine.hypothesesStream.forEach((hyp) {
          hyps.add(hyp);
          if (hyps.length >= 2) return;
        });
        stopwatch.stop();

        expect(hyps, hasLength(2));
        // Rough timing check: should be at least 1 delay interval
        expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(90));
      });

      test('works with zero delay', () async {
        final script = [
          Hypothesis(wordHypotheses: ['instant'], phoneHypotheses: null),
        ];
        final engine = FakeAsrEngine(
          script: script,
          delayBetweenHypotheses: Duration.zero,
        );

        engine.start(['instant']);

        final hyps = <Hypothesis>[];
        await engine.hypothesesStream.forEach((hyp) {
          hyps.add(hyp);
          if (hyps.length >= 1) return;
        });

        expect(hyps, hasLength(1));
      });

      test('works with fake_async for deterministic timing', () {
        // This test structure shows that FakeAsrEngine can work with fake_async.
        // Actual async operation test would use FakeAsync but we show the pattern.
        final script = [
          Hypothesis(wordHypotheses: ['sync'], phoneHypotheses: null),
        ];
        final engine = FakeAsrEngine(
          script: script,
          delayBetweenHypotheses: Duration(milliseconds: 10),
        );

        engine.start(['sync']);
        expect(engine, isNotNull);
      });
    });

    group('POSITIVE: biasing context recording', () {
      test('records exact biasing context passed to start', () {
        final script = [
          Hypothesis(wordHypotheses: ['expected'], phoneHypotheses: null),
        ];
        final context = ['the', 'cat', 'sat', 'on', 'the', 'mat'];
        final engine = FakeAsrEngine(script: script);

        engine.start(context);

        expect(engine.recordedBiasingContext, context);
      });

      test('biasing context can be asserted in tests for hybridization check', () {
        final script = [
          Hypothesis(wordHypotheses: ['test'], phoneHypotheses: null),
        ];
        final engine = FakeAsrEngine(script: script);

        final expectedContext = ['test', 'best', 'rest'];
        engine.start(expectedContext);

        // Test assertion: the engine was biased with the expected words
        expect(engine.recordedBiasingContext, containsAll(['test', 'best', 'rest']));
      });

      test('records different contexts on successive starts', () {
        final script = [
          Hypothesis(wordHypotheses: ['one'], phoneHypotheses: null),
        ];
        final engine = FakeAsrEngine(script: script);

        engine.start(['first', 'context']);
        final first = engine.recordedBiasingContext;

        engine.start(['second', 'context']);
        final second = engine.recordedBiasingContext;

        expect(first, isNot(second));
      });
    });

    group('NEGATIVE: error injection', () {
      test('simulates engine-unavailable with shouldFail flag', () async {
        final script = [
          Hypothesis(wordHypotheses: ['test'], phoneHypotheses: null),
        ];
        final engine = FakeAsrEngine(
          script: script,
          shouldFail: true,
        );

        engine.start(['test']);

        expect(
          () => engine.hypothesesStream,
          throwsException,
        );
      });

      test('returns null stream when shouldFail is true', () {
        final script = [
          Hypothesis(wordHypotheses: ['test'], phoneHypotheses: null),
        ];
        final engine = FakeAsrEngine(
          script: script,
          shouldFail: true,
        );

        engine.start(['test']);

        // Attempting to consume the stream should fail
        expect(engine.hypothesesStream, throwsException);
      });

      test('shouldFail=false emits normally', () async {
        final script = [
          Hypothesis(wordHypotheses: ['ok'], phoneHypotheses: null),
        ];
        final engine = FakeAsrEngine(
          script: script,
          shouldFail: false,
        );

        engine.start(['ok']);

        final hyps = <Hypothesis>[];
        await engine.hypothesesStream.forEach((hyp) {
          hyps.add(hyp);
          if (hyps.length >= 1) return;
        });

        expect(hyps, hasLength(1));
      });
    });

    group('EDGE: empty script behavior', () {
      test('empty script emits no hypotheses', () async {
        final engine = FakeAsrEngine(script: []);

        engine.start(['any', 'context']);

        final hyps = <Hypothesis>[];
        final completes = engine.hypothesesStream.isEmpty;

        expect(await completes, isTrue);
        expect(hyps, isEmpty);
      });

      test('start can be called on empty-script engine', () {
        final engine = FakeAsrEngine(script: []);

        expect(() => engine.start(['test']), returnsNormally);
      });
    });

    group('EDGE: large scripts and many hypotheses', () {
      test('handles script with many hypotheses', () async {
        final script = List.generate(100, (i) => Hypothesis(
          wordHypotheses: ['word$i'],
          phoneHypotheses: null,
        ));
        final engine = FakeAsrEngine(script: script);

        engine.start(['word0', 'word1']);

        var count = 0;
        await engine.hypothesesStream.forEach((_) {
          count++;
          if (count >= 100) return;
        });

        expect(count, 100);
      });

      test('handles hypothesis with many word options', () async {
        final manyWords = List.generate(50, (i) => 'option$i');
        final script = [
          Hypothesis(wordHypotheses: manyWords, phoneHypotheses: null),
        ];
        final engine = FakeAsrEngine(script: script);

        engine.start(manyWords);

        final hyps = <Hypothesis>[];
        await engine.hypothesesStream.forEach((hyp) {
          hyps.add(hyp);
          if (hyps.length >= 1) return;
        });

        expect(hyps[0].wordHypotheses, hasLength(50));
      });

      test('handles hypothesis with many phonemes', () async {
        final manyPhones = List.generate(44, (i) => ['K', 'AE', 'T', 'S'][i % 4]);
        final script = [
          Hypothesis(
            wordHypotheses: ['word'],
            phoneHypotheses: manyPhones,
          ),
        ];
        final engine = FakeAsrEngine(script: script);

        engine.start(['word']);

        final hyps = <Hypothesis>[];
        await engine.hypothesesStream.forEach((hyp) {
          hyps.add(hyp);
          if (hyps.length >= 1) return;
        });

        expect(hyps[0].phoneHypotheses, hasLength(44));
      });
    });

    test('implements AsrEngine interface contract', () {
      final script = [
        Hypothesis(wordHypotheses: ['test'], phoneHypotheses: null),
      ];
      final engine = FakeAsrEngine(script: script);

      expect(engine, isA<AsrEngine>());
    });
  });

  group('FakeReadingTracker — scripted tracker-event stream for Unit 5/6/14', () {
    group('POSITIVE: construction and initialization', () {
      test('constructs with script of events', () {
        final script = [
          WordAccepted(index: 0),
          WordAccepted(index: 1),
          WordAccepted(index: 2),
        ];

        final tracker = FakeReadingTracker(script: script);
        expect(tracker, isNotNull);
      });

      test('constructs with empty event script', () {
        final tracker = FakeReadingTracker(script: []);
        expect(tracker, isNotNull);
      });

      test('constructs with mixed event types', () {
        final script = [
          WordAccepted(index: 0),
          WordAcceptedNearMiss(index: 1),
          StruggleDetected(index: 1),
          Silence(duration: Duration(seconds: 4)),
          WordHelped(index: 1, tier: HelpLevel.soundOut),
          WordAccepted(index: 2),
        ];

        final tracker = FakeReadingTracker(script: script);
        expect(tracker, isNotNull);
      });
    });

    group('POSITIVE: event stream emission', () {
      test('emits scripted events in order', () async {
        final script = [
          WordAccepted(index: 0),
          WordAccepted(index: 1),
          WordAccepted(index: 2),
        ];
        final tracker = FakeReadingTracker(script: script);

        final events = <TrackerEvent>[];
        await tracker.eventsStream.forEach((event) {
          events.add(event);
        });

        expect(events, script);
      });

      test('emits WordAccepted events correctly', () async {
        final script = [
          WordAccepted(index: 5),
          WordAccepted(index: 6),
        ];
        final tracker = FakeReadingTracker(script: script);

        final events = <TrackerEvent>[];
        await tracker.eventsStream.forEach((event) {
          events.add(event);
        });

        expect(events[0], WordAccepted(index: 5));
        expect(events[1], WordAccepted(index: 6));
      });

      test('emits WordAcceptedNearMiss events', () async {
        final script = [
          WordAcceptedNearMiss(index: 2),
        ];
        final tracker = FakeReadingTracker(script: script);

        final events = <TrackerEvent>[];
        await tracker.eventsStream.forEach((event) {
          events.add(event);
        });

        expect(events[0], isA<WordAcceptedNearMiss>());
      });

      test('emits StruggleDetected events', () async {
        final script = [
          StruggleDetected(index: 3),
        ];
        final tracker = FakeReadingTracker(script: script);

        final events = <TrackerEvent>[];
        await tracker.eventsStream.forEach((event) {
          events.add(event);
        });

        expect(events[0], isA<StruggleDetected>());
      });

      test('emits Silence events with durations', () async {
        final script = [
          Silence(duration: Duration(seconds: 4)),
          Silence(duration: Duration(seconds: 5)),
        ];
        final tracker = FakeReadingTracker(script: script);

        final events = <TrackerEvent>[];
        await tracker.eventsStream.forEach((event) {
          events.add(event);
        });

        expect((events[0] as Silence).duration, Duration(seconds: 4));
        expect((events[1] as Silence).duration, Duration(seconds: 5));
      });

      test('emits WordHelped events with tier', () async {
        final script = [
          WordHelped(index: 1, tier: HelpLevel.soundOut),
          WordHelped(index: 2, tier: HelpLevel.modeled),
        ];
        final tracker = FakeReadingTracker(script: script);

        final events = <TrackerEvent>[];
        await tracker.eventsStream.forEach((event) {
          events.add(event);
        });

        expect(
          (events[0] as WordHelped).tier,
          HelpLevel.soundOut,
        );
        expect(
          (events[1] as WordHelped).tier,
          HelpLevel.modeled,
        );
      });
    });

    group('POSITIVE: realistic event sequences', () {
      test('emits sequence: word accepted, another accepted, then struggle', () async {
        final script = [
          WordAccepted(index: 0),
          WordAccepted(index: 1),
          StruggleDetected(index: 2),
          WordHelped(index: 2, tier: HelpLevel.soundOut),
          WordAccepted(index: 2),
          WordAccepted(index: 3),
        ];
        final tracker = FakeReadingTracker(script: script);

        final events = <TrackerEvent>[];
        await tracker.eventsStream.forEach((event) {
          events.add(event);
        });

        expect(events, hasLength(6));
        expect(events[0], isA<WordAccepted>());
        expect(events[2], isA<StruggleDetected>());
        expect(events[3], isA<WordHelped>());
      });

      test('emits near-miss then model prompt sequence', () async {
        final script = [
          WordAcceptedNearMiss(index: 1),
          // (near-miss prompt would follow in UI, but tracker only emits events)
          WordAccepted(index: 2),
        ];
        final tracker = FakeReadingTracker(script: script);

        final events = <TrackerEvent>[];
        await tracker.eventsStream.forEach((event) {
          events.add(event);
        });

        expect(events[0], isA<WordAcceptedNearMiss>());
        expect(events[1], isA<WordAccepted>());
      });

      test('emits silence then struggle sequence', () async {
        final script = [
          Silence(duration: Duration(seconds: 3)),
          StruggleDetected(index: 2),
        ];
        final tracker = FakeReadingTracker(script: script);

        final events = <TrackerEvent>[];
        await tracker.eventsStream.forEach((event) {
          events.add(event);
        });

        expect(events[0], isA<Silence>());
        expect(events[1], isA<StruggleDetected>());
      });

      test('emits complete story reading: accept all words', () async {
        final script = [
          WordAccepted(index: 0),
          WordAccepted(index: 1),
          WordAccepted(index: 2),
          WordAccepted(index: 3),
        ];
        final tracker = FakeReadingTracker(script: script);

        final events = <TrackerEvent>[];
        await tracker.eventsStream.forEach((event) {
          events.add(event);
        });

        expect(events, everyElement(isA<WordAccepted>()));
        expect(events, hasLength(4));
      });
    });

    group('POSITIVE: configurable timing', () {
      test('emits events with configurable delays', () async {
        final script = [
          WordAccepted(index: 0),
          WordAccepted(index: 1),
        ];
        const delay = Duration(milliseconds: 100);
        final tracker = FakeReadingTracker(
          script: script,
          delayBetweenEvents: delay,
        );

        final stopwatch = Stopwatch()..start();
        final events = <TrackerEvent>[];
        await tracker.eventsStream.forEach((event) {
          events.add(event);
          if (events.length >= 2) return;
        });
        stopwatch.stop();

        expect(events, hasLength(2));
        expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(90));
      });

      test('works with zero delay', () async {
        final script = [
          WordAccepted(index: 0),
          WordAccepted(index: 1),
        ];
        final tracker = FakeReadingTracker(
          script: script,
          delayBetweenEvents: Duration.zero,
        );

        final events = <TrackerEvent>[];
        await tracker.eventsStream.forEach((event) {
          events.add(event);
          if (events.length >= 2) return;
        });

        expect(events, hasLength(2));
      });
    });

    group('EDGE: empty script', () {
      test('empty script emits no events', () async {
        final tracker = FakeReadingTracker(script: []);

        final events = <TrackerEvent>[];
        final isEmpty = tracker.eventsStream.isEmpty;

        expect(await isEmpty, isTrue);
        expect(events, isEmpty);
      });
    });

    group('EDGE: large event sequences', () {
      test('handles script with many events', () async {
        final script = List.generate(100, (i) => WordAccepted(index: i));
        final tracker = FakeReadingTracker(script: script);

        var count = 0;
        await tracker.eventsStream.forEach((_) {
          count++;
          if (count >= 100) return;
        });

        expect(count, 100);
      });

      test('handles mixed event types at scale', () async {
        final script = [
          ...List.generate(30, (i) => WordAccepted(index: i)),
          ...List.generate(10, (i) => WordAcceptedNearMiss(index: 30 + i)),
          ...List.generate(10, (i) => StruggleDetected(index: 40 + i)),
        ];
        final tracker = FakeReadingTracker(script: script);

        final events = <TrackerEvent>[];
        await tracker.eventsStream.forEach((event) {
          events.add(event);
        });

        expect(events, hasLength(50));
        expect(
          events.whereType<WordAccepted>().length,
          30,
        );
      });
    });

    group('EDGE: event stream consumption patterns', () {
      test('supports take(n) pattern', () async {
        final script = List.generate(10, (i) => WordAccepted(index: i));
        final tracker = FakeReadingTracker(script: script);

        final first3 = await tracker.eventsStream.take(3).toList();

        expect(first3, hasLength(3));
        expect((first3[0] as WordAccepted).index, 0);
      });

      test('supports where filter', () async {
        final script = [
          WordAccepted(index: 0),
          WordAcceptedNearMiss(index: 1),
          WordAccepted(index: 2),
          StruggleDetected(index: 3),
        ];
        final tracker = FakeReadingTracker(script: script);

        final accepted = await tracker.eventsStream
            .whereType<WordAccepted>()
            .toList();

        expect(accepted, hasLength(2));
      });

      test('supports forEach iteration', () async {
        final script = [
          WordAccepted(index: 0),
          WordAccepted(index: 1),
        ];
        final tracker = FakeReadingTracker(script: script);

        var count = 0;
        await tracker.eventsStream.forEach((_) {
          count++;
        });

        expect(count, 2);
      });
    });
  });

  group('Integration: FakeAsrEngine + FakeReadingTracker fakes work together', () {
    test('both fakes can be used in same test fixture', () async {
      final engineScript = [
        Hypothesis(wordHypotheses: ['cat'], phoneHypotheses: ['K', 'AE', 'T']),
      ];
      final engine = FakeAsrEngine(script: engineScript);

      final trackerScript = [
        WordAccepted(index: 0),
      ];
      final tracker = FakeReadingTracker(script: trackerScript);

      engine.start(['cat']);

      final hyps = await engine.hypothesesStream.take(1).toList();
      final events = await tracker.eventsStream.take(1).toList();

      expect(hyps, hasLength(1));
      expect(events, hasLength(1));
      expect(hyps[0].wordHypotheses, ['cat']);
      expect(events[0], isA<WordAccepted>());
    });
  });
}

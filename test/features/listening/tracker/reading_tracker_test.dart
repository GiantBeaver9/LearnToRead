/// Core contract tests for the listening tracker orchestrator (PRD §8 Unit 4,
/// ticket listening-tracker). This suite (together with its five siblings —
/// fixture_contract_test.dart, fallback_test.dart, silence_detector_test.dart,
/// cloud_cap_test.dart, no_audio_storage_test.dart) IS the tracker's
/// specification. THIS file is the canonical source for the pinned API; the
/// siblings restate only the slice they exercise.
///
/// Pinned API (implementation does not exist yet — red-for-right-reason):
///
///   lib/features/listening/tracker/reading_tracker.dart:
///     class ReadingTracker {
///       ReadingTracker({
///         required AsrEngine engine,
///         required List<WordToken> sentence,
///         required bool micConsent,
///         AsrEngine? onDeviceFallbackEngine,   // used only for the A-7
///                                               // cloud-minute-cap silent
///                                               // downgrade -- NEVER for
///                                               // the tap fallback chain.
///         bool engineIsMetered = false,
///         CloudMinuteCap? cloudMinuteCap,      // required when
///                                               // engineIsMetered is true
///         Duration struggleSilenceThreshold = kStruggleT1,
///         int struggleConsecutiveNonMatchingBursts =
///             kStruggleConsecutiveNonMatchingBursts,
///       });
///
///       Stream<TrackerEvent> get eventsStream;  // broadcast
///       bool get isListening;   // mic/ASR actively open right now
///       bool get isTapMode;     // fallen back to tap (failure or no consent)
///       bool get micConsent;
///       Duration get struggleSilenceThreshold;
///       int get struggleConsecutiveNonMatchingBursts;
///
///       void start();   // reads micConsent; either engine.start(biasing)
///                        // where biasing == sentence.map((w) => w.text), or
///                        // (no consent / engine failure) enters tap mode.
///       void stop();     // engine.stop(); eventsStream completes; no
///                        // further events from any source afterwards.
///       void pause();    // suspends recognition (engine.stop()); isListening
///                        // -> false; matcher/currentIndex untouched.
///       void resume();   // re-starts recognition at the SAME word
///                        // (engine.start(biasing) again); isListening ->
///                        // true; silence window restarts fresh (paused
///                        // time never counts as silence).
///       void tapCurrentWord();          // always available, any mode;
///                                        // emits WordAccepted(index) for
///                                        // the current word, identical in
///                                        // shape to an ASR acceptance, and
///                                        // advances exactly one word.
///       void helpCompleted(HelpLevel tier); // emits WordHelped(index, tier)
///                                        // for the current word and
///                                        // advances exactly one word.
///       void updateMicConsent(bool consent); // takes effect immediately;
///                                        // consent -> false while listening
///                                        // degrades to tap mode without
///                                        // interrupting eventsStream.
///     }
///
/// Event routing from WordMatcher.onHypothesis results (word-matcher, reused
/// never forked):
///   - MatchKind.exact     -> WordAccepted(index: wordIndex)
///   - MatchKind.nearMiss  -> WordAcceptedNearMiss(index: wordIndex)
///   - MatchKind.reject    -> no event by itself; increments a per-word
///     "consecutive non-matching burst" counter. Reaching
///     struggleConsecutiveNonMatchingBursts (A-12a, default
///     kStruggleConsecutiveNonMatchingBursts = 2) emits
///     StruggleDetected(index: wordIndex) and resets the counter. The
///     counter resets to 0 whenever the current word advances (by any
///     path: ASR accept/near-miss/back-fill, tap, or help).
///   - Lookahead back-fill (matcher returns two results) -> two SEPARATE
///     TrackerEvents emitted in the matcher's emission order (current word
///     first, next word second).
///   - Empty results (non-speech junk, repeats; matcher docs A-12a) feed
///     NEITHER the struggle counter NOR the silence timer.
///
/// Silence / struggle-path-b (A-12b): an internal SilenceDetector runs with
/// threshold == struggleSilenceThreshold while the tracker is actively
/// listening (started, not paused/stopped). It resets (noteActivity) on
/// tracker start/resume and on every non-empty matcher result (accept,
/// near-miss, reject, or back-fill) -- i.e. any burst that carried real
/// speech content, matching or not. Reaching the threshold emits, in order,
/// Silence(duration: struggleSilenceThreshold) THEN
/// StruggleDetected(index: currentIndex) -- both are the tuning-file-driven
/// T1 trigger sufficient for Unit 6. After firing it does not re-fire on its
/// own; it restarts only when the word advances or the tracker resumes.
///
/// pause()/resume() stop the silence timer for the paused span so paused
/// time is never counted as silence.
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/domain/tuning.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/contracts/fake_asr_engine.dart';
import 'package:learn_to_read/features/listening/contracts/tracker_events.dart';
import 'package:learn_to_read/features/listening/tracker/reading_tracker.dart';

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

WordToken get _dog => _tok('dog', [
      (graphemes: 'd', phonemeId: 'D'),
      (graphemes: 'o', phonemeId: 'AO'),
      (graphemes: 'g', phonemeId: 'G'),
    ]);

Hypothesis _word(String w, {List<String>? phones}) =>
    Hypothesis(wordHypotheses: [w], phoneHypotheses: phones);

/// A hand-controlled AsrEngine test double: unlike [FakeAsrEngine] (whose
/// `hypothesesStream` getter mints a brand-new one-shot generator every
/// access, restarting its script from the top), this double exposes ONE
/// persistent broadcast stream across the engine's whole lifetime plus call
/// counters, so tests can push hypotheses at exactly chosen moments (e.g.
/// straddling a pause()/resume()) and assert start/stop call counts.
class _ControlledAsrEngine implements AsrEngine {
  final _controller = StreamController<Hypothesis>.broadcast();
  final List<List<String>> startCalls = [];
  int stopCallCount = 0;

  List<String>? get recordedBiasingContext =>
      startCalls.isEmpty ? null : startCalls.last;

  @override
  void start(List<String> biasingContext) => startCalls.add(biasingContext);

  @override
  void stop() => stopCallCount += 1;

  @override
  Stream<Hypothesis> get hypothesesStream => _controller.stream;

  void emit(Hypothesis h) => _controller.add(h);
}

void main() {
  group('ReadingTracker — construction & expected-text hybridization', () {
    test('POSITIVE: engine is started with the sentence words as biasing '
        'context (expected-text hybridization always on)', () {
      final engine = FakeAsrEngine(script: const []);
      final tracker = ReadingTracker(
        engine: engine,
        sentence: [_cat, _sun],
        micConsent: true,
      );

      tracker.start();

      expect(engine.recordedBiasingContext, ['cat', 'sun']);
    });

    test('POSITIVE: isListening is true immediately after start() with '
        'consent and a healthy engine', () {
      final engine = FakeAsrEngine(script: const []);
      final tracker =
          ReadingTracker(engine: engine, sentence: [_cat], micConsent: true);

      tracker.start();

      expect(tracker.isListening, isTrue);
      expect(tracker.isTapMode, isFalse);
    });
  });

  group('ReadingTracker — exact acceptance emits wordAccepted', () {
    test('POSITIVE: a hypothesis exact-matching the current word emits '
        'WordAccepted(index) and advances', () {
      fakeAsync((async) {
        final engine = _ControlledAsrEngine();
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

        expect(events, [WordAccepted(index: 0)]);
      });
    });

    test('POSITIVE: reading the whole sentence emits WordAccepted for '
        'every index in order', () {
      fakeAsync((async) {
        final engine = _ControlledAsrEngine();
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
        engine.emit(_word('sun'));
        async.flushMicrotasks();

        expect(events, [WordAccepted(index: 0), WordAccepted(index: 1)]);
      });
    });
  });

  group('ReadingTracker — near-miss acceptance emits wordAcceptedNearMiss '
      '(not wordAccepted)', () {
    test('POSITIVE: a close-enough production ("gat" for "cat") emits '
        'WordAcceptedNearMiss(index), never WordAccepted', () {
      fakeAsync((async) {
        final engine = _ControlledAsrEngine();
        final tracker =
            ReadingTracker(engine: engine, sentence: [_cat], micConsent: true);
        final events = <TrackerEvent>[];
        tracker.eventsStream.listen(events.add);

        tracker.start();
        engine.emit(_word('gat'));
        async.flushMicrotasks();

        expect(events, [WordAcceptedNearMiss(index: 0)]);
        expect(events, isNot(contains(isA<WordAccepted>())));
      });
    });
  });

  group('ReadingTracker — lookahead back-fill flows through from the '
      'matcher as two separate events', () {
    test('POSITIVE: a hypothesis that skips to the next word back-fills the '
        'current word as WordAccepted, then emits the next word\'s own '
        'grade, in that order', () {
      fakeAsync((async) {
        final engine = _ControlledAsrEngine();
        final tracker = ReadingTracker(
          engine: engine,
          sentence: [_cat, _sun],
          micConsent: true,
        );
        final events = <TrackerEvent>[];
        tracker.eventsStream.listen(events.add);

        tracker.start();
        // Never says "cat" -- jumps straight to "sun". Matcher back-fills.
        engine.emit(_word('sun'));
        async.flushMicrotasks();

        expect(events, [WordAccepted(index: 0), WordAccepted(index: 1)]);
      });
    });

    test('POSITIVE: back-fill with a near-miss on the lookahead word grades '
        'that second event as WordAcceptedNearMiss', () {
      fakeAsync((async) {
        final engine = _ControlledAsrEngine();
        final tracker = ReadingTracker(
          engine: engine,
          sentence: [_cat, _sun],
          micConsent: true,
        );
        final events = <TrackerEvent>[];
        tracker.eventsStream.listen(events.add);

        tracker.start();
        // "sen" -- near-miss of "sun" -- while "cat" was never heard.
        engine.emit(_word('sen', phones: ['S', 'EH', 'N']));
        async.flushMicrotasks();

        expect(events, [WordAccepted(index: 0), WordAcceptedNearMiss(index: 1)]);
      });
    });
  });

  group('ReadingTracker — struggle detection path (a): two consecutive '
      'non-matching finalized bursts (A-12a)', () {
    test('POSITIVE: two consecutive non-matching bursts on the same word '
        'emit exactly one StruggleDetected(index)', () {
      fakeAsync((async) {
        final engine = _ControlledAsrEngine();
        final tracker =
            ReadingTracker(engine: engine, sentence: [_cat], micConsent: true);
        final events = <TrackerEvent>[];
        tracker.eventsStream.listen(events.add);

        tracker.start();
        engine.emit(_word('dog'));
        async.flushMicrotasks();
        engine.emit(_word('zubzub'));
        async.flushMicrotasks();

        expect(events, [StruggleDetected(index: 0)]);
      });
    });

    test('NEGATIVE: one non-matching burst followed by a match does NOT '
        'raise struggleDetected', () {
      fakeAsync((async) {
        final engine = _ControlledAsrEngine();
        final tracker =
            ReadingTracker(engine: engine, sentence: [_cat], micConsent: true);
        final events = <TrackerEvent>[];
        tracker.eventsStream.listen(events.add);

        tracker.start();
        engine.emit(_word('dog'));
        async.flushMicrotasks();
        engine.emit(_word('cat'));
        async.flushMicrotasks();

        expect(events, [WordAccepted(index: 0)]);
        expect(events, isNot(contains(isA<StruggleDetected>())));
      });
    });

    test('NEGATIVE: non-speech junk bursts (empty/punctuation-only) never '
        'count toward the consecutive-non-matching counter', () {
      fakeAsync((async) {
        final engine = _ControlledAsrEngine();
        final tracker =
            ReadingTracker(engine: engine, sentence: [_cat], micConsent: true);
        final events = <TrackerEvent>[];
        tracker.eventsStream.listen(events.add);

        tracker.start();
        engine.emit(_word('dog')); // 1 real non-match
        async.flushMicrotasks();
        engine.emit(_word('!!!')); // junk -- must not count as a 2nd
        async.flushMicrotasks();
        engine.emit(_word('   ')); // junk again
        async.flushMicrotasks();

        expect(events, isEmpty,
            reason: 'only one genuine non-matching burst has occurred; junk '
                'bursts must not push the count to 2');
      });
    });

    test('EDGE: a repeat of the previously accepted word between two '
        'non-matching bursts does not reset or advance the counter '
        '(matcher: repeats are non-events, A-12a)', () {
      fakeAsync((async) {
        final engine = _ControlledAsrEngine();
        final tracker = ReadingTracker(
          engine: engine,
          sentence: [_cat, _sun],
          micConsent: true,
        );
        final events = <TrackerEvent>[];
        tracker.eventsStream.listen(events.add);

        tracker.start();
        engine.emit(_word('cat'));
        async.flushMicrotasks(); // accepted, now on "sun"
        engine.emit(_word('dog'));
        async.flushMicrotasks(); // 1st non-match on "sun"
        engine.emit(_word('cat'));
        async.flushMicrotasks(); // repeat of the prior word -- non-event
        engine.emit(_word('dog'));
        async.flushMicrotasks(); // 2nd non-match on "sun" -> struggle

        expect(events, [WordAccepted(index: 0), StruggleDetected(index: 1)]);
      });
    });

    test('POSITIVE: struggleConsecutiveNonMatchingBursts is tunable -- '
        'lowering it to 1 struggles on a single non-match', () {
      fakeAsync((async) {
        final engine = _ControlledAsrEngine();
        final tracker = ReadingTracker(
          engine: engine,
          sentence: [_cat],
          micConsent: true,
          struggleConsecutiveNonMatchingBursts: 1,
        );
        final events = <TrackerEvent>[];
        tracker.eventsStream.listen(events.add);

        tracker.start();
        engine.emit(_word('dog'));
        async.flushMicrotasks();

        expect(events, [StruggleDetected(index: 0)]);
      });
    });

    test('POSITIVE: default struggleConsecutiveNonMatchingBursts equals the '
        'tuning-file constant', () {
      final tracker = ReadingTracker(
        engine: FakeAsrEngine(script: const []),
        sentence: [_cat],
        micConsent: true,
      );
      expect(tracker.struggleConsecutiveNonMatchingBursts,
          kStruggleConsecutiveNonMatchingBursts);
    });
  });

  group('ReadingTracker — struggle detection path (b): sustained silence '
      '>= T1 (A-12b), with silence(duration) events', () {
    test('POSITIVE: silence sustained for exactly T1 emits Silence(duration: '
        'T1) then StruggleDetected(index) on the current word', () {
      fakeAsync((async) {
        final engine = _ControlledAsrEngine();
        final tracker =
            ReadingTracker(engine: engine, sentence: [_cat], micConsent: true);
        final events = <TrackerEvent>[];
        tracker.eventsStream.listen(events.add);

        tracker.start();
        async.elapse(kStruggleT1);

        expect(events, [Silence(duration: kStruggleT1), StruggleDetected(index: 0)]);
      });
    });

    test('NEGATIVE: silence just under T1 (3.9s of a 4s threshold) emits '
        'nothing', () {
      fakeAsync((async) {
        final engine = _ControlledAsrEngine();
        final tracker =
            ReadingTracker(engine: engine, sentence: [_cat], micConsent: true);
        final events = <TrackerEvent>[];
        tracker.eventsStream.listen(events.add);

        tracker.start();
        async.elapse(const Duration(milliseconds: 3900));

        expect(events, isEmpty);
      });
    });

    test('POSITIVE: silence just over T1 (4.1s of a 4s threshold) has '
        'already fired both events', () {
      fakeAsync((async) {
        final engine = _ControlledAsrEngine();
        final tracker =
            ReadingTracker(engine: engine, sentence: [_cat], micConsent: true);
        final events = <TrackerEvent>[];
        tracker.eventsStream.listen(events.add);

        tracker.start();
        async.elapse(const Duration(milliseconds: 4100));

        expect(events, [Silence(duration: kStruggleT1), StruggleDetected(index: 0)]);
      });
    });

    test('POSITIVE: any real (non-junk) hypothesis resets the silence '
        'window, even a reject', () {
      fakeAsync((async) {
        final engine = _ControlledAsrEngine();
        final tracker =
            ReadingTracker(engine: engine, sentence: [_cat], micConsent: true);
        final events = <TrackerEvent>[];
        tracker.eventsStream.listen(events.add);

        tracker.start();
        async.elapse(const Duration(seconds: 3));
        engine.emit(_word('dog')); // reject; resets the silence window
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));

        expect(events, isEmpty,
            reason: 'only 3s of silence have elapsed since the last activity '
                '(the reject); the 4s window never completed');
      });
    });

    test('POSITIVE: struggleSilenceThreshold is tunable -- a 1s threshold '
        'fires after 1s of silence, not 4s', () {
      fakeAsync((async) {
        final engine = _ControlledAsrEngine();
        final tracker = ReadingTracker(
          engine: engine,
          sentence: [_cat],
          micConsent: true,
          struggleSilenceThreshold: const Duration(seconds: 1),
        );
        final events = <TrackerEvent>[];
        tracker.eventsStream.listen(events.add);

        tracker.start();
        async.elapse(const Duration(seconds: 1));

        expect(events, [
          Silence(duration: const Duration(seconds: 1)),
          StruggleDetected(index: 0),
        ]);
      });
    });

    test('POSITIVE: default struggleSilenceThreshold equals the tuning-file '
        'T1 constant', () {
      final tracker = ReadingTracker(
        engine: FakeAsrEngine(script: const []),
        sentence: [_cat],
        micConsent: true,
      );
      expect(tracker.struggleSilenceThreshold, kStruggleT1);
    });

    test('EDGE: after firing once via silence, remaining silent does not '
        'raise a second Silence/StruggleDetected pair on its own', () {
      fakeAsync((async) {
        final engine = _ControlledAsrEngine();
        final tracker =
            ReadingTracker(engine: engine, sentence: [_cat], micConsent: true);
        final events = <TrackerEvent>[];
        tracker.eventsStream.listen(events.add);

        tracker.start();
        async.elapse(kStruggleT1);
        expect(events, hasLength(2));
        async.elapse(kStruggleT1 * 3);

        expect(events, hasLength(2),
            reason: 'struggle-by-silence is single-shot until the word '
                'advances or the tracker resumes');
      });
    });
  });

  group('ReadingTracker — mic lifecycle: isListening, pause, resume', () {
    test('POSITIVE: pause() flips isListening to false and stops the '
        'engine', () {
      final engine = _ControlledAsrEngine();
      final tracker =
          ReadingTracker(engine: engine, sentence: [_cat], micConsent: true);

      tracker.start();
      tracker.pause();

      expect(tracker.isListening, isFalse);
      expect(engine.stopCallCount, 1);
    });

    test('POSITIVE: resume() flips isListening back to true and starts the '
        'engine again with the same biasing context', () {
      final engine = _ControlledAsrEngine();
      final tracker = ReadingTracker(
        engine: engine,
        sentence: [_cat, _sun],
        micConsent: true,
      );

      tracker.start();
      tracker.pause();
      tracker.resume();

      expect(tracker.isListening, isTrue);
      expect(engine.startCalls, hasLength(2));
      expect(engine.recordedBiasingContext, ['cat', 'sun']);
    });

    test('POSITIVE: pausing mid-sentence and resuming continues at the same '
        'word -- accepted words before pause stay accepted, the word after '
        'resume is still the one that was current before pause', () {
      fakeAsync((async) {
        final engine = _ControlledAsrEngine();
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
        tracker.pause();
        tracker.resume();
        engine.emit(_word('sun'));
        async.flushMicrotasks();

        expect(events, [WordAccepted(index: 0), WordAccepted(index: 1)]);
      });
    });

    test('POSITIVE: paused time is never counted as silence -- resuming '
        'restarts the silence window fresh', () {
      fakeAsync((async) {
        final engine = _ControlledAsrEngine();
        final tracker =
            ReadingTracker(engine: engine, sentence: [_cat], micConsent: true);
        final events = <TrackerEvent>[];
        tracker.eventsStream.listen(events.add);

        tracker.start();
        async.elapse(const Duration(seconds: 3));
        tracker.pause();
        // A long pause (e.g. narration, vocab card) -- must not count.
        async.elapse(const Duration(minutes: 5));
        tracker.resume();
        async.elapse(const Duration(milliseconds: 3900));
        expect(events, isEmpty,
            reason: 'the silence window restarted at resume(); only 3.9s '
                'have elapsed since then');
        async.elapse(const Duration(milliseconds: 200));
        expect(events, [Silence(duration: kStruggleT1), StruggleDetected(index: 0)]);
      });
    });
  });

  group('ReadingTracker — tapCurrentWord() as a manual override (PRD: '
      'tap-the-word always available)', () {
    test('POSITIVE: tapping the current word while the ASR engine is '
        'actively listening emits WordAccepted identical in shape to an '
        'ASR acceptance', () {
      final engine = _ControlledAsrEngine();
      final tracker = ReadingTracker(
        engine: engine,
        sentence: [_cat, _sun],
        micConsent: true,
      );
      final events = <TrackerEvent>[];
      tracker.eventsStream.listen(events.add);

      tracker.start();
      tracker.tapCurrentWord();

      expect(events, [WordAccepted(index: 0)]);
    });

    test('POSITIVE: repeated taps advance one word at a time, in order', () {
      final engine = _ControlledAsrEngine();
      final tracker = ReadingTracker(
        engine: engine,
        sentence: [_cat, _sun, _dog],
        micConsent: true,
      );
      final events = <TrackerEvent>[];
      tracker.eventsStream.listen(events.add);

      tracker.start();
      tracker.tapCurrentWord();
      tracker.tapCurrentWord();
      tracker.tapCurrentWord();

      expect(events,
          [WordAccepted(index: 0), WordAccepted(index: 1), WordAccepted(index: 2)]);
    });

    test('EDGE: tapping after the sentence is already complete is a silent '
        'no-op (no extra events, no error)', () {
      final engine = _ControlledAsrEngine();
      final tracker =
          ReadingTracker(engine: engine, sentence: [_cat], micConsent: true);
      final events = <TrackerEvent>[];
      tracker.eventsStream.listen(events.add);

      tracker.start();
      tracker.tapCurrentWord();
      tracker.tapCurrentWord();

      expect(events, [WordAccepted(index: 0)]);
    });
  });

  group('ReadingTracker — helpCompleted(tier) emits wordHelped and advances', () {
    test('POSITIVE: helpCompleted(HelpLevel.soundOut) emits WordHelped '
        '(index, tier: soundOut) for the current word and advances', () {
      final engine = _ControlledAsrEngine();
      final tracker = ReadingTracker(
        engine: engine,
        sentence: [_cat, _sun],
        micConsent: true,
      );
      final events = <TrackerEvent>[];
      tracker.eventsStream.listen(events.add);

      tracker.start();
      tracker.helpCompleted(HelpLevel.soundOut);

      expect(events, [WordHelped(index: 0, tier: HelpLevel.soundOut)]);
    });

    test('POSITIVE: helpCompleted(HelpLevel.modeled) emits WordHelped with '
        'tier modeled', () {
      final engine = _ControlledAsrEngine();
      final tracker =
          ReadingTracker(engine: engine, sentence: [_cat], micConsent: true);
      final events = <TrackerEvent>[];
      tracker.eventsStream.listen(events.add);

      tracker.start();
      tracker.helpCompleted(HelpLevel.modeled);

      expect(events, [WordHelped(index: 0, tier: HelpLevel.modeled)]);
    });

    test('POSITIVE: after helpCompleted advances the word, a subsequent '
        'ASR hypothesis for the NEXT word is processed as the new current '
        'word (matcher stayed in sync)', () {
      fakeAsync((async) {
        final engine = _ControlledAsrEngine();
        final tracker = ReadingTracker(
          engine: engine,
          sentence: [_cat, _sun],
          micConsent: true,
        );
        final events = <TrackerEvent>[];
        tracker.eventsStream.listen(events.add);

        tracker.start();
        tracker.helpCompleted(HelpLevel.soundOut);
        engine.emit(_word('sun'));
        async.flushMicrotasks();

        expect(events, [
          WordHelped(index: 0, tier: HelpLevel.soundOut),
          WordAccepted(index: 1),
        ]);
      });
    });

    test('EDGE: helpCompleted(HelpLevel.none) still emits and advances '
        '(HelpLevel enum coverage)', () {
      final engine = _ControlledAsrEngine();
      final tracker =
          ReadingTracker(engine: engine, sentence: [_cat], micConsent: true);
      final events = <TrackerEvent>[];
      tracker.eventsStream.listen(events.add);

      tracker.start();
      tracker.helpCompleted(HelpLevel.none);

      expect(events, [WordHelped(index: 0, tier: HelpLevel.none)]);
    });

    test('EDGE: helpCompleted after the sentence is complete is a silent '
        'no-op', () {
      final engine = _ControlledAsrEngine();
      final tracker =
          ReadingTracker(engine: engine, sentence: [_cat], micConsent: true);
      final events = <TrackerEvent>[];
      tracker.eventsStream.listen(events.add);

      tracker.start();
      tracker.tapCurrentWord();
      tracker.helpCompleted(HelpLevel.soundOut);

      expect(events, [WordAccepted(index: 0)]);
    });
  });

  group('ReadingTracker — start/stop lifecycle', () {
    test('POSITIVE: stop() calls engine.stop()', () {
      final engine = _ControlledAsrEngine();
      final tracker =
          ReadingTracker(engine: engine, sentence: [_cat], micConsent: true);

      tracker.start();
      tracker.stop();

      expect(engine.stopCallCount, 1);
    });

    test('POSITIVE: no events are emitted after stop(), even if the '
        'underlying engine stream still has a hypothesis pushed into it', () {
      final engine = _ControlledAsrEngine();
      final tracker = ReadingTracker(
        engine: engine,
        sentence: [_cat, _sun],
        micConsent: true,
      );
      final events = <TrackerEvent>[];
      tracker.eventsStream.listen(events.add);

      tracker.start();
      tracker.stop();
      engine.emit(_word('cat'));

      expect(events, isEmpty);
    });

    test('POSITIVE: eventsStream completes (is done) once stop() is '
        'called', () async {
      final engine = _ControlledAsrEngine();
      final tracker =
          ReadingTracker(engine: engine, sentence: [_cat], micConsent: true);

      tracker.start();
      final doneFuture = tracker.eventsStream.isEmpty;
      tracker.stop();

      await expectLater(doneFuture, completion(isTrue));
    });

    test('POSITIVE: calling tapCurrentWord()/helpCompleted() after stop() '
        'is a silent no-op', () {
      final engine = _ControlledAsrEngine();
      final tracker =
          ReadingTracker(engine: engine, sentence: [_cat], micConsent: true);
      final events = <TrackerEvent>[];
      tracker.eventsStream.listen(events.add);

      tracker.start();
      tracker.stop();
      tracker.tapCurrentWord();
      tracker.helpCompleted(HelpLevel.soundOut);

      expect(events, isEmpty);
    });

    test('EDGE: an empty sentence is immediately complete -- start() and '
        'stop() never throw and produce no events', () {
      final engine = _ControlledAsrEngine();
      final tracker =
          ReadingTracker(engine: engine, sentence: const [], micConsent: true);
      final events = <TrackerEvent>[];
      tracker.eventsStream.listen(events.add);

      expect(() => tracker.start(), returnsNormally);
      expect(() => tracker.tapCurrentWord(), returnsNormally);
      expect(() => tracker.stop(), returnsNormally);
      expect(events, isEmpty);
    });
  });
}

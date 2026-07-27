/// Contract tests for the listening tracker (PRD §8 Unit 4, ticket
/// listening-tracker): scripted fixture hypothesis sets drive the FULL
/// tracker (ReadingTracker + AsrEngine + WordMatcher wired together, exactly
/// as production would run it) and assert the exact expected event stream.
///
/// PRD §8 Unit 4 acceptance: "Contract tests against a small recorded
/// fixture set (clear read, hesitant read, near-miss mispronunciation,
/// silence) drive the full tracker; expected event streams asserted.
/// Happy-path fixtures only for POC; noise/cross-talk fixtures are a
/// post-POC backlog item, recorded" (also: docs/tickets/listening-tracker.json
/// notes). Real recorded-child-audio contract tests are an owner-run
/// [DEVICE] item tracked separately; this suite realizes the acceptance
/// headlessly via [FakeAsrEngine] scripted hypotheses, per the ticket's
/// validator note.
///
/// Pinned API under test: see reading_tracker_test.dart (canonical). This
/// file additionally pins that [FakeAsrEngine]'s own script/delay timing --
/// not just a hand-rolled stream double -- correctly drives the tracker
/// end-to-end, including its delay semantics under fake_async.
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
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

/// 'the' 'cat' 'sat' -- the canonical 3-word fixture sentence used across
/// this file's scripted scenarios.
WordToken get _the => _tok('the', [
      (graphemes: 'th', phonemeId: 'DH'),
      (graphemes: 'e', phonemeId: 'AH'),
    ]);

WordToken get _cat => _tok('cat', [
      (graphemes: 'c', phonemeId: 'K'),
      (graphemes: 'a', phonemeId: 'AE'),
      (graphemes: 't', phonemeId: 'T'),
    ]);

WordToken get _sat => _tok('sat', [
      (graphemes: 's', phonemeId: 'S'),
      (graphemes: 'a', phonemeId: 'AE'),
      (graphemes: 't', phonemeId: 'T'),
    ]);

Hypothesis _word(String w, {List<String>? phones}) =>
    Hypothesis(wordHypotheses: [w], phoneHypotheses: phones);

void main() {
  group('Fixture: clear read -- every word matches on the first burst', () {
    test('POSITIVE: exact hypotheses for every word, in order, produce '
        'WordAccepted for every index and complete the sentence', () {
      fakeAsync((async) {
        final sentence = [_the, _cat, _sat];
        final engine = FakeAsrEngine(
          script: [_word('the'), _word('cat'), _word('sat')],
        );
        final tracker =
            ReadingTracker(engine: engine, sentence: sentence, micConsent: true);
        final events = <TrackerEvent>[];
        tracker.eventsStream.listen(events.add);

        tracker.start();
        async.flushMicrotasks();

        expect(events, [
          WordAccepted(index: 0),
          WordAccepted(index: 1),
          WordAccepted(index: 2),
        ]);
        expect(engine.recordedBiasingContext, ['the', 'cat', 'sat'],
            reason: 'expected-text hybridization: biasing == sentence words');
      });
    });
  });

  group('Fixture: hesitant read -- pauses under T1 and one false start, '
      'still completes with no spurious struggle', () {
    test('POSITIVE: a 2s pause (< T1) and one non-matching burst that is '
        'then corrected still reads clean -- no Silence, no '
        'StruggleDetected', () {
      fakeAsync((async) {
        final sentence = [_the, _cat, _sat];
        final engine = FakeAsrEngine(
          script: [
            _word('the'),
            _word('gog'), // false start on "cat" -- 1 non-match only
            _word('cat'), // self-correction
            _word('sat'),
          ],
          delayBetweenHypotheses: const Duration(seconds: 2),
        );
        final tracker =
            ReadingTracker(engine: engine, sentence: sentence, micConsent: true);
        final events = <TrackerEvent>[];
        tracker.eventsStream.listen(events.add);

        tracker.start();
        // 4 scripted hypotheses x 2s delay each = 8s of elapsed time,
        // comfortably clearing every 2s inter-hypothesis gap without any
        // single gap reaching the 4s (T1) silence threshold.
        async.elapse(const Duration(seconds: 9));

        expect(events, [
          WordAccepted(index: 0),
          WordAccepted(index: 1),
          WordAccepted(index: 2),
        ]);
        expect(events, isNot(contains(isA<Silence>())));
        expect(events, isNot(contains(isA<StruggleDetected>())));
      });
    });
  });

  group('Fixture: near-miss mispronunciation -- close-enough production '
      'turns the word green via the dedicated near-miss event', () {
    test('POSITIVE: "gat" for "cat" mid-sentence emits '
        'WordAcceptedNearMiss(index) for that word only, WordAccepted for '
        'the rest', () {
      fakeAsync((async) {
        final sentence = [_the, _cat, _sat];
        final engine = FakeAsrEngine(
          script: [_word('the'), _word('gat'), _word('sat')],
        );
        final tracker =
            ReadingTracker(engine: engine, sentence: sentence, micConsent: true);
        final events = <TrackerEvent>[];
        tracker.eventsStream.listen(events.add);

        tracker.start();
        async.flushMicrotasks();

        expect(events, [
          WordAccepted(index: 0),
          WordAcceptedNearMiss(index: 1),
          WordAccepted(index: 2),
        ]);
      });
    });
  });

  group('Fixture: silence -- no speech at all on the current word for T1', () {
    test('POSITIVE: silence for T1 with the engine never emitting anything '
        'produces Silence(duration: T1) then StruggleDetected(index: 0); '
        'the sentence remains incomplete (this fixture pins the trigger, '
        'not completion)', () {
      fakeAsync((async) {
        final sentence = [_the, _cat, _sat];
        final engine = FakeAsrEngine(script: const []);
        final tracker =
            ReadingTracker(engine: engine, sentence: sentence, micConsent: true);
        final events = <TrackerEvent>[];
        tracker.eventsStream.listen(events.add);

        tracker.start();
        async.elapse(kStruggleT1);

        expect(events, [Silence(duration: kStruggleT1), StruggleDetected(index: 0)]);
        expect(engine.recordedBiasingContext, ['the', 'cat', 'sat']);
      });
    });
  });

  group('Lookahead back-fill flows through end-to-end from the matcher '
      'through the full tracker', () {
    test('POSITIVE: skipping straight to word 2 back-fills word 1 as '
        'WordAccepted before word 2\'s own grade, both via a single '
        'FakeAsrEngine burst', () {
      fakeAsync((async) {
        final sentence = [_cat, _sat];
        final engine = FakeAsrEngine(script: [_word('sat')]);
        final tracker =
            ReadingTracker(engine: engine, sentence: sentence, micConsent: true);
        final events = <TrackerEvent>[];
        tracker.eventsStream.listen(events.add);

        tracker.start();
        async.flushMicrotasks();

        expect(events, [WordAccepted(index: 0), WordAccepted(index: 1)]);
      });
    });
  });

  group('Post-POC backlog (recorded, not tested here per ticket notes)', () {
    test(
      'documents that noise/cross-talk fixtures are explicitly deferred '
      '(PRD §8 Unit 4: "happy-path fixtures only for POC")',
      () {
        // No assertion: this test exists to make the deferral discoverable
        // from the suite itself, alongside docs/tickets/listening-tracker.json.
        expect(true, isTrue);
      },
      skip: 'post-POC backlog: noise/cross-talk fixtures not authored for '
          'POC per PRD §8 Unit 4 and the listening-tracker ticket notes',
    );
  });
}

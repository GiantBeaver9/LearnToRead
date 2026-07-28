/// Cloud minute cap tests (PRD §9 A-7, §8 Unit 4, ticket listening-tracker):
/// if a metered cloud engine substitutes for the default on-device engine,
/// usage is capped at 20 cloud-minutes per profile per day; reaching the cap
/// silently downgrades the tracker to the on-device engine with no
/// user-visible interruption. All timing is deterministic via fake_async.
///
/// Pinned API (implementation does not exist yet — red-for-right-reason):
///
///   lib/features/listening/tracker/cloud_minute_cap.dart:
///     const int kCloudDailyCapMinutes = 20; // A-7
///
///     class CloudMinuteCap {
///       CloudMinuteCap({int dailyCapMinutes = kCloudDailyCapMinutes});
///
///       int get dailyCapMinutes;
///       Duration get dailyCap;      // Duration(minutes: dailyCapMinutes)
///       Duration get usedToday;
///       bool get isCapReached;      // usedToday >= dailyCap
///
///       void recordUsage(Duration elapsed); // accrues cloud-engine-active
///                                            // time toward today's tally
///       void reset();                       // clears usedToday to zero
///                                            // (e.g. new calendar day)
///     }
///
/// Day-boundary / calendar-reset persistence (i.e. exactly when a "new day"
/// starts across app restarts) is explicitly NOT pinned by this ticket's
/// accept criteria and is left to whichever unit wires CloudMinuteCap to
/// profile storage; [reset] exists as the mechanism, its trigger is
/// unpinned here.
///
/// ReadingTracker integration (see reading_tracker_test.dart for the
/// canonical constructor): passing `engineIsMetered: true` together with a
/// `cloudMinuteCap` and an `onDeviceFallbackEngine` makes the tracker accrue
/// listening time against the cap while the metered engine is active and,
/// once the cap is reached, silently swap to the on-device engine (stop the
/// metered engine, start the on-device engine with the same biasing
/// context) without erroring or closing eventsStream. The exact internal
/// check granularity is an implementation detail; these tests assert only
/// that the swap has not happened before the cap and has happened by a
/// generous margin after it.
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/contracts/fake_asr_engine.dart';
import 'package:learn_to_read/features/listening/contracts/tracker_events.dart';
import 'package:learn_to_read/features/listening/tracker/cloud_minute_cap.dart';
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

void main() {
  group('CloudMinuteCap — unit behavior', () {
    test('POSITIVE: default dailyCapMinutes is the A-7 pinned constant (20)', () {
      final cap = CloudMinuteCap();
      expect(cap.dailyCapMinutes, kCloudDailyCapMinutes);
      expect(kCloudDailyCapMinutes, 20);
    });

    test('POSITIVE: dailyCap exposes the constant as a Duration', () {
      final cap = CloudMinuteCap(dailyCapMinutes: 5);
      expect(cap.dailyCap, const Duration(minutes: 5));
    });

    test('POSITIVE: usedToday starts at zero', () {
      final cap = CloudMinuteCap();
      expect(cap.usedToday, Duration.zero);
    });

    test('POSITIVE: isCapReached is false below the cap', () {
      final cap = CloudMinuteCap(dailyCapMinutes: 5);
      cap.recordUsage(const Duration(minutes: 4));
      expect(cap.isCapReached, isFalse);
    });

    test('POSITIVE: isCapReached becomes true exactly at the cap', () {
      final cap = CloudMinuteCap(dailyCapMinutes: 5);
      cap.recordUsage(const Duration(minutes: 5));
      expect(cap.isCapReached, isTrue);
    });

    test('POSITIVE: isCapReached stays true beyond the cap', () {
      final cap = CloudMinuteCap(dailyCapMinutes: 5);
      cap.recordUsage(const Duration(minutes: 5));
      cap.recordUsage(const Duration(minutes: 2));
      expect(cap.isCapReached, isTrue);
      expect(cap.usedToday, const Duration(minutes: 7));
    });

    test('POSITIVE: recordUsage accumulates across multiple calls', () {
      final cap = CloudMinuteCap(dailyCapMinutes: 20);
      cap.recordUsage(const Duration(minutes: 5));
      cap.recordUsage(const Duration(minutes: 5));
      cap.recordUsage(const Duration(minutes: 5));
      expect(cap.usedToday, const Duration(minutes: 15));
      expect(cap.isCapReached, isFalse);
    });

    test('POSITIVE: reset() clears usedToday back to zero', () {
      final cap = CloudMinuteCap(dailyCapMinutes: 5);
      cap.recordUsage(const Duration(minutes: 5));
      expect(cap.isCapReached, isTrue);

      cap.reset();

      expect(cap.usedToday, Duration.zero);
      expect(cap.isCapReached, isFalse);
    });

    test('EDGE: dailyCapMinutes is tunable, not hardcoded', () {
      final tiny = CloudMinuteCap(dailyCapMinutes: 1);
      tiny.recordUsage(const Duration(seconds: 61));
      expect(tiny.isCapReached, isTrue);

      final generous = CloudMinuteCap(dailyCapMinutes: 60);
      generous.recordUsage(const Duration(minutes: 20));
      expect(generous.isCapReached, isFalse);
    });

    test('EDGE: recordUsage(Duration.zero) never advances the tally', () {
      final cap = CloudMinuteCap(dailyCapMinutes: 5);
      cap.recordUsage(Duration.zero);
      expect(cap.usedToday, Duration.zero);
      expect(cap.isCapReached, isFalse);
    });
  });

  group('ReadingTracker + CloudMinuteCap — silent downgrade integration '
      '(A-7, R2)', () {
    test('POSITIVE: before the cap is reached, the metered engine stays '
        'active -- no swap to on-device', () {
      fakeAsync((async) {
        final cloudEngine = FakeAsrEngine(script: const []);
        final onDeviceEngine = FakeAsrEngine(script: const []);
        final cap = CloudMinuteCap(dailyCapMinutes: 1);
        final tracker = ReadingTracker(
          engine: cloudEngine,
          sentence: [_cat],
          micConsent: true,
          engineIsMetered: true,
          cloudMinuteCap: cap,
          onDeviceFallbackEngine: onDeviceEngine,
          // Large so unrelated silence/struggle events don't clutter this
          // test's assertions.
          struggleSilenceThreshold: const Duration(hours: 1),
        );
        final events = <TrackerEvent>[];
        tracker.eventsStream.listen(events.add);

        tracker.start();
        async.elapse(const Duration(seconds: 30)); // well under the 1-min cap

        expect(onDeviceEngine.recordedBiasingContext, isNull,
            reason: 'the on-device fallback must not be touched yet');
      });
    });

    test('POSITIVE: once the cap is reached, the tracker silently swaps to '
        'the on-device engine with the same biasing context', () {
      fakeAsync((async) {
        final cloudEngine = FakeAsrEngine(script: const []);
        final onDeviceEngine = FakeAsrEngine(script: const []);
        final cap = CloudMinuteCap(dailyCapMinutes: 1);
        final tracker = ReadingTracker(
          engine: cloudEngine,
          sentence: [_cat],
          micConsent: true,
          engineIsMetered: true,
          cloudMinuteCap: cap,
          onDeviceFallbackEngine: onDeviceEngine,
          struggleSilenceThreshold: const Duration(hours: 1),
        );
        final events = <TrackerEvent>[];
        var streamErrored = false;
        tracker.eventsStream
            .listen(events.add, onError: (_) => streamErrored = true);

        tracker.start();
        // Generous margin past the 1-minute cap.
        async.elapse(const Duration(minutes: 2));

        expect(onDeviceEngine.recordedBiasingContext, ['cat'],
            reason: 'the on-device fallback is started with the same '
                'expected-text biasing context');
        expect(streamErrored, isFalse);
        expect(cap.isCapReached, isTrue);
      });
    });

    test('POSITIVE: after the silent downgrade, hypotheses now arrive from '
        'the on-device engine and are still processed normally -- no '
        'interruption to reading', () {
      fakeAsync((async) {
        final cloudEngine = FakeAsrEngine(script: const []);
        // Once the tracker subscribes to this engine (at downgrade time),
        // it immediately emits an exact match for "cat".
        final onDeviceEngine = FakeAsrEngine(script: [
          Hypothesis(wordHypotheses: const ['cat'], phoneHypotheses: null),
        ]);
        final cap = CloudMinuteCap(dailyCapMinutes: 1);
        final tracker = ReadingTracker(
          engine: cloudEngine,
          sentence: [_cat],
          micConsent: true,
          engineIsMetered: true,
          cloudMinuteCap: cap,
          onDeviceFallbackEngine: onDeviceEngine,
          struggleSilenceThreshold: const Duration(hours: 1),
        );
        final events = <TrackerEvent>[];
        tracker.eventsStream.listen(events.add);

        tracker.start();
        async.elapse(const Duration(minutes: 2)); // forces the downgrade

        // The word accepted via the on-device engine after the downgrade
        // confirms the tracker is now listening on it and the matching
        // pipeline is intact -- no interruption to reading.
        expect(events, [WordAccepted(index: 0)]);
      });
    });

    test('EDGE: a tracker with engineIsMetered: false never touches the '
        'cloud minute cap even if one is supplied', () {
      fakeAsync((async) {
        final engine = FakeAsrEngine(script: const []);
        final onDeviceEngine = FakeAsrEngine(script: const []);
        final cap = CloudMinuteCap(dailyCapMinutes: 1);
        final tracker = ReadingTracker(
          engine: engine,
          sentence: [_cat],
          micConsent: true,
          engineIsMetered: false,
          cloudMinuteCap: cap,
          onDeviceFallbackEngine: onDeviceEngine,
          struggleSilenceThreshold: const Duration(hours: 1),
        );

        tracker.start();
        async.elapse(const Duration(minutes: 5));

        expect(cap.usedToday, Duration.zero);
        expect(onDeviceEngine.recordedBiasingContext, isNull);
      });
    });
  });
}

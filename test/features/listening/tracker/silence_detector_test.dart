/// Unit tests for the standalone silence timer used by the listening
/// tracker's struggle-detection path (b) (PRD §8 Unit 4, §9 A-12b, ticket
/// listening-tracker). All timing is deterministic via fake_async -- no
/// wall-clock sleeps anywhere in this suite.
///
/// Pinned API (implementation does not exist yet — red-for-right-reason):
///
///   lib/features/listening/tracker/silence_detector.dart:
///     class SilenceDetector {
///       SilenceDetector({
///         required Duration threshold,
///         required void Function(Duration duration) onThreshold,
///       });
///
///       Duration get threshold;
///       bool get isRunning;
///
///       void start();        // begins (or restarts) the countdown from now
///       void noteActivity(); // equivalent to stop-then-start: resets the
///                             // countdown to a fresh [threshold] from now
///       void stop();         // cancels any pending countdown; onThreshold
///                             // will not fire until start() is called again
///     }
///
/// onThreshold fires exactly once, with duration == threshold, when
/// [threshold] elapses since the most recent start()/noteActivity() call
/// without an intervening stop(). It never fires spontaneously more than
/// once per start()/noteActivity() cycle -- callers that want it to arm
/// again call start() (or noteActivity()) again.
library;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/features/listening/tracker/silence_detector.dart';

void main() {
  group('SilenceDetector — construction', () {
    test('POSITIVE: constructs with a threshold and callback', () {
      final detector = SilenceDetector(
        threshold: const Duration(seconds: 4),
        onThreshold: (_) {},
      );
      expect(detector.threshold, const Duration(seconds: 4));
    });

    test('POSITIVE: is not running before start() is called', () {
      final detector = SilenceDetector(
        threshold: const Duration(seconds: 4),
        onThreshold: (_) {},
      );
      expect(detector.isRunning, isFalse);
    });
  });

  group('SilenceDetector — fires once threshold elapses', () {
    test('POSITIVE: fires onThreshold with duration == threshold after '
        'exactly the threshold elapses', () {
      fakeAsync((async) {
        Duration? fired;
        final detector = SilenceDetector(
          threshold: const Duration(seconds: 4),
          onThreshold: (d) => fired = d,
        );

        detector.start();
        async.elapse(const Duration(seconds: 4));

        expect(fired, const Duration(seconds: 4));
      });
    });

    test('POSITIVE: isRunning is true immediately after start()', () {
      fakeAsync((async) {
        final detector = SilenceDetector(
          threshold: const Duration(seconds: 4),
          onThreshold: (_) {},
        );
        detector.start();
        expect(detector.isRunning, isTrue);
      });
    });

    test('NEGATIVE: boundary — 3.9s of a 4s threshold does not fire', () {
      fakeAsync((async) {
        Duration? fired;
        final detector = SilenceDetector(
          threshold: const Duration(seconds: 4),
          onThreshold: (d) => fired = d,
        );

        detector.start();
        async.elapse(const Duration(milliseconds: 3900));

        expect(fired, isNull);
      });
    });

    test('POSITIVE: boundary — 4.1s of a 4s threshold has already fired', () {
      fakeAsync((async) {
        Duration? fired;
        final detector = SilenceDetector(
          threshold: const Duration(seconds: 4),
          onThreshold: (d) => fired = d,
        );

        detector.start();
        async.elapse(const Duration(milliseconds: 4100));

        expect(fired, const Duration(seconds: 4));
      });
    });

    test('POSITIVE: fires only once even if time keeps elapsing after the '
        'threshold', () {
      fakeAsync((async) {
        var callCount = 0;
        final detector = SilenceDetector(
          threshold: const Duration(seconds: 4),
          onThreshold: (_) => callCount += 1,
        );

        detector.start();
        async.elapse(const Duration(seconds: 4));
        expect(callCount, 1);
        async.elapse(const Duration(seconds: 20));

        expect(callCount, 1,
            reason: 'single-shot per start()/noteActivity() cycle');
      });
    });
  });

  group('SilenceDetector — noteActivity() resets the countdown', () {
    test('POSITIVE: noteActivity() before the threshold elapses restarts '
        'the countdown -- only threshold time after the LAST activity '
        'fires', () {
      fakeAsync((async) {
        Duration? fired;
        final detector = SilenceDetector(
          threshold: const Duration(seconds: 4),
          onThreshold: (d) => fired = d,
        );

        detector.start();
        async.elapse(const Duration(seconds: 3));
        expect(fired, isNull);

        detector.noteActivity();
        async.elapse(const Duration(seconds: 3));
        expect(fired, isNull,
            reason: 'only 3s have passed since the reset; threshold is 4s');

        async.elapse(const Duration(seconds: 1, milliseconds: 100));
        expect(fired, const Duration(seconds: 4));
      });
    });

    test('POSITIVE: repeated noteActivity() calls keep deferring the fire '
        'indefinitely', () {
      fakeAsync((async) {
        var callCount = 0;
        final detector = SilenceDetector(
          threshold: const Duration(seconds: 4),
          onThreshold: (_) => callCount += 1,
        );

        detector.start();
        for (var i = 0; i < 5; i++) {
          async.elapse(const Duration(seconds: 3));
          detector.noteActivity();
        }

        expect(callCount, 0);
      });
    });
  });

  group('SilenceDetector — stop() cancels the pending countdown', () {
    test('POSITIVE: stop() before the threshold elapses prevents the fire '
        'even as more time passes', () {
      fakeAsync((async) {
        var callCount = 0;
        final detector = SilenceDetector(
          threshold: const Duration(seconds: 4),
          onThreshold: (_) => callCount += 1,
        );

        detector.start();
        async.elapse(const Duration(seconds: 2));
        detector.stop();
        async.elapse(const Duration(seconds: 10));

        expect(callCount, 0);
      });
    });

    test('POSITIVE: isRunning is false after stop()', () {
      fakeAsync((async) {
        final detector = SilenceDetector(
          threshold: const Duration(seconds: 4),
          onThreshold: (_) {},
        );
        detector.start();
        detector.stop();
        expect(detector.isRunning, isFalse);
      });
    });

    test('EDGE: stop() before start() is a safe no-op', () {
      final detector = SilenceDetector(
        threshold: const Duration(seconds: 4),
        onThreshold: (_) {},
      );
      expect(() => detector.stop(), returnsNormally);
    });

    test('EDGE: calling stop() twice is a safe no-op', () {
      final detector = SilenceDetector(
        threshold: const Duration(seconds: 4),
        onThreshold: (_) {},
      );
      detector.start();
      detector.stop();
      expect(() => detector.stop(), returnsNormally);
    });
  });

  group('SilenceDetector — restart after firing', () {
    test('POSITIVE: calling start() again after firing re-arms the '
        'detector for another full threshold', () {
      fakeAsync((async) {
        var callCount = 0;
        final detector = SilenceDetector(
          threshold: const Duration(seconds: 4),
          onThreshold: (_) => callCount += 1,
        );

        detector.start();
        async.elapse(const Duration(seconds: 4));
        expect(callCount, 1);

        detector.start();
        async.elapse(const Duration(seconds: 3));
        expect(callCount, 1);
        async.elapse(const Duration(seconds: 1, milliseconds: 100));
        expect(callCount, 2);
      });
    });

    test('EDGE: calling start() again while already running restarts the '
        'countdown from zero rather than double-firing early', () {
      fakeAsync((async) {
        var callCount = 0;
        final detector = SilenceDetector(
          threshold: const Duration(seconds: 4),
          onThreshold: (_) => callCount += 1,
        );

        detector.start();
        async.elapse(const Duration(seconds: 3));
        detector.start(); // restart before the first countdown completed
        async.elapse(const Duration(seconds: 3));
        expect(callCount, 0,
            reason: 'restarting resets the clock; only 3s have passed since '
                'the second start()');
        async.elapse(const Duration(seconds: 1, milliseconds: 100));
        expect(callCount, 1);
      });
    });
  });

  group('SilenceDetector — threshold is tunable (never hardcoded)', () {
    test('POSITIVE: a 1-second threshold fires after 1s, not 4s', () {
      fakeAsync((async) {
        Duration? fired;
        final detector = SilenceDetector(
          threshold: const Duration(seconds: 1),
          onThreshold: (d) => fired = d,
        );

        detector.start();
        async.elapse(const Duration(seconds: 1));

        expect(fired, const Duration(seconds: 1));
      });
    });

    test('POSITIVE: a long threshold (30s) does not fire early', () {
      fakeAsync((async) {
        var callCount = 0;
        final detector = SilenceDetector(
          threshold: const Duration(seconds: 30),
          onThreshold: (_) => callCount += 1,
        );

        detector.start();
        async.elapse(const Duration(seconds: 29));

        expect(callCount, 0);
      });
    });
  });
}

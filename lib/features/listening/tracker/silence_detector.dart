/// Standalone silence timer behind struggle-detection path (b)
/// (PRD §8 Unit 4, §9 A-12b).
///
/// A-12 pins two independent struggle paths: (a) two consecutive finalized
/// hypothesis bursts containing speech that fails to match the current word,
/// and (b) sustained silence >= T1. This class is (b) and nothing else: a
/// single-shot countdown that the tracker re-arms on every burst of real
/// speech, on word advance, and on resume.
///
/// It owns no clock of its own beyond [Timer], so `fake_async` drives it
/// deterministically — there are no wall-clock sleeps anywhere in the
/// listening pipeline.
///
/// The threshold is always injected (from `kStruggleT1` in
/// lib/domain/tuning.dart, via `ReadingTracker.struggleSilenceThreshold`) and
/// never hardcoded here: a pilot tuning pass touches only the tuning file.
///
/// T1 relationship with the stuck-word scaffold (Unit 6): the same T1 that
/// fires this detector is the trigger the scaffold's tier-1 help waits on.
/// The tracker emits `Silence(duration: T1)` immediately followed by
/// `StruggleDetected(index)`; Unit 6 subscribes to the tracker's event stream
/// and starts its own tier-2 wait (T2) from there. The two timers are
/// deliberately separate — this one lives entirely inside the tracker and
/// never knows about help tiers.
library;

import 'dart:async';

/// A single-shot "nothing happened for [threshold]" countdown.
///
/// ```dart
/// final detector = SilenceDetector(
///   threshold: kStruggleT1,
///   onThreshold: (d) => emit(Silence(duration: d)),
/// );
/// detector.start();        // arm
/// detector.noteActivity(); // a burst of real speech: re-arm from now
/// detector.stop();         // paused / stopped: disarm
/// ```
///
/// [onThreshold] fires exactly once per [start]/[noteActivity] cycle, with
/// `duration == threshold`. After it fires the detector is idle until a
/// caller arms it again — that is what makes struggle-by-silence a
/// once-per-word event rather than a repeating alarm.
class SilenceDetector {
  /// Creates a detector that calls [onThreshold] once [threshold] elapses
  /// without activity.
  SilenceDetector({required this.threshold, required this.onThreshold});

  /// How long without activity counts as silence (injected; see
  /// `kStruggleT1`).
  final Duration threshold;

  /// Invoked with [threshold] when the countdown completes.
  final void Function(Duration duration) onThreshold;

  Timer? _timer;

  /// True while a countdown is pending (armed and not yet fired/cancelled).
  bool get isRunning => _timer != null;

  /// Begins — or restarts from zero — the countdown.
  ///
  /// Calling [start] while already running discards the pending countdown and
  /// starts a fresh one; it never double-fires or fires early.
  void start() {
    _timer?.cancel();
    _timer = Timer(threshold, _fire);
  }

  /// Resets the countdown to a fresh [threshold] from now.
  ///
  /// Semantically identical to [start]; the separate name is the vocabulary
  /// the tracker uses at the call sites where *speech was heard* (as opposed
  /// to *the word advanced* or *listening resumed*).
  void noteActivity() => start();

  /// Cancels any pending countdown. [onThreshold] will not fire until the
  /// detector is armed again. Safe before [start] and safe to repeat.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _fire() {
    _timer = null;
    onThreshold(threshold);
  }
}

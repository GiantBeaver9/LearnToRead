/// FakeReadingTracker: scripted tracker event stream for testing (Unit 4 fakes).
///
/// Emits a predefined sequence of tracker events (wordAccepted, struggle,
/// silence, etc.) with configurable timing. Used to test Units 5–6–14
/// without invoking the real matching layer or engine.
library;

import 'dart:async';
import 'tracker_events.dart';

/// Fake reading tracker for testing: emits scripted event sequences.
///
/// Use [FakeReadingTracker] to test the reading screen and stuck-word
/// scaffold without the full matching pipeline. Configure the event script,
/// delays, and iterate in tests.
class FakeReadingTracker {
  /// Constructs a fake tracker with a scripted event sequence.
  ///
  /// [script]: list of tracker events to emit in order.
  /// [delayBetweenEvents]: delay before emitting each event.
  /// Defaults to [Duration.zero].
  FakeReadingTracker({
    required this.script,
    this.delayBetweenEvents = const Duration(),
  });

  /// The scripted event sequence to emit.
  final List<TrackerEvent> script;

  /// Delay before emitting each event.
  final Duration delayBetweenEvents;

  /// Stream of tracker events.
  ///
  /// Emits events from [script] in order, with [delayBetweenEvents]
  /// between each emission. Completes when the script is exhausted.
  Stream<TrackerEvent> get eventsStream => _emitEvents();

  /// Internal stream factory.
  Stream<TrackerEvent> _emitEvents() async* {
    for (final event in script) {
      if (delayBetweenEvents > Duration.zero) {
        await Future.delayed(delayBetweenEvents);
      }
      yield event;
    }
  }
}

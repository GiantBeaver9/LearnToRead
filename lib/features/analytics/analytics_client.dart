/// The single entry point screens use to record analytics — and the
/// single place the kill switch lives (PRD §8 Unit 12: "A single build
/// flag disables all analytics (for review builds and as a kill switch)";
/// acceptance: "kill-switch build emits zero network calls... the client
/// becomes a no-op").
///
/// When [AnalyticsClient.enabled] is false the client short-circuits
/// *before* anything else happens: no schema validation, no serialization,
/// no file write, no transport call. Not "queued but never sent" — nothing
/// is recorded at all, so a review build leaves no analytics residue on
/// the device.
library;

import 'event_queue.dart';
import 'event_schema.dart';

/// The single build flag: `--dart-define=DISABLE_ANALYTICS=true` turns the
/// whole feature off.
const bool kAnalyticsDisabledByBuildFlag =
    bool.fromEnvironment('DISABLE_ANALYTICS');

/// Whether analytics is compiled in for this build.
const bool kAnalyticsEnabled = !kAnalyticsDisabledByBuildFlag;

/// Records analytics events, or does nothing at all.
class AnalyticsClient {
  /// Creates a client writing into [queue].
  ///
  /// Production passes [kAnalyticsEnabled] for [enabled]; tests pass the
  /// flag explicitly.
  AnalyticsClient({required this.enabled, required EventQueue queue})
      : _queue = queue;

  /// Whether analytics is on. When false, every method is a no-op.
  final bool enabled;

  final EventQueue _queue;

  /// Records [event] into the offline queue. Never sends by itself — see
  /// [flush].
  ///
  /// A no-op when [enabled] is false, including for structurally invalid
  /// events: the kill switch short-circuits before validation, so a
  /// disabled client cannot throw.
  Future<void> track(AnalyticsEvent event) async {
    if (!enabled) return;
    final payload = event.toPayload();
    try {
      validateEventPayload(payload);
    } on SchemaViolation catch (violation) {
      // A schema violation is a programming error at the emitting call
      // site, so it must be loud in debug/test builds — but analytics must
      // never crash a child's reading session in release, and an invalid
      // payload must never be transmitted. Hence: assert, then drop.
      assert(false, '$violation');
      return;
    }
    await _queue.enqueue(payload);
  }

  /// Attempts to deliver everything queued, in batches.
  ///
  /// Returns how many payloads were accepted and how many were dropped for
  /// exceeding the 30-day retention limit. A no-op (and all-zero result)
  /// when [enabled] is false.
  Future<({int sent, int dropped})> flush() async {
    if (!enabled) return (sent: 0, dropped: 0);
    return _queue.flush();
  }
}

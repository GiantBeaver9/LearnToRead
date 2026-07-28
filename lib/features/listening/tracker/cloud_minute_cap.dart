/// Per-profile daily cloud-minute tally (PRD §9 A-7, §8 Unit 4, risk R2).
///
/// The default ASR engine is on-device (A-10), which makes metering moot.
/// If a *metered* cloud engine substitutes behind the same
/// [AsrEngine](../contracts/asr_engine.dart) interface, its active listening
/// time is capped at [kCloudDailyCapMinutes] minutes per profile per day;
/// when the cap is reached the tracker silently downgrades to the on-device
/// engine with no user-visible interruption (R2).
///
/// This class is a pure, in-memory tally: it owns no clock, no storage and
/// no engine. Callers ([ReadingTracker](reading_tracker.dart)) accrue time
/// with [recordUsage] while the metered engine is actually listening, and
/// clear the tally with [reset].
///
/// Day-boundary persistence (exactly when a "new day" starts, and how the
/// tally survives app restarts) is deliberately NOT pinned by this unit:
/// [reset] is the mechanism, and whichever unit wires a [CloudMinuteCap] to
/// profile storage owns its trigger.
library;

/// A-7: cloud-minutes allowed per profile per day when a metered cloud
/// engine substitutes for the default on-device engine.
const int kCloudDailyCapMinutes = 20;

/// In-memory daily tally of metered cloud-engine listening time.
///
/// ```dart
/// final cap = CloudMinuteCap();          // 20 minutes (A-7)
/// cap.recordUsage(const Duration(seconds: 30));
/// if (cap.isCapReached) { /* silent downgrade to on-device */ }
/// ```
class CloudMinuteCap {
  /// Creates a tally with a daily ceiling of [dailyCapMinutes] minutes.
  ///
  /// Defaults to the A-7 pinned constant [kCloudDailyCapMinutes]; the
  /// parameter exists so pilots (and tests) can tune the ceiling without
  /// touching call sites — it is never hardcoded downstream.
  CloudMinuteCap({this.dailyCapMinutes = kCloudDailyCapMinutes});

  /// The daily ceiling, in whole minutes.
  final int dailyCapMinutes;

  Duration _usedToday = Duration.zero;

  /// The daily ceiling expressed as a [Duration].
  Duration get dailyCap => Duration(minutes: dailyCapMinutes);

  /// Metered cloud-engine time accrued since the last [reset].
  Duration get usedToday => _usedToday;

  /// True once [usedToday] has reached (or passed) [dailyCap].
  ///
  /// The boundary is inclusive: exactly [dailyCap] counts as reached, so the
  /// downgrade happens *at* the cap rather than one tick after it.
  bool get isCapReached => _usedToday >= dailyCap;

  /// Accrues [elapsed] of metered cloud-engine listening toward today's
  /// tally. Accumulates across calls; [Duration.zero] never moves the tally.
  void recordUsage(Duration elapsed) {
    if (elapsed <= Duration.zero) return;
    _usedToday += elapsed;
  }

  /// Clears the tally back to zero (e.g. a new calendar day).
  void reset() {
    _usedToday = Duration.zero;
  }

  @override
  String toString() =>
      'CloudMinuteCap(usedToday: $_usedToday, dailyCap: $dailyCap)';
}

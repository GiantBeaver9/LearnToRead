/// Session boundaries and story-abandonment detection (PRD §8 Unit 12,
/// pinned verbatim):
///
/// - "a **session** starts at profile selection and ends when the app is
///   backgrounded for more than 120 s, is closed, or the profile switches
///   (timeout is a tunable constant)."
/// - "**`story_abandoned`** fires when the reading screen is exited after
///   `story_started` but before `story_completed` — including via session
///   end — and carries whether a help event occurred in the preceding
///   30 s (the §4.4 frustration marker)."
///
/// This class owns *only* those two rules. It emits the `session_start`
/// and `story_abandoned` events (the ones nobody else is in a position to
/// know about) through [SessionTracker.onEvent]; every other §5 event is
/// emitted by the screen that causes it, straight to `AnalyticsClient`.
///
/// Everything is driven by the injected [Clock] and explicit lifecycle
/// calls — there are no timers inside, so the app shell decides when
/// "backgrounded" happens and tests script it exactly.
library;

import 'event_schema.dart';
import 'events.dart';

/// How long the app may stay backgrounded before the session ends
/// (PRD §8 Unit 12; tunable).
const Duration kSessionBackgroundTimeout = Duration(seconds: 120);

/// How recently `help_given` must have fired for an abandonment to be
/// flagged as post-help (PRD §8 Unit 12 / §4.4; tunable).
const Duration kAbandonmentHelpWindow = Duration(seconds: 30);

/// Tracks the current reading session and fires `story_abandoned`.
class SessionTracker {
  /// Creates a tracker that emits events via [onEvent].
  ///
  /// [backgroundTimeout] and [helpWindow] are independently tunable
  /// constants, defaulting to the pinned 120 s / 30 s.
  SessionTracker({
    required Clock clock,
    required this.installId,
    required void Function(AnalyticsEvent event) onEvent,
    this.backgroundTimeout = kSessionBackgroundTimeout,
    this.helpWindow = kAbandonmentHelpWindow,
  })  : _clock = clock,
        _onEvent = onEvent;

  final Clock _clock;
  final void Function(AnalyticsEvent event) _onEvent;

  /// The random per-install UUID stamped on every emitted event.
  final String installId;

  /// Background duration beyond which the session is considered ended.
  final Duration backgroundTimeout;

  /// Window before an abandonment in which a `help_given` counts as
  /// "help in the last 30 s".
  final Duration helpWindow;

  int? _profileOrdinal;
  int? _levelOrdinal;
  String? _activeStoryId;
  DateTime? _lastHelpAt;
  DateTime? _backgroundedAt;

  /// Whether a session is currently open.
  bool get isSessionActive => _profileOrdinal != null;

  /// The story currently being read, if any.
  String? get activeStoryId => _activeStoryId;

  /// Starts a session at profile selection.
  ///
  /// Calling this while a session is already open *is* a profile switch:
  /// the open session ends first (running the same abandonment check as
  /// any other session ending, and attributing the abandonment to the old
  /// profile), and only then does the new session start.
  void startSession({required int profileOrdinal, required int levelOrdinal}) {
    if (isSessionActive) _endSession();
    _profileOrdinal = profileOrdinal;
    _levelOrdinal = levelOrdinal;
    _activeStoryId = null;
    _lastHelpAt = null;
    _backgroundedAt = null;
    _emit(AnalyticsEventName.sessionStart);
  }

  /// The app went to the background; the clock on [backgroundTimeout]
  /// starts now.
  void onBackground() {
    if (!isSessionActive) return;
    _backgroundedAt = _clock();
  }

  /// The app came back. If it was away for longer than
  /// [backgroundTimeout], the session ended while it was away.
  void onForeground() {
    final backgroundedAt = _backgroundedAt;
    if (backgroundedAt == null) return;
    _backgroundedAt = null;
    if (_clock().difference(backgroundedAt) > backgroundTimeout) {
      // The session did not end now, when the app came back — it ended
      // when the child put the app down. Dating the ending (and therefore
      // the abandonment, and therefore the help-recency window) at
      // backgrounding is what makes "helped, then walked away" register as
      // post-help frustration however long the app then sat closed.
      _endSession(endedAt: backgroundedAt);
    }
  }

  /// The app is closing: the session ends now.
  void onClose() {
    if (!isSessionActive) return;
    _endSession();
  }

  /// A story was opened on the reading screen.
  void onStoryStarted({required String storyId}) {
    if (!isSessionActive) return;
    _activeStoryId = storyId;
    // Help recency is per story: a help given in a previous story must not
    // flag the next story's abandonment.
    _lastHelpAt = null;
  }

  /// The current story was read to the end — it can no longer be
  /// abandoned.
  void onStoryCompleted() {
    _activeStoryId = null;
    _lastHelpAt = null;
  }

  /// The reading screen was left. Mid-story, that is an abandonment even
  /// though the session itself continues.
  void onReadingScreenExited() => _abandonIfMidStory();

  /// A help tier fired; starts/refreshes the [helpWindow].
  void onHelpGiven() {
    if (!isSessionActive) return;
    _lastHelpAt = _clock();
  }

  /// Ends the open session, abandoning any story still in progress.
  ///
  /// [endedAt] is when the session actually ended, which is "now" for a
  /// close or a profile switch but is the moment of backgrounding for a
  /// background timeout.
  void _endSession({DateTime? endedAt}) {
    _abandonIfMidStory(at: endedAt);
    _profileOrdinal = null;
    _levelOrdinal = null;
    _activeStoryId = null;
    _lastHelpAt = null;
    _backgroundedAt = null;
  }

  /// Emits `story_abandoned` exactly once per started-but-not-completed
  /// story: clearing [_activeStoryId] here is what stops a direct exit and
  /// a later session end from double-firing.
  void _abandonIfMidStory({DateTime? at}) {
    final storyId = _activeStoryId;
    if (storyId == null || !isSessionActive) return;
    final abandonedAt = at ?? _clock();
    _activeStoryId = null;
    _emit(
      AnalyticsEventName.storyAbandoned,
      at: abandonedAt,
      storyId: storyId,
      fields: {'helpInLast30s': _helpWithinWindow(abandonedAt)},
    );
    _lastHelpAt = null;
  }

  bool _helpWithinWindow(DateTime abandonedAt) {
    final lastHelpAt = _lastHelpAt;
    if (lastHelpAt == null) return false;
    return abandonedAt.difference(lastHelpAt) <= helpWindow;
  }

  void _emit(
    AnalyticsEventName name, {
    DateTime? at,
    String? storyId,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    _onEvent(AnalyticsEvent(
      name: name,
      timestamp: at ?? _clock(),
      installId: installId,
      profileOrdinal: _profileOrdinal!,
      levelOrdinal: _levelOrdinal!,
      storyId: storyId,
      fields: fields,
    ));
  }
}

/// Platform on-device ASR engine adapter (PRD §9 A-10; platform-asr-adapter).
///
/// The Dart half of the production Android handler
/// (`android/.../AsrSpeechHandler.kt`): an [AsrEngine] over the platform's
/// on-device `SpeechRecognizer`, wired behind the existing engine seam
/// (`asrEngineProvider`) so swapping it in is the one-line boot override the
/// seam was designed for. Built at owner direction, superseding the Unit 0
/// spike gate.
///
/// ## Channel contract (must match AsrSpeechHandler.kt exactly)
///
///   method channel [methodChannelName]:
///     `start` -> arguments: `{ "biasingWords": [String] }`
///     `stop`  -> arguments: none
///
///   event channel [eventChannelName] emits, per hypothesis burst:
///     `{ "words": [String],   // top alternatives, best first
///        "isFinal": bool }`   // false for partials, true for finals
///
/// Both partials and finals are forwarded as [Hypothesis] objects — the
/// matcher's whitespace-split candidate extraction and repeat handling are
/// built for cumulative bursts. `phoneHypotheses` is always null: Android
/// SpeechRecognizer exposes no phone-level detail (the Unit 0 spike finding);
/// Unit 14's sound mode approximates downstream by phonetic distance.
///
/// ## Stream semantics (pinned by sharedAsrEngineProvider's header)
///
/// One long-lived broadcast stream, the SAME object on every
/// [hypothesesStream] access, that survives [stop]/re-[start] cycles —
/// vocabulary cards and narration replays must never replay history or get a
/// dead stream. The AsrEngine contract permits this ("may be closed OR
/// produce no new events" after stop): here it stays open and silent.
///
/// ## Errors
///
/// The native side handles every recoverable condition itself (the
/// continuous-listening restart loop with backoff); only unrecoverable
/// failures arrive here, as channel error events. They are logged and
/// forwarded as stream *errors* — never data, and never a stream close — so
/// `ReadingTracker`'s A-7/fallback chain (which listens with
/// `cancelOnError: true`) owns the policy: it degrades that session to tap
/// mode while the stream stays alive for the next session's restart.
///
/// On hosts without the native handler (tests, desktop, iOS until its
/// adapter lands) every channel interaction raises [MissingPluginException];
/// this engine swallows it and behaves as a silent engine — [start] succeeds,
/// nothing ever arrives — exactly the shipped `FakeAsrEngine(script: [])`
/// posture, so nothing off-Android can crash.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';

/// [AsrEngine] over the platform's on-device recognizer (Android
/// SpeechRecognizer with contextual biasing, PRD §9 A-10).
class PlatformAsrEngine implements AsrEngine {
  /// Creates the engine. Nothing platform-side happens until [start].
  PlatformAsrEngine();

  /// Method channel name. Must match AsrSpeechHandler.kt exactly.
  static const String methodChannelName = 'learn_to_read/asr/method';

  /// Event channel name. Must match AsrSpeechHandler.kt exactly.
  static const String eventChannelName = 'learn_to_read/asr/events';

  static const MethodChannel _methodChannel = MethodChannel(methodChannelName);
  static const EventChannel _eventChannel = EventChannel(eventChannelName);

  /// The one long-lived hypothesis pipe. Never closed by [stop] — the same
  /// stream must serve every start/stop cycle of the app session.
  final StreamController<Hypothesis> _hypotheses =
      StreamController<Hypothesis>.broadcast();

  /// Cached so every [hypothesesStream] access returns the IDENTICAL object
  /// (a broadcast controller's `stream` getter mints a new view per access).
  late final Stream<Hypothesis> _stream = _hypotheses.stream;

  StreamSubscription<dynamic>? _eventSubscription;
  bool _disposed = false;

  @override
  Stream<Hypothesis> get hypothesesStream => _stream;

  @override
  void start(List<String> biasingContext) {
    if (_disposed) return;
    _ensureSubscribed();
    // Fire-and-forget: AsrEngine.start is synchronous void. A start-while-
    // started is handled natively as a graceful stop-then-restart.
    unawaited(
      _invoke('start', <String, Object?>{
        'biasingWords': List<String>.of(biasingContext),
      }),
    );
  }

  @override
  void stop() {
    if (_disposed) return;
    // Stops native recognition; deliberately does NOT close [_hypotheses]
    // and does NOT cancel the event subscription — the stream stays alive
    // (and silent: the native side emits nothing once stopped) so a later
    // start() resumes on the same pipe.
    unawaited(_invoke('stop'));
  }

  /// Releases the channel subscription and closes the stream for good.
  /// Not part of [AsrEngine]; for app teardown and tests only.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_eventSubscription?.cancel());
    _eventSubscription = null;
    if (!_hypotheses.isClosed) unawaited(_hypotheses.close());
  }

  /// Subscribes the event channel exactly once, lazily, on first [start] —
  /// so merely constructing the engine (or reading [hypothesesStream])
  /// touches no platform channel.
  void _ensureSubscribed() {
    if (_eventSubscription != null) return;
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
          _onEvent,
          onError: _onEventError,
          // The platform stream must never end; if it somehow does, the
          // engine simply goes silent (the stream itself stays open).
          onDone: () {},
          cancelOnError: false,
        );
  }

  void _onEvent(dynamic payload) {
    final hypothesis = _decode(payload);
    if (hypothesis == null) {
      debugPrint('PlatformAsrEngine: dropped malformed event $payload');
      return;
    }
    if (!_hypotheses.isClosed) _hypotheses.add(hypothesis);
  }

  /// Maps one channel payload to a [Hypothesis], or null when malformed.
  ///
  /// `words` are the recognizer's top alternatives, best first ->
  /// [Hypothesis.wordHypotheses]. `isFinal` is carried on the wire for the
  /// restart loop's benefit but not modelled on [Hypothesis]; partials and
  /// finals alike are forwarded. [Hypothesis.phoneHypotheses] is always null
  /// (the platform recognizer exposes none — Unit 0 spike finding).
  Hypothesis? _decode(dynamic payload) {
    if (payload is! Map) return null;
    final rawWords = payload['words'];
    if (rawWords is! List) return null;
    final words = <String>[
      for (final word in rawWords)
        if (word is String && word.trim().isNotEmpty) word,
    ];
    if (words.isEmpty) return null;
    return Hypothesis(wordHypotheses: words, phoneHypotheses: null);
  }

  void _onEventError(Object error, StackTrace stackTrace) {
    if (error is MissingPluginException) {
      // Host/desktop/test: no native handler. Silent-engine posture — the
      // subscription is dead but the hypothesis stream stays open and empty.
      debugPrint(
        'PlatformAsrEngine: no native ASR handler on this platform; '
        'engine is silent',
      );
      return;
    }
    // An unrecoverable native failure (permission denied, recognizer gone,
    // restart loop exhausted). Log it, then forward as a stream ERROR — not
    // a close — so the tracker's fallback chain owns the policy (it cancels
    // its own subscription and degrades to tap) while the stream stays
    // alive for a later restart.
    debugPrint('PlatformAsrEngine: engine error: $error');
    if (!_hypotheses.isClosed) _hypotheses.addError(error, stackTrace);
  }

  /// Invokes one native method, absorbing the failures that must not
  /// propagate: [MissingPluginException] (non-Android host — behave as a
  /// silent engine) and [PlatformException] (e.g. ENGINE_UNAVAILABLE at
  /// start), which is routed through the same stream-error path as an
  /// event-channel error so the tracker can degrade to tap.
  Future<void> _invoke(String method, [Object? arguments]) async {
    try {
      await _methodChannel.invokeMethod<void>(method, arguments);
    } on MissingPluginException {
      debugPrint(
        'PlatformAsrEngine: "$method" has no native handler on this '
        'platform; engine is silent',
      );
    } on PlatformException catch (error, stackTrace) {
      _onEventError(error, stackTrace);
    }
  }
}

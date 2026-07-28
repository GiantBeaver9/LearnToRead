/// The listening pipeline's runtime (PRD §8 Unit 4, §9 A-7 / A-10 / A-12).
///
/// [ReadingTracker] is the hybrid layer's orchestrator: it opens a
/// consent-gated microphone session, starts an [AsrEngine] biased with the
/// expected sentence words, feeds every finalized hypothesis to the
/// [WordMatcher] (reused, never forked), and turns the matcher's typed
/// results into the single pinned event stream Units 5-6 consume:
///
///   `wordAccepted(index)` · `wordAcceptedNearMiss(index)` ·
///   `struggleDetected(index)` · `silence(duration)` · `wordHelped(index, tier)`
///
/// Everything below the event stream is invisible above it. On-device (A-10),
/// a substituted metered cloud engine, and the tap fallback all produce
/// identically shaped acceptance events, so the reading screen contains no
/// recognition logic and no engine knowledge.
///
/// ## What this unit owns
///
/// - **Expected-text hybridization is always on.** The engine is never
///   started without the sentence words as its biasing context (PRD §6:
///   "never open-ended transcription").
/// - **Struggle detection, both A-12 paths.** (a) `struggleConsecutiveNonMatchingBursts`
///   consecutive finalized bursts that carry speech but fail to match the
///   current word; (b) sustained silence >= `struggleSilenceThreshold` (T1),
///   which emits `Silence(duration: T1)` and then `StruggleDetected(index)`.
///   Both constants come from lib/domain/tuning.dart and are injectable.
/// - **The fallback chain.** Engine failure at start (mic unavailable) or
///   mid-stream, and consent revoked at any moment, degrade to tap mode
///   silently: no error reaches `eventsStream`, the stream never closes or
///   skips a beat, and `isTapMode` flips so the reading screen can reveal its
///   discreet tap affordance.
/// - **The A-7 silent downgrade.** With a metered cloud engine, listening
///   time accrues against a [CloudMinuteCap]; at the cap the tracker stops
///   the metered engine and starts `onDeviceFallbackEngine` with the same
///   biasing context. This is *not* the tap fallback — it is a swap between
///   two real engines, invisible to the child (R2).
/// - **Mic lifecycle.** [isListening] is the design system's listening
///   indicator state. [pause] suspends recognition (narration playing, vocab
///   card open) and [resume] restarts it at the same word with a fresh
///   silence window, so paused time is never counted as silence.
///
/// ## What this unit deliberately does not own
///
/// - Close-enough policy, lookahead and repeats: [WordMatcher] (word-matcher).
/// - Tier 1/2 help, the near-miss prompt, and the T2 wait: the stuck-word
///   scaffold (Unit 6). This tracker only *emits* `struggleDetected` /
///   `wordAcceptedNearMiss`, and accepts [helpCompleted] back from the
///   scaffold when a helped word is finished.
/// - Any UI. See docs/listening-tracker.md for the app-shell wiring, in
///   particular the T1-timer relationship between this unit's
///   [struggleSilenceThreshold] and the scaffold's T2 wait.
///
/// ## No audio, ever
///
/// Nothing here touches a filesystem, a buffer, or a codec: the tracker's
/// whole input surface is `Hypothesis` strings and its whole output surface
/// is `TrackerEvent`. The frozen suite gates this statically over all five
/// tracker sources.
library;

import 'dart:async';
import 'dart:collection';

import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/domain/tuning.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/contracts/tracker_events.dart';
import 'package:learn_to_read/features/listening/matcher/match_result.dart';
import 'package:learn_to_read/features/listening/matcher/word_matcher.dart';
import 'package:learn_to_read/features/listening/tracker/cloud_minute_cap.dart';
import 'package:learn_to_read/features/listening/tracker/mic_session.dart';
import 'package:learn_to_read/features/listening/tracker/silence_detector.dart';
import 'package:learn_to_read/features/listening/tracker/tap_engine.dart';

/// How often metered cloud-engine listening time is accrued against the
/// A-7 cap. Not a tuning-file constant: it is the sampling granularity of an
/// internal timer, not a behavioural threshold (the threshold itself is
/// [CloudMinuteCap.dailyCapMinutes]).
const Duration _cloudUsageTick = Duration(seconds: 1);

/// Safety bound on one eager-drain pass (see [_runEagerly]); anything beyond
/// it is handed back to the normal microtask queue rather than spun on.
const int _maxEagerMicrotasks = 4096;

/// Orchestrates engine + matcher for one sentence read and emits the single
/// pinned tracker event stream.
///
/// ```dart
/// final tracker = ReadingTracker(
///   engine: platformOnDeviceEngine,   // A-10
///   sentence: page.words,
///   micConsent: profile.micConsentGranted,
/// );
/// tracker.eventsStream.listen(readingScreen.apply);
/// tracker.start();
/// ```
class ReadingTracker {
  /// Creates a tracker for one sentence.
  ///
  /// [engine] is the primary recognizer (A-10 on-device by default; any
  /// engine behind the same interface may substitute). [sentence] is the
  /// expected text: its words are both the matcher's targets and the
  /// engine's biasing context. [micConsent] is the profile's current
  /// consent (Unit 10) — read here at construction and again on every
  /// [updateMicConsent].
  ///
  /// [onDeviceFallbackEngine] is used **only** for the A-7 cloud-minute-cap
  /// downgrade, never for the tap fallback chain; [engineIsMetered] together
  /// with [cloudMinuteCap] arms that downgrade.
  ///
  /// [struggleSilenceThreshold] (T1, A-12b) and
  /// [struggleConsecutiveNonMatchingBursts] (A-12a) default to the tuning
  /// file's constants and exist as parameters so pilot tuning stays a
  /// single-file change.
  ReadingTracker({
    required AsrEngine engine,
    required List<WordToken> sentence,
    required bool micConsent,
    AsrEngine? onDeviceFallbackEngine,
    bool engineIsMetered = false,
    CloudMinuteCap? cloudMinuteCap,
    this.struggleSilenceThreshold = kStruggleT1,
    this.struggleConsecutiveNonMatchingBursts =
        kStruggleConsecutiveNonMatchingBursts,
  })  : assert(
          !engineIsMetered || cloudMinuteCap != null,
          'a metered engine requires a CloudMinuteCap to meter it against '
          '(PRD §9 A-7)',
        ),
        _primaryEngine = engine,
        _onDeviceFallbackEngine = onDeviceFallbackEngine,
        _engineIsMetered = engineIsMetered,
        _cloudMinuteCap = cloudMinuteCap,
        _sentence = List<WordToken>.unmodifiable(sentence),
        _biasingContext =
            List<String>.unmodifiable(sentence.map((word) => word.text)),
        _matcher = WordMatcher(sentence: sentence),
        _micSession = MicSession(consentGranted: micConsent) {
    _silence = SilenceDetector(
      threshold: struggleSilenceThreshold,
      onThreshold: _onSilenceThreshold,
    );
  }

  /// T1 (A-12b): sustained silence on the current word at or beyond this
  /// window emits `Silence(duration)` then `StruggleDetected(index)`.
  final Duration struggleSilenceThreshold;

  /// A-12a: how many consecutive finalized bursts carrying speech that fails
  /// to match the current word raise `StruggleDetected`.
  final int struggleConsecutiveNonMatchingBursts;

  final AsrEngine _primaryEngine;
  final AsrEngine? _onDeviceFallbackEngine;
  final CloudMinuteCap? _cloudMinuteCap;
  final List<WordToken> _sentence;
  final List<String> _biasingContext;
  final WordMatcher _matcher;
  final MicSession _micSession;
  final TapEngine _tapEngine = TapEngine();
  final StreamController<TrackerEvent> _events =
      StreamController<TrackerEvent>.broadcast(sync: true);

  late final SilenceDetector _silence;

  bool _engineIsMetered;
  AsrEngine? _activeEngine;
  StreamSubscription<Hypothesis>? _engineSub;
  StreamSubscription<Hypothesis>? _tapSub;
  Timer? _cloudUsageTimer;

  bool _started = false;
  bool _stopped = false;
  bool _paused = false;
  bool _tapMode = false;
  bool _engineFailed = false;
  int _nonMatchingBursts = 0;

  // --- the single public channel -------------------------------------------

  /// The one channel this unit exposes: a broadcast stream of the five pinned
  /// [TrackerEvent] types, in emission order. Completes on [stop] and never
  /// carries an error — every engine failure is absorbed into the fallback
  /// chain instead.
  Stream<TrackerEvent> get eventsStream => _events.stream;

  /// Whether the microphone/ASR is actively open right now.
  ///
  /// This is the design system's listening-indicator state. It is false
  /// before [start], while [pause]d, in tap mode, and after [stop].
  bool get isListening => _micSession.isOpen;

  /// Whether the tracker has degraded to tap-the-word input (engine failure,
  /// mic unavailable, or consent withheld/revoked).
  ///
  /// Tapping works in *every* mode; this flag exists so the reading screen
  /// can surface its discreet tap affordance when tapping is the only input
  /// left.
  bool get isTapMode => _tapMode;

  /// The profile's current microphone consent, as last read (Unit 10).
  bool get micConsent => _micSession.consentGranted;

  // --- lifecycle -----------------------------------------------------------

  /// Starts the session: reads consent, and either starts [engine] with the
  /// sentence words as its biasing context or (no consent / engine failure)
  /// enters tap mode. Idempotent; a no-op after [stop].
  void start() {
    if (_started || _stopped) return;
    _started = true;
    // Tap is always available, in every mode, so the tap engine is wired for
    // the whole session rather than only after a fallback.
    _tapEngine.start(_biasingContext);
    _tapSub = _tapEngine.hypothesesStream.listen(_onHypothesis);
    _beginRecognition();
  }

  /// Suspends recognition (narration playing, vocabulary card open).
  ///
  /// The engine is stopped and the mic session closed, but the matcher and
  /// the current word are untouched, and the silence countdown is disarmed so
  /// paused time is never counted as silence.
  void pause() {
    if (!_started || _stopped || _paused) return;
    _paused = true;
    _silence.stop();
    _stopCloudAccrual();
    _micSession.close();
    if (!_tapMode) _detachEngine(stopEngine: true);
  }

  /// Resumes recognition at the same word: the engine is started again with
  /// the same biasing context and the silence window restarts fresh.
  void resume() {
    if (!_started || _stopped || !_paused) return;
    _paused = false;
    _beginRecognition();
  }

  /// Ends the session: stops the engine, disarms every timer, and completes
  /// [eventsStream]. No event from any source is emitted afterwards, and
  /// [tapCurrentWord] / [helpCompleted] become silent no-ops.
  void stop() {
    if (_stopped) return;
    _stopped = true;
    _silence.stop();
    _stopCloudAccrual();
    _micSession.close();
    _detachEngine(stopEngine: !_tapMode);
    _tapSub?.cancel();
    _tapSub = null;
    _tapEngine.stop();
    if (!_events.isClosed) _events.close();
  }

  // --- manual input --------------------------------------------------------

  /// Accepts the current word by tap — always available, in any mode.
  ///
  /// The tap is pushed through [TapEngine] as an exact-text hypothesis, so it
  /// travels the same matcher path as speech and emits a `WordAccepted` that
  /// is identical in shape to an ASR acceptance. Advances exactly one word;
  /// a silent no-op once the sentence is complete or after [stop].
  void tapCurrentWord() {
    if (!_started || _stopped || _matcher.isComplete) return;
    _tapEngine.tapWord(_sentence[_matcher.currentIndex].text);
  }

  /// Records that the stuck-word scaffold (Unit 6) finished helping the
  /// current word at [tier].
  ///
  /// Emits `WordHelped(index, tier)` and advances exactly one word — the word
  /// turns green like any other (the child is never told they were wrong) and
  /// the help is recorded invisibly downstream. A silent no-op once the
  /// sentence is complete or after [stop].
  void helpCompleted(HelpLevel tier) {
    if (!_started || _stopped || _matcher.isComplete) return;
    final index = _matcher.currentIndex;
    _emit(WordHelped(index: index, tier: tier));
    // Advance the matcher without emitting an acceptance: feeding it the
    // target word's own text is the one input guaranteed to advance exactly
    // one word, and its results are intentionally discarded.
    _matcher.onHypothesis(
      Hypothesis(wordHypotheses: [_sentence[index].text], phoneHypotheses: null),
    );
    _nonMatchingBursts = 0;
    _armSilence();
  }

  /// Applies a consent change immediately (Unit 10).
  ///
  /// Revoking consent mid-session stops the engine and degrades to tap mode
  /// without interrupting [eventsStream]. Granting consent back re-opens the
  /// mic and restarts recognition at the same word, unless the tracker is in
  /// tap mode because the engine itself failed.
  void updateMicConsent(bool consent) {
    if (consent == _micSession.consentGranted) return;
    _micSession.updateConsent(consent);
    if (_stopped || !_started) return;
    if (!consent) {
      _stopCloudAccrual();
      _detachEngine(stopEngine: true);
      _enterTapMode();
      return;
    }
    if (!_paused && _tapMode && !_engineFailed) _beginRecognition();
  }

  // --- recognition plumbing ------------------------------------------------

  void _beginRecognition() {
    if (!_micSession.canOpen) {
      _enterTapMode();
      return;
    }
    final engine = _activeEngine ?? _primaryEngine;
    _activeEngine = engine;
    _tapMode = false;
    _micSession.open();
    _armSilence();
    _startCloudAccrual();
    _attachEngine(engine);
  }

  /// Starts [engine] with the expected-text biasing context and subscribes to
  /// its hypotheses. Any synchronous failure (the mic-unavailable shape: the
  /// stream throws on first access) degrades to tap mode silently.
  void _attachEngine(AsrEngine engine) {
    try {
      engine.start(_biasingContext);
      _runEagerly(() {
        _engineSub = engine.hypothesesStream.listen(
          _onHypothesis,
          onError: (Object error, StackTrace stackTrace) =>
              _handleEngineFailure(engine),
          cancelOnError: true,
        );
      });
    } catch (_) {
      _handleEngineFailure(engine);
    }
  }

  void _detachEngine({required bool stopEngine}) {
    _engineSub?.cancel();
    _engineSub = null;
    if (stopEngine) _activeEngine?.stop();
  }

  /// Engine failure at start or mid-stream: clean the failed engine up and
  /// fall back to tap. The event stream is never errored or closed — from the
  /// child's point of view nothing happened except that the word now waits
  /// for a tap.
  void _handleEngineFailure(AsrEngine engine) {
    _engineFailed = true;
    _stopCloudAccrual();
    _engineSub?.cancel();
    _engineSub = null;
    engine.stop();
    _enterTapMode();
  }

  void _enterTapMode() {
    _tapMode = true;
    _paused = false;
    _micSession.close();
    // The T1 struggle trigger stays armed: a child stuck in tap mode needs
    // the stuck-word scaffold just as much as one stuck with the mic open.
    _armSilence();
  }

  // --- hypothesis routing --------------------------------------------------

  /// Routes one finalized hypothesis burst (from any engine, including a tap)
  /// through the matcher and out as tracker events.
  void _onHypothesis(Hypothesis hypothesis) {
    if (!_started || _stopped) return;
    final results = _matcher.onHypothesis(hypothesis);
    // Empty results are non-speech junk or a repeat of the last accepted
    // word: per A-12a they feed neither the struggle counter nor the silence
    // window.
    if (results.isEmpty) return;
    for (final result in results) {
      _route(result);
    }
    // Any burst that carried real speech content — matching or not — is
    // activity: re-arm the silence window from now.
    _armSilence();
  }

  void _route(MatchResult result) {
    switch (result.kind) {
      case MatchKind.exact:
        _nonMatchingBursts = 0;
        _emit(WordAccepted(index: result.wordIndex));
      case MatchKind.nearMiss:
        _nonMatchingBursts = 0;
        _emit(WordAcceptedNearMiss(index: result.wordIndex));
      case MatchKind.reject:
        // A-12a: rejects emit nothing by themselves; only the run of them
        // matters.
        _nonMatchingBursts += 1;
        if (_nonMatchingBursts >= struggleConsecutiveNonMatchingBursts) {
          _nonMatchingBursts = 0;
          _emit(StruggleDetected(index: result.wordIndex));
        }
    }
  }

  // --- silence / struggle path (b) -----------------------------------------

  /// Arms (or re-arms) the T1 silence window, unless there is nothing left to
  /// be silent about.
  void _armSilence() {
    if (_stopped || _paused || !_started || _matcher.isComplete) {
      _silence.stop();
      return;
    }
    _silence.start();
  }

  void _onSilenceThreshold(Duration duration) {
    if (_stopped || _paused || _matcher.isComplete) return;
    // Order is pinned: the raw silence fact first (Unit 6's T1 trigger), then
    // the struggle it implies (A-12b). Single-shot — the detector re-arms
    // only when the word advances or the tracker resumes.
    _emit(Silence(duration: duration));
    _emit(StruggleDetected(index: _matcher.currentIndex));
  }

  // --- A-7 metered cloud engine --------------------------------------------

  void _startCloudAccrual() {
    if (!_engineIsMetered || _cloudMinuteCap == null) return;
    _cloudUsageTimer?.cancel();
    _cloudUsageTimer = Timer.periodic(_cloudUsageTick, _onCloudUsageTick);
  }

  void _stopCloudAccrual() {
    _cloudUsageTimer?.cancel();
    _cloudUsageTimer = null;
  }

  void _onCloudUsageTick(Timer timer) {
    final cap = _cloudMinuteCap;
    if (!_engineIsMetered || cap == null || _stopped) {
      _stopCloudAccrual();
      return;
    }
    cap.recordUsage(_cloudUsageTick);
    if (cap.isCapReached) _downgradeFromMeteredEngine();
  }

  /// A-7 / R2: the daily cloud-minute cap is reached. Swap the metered engine
  /// for the on-device one, same biasing context, no user-visible
  /// interruption — this is an engine swap, not the tap fallback.
  void _downgradeFromMeteredEngine() {
    _stopCloudAccrual();
    _engineIsMetered = false;
    _detachEngine(stopEngine: true);
    final onDevice = _onDeviceFallbackEngine;
    if (onDevice == null) {
      // Nothing to downgrade to: tap is the last link of the chain.
      _enterTapMode();
      return;
    }
    _activeEngine = onDevice;
    _attachEngine(onDevice);
  }

  // --- emission ------------------------------------------------------------

  void _emit(TrackerEvent event) {
    if (_stopped || _events.isClosed) return;
    _events.add(event);
  }

  // --- eager engine drain --------------------------------------------------
  //
  // Acceptance pins that "engine choice is invisible above this interface":
  // the same scripted read must produce the same events whether it arrives by
  // tap (synchronous) or from an engine. Engines whose hypothesis stream is
  // generated at subscription time would otherwise only deliver on a later
  // microtask, making the ASR path observably later than the tap path.
  //
  // So the subscription is created inside a forked zone that, for the
  // duration of the subscribe call, collects scheduled microtasks into a
  // local queue which is then drained in place. Outside that window the zone
  // delegates to its parent unchanged, so ordinary asynchronous engines
  // (platform channels, broadcast controllers) behave exactly as before and
  // fake_async still owns the clock.

  final Queue<void Function()> _eagerQueue = Queue<void Function()>();
  bool _draining = false;
  Zone? _eagerZone;

  Zone get _engineZone => _eagerZone ??= Zone.current.fork(
        specification: ZoneSpecification(
          scheduleMicrotask: (self, parent, zone, task) {
            if (_draining) {
              _eagerQueue.add(task);
            } else {
              parent.scheduleMicrotask(zone, task);
            }
          },
        ),
      );

  void _runEagerly(void Function() body) {
    final zone = _engineZone;
    final wasDraining = _draining;
    _draining = true;
    try {
      zone.run(body);
      if (wasDraining) return;
      var drained = 0;
      while (_eagerQueue.isNotEmpty && drained < _maxEagerMicrotasks) {
        drained += 1;
        zone.run(_eagerQueue.removeFirst());
      }
    } finally {
      if (!wasDraining) {
        _draining = false;
        while (_eagerQueue.isNotEmpty) {
          scheduleMicrotask(_eagerQueue.removeFirst());
        }
      }
    }
  }
}

/// A lightweight engine+scorer loop for one Sound Garden echo attempt (PRD
/// §8 Unit 15 "a gentle prompt invites the child to say it back, scored
/// with sound-level matching"; §8 Unit 4 sound mode; §9 A-13; ticket
/// sound-garden accept entry 4).
///
/// [EchoSession] wires exactly one [AsrEngine] to exactly one
/// [SoundModeScorer] for one attempt. Ticket note: "do NOT pull in
/// listening-tracker (no words, no silence/struggle/tap semantics here)" --
/// there is deliberately no notion of a word, a silence timer, a struggle
/// counter, or a tap fallback anywhere in this file.
library;

import 'dart:async';

import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/matcher/sound_mode_scorer.dart';

/// The outcome of one echo attempt, snapshotted at [EchoSession.stop].
class EchoResult {
  const EchoResult({required this.matched, required this.matchedFraction});

  /// Whether the scorer's A-13 threshold was reached at any point during
  /// the attempt.
  final bool matched;

  /// The scorer's weighted matched fraction at the moment [EchoSession.stop]
  /// was called.
  final double matchedFraction;
}

/// Drives one echo attempt end to end: starts [engine] with [biasingContext],
/// feeds every finalized hypothesis to [scorer], and reports the first
/// moment the scorer's A-13 threshold is crossed.
class EchoSession {
  EchoSession({
    required this.engine,
    required this.scorer,
    this.biasingContext = const [],
  });

  /// The ASR engine this session drives (started once, stopped once).
  final AsrEngine engine;

  /// The sound-mode scorer this session feeds every hypothesis to. Its
  /// configuration (threshold, per-phoneme distance, drilled-phoneme
  /// weight) is entirely the caller's choice -- this session never inspects
  /// or overrides it, which is how "asserted via matcher config injection"
  /// (ticket accept entry 4) holds: whatever [scorer] this session is given
  /// is exactly the scoring rule its hypotheses are run through.
  final SoundModeScorer scorer;

  /// Forwarded verbatim to `engine.start`. Sound mode has no expected-text
  /// hybridization concept (that is word-mode's, PRD §6), so this is
  /// whatever context the caller wants to bias the engine with, defaulting
  /// to none.
  final List<String> biasingContext;

  StreamSubscription<Hypothesis>? _subscription;
  bool _isListening = false;
  bool _matchFired = false;
  EchoResult? _result;

  /// True from [start] until [stop].
  bool get isListening => _isListening;

  /// Mirrors `scorer.accepted` -- monotone, never reverts to false once
  /// true.
  bool get matched => scorer.accepted;

  /// Mirrors `scorer.matchedFraction`.
  double get matchedFraction => scorer.matchedFraction;

  /// Starts the attempt: calls `engine.start(biasingContext)`, then
  /// subscribes to `engine.hypothesesStream`, feeding every hypothesis to
  /// `scorer.onHypothesis`. The first time `scorer.accepted` flips from
  /// false to true, [onMatch] fires exactly once -- never again for this
  /// session, even if more hypotheses arrive afterward.
  void start({void Function()? onMatch}) {
    engine.start(biasingContext);
    _isListening = true;
    _subscription = engine.hypothesesStream.listen((hypothesis) {
      final wasAccepted = scorer.accepted;
      scorer.onHypothesis(hypothesis);
      if (!wasAccepted && scorer.accepted && !_matchFired) {
        _matchFired = true;
        onMatch?.call();
      }
    });
  }

  /// Cancels the hypothesis subscription, calls `engine.stop()`, flips
  /// [isListening] false, and returns the final [EchoResult]. Idempotent:
  /// calling [stop] again is a safe no-op that returns the same result
  /// without touching `engine.stop()` a second time.
  EchoResult stop() {
    final existing = _result;
    if (existing != null) {
      return existing;
    }
    _subscription?.cancel();
    _subscription = null;
    engine.stop();
    _isListening = false;
    final result = EchoResult(matched: scorer.accepted, matchedFraction: scorer.matchedFraction);
    _result = result;
    return result;
  }
}

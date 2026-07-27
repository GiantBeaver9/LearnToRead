/// Sound-mode scorer (PRD §8 Unit 14, §8 Unit 4 sound mode, §9 A-13;
/// ticket word-matcher).
///
/// Sound mode listens for the SOUNDS, not word identity: the tongue-twister
/// or Sound Garden echo target is a phoneme sequence, and producing the
/// sounds advances the score even where word recognition would fail.
/// Serves both twister flow (Unit 14) and Sound Garden echo (Unit 15).
///
/// Pinned scoring formula (A-13; weight in numerator AND denominator, so
/// double-weighting can flip the verdict in both directions):
///
///     matchedFraction = sum(weight_i for matched positions i)
///                     / sum(weight_i for all positions i)
///
/// where `weight_i` = [targetPhonemeWeight] when the sequence position holds
/// the drilled [targetPhonemeId], else 1; a position counts as matched when
/// a produced phoneme aligns to it within [perPhonemeMaxDistance]. Accepted
/// when `matchedFraction >= matchThreshold` (inclusive). Defaults come from
/// lib/domain/tuning.dart (A-13: 0.60 / distance 1 / weight 2) — never
/// hardcoded here.
///
/// Alignment is greedy in-order (orchestrator-pinned default 6): each burst
/// is walked left-to-right, each produced phoneme claiming the first still-
/// unmatched target position at or after the previous claim that lies
/// within [perPhonemeMaxDistance]; productions that fit nowhere (out of
/// order, or the sequence is already fully matched) are ignored WITHOUT
/// penalty — sound mode never punishes extra or disordered sounds, it only
/// credits covered ones. Matched positions persist across bursts
/// (incremental tracking), so the fraction is monotone and never exceeds
/// 1.0.
///
/// The inter-phoneme distance is uniform (pinned default 1): identical ids
/// are distance 0, differing ids distance 1. With the default
/// [perPhonemeMaxDistance] of 1 any in-order production therefore covers
/// positions one-for-one; omissions are never matched. Tightening the
/// tunable to 0 restricts matching to exact phoneme identity.
///
/// Where the engine exposes no phone-level detail (`phoneHypotheses` null),
/// the scorer approximates by scoring the comparison G2P of the top word
/// hypothesis against the sequence (both paths are contract-tested). A
/// non-null-but-empty phone list means "phones supported, nothing heard"
/// and contributes nothing — it does not fall back to the word path.
library;

import 'package:learn_to_read/domain/tuning.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/matcher/grapheme_to_phoneme.dart';

/// Uniform inter-phoneme distance (orchestrator-pinned default 1).
int _perPhonemeDistance(String a, String b) => a == b ? 0 : 1;

/// Incremental scorer for one sound-mode attempt (one twister run or one
/// Sound Garden echo). Feed every finalized [Hypothesis] to [onHypothesis];
/// read [matchedFraction] / [accepted] at any point.
class SoundModeScorer {
  /// Creates a scorer for [targetPhonemeSequence] drilling [targetPhonemeId].
  /// Threshold parameters default to the A-13 constants in
  /// lib/domain/tuning.dart; inject overrides only for tests or pilot
  /// experiments.
  SoundModeScorer({
    required List<String> targetPhonemeSequence,
    required this.targetPhonemeId,
    this.matchThreshold = kSoundModeMatchThreshold,
    this.perPhonemeMaxDistance = kSoundModePerPhonemeMaxDistance,
    this.targetPhonemeWeight = kSoundModeTargetPhonemeWeight,
  }) : _sequence = List.unmodifiable(targetPhonemeSequence),
       _matched = List<bool>.filled(targetPhonemeSequence.length, false);

  /// The full phoneme sequence of the twister/card being echoed.
  final List<String> _sequence;

  /// The drilled phoneme; its instances in the sequence weigh
  /// [targetPhonemeWeight] instead of 1.
  final String targetPhonemeId;

  /// Minimum weighted fraction for acceptance (inclusive `>=`).
  final double matchThreshold;

  /// Max per-phoneme distance for a produced phoneme to claim a position.
  final int perPhonemeMaxDistance;

  /// Weight of drilled-phoneme positions in numerator and denominator.
  final int targetPhonemeWeight;

  /// Which sequence positions have been matched so far (persists across
  /// bursts).
  final List<bool> _matched;

  int _weightOf(int position) =>
      _sequence[position] == targetPhonemeId ? targetPhonemeWeight : 1;

  /// Weighted fraction of the target sequence matched so far, in
  /// [0.0, 1.0]. 0.0 for silence; for the degenerate empty sequence there
  /// is nothing to credit, so the fraction is 0.0 (never accepts).
  double get matchedFraction {
    var total = 0;
    var matched = 0;
    for (var i = 0; i < _sequence.length; i++) {
      final w = _weightOf(i);
      total += w;
      if (_matched[i]) matched += w;
    }
    if (total == 0) return 0.0;
    return matched / total;
  }

  /// True when [matchedFraction] has reached [matchThreshold] (inclusive).
  /// Monotone: once accepted, later bursts never revoke it.
  bool get accepted => matchedFraction >= matchThreshold;

  /// Consumes one finalized hypothesis burst, crediting newly covered
  /// sequence positions (greedy in-order; see library doc). Degenerate
  /// hypotheses (no words and no phones, or an empty phone list) are
  /// no-ops and never throw.
  void onHypothesis(Hypothesis h) {
    final produced = _producedPhonemes(h);
    var scan = 0; // each burst may re-attempt from the top of the sequence
    for (final phoneme in produced) {
      for (var i = scan; i < _sequence.length; i++) {
        if (_matched[i]) continue;
        if (_perPhonemeDistance(phoneme, _sequence[i]) <=
            perPhonemeMaxDistance) {
          _matched[i] = true;
          scan = i + 1;
          break;
        }
      }
      // No claimable position: the production is ignored without penalty
      // (pinned default 6 — out-of-order/extra sounds are non-events).
    }
  }

  /// The phoneme sequence this burst produced: engine phones when the
  /// engine surfaced them (even an empty list — that is "nothing heard",
  /// not "no phone support"), else the comparison-G2P approximation of the
  /// top word hypothesis (whitespace-split, pinned default 7).
  List<String> _producedPhonemes(Hypothesis h) {
    final phones = h.phoneHypotheses;
    if (phones != null) return phones;
    if (h.wordHypotheses.isEmpty) return const [];
    return [
      for (final token in h.wordHypotheses.first.split(RegExp(r'\s+')))
        ...graphemesToPhonemes(token),
    ];
  }
}

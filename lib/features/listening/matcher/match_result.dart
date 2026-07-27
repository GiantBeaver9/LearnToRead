/// Typed match outcomes for the hybrid matching layer (PRD §8 Unit 4,
/// ticket word-matcher).
///
/// The matcher classifies every scored hypothesis burst into one of three
/// grades. The two acceptance grades are deliberately distinguishable
/// (§5 analytics: `word_read` correct vs near_miss; tracker events
/// `wordAccepted` vs `wordAcceptedNearMiss`) — they must never collapse.
library;

/// The grade of a scored hypothesis against a target word.
enum MatchKind {
  /// The hypothesis is the target word: textually equal after case and
  /// punctuation normalization, or phonetically identical (distance 0 —
  /// homophones grade as exact, orchestrator-pinned default 3).
  exact,

  /// Phonetically close enough per the Unit 4 policy ("gat" for "cat"):
  /// phoneme edit distance within the tuning threshold but not zero.
  /// Accepted — the word advances — but flagged so Unit 6 can run the
  /// near-miss prompt path and analytics record the distinction.
  nearMiss,

  /// Neither the target nor close enough (nor the lookahead-1 next word,
  /// nor a repeat of the most recently accepted word). The word does not
  /// advance; the failed distance feeds struggle detection in the tracker.
  reject,
}

/// One classified outcome for one sentence word, produced by
/// `WordMatcher.onHypothesis`. A single hypothesis burst may yield zero
/// results (non-speech junk, repeats), one (plain accept/reject), or two
/// (lookahead back-fill: current word confirmed, next word accepted).
class MatchResult {
  /// Creates a match result. [phonemeDistance] is 0 for a textual exact
  /// match, the measured distance for a near-miss, and the failed distance
  /// for a reject; it is null only where no distance is meaningful (a
  /// lookahead back-filled word that had no hypothesis of its own).
  const MatchResult({
    required this.kind,
    required this.wordIndex,
    this.phonemeDistance,
  });

  /// The grade of this outcome.
  final MatchKind kind;

  /// Index of the sentence word this result is about.
  final int wordIndex;

  /// Phoneme edit distance backing the grade (see constructor doc); null
  /// for back-filled words that were never directly heard.
  final int? phonemeDistance;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MatchResult &&
          other.kind == kind &&
          other.wordIndex == wordIndex &&
          other.phonemeDistance == phonemeDistance);

  @override
  int get hashCode => Object.hash(kind, wordIndex, phonemeDistance);

  @override
  String toString() =>
      'MatchResult('
      'kind: $kind, wordIndex: $wordIndex, phonemeDistance: $phonemeDistance)';
}

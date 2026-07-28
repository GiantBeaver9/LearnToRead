/// Phoneme-level edit distance (PRD §8 Unit 4).
///
/// The pinned closeness metric behind the Unit 4 match policy: a standard
/// Levenshtein edit distance over phoneme-id sequences. Per the
/// orchestrator-pinned default (1), the inter-phoneme distance is uniform —
/// any substitution, insertion, or deletion costs exactly 1; there is no
/// confusability weighting between phoneme pairs. The distance is symmetric,
/// zero iff the sequences are equal, at least the length difference, and at
/// most the longer sequence's length.
library;

/// Returns the Levenshtein edit distance between two phoneme-id sequences.
///
/// Unit cost for substitution, insertion, and deletion. Phoneme ids are
/// compared as opaque strings ('G' vs 'K' costs 1, exactly like any other
/// differing pair). Examples: `[G,AE,T]` vs `[K,AE,T]` is 1 (the canonical
/// "gat"/"cat" near-miss); `[D,AO,G]` vs `[K,AE,T]` is 3 (the canonical
/// "dog"/"cat" reject).
int phonemeEditDistance(List<String> a, List<String> b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;

  // Two-row dynamic program: prev[j] = distance(a[0..i-1], b[0..j-1]).
  var prev = List<int>.generate(b.length + 1, (j) => j);
  var curr = List<int>.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    curr[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final substitutionCost = a[i - 1] == b[j - 1] ? 0 : 1;
      var best = prev[j - 1] + substitutionCost; // substitute (or keep)
      final deletion = prev[j] + 1;
      if (deletion < best) best = deletion;
      final insertion = curr[j - 1] + 1;
      if (insertion < best) best = insertion;
      curr[j] = best;
    }
    final swap = prev;
    prev = curr;
    curr = swap;
  }
  return prev[b.length];
}

/// A-18 (KidSpeak-informed, ratified — PRD §9 A-18): the confusability-
/// weighted substitution-cost table layered on top of the uniform
/// [phonemeEditDistance] metric via [phonemeEditDistanceWeighted].
///
/// Standard ASR is documented to hallucinate fluent-but-wrong text on
/// children's speech; this table lets substitutions along documented
/// child-speech / child-ASR confusion axes cost 0.5 instead of 1, so
/// acceptance widens exactly along the axes children and child-ASR
/// actually confuse and nowhere else. Every entry is an (unordered)
/// phoneme-id pair — lookup is symmetric, both orientations match — drawn
/// from [kEnglishPhonemeIds], costed at exactly 0.5. The 15 pairs span 6
/// axes:
///   - Gliding: R/L -> W.
///   - Stopping: TH -> D/T, DH -> D.
///   - Th-fronting: TH -> F, DH -> V.
///   - Velar fronting: K -> T, G -> D.
///   - Voicing pairs: P/B, T/D, K/G, F/V, S/Z.
///   - Labial/fricative acoustic confusion: W <-> F.
const List<(String, String, double)> kConfusablePhonemePairs = [
  // Gliding.
  ('R', 'W', 0.5),
  ('L', 'W', 0.5),
  // Stopping.
  ('TH', 'D', 0.5),
  ('TH', 'T', 0.5),
  ('DH', 'D', 0.5),
  // Th-fronting.
  ('TH', 'F', 0.5),
  ('DH', 'V', 0.5),
  // Velar fronting.
  ('K', 'T', 0.5),
  ('G', 'D', 0.5),
  // Voicing pairs.
  ('P', 'B', 0.5),
  ('T', 'D', 0.5),
  ('K', 'G', 0.5),
  ('F', 'V', 0.5),
  ('S', 'Z', 0.5),
  // Labial/fricative acoustic confusion.
  ('W', 'F', 0.5),
];

/// Looks up the A-18 substitution cost for differing phoneme ids [x] and
/// [y] (symmetric — checks both orientations against
/// [kConfusablePhonemePairs]); 0.5 when the unordered pair is listed, else
/// the unweighted default of 1.
double _substitutionCost(String x, String y) {
  for (final (a, b, cost) in kConfusablePhonemePairs) {
    if ((a == x && b == y) || (a == y && b == x)) return cost;
  }
  return 1;
}

/// Returns the A-18 confusability-weighted edit distance between two
/// phoneme-id sequences.
///
/// Same Levenshtein shape as [phonemeEditDistance] — unit cost for
/// insertion/deletion, 0 for identity — except the substitution cost for a
/// differing pair is 0.5 when that unordered pair appears in
/// [kConfusablePhonemePairs], else 1 (unchanged). Symmetric, zero iff the
/// sequences are equal, and never greater than [phonemeEditDistance] on the
/// same inputs — confusable substitutions only ever reduce cost.
double phonemeEditDistanceWeighted(List<String> a, List<String> b) {
  if (a.isEmpty) return b.length.toDouble();
  if (b.isEmpty) return a.length.toDouble();

  // Two-row dynamic program: prev[j] = distance(a[0..i-1], b[0..j-1]).
  var prev = List<double>.generate(b.length + 1, (j) => j.toDouble());
  var curr = List<double>.filled(b.length + 1, 0);

  for (var i = 1; i <= a.length; i++) {
    curr[0] = i.toDouble();
    for (var j = 1; j <= b.length; j++) {
      final substitutionCost =
          a[i - 1] == b[j - 1] ? 0.0 : _substitutionCost(a[i - 1], b[j - 1]);
      var best = prev[j - 1] + substitutionCost; // substitute (or keep)
      final deletion = prev[j] + 1;
      if (deletion < best) best = deletion;
      final insertion = curr[j - 1] + 1;
      if (insertion < best) best = insertion;
      curr[j] = best;
    }
    final swap = prev;
    prev = curr;
    curr = swap;
  }
  return prev[b.length];
}

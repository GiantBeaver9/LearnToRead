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

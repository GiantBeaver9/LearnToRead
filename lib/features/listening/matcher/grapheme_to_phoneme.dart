/// Matcher-internal comparison grapheme-to-phoneme (ticket word-matcher).
///
/// The Unit 4 match policy pins phoneme-level edit distance, but hypothesis
/// words arrive from the engine as text and an arbitrary out-of-vocabulary
/// hypothesis like "gat" has no authored `graphemePhonemeMap`. This tiny
/// deterministic G2P exists ONLY so such hypotheses can be phonetically
/// compared against an authored target; it is never applied to target words
/// (closeness is always measured against the AUTHORED map) and it is not a
/// linguistics project.
///
/// Scope and limits (documented per ticket):
/// - Letterwise-regular decoding: one phoneme per letter, plus a small set
///   of common consonant digraphs (sh, ch, th, ng, ck) decoded greedily
///   left-to-right. 'x' expands to K,S.
/// - Vowels always map to their short/lax sound (a→AE, e→EH, i→IH, o→AO,
///   u→AH). No silent-e, vowel teams, r-controlled vowels, stress, or
///   context sensitivity of any kind.
/// - Total and deterministic: any input string is accepted; characters
///   outside a–z (after lowercasing) are ignored; empty or all-punctuation
///   input yields an empty sequence; the same input always yields the same
///   output.
/// - Output is drawn exclusively from `kEnglishPhonemeIds` (the pinned 44
///   phoneme inventory in lib/domain/models/content_models.dart).
///
/// This is adequate for the matcher's job — scoring short, letterwise-
/// regular child productions near a known target — and deliberately nothing
/// more.
library;

/// Greedily-decoded multi-letter graphemes, checked before single letters.
/// Kept deliberately small; see the library doc for limits.
const Map<String, List<String>> _digraphs = {
  'sh': ['SH'],
  'ch': ['CH'],
  'th': ['TH'],
  'ng': ['NG'],
  'ck': ['K'],
};

/// One-phoneme-per-letter fallback map (letterwise-regular decoding).
const Map<String, List<String>> _letters = {
  'a': ['AE'],
  'b': ['B'],
  'c': ['K'],
  'd': ['D'],
  'e': ['EH'],
  'f': ['F'],
  'g': ['G'],
  'h': ['HH'],
  'i': ['IH'],
  'j': ['JH'],
  'k': ['K'],
  'l': ['L'],
  'm': ['M'],
  'n': ['N'],
  'o': ['AO'],
  'p': ['P'],
  'q': ['K'],
  'r': ['R'],
  's': ['S'],
  't': ['T'],
  'u': ['AH'],
  'v': ['V'],
  'w': ['W'],
  'x': ['K', 'S'],
  'y': ['Y'],
  'z': ['Z'],
};

/// Converts an arbitrary hypothesis word to a comparison phoneme sequence.
///
/// Deterministic and total: never throws, ignores non-letter characters,
/// returns an empty list for input with no letters. Every emitted id is a
/// member of `kEnglishPhonemeIds`. Example: `'gat'` → `['G', 'AE', 'T']`
/// (phoneme distance 1 from the authored "cat" — the PRD's canonical
/// near-miss).
List<String> graphemesToPhonemes(String word) {
  final normalized = word.toLowerCase();
  final phonemes = <String>[];
  var i = 0;
  while (i < normalized.length) {
    if (i + 1 < normalized.length) {
      final pair = normalized.substring(i, i + 2);
      final digraph = _digraphs[pair];
      if (digraph != null) {
        phonemes.addAll(digraph);
        i += 2;
        continue;
      }
    }
    final single = _letters[normalized[i]];
    if (single != null) phonemes.addAll(single);
    i += 1; // non-letters (digits, punctuation) are skipped silently
  }
  return phonemes;
}

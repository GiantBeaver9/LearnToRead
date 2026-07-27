/// Contract tests for the A-18 confusability-weighted phoneme cost table
/// (PRD §9 A-18, ratified). This suite IS the A-18 acceptance-widening
/// specification for the word-matcher unit.
///
/// A-18 (KidSpeak-informed): standard ASR hallucinates fluent-but-wrong text
/// on children's speech, so the phoneme-distance metric gains a
/// confusability-weighted cost table (tunable): substitutions along
/// documented child-speech / child-ASR confusion axes cost 0.5 instead of 1
/// — gliding (R/L → W), stopping (TH → D/T, DH → D), th-fronting
/// (TH → F, DH → V), velar fronting (K → T, G → D), voicing pairs
/// (P/B, T/D, K/G, F/V, S/Z), and labial/fricative acoustic confusion
/// (W ↔ F, e.g. "while" heard as "file"). All other costs and thresholds
/// are unchanged.
///
/// Pinned API additions (implementation does not exist yet — this whole
/// file must fail red-for-right-reason: undefined symbols
/// `kConfusablePhonemePairs`, `phonemeEditDistanceWeighted`, and the
/// `WordMatcher.phonemeDistanceFn` constructor parameter). The 91 tests in
/// the 5 existing matcher suite files (lookahead_test.dart,
/// phoneme_distance_test.dart, self_correction_test.dart,
/// sound_mode_scorer_test.dart, word_matcher_test.dart) are untouched and
/// must stay green — nothing below edits or re-imports their private
/// fixtures.
///
///   - lib/features/listening/matcher/phoneme_distance.dart (ADDITIONS
///     only; the existing `phonemeEditDistance` — the frozen uniform
///     Levenshtein metric behind the canonical gat/cat=1, dog/cat=3 anchors
///     — is untouched):
///       `const List<(String, String, double)> kConfusablePhonemePairs`
///         The A-18 table: each record is an (unordered) phoneme-id pair
///         and its substitution cost. Every listed pair costs exactly 0.5;
///         lookup is symmetric (a pair matches regardless of which side is
///         `a` and which is `b`). Every phoneme id used is a member of
///         `kEnglishPhonemeIds`. Documents the 15 pairs across the 6 A-18
///         axes: gliding {R,W} {L,W}; stopping {TH,D} {TH,T} {DH,D};
///         th-fronting {TH,F} {DH,V}; velar fronting {K,T} {G,D}; voicing
///         {P,B} {T,D} {K,G} {F,V} {S,Z}; labial/fricative {W,F}.
///       `double phonemeEditDistanceWeighted(List<String> a, List<String> b)`
///         Same Levenshtein shape as `phonemeEditDistance` (unit cost for
///         insertion/deletion, 0 for identity) EXCEPT the substitution cost
///         for a differing pair is 0.5 when that unordered pair appears in
///         `kConfusablePhonemePairs`, else 1 (unchanged). Symmetric, zero
///         iff the sequences are equal, and never greater than
///         `phonemeEditDistance` on the same inputs (confusable
///         substitutions only ever reduce cost).
///
///   - lib/features/listening/matcher/word_matcher.dart (ADDITIONS only):
///       `WordMatcher` gains one new optional named constructor parameter:
///         `num Function(List<String> a, List<String> b) phonemeDistanceFn`
///       defaulting to `phonemeEditDistance` (the existing uniform metric),
///       used internally by `_score` in place of the hardcoded call. Every
///       existing call site (all 91 frozen tests) omits this parameter, so
///       its behavior is byte-for-byte unchanged. Passing
///       `phonemeEditDistanceWeighted` switches ONLY the word-mode
///       ACCEPTANCE path (near-miss/reject grading) to A-18 weighted costs;
///       `MatchKind` classification rules, thresholds, and every other
///       matcher policy are unaffected.
///
/// CONFLICT NOTE (resolved by construction, see the "gat/cat conflict
/// guard" test below): A-18's voicing-pair axis includes K/G. The frozen
/// `phoneme_distance_test.dart` pins the canonical `phonemeEditDistance`
/// (uniform) gat/cat distance at exactly 1 — that anchor must not move. It
/// doesn't: `phonemeEditDistance` is untouched (no confusability weighting
/// exists in that function at all), and A-18 lands entirely in the new,
/// separate `phonemeEditDistanceWeighted` function plus an opt-in
/// `WordMatcher` parameter. Under the NEW weighted function, gat/cat's
/// distance becomes 0.5 (G/K is a voicing pair) instead of 1 — a different
/// number — but the ACCEPTANCE OUTCOME is unchanged: 0.5 is still within
/// the short-word threshold (1), so "gat" is still a near-miss of "cat"
/// either way. Nothing here ever asserts `phonemeEditDistance(gat, cat) !=
/// 1`; the frozen anchor is read verbatim (imported, not reimplemented) and
/// re-affirmed unmoved.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/tuning.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/matcher/match_result.dart';
import 'package:learn_to_read/features/listening/matcher/phoneme_distance.dart';
import 'package:learn_to_read/features/listening/matcher/word_matcher.dart';

/// Every A-18-documented confusion axis, as (a, b) pairs. Order within a
/// pair is arbitrary — lookup against `kConfusablePhonemePairs` must be
/// symmetric, so tests below check both orientations.
const List<(String, String)> _a18AxisPairs = [
  // Gliding: R/L -> W.
  ('R', 'W'),
  ('L', 'W'),
  // Stopping: TH -> D/T, DH -> D.
  ('TH', 'D'),
  ('TH', 'T'),
  ('DH', 'D'),
  // Th-fronting: TH -> F, DH -> V.
  ('TH', 'F'),
  ('DH', 'V'),
  // Velar fronting: K -> T, G -> D.
  ('K', 'T'),
  ('G', 'D'),
  // Voicing pairs.
  ('P', 'B'),
  ('T', 'D'),
  ('K', 'G'),
  ('F', 'V'),
  ('S', 'Z'),
  // Labial/fricative acoustic confusion: W <-> F ("while" heard as "file").
  ('W', 'F'),
];

/// Looks up the confusion cost between [x] and [y] in
/// [kConfusablePhonemePairs], checking both orientations (the table is
/// consulted symmetrically). Returns null if the pair is not listed.
double? _confusionCost(String x, String y) {
  for (final (a, b, cost) in kConfusablePhonemePairs) {
    if ((a == x && b == y) || (a == y && b == x)) return cost;
  }
  return null;
}

WordToken _tok(String text, List<({String graphemes, String phonemeId})> map) =>
    WordToken(
      text: text,
      graphemePhonemeMap: map,
      pronunciationAudioRef: 'audio/$text.mp3',
    );

/// 'cat' = K,AE,T (3 phonemes, short word) — local fixture, independent of
/// word_matcher_test.dart's private `_cat`.
WordToken get _cat => _tok('cat', [
      (graphemes: 'c', phonemeId: 'K'),
      (graphemes: 'a', phonemeId: 'AE'),
      (graphemes: 't', phonemeId: 'T'),
    ]);

/// 'while' = W,AY,L (3 phonemes, short word) — authored map uses digraph
/// units 'wh' and 'le', same convention as word_matcher_test.dart's `_said`
/// fixture (the authored map is hand-built, independent of the crude
/// letterwise G2P used for un-authored hypothesis text).
WordToken get _while => _tok('while', [
      (graphemes: 'wh', phonemeId: 'W'),
      (graphemes: 'i', phonemeId: 'AY'),
      (graphemes: 'le', phonemeId: 'L'),
    ]);

/// 'cap' = K,AE,P (3 phonemes, short word).
WordToken get _cap => _tok('cap', [
      (graphemes: 'c', phonemeId: 'K'),
      (graphemes: 'a', phonemeId: 'AE'),
      (graphemes: 'p', phonemeId: 'P'),
    ]);

Hypothesis _word(String w, {List<String>? phones}) =>
    Hypothesis(wordHypotheses: [w], phoneHypotheses: phones);

void main() {
  group('fixture premise — pinned tuning defaults unchanged by A-18', () {
    test('POSITIVE: word-mode tuning constants hold their pinned values '
        '(A-18 touches costs only, never thresholds)', () {
      expect(kWordModeShortWordMaxPhonemes, 4);
      expect(kWordModeMaxSubstitutedPhonemesShortWord, 1);
      expect(kWordModeMaxSubstitutedPhonemesLongWord, 2);
    });
  });

  group('kConfusablePhonemePairs — A-18 table completeness', () {
    test('POSITIVE: every documented A-18 axis pair is present, costed at '
        '0.5', () {
      for (final (a, b) in _a18AxisPairs) {
        final cost = _confusionCost(a, b);
        expect(
          cost,
          0.5,
          reason: 'A-18 axis pair ($a, $b) must be in kConfusablePhonemePairs '
              'at cost 0.5',
        );
      }
    });

    test('EDGE: lookup is symmetric — every axis pair is found in either '
        'orientation', () {
      for (final (a, b) in _a18AxisPairs) {
        expect(
          _confusionCost(a, b),
          _confusionCost(b, a),
          reason: 'confusion cost for ($a, $b) must equal cost for ($b, $a)',
        );
      }
    });

    test('POSITIVE: every phoneme id in the table is one of the pinned 44 '
        'English phonemes', () {
      for (final (a, b, _) in kConfusablePhonemePairs) {
        expect(
          kEnglishPhonemeIds.contains(a),
          isTrue,
          reason: '$a must be a member of kEnglishPhonemeIds',
        );
        expect(
          kEnglishPhonemeIds.contains(b),
          isTrue,
          reason: '$b must be a member of kEnglishPhonemeIds',
        );
      }
    });

    test('POSITIVE: every table entry costs exactly 0.5 (A-18 pins one '
        'discount, not a graded scale)', () {
      for (final (_, __, cost) in kConfusablePhonemePairs) {
        expect(cost, 0.5);
      }
    });

    test('NEGATIVE: an arbitrary non-confusable pair is absent from the '
        'table', () {
      expect(_confusionCost('M', 'ZH'), isNull);
      expect(_confusionCost('AA', 'IY'), isNull,
          reason: 'A-18 axes are consonant substitutions only — no vowel '
              'pair is listed');
    });
  });

  group('phonemeEditDistanceWeighted — weighted math on canonical A-18 '
      'pairs', () {
    test('POSITIVE: identical sequences still have distance 0', () {
      expect(phonemeEditDistanceWeighted(['K', 'AE', 'T'], ['K', 'AE', 'T']),
          0);
    });

    test('POSITIVE: "while" vs "file" — W/F labial-fricative confusion — '
        'costs 0.5 (W,AY,L vs F,AY,L)', () {
      expect(
        phonemeEditDistanceWeighted(['W', 'AY', 'L'], ['F', 'AY', 'L']),
        0.5,
      );
    });

    test('POSITIVE: "rail" vs "wail" — R/W gliding — costs 0.5 '
        '(R,EY,L vs W,EY,L)', () {
      expect(
        phonemeEditDistanceWeighted(['R', 'EY', 'L'], ['W', 'EY', 'L']),
        0.5,
      );
    });

    test('POSITIVE: "thin" vs "fin" — TH/F th-fronting — costs 0.5 '
        '(TH,IH,N vs F,IH,N)', () {
      expect(
        phonemeEditDistanceWeighted(['TH', 'IH', 'N'], ['F', 'IH', 'N']),
        0.5,
      );
    });

    test('POSITIVE: "pat" vs "bat" — P/B voicing — costs 0.5 '
        '(P,AE,T vs B,AE,T)', () {
      expect(
        phonemeEditDistanceWeighted(['P', 'AE', 'T'], ['B', 'AE', 'T']),
        0.5,
      );
    });

    test('POSITIVE: two confusable substitutions accumulate to 1.0 — '
        '"cap" vs "tab" (K/T velar fronting + P/B voicing)', () {
      expect(
        phonemeEditDistanceWeighted(['K', 'AE', 'P'], ['T', 'AE', 'B']),
        1.0,
      );
      expect(
        1.0,
        lessThanOrEqualTo(kWordModeMaxSubstitutedPhonemesShortWord),
        reason: 'two stacked 0.5 confusions in a short word must still '
            'clear the short-word near-miss threshold',
      );
    });

    test('NEGATIVE: a non-confusion substitution still costs 1 '
        '(S,AH,N vs S,AH,M — N/M is not an A-18 axis)', () {
      expect(
        phonemeEditDistanceWeighted(['S', 'AH', 'N'], ['S', 'AH', 'M']),
        1,
      );
    });

    test('NEGATIVE: gat/cat conflict guard — weighted distance moves to '
        '0.5 (K/G voicing pair) but the frozen uniform anchor does not '
        'move and the acceptance outcome is unchanged', () {
      // The frozen anchor, read verbatim from the untouched function.
      expect(phonemeEditDistance(['G', 'AE', 'T'], ['K', 'AE', 'T']), 1,
          reason: 'phoneme_distance_test.dart pins this at exactly 1 — '
              'must never move');
      // The new, separate function may legitimately compute a different
      // number for the same pair...
      expect(
        phonemeEditDistanceWeighted(['G', 'AE', 'T'], ['K', 'AE', 'T']),
        0.5,
      );
      // ...but the near-miss ACCEPTANCE outcome is unchanged either way:
      // both 1 and 0.5 sit at-or-under the short-word threshold.
      expect(1, lessThanOrEqualTo(kWordModeMaxSubstitutedPhonemesShortWord));
      expect(
        0.5,
        lessThanOrEqualTo(kWordModeMaxSubstitutedPhonemesShortWord),
      );
    });

    test('EDGE: weighted distance is symmetric, like the uniform metric',
        () {
      final pairs = <(List<String>, List<String>)>[
        (['W', 'AY', 'L'], ['F', 'AY', 'L']),
        (['K', 'AE', 'P'], ['T', 'AE', 'B']),
        (['S', 'AH', 'N'], ['S', 'AH', 'M']),
        (['G', 'AE', 'T'], ['K', 'AE', 'T']),
      ];
      for (final (a, b) in pairs) {
        expect(
          phonemeEditDistanceWeighted(a, b),
          phonemeEditDistanceWeighted(b, a),
          reason: 'weighted distance($a, $b) must equal weighted '
              'distance($b, $a)',
        );
      }
    });

    test('EDGE: weighted distance never exceeds the uniform distance on '
        'the same inputs (confusable substitutions only ever discount)',
        () {
      final pairs = <(List<String>, List<String>)>[
        (['W', 'AY', 'L'], ['F', 'AY', 'L']),
        (['K', 'AE', 'P'], ['T', 'AE', 'B']),
        (['S', 'AH', 'N'], ['S', 'AH', 'M']),
        (['G', 'AE', 'T'], ['K', 'AE', 'T']),
        (['D', 'AO', 'G'], ['K', 'AE', 'T']),
      ];
      for (final (a, b) in pairs) {
        expect(
          phonemeEditDistanceWeighted(a, b),
          lessThanOrEqualTo(phonemeEditDistance(a, b)),
          reason: 'weighted($a, $b) must never be greater than '
              'uniform($a, $b)',
        );
      }
    });

    test('EDGE: three non-confusable substitutions (dog/cat) still cost 3 '
        '— the canonical reject pair is unaffected by A-18', () {
      expect(
        phonemeEditDistanceWeighted(['D', 'AO', 'G'], ['K', 'AE', 'T']),
        3,
      );
    });
  });

  group('WordMatcher acceptance path — A-18 weighted grading is opt-in',
      () {
    test('POSITIVE: default WordMatcher (no phonemeDistanceFn override) '
        'still grades "gat" a near-miss of "cat" at uniform distance 1 — '
        'the frozen default behavior', () {
      final m = WordMatcher(sentence: [_cat]);
      final results = m.onHypothesis(_word('gat'));
      expect(results.single.kind, MatchKind.nearMiss);
    });

    test('POSITIVE: WordMatcher with phonemeDistanceFn: '
        'phonemeEditDistanceWeighted grades "file" a near-miss of target '
        '"while" (W/F labial-fricative confusion, A-18)', () {
      final m = WordMatcher(
        sentence: [_while],
        phonemeDistanceFn: phonemeEditDistanceWeighted,
      );
      final results = m.onHypothesis(_word('file', phones: ['F', 'AY', 'L']));
      expect(results, hasLength(1));
      expect(results.single.kind, MatchKind.nearMiss);
      expect(m.currentIndex, 1, reason: 'near-miss acceptance advances');
    });

    test('POSITIVE: a two-confusion word ("tab" vs target "cap") is '
        'REJECTED by the default uniform matcher (distance 2 exceeds the '
        'short-word threshold) but ACCEPTED as a near-miss once weighted '
        '(distance 1.0 clears it) — the concrete A-18 acceptance widening',
        () {
      final uniform = WordMatcher(sentence: [_cap]);
      final uniformResult =
          uniform.onHypothesis(_word('tab', phones: ['T', 'AE', 'B'])).single;
      expect(uniformResult.kind, MatchKind.reject,
          reason: 'uniform distance is 2 (K/T and P/B both cost 1), over '
              'the short-word threshold of 1');

      final weighted = WordMatcher(
        sentence: [_cap],
        phonemeDistanceFn: phonemeEditDistanceWeighted,
      );
      final weightedResult =
          weighted.onHypothesis(_word('tab', phones: ['T', 'AE', 'B'])).single;
      expect(weightedResult.kind, MatchKind.nearMiss,
          reason: 'weighted distance is 1.0 (two 0.5 confusions), at the '
              'short-word threshold of 1 — A-18 unlocks this acceptance');
    });

    test('NEGATIVE: a non-confusion pair beyond threshold still rejects '
        'under weighted grading too ("dog" vs target "cat", 3 '
        'non-confusable substitutions)', () {
      final weighted = WordMatcher(
        sentence: [_cat],
        phonemeDistanceFn: phonemeEditDistanceWeighted,
      );
      final result = weighted
          .onHypothesis(_word('dog', phones: ['D', 'AO', 'G']))
          .single;
      expect(result.kind, MatchKind.reject,
          reason: 'A-18 widens acceptance only along its documented axes — '
              'dog/cat has none, so weighting must not rescue it');
    });

    test('EDGE: weighted grading never changes exact-match classification '
        '— a textually exact hypothesis is still exact, not near-miss',
        () {
      final weighted = WordMatcher(
        sentence: [_while],
        phonemeDistanceFn: phonemeEditDistanceWeighted,
      );
      final result = weighted.onHypothesis(_word('while')).single;
      expect(result.kind, MatchKind.exact);
    });
  });
}

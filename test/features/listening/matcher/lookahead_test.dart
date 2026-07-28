/// Contract tests for lookahead-1 with back-fill (PRD §8 Unit 4, pinned):
/// "hearing the next word confirms the current one".
///
/// Pinned semantics under test:
///   - A hypothesis that fails the current word but matches the NEXT word
///     (exact or near-miss, per the standard close-enough policy) accepts
///     BOTH: the current word is back-filled as accepted and the next word
///     is accepted with its own match grade. Emission order is pinned:
///     current first, then next (the tracker must emit wordAccepted for the
///     current index before the next index).
///   - The back-filled current word is graded [MatchKind.exact]: the
///     tracker-events contract (WordAccepted doc) routes lookahead
///     back-fill to plain wordAccepted, never wordAcceptedNearMiss.
///   - Lookahead depth is exactly 1: a hypothesis matching only the word
///     at currentIndex+2 is a reject.
///   - A hypothesis that exactly matches the CURRENT word never skips
///     ahead, whatever else it resembles.
///
/// Fixture sentence: cat sun fish — adjacent words are mutually distant
/// (pairwise phoneme distance 3), so no test is confounded by accidental
/// near-misses between neighbors.
///
/// Imports the not-yet-written implementation: red-for-right-reason.

library;

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/matcher/match_result.dart';
import 'package:learn_to_read/features/listening/matcher/word_matcher.dart';

WordToken _tok(String text, List<({String graphemes, String phonemeId})> map) =>
    WordToken(
      text: text,
      graphemePhonemeMap: map,
      pronunciationAudioRef: 'audio/$text.mp3',
    );

WordToken get _cat => _tok('cat', [
      (graphemes: 'c', phonemeId: 'K'),
      (graphemes: 'a', phonemeId: 'AE'),
      (graphemes: 't', phonemeId: 'T'),
    ]);

WordToken get _sun => _tok('sun', [
      (graphemes: 's', phonemeId: 'S'),
      (graphemes: 'u', phonemeId: 'AH'),
      (graphemes: 'n', phonemeId: 'N'),
    ]);

WordToken get _fish => _tok('fish', [
      (graphemes: 'f', phonemeId: 'F'),
      (graphemes: 'i', phonemeId: 'IH'),
      (graphemes: 'sh', phonemeId: 'SH'),
    ]);

Hypothesis _word(String w, {List<String>? phones}) =>
    Hypothesis(wordHypotheses: [w], phoneHypotheses: phones);

void main() {
  group('WordMatcher lookahead-1 — back-fill', () {
    test('POSITIVE: hypothesis exactly matching the NEXT word back-fills '
        'the current word — both advance, current emitted before next '
        '(the ordering contract)', () {
      final m = WordMatcher(sentence: [_cat, _sun, _fish]);
      expect(m.currentIndex, 0);

      final results = m.onHypothesis(_word('sun'));

      expect(results, hasLength(2),
          reason: 'back-fill must report both the confirmed current word '
              'and the heard next word');
      expect(results[0].wordIndex, 0,
          reason: 'current word must be emitted first');
      expect(results[0].kind, MatchKind.exact,
          reason: 'back-filled acceptance maps to plain wordAccepted '
              '(tracker-events contract), so its grade is exact');
      expect(results[1].wordIndex, 1);
      expect(results[1].kind, MatchKind.exact);
      expect(m.currentIndex, 2, reason: 'both words advanced');
    });

    test('POSITIVE: a NEAR-MISS of the next word also back-fills — next '
        'word keeps its near-miss grade, current is back-filled as '
        'accepted ("fun" F,AH,N vs next "sun" S,AH,N)', () {
      final m = WordMatcher(sentence: [_cat, _sun, _fish]);

      final results = m.onHypothesis(_word('fun', phones: ['F', 'AH', 'N']));

      expect(results, hasLength(2));
      expect(results[0].wordIndex, 0);
      expect(results[0].kind, MatchKind.exact);
      expect(results[1].wordIndex, 1);
      expect(results[1].kind, MatchKind.nearMiss,
          reason: 'the heard word was itself only close-enough; the '
              'near-miss grade must survive back-fill for §5 analytics');
      expect(m.currentIndex, 2);
    });

    test('POSITIVE: back-fill chains across the sentence — reading word '
        'pairs by their second word completes the text', () {
      final m = WordMatcher(sentence: [_cat, _sun, _fish]);
      m.onHypothesis(_word('sun')); // back-fills cat, accepts sun
      final results = m.onHypothesis(_word('fish'));
      expect(results.single.kind, MatchKind.exact);
      expect(results.single.wordIndex, 2);
      expect(m.isComplete, isTrue);
    });

    test('POSITIVE: back-fill works on the final word pair and completes '
        'the sentence', () {
      final m = WordMatcher(sentence: [_cat, _sun]);
      final results = m.onHypothesis(_word('sun'));
      expect(results, hasLength(2));
      expect(m.currentIndex, 2);
      expect(m.isComplete, isTrue);
    });
  });

  group('WordMatcher lookahead-1 — depth and precedence limits', () {
    test('NEGATIVE: lookahead depth is exactly 1 — a hypothesis matching '
        'only currentIndex+2 is a reject and nothing advances', () {
      final m = WordMatcher(sentence: [_cat, _sun, _fish]);

      final results = m.onHypothesis(_word('fish'));

      expect(results, hasLength(1));
      expect(results.single.kind, MatchKind.reject);
      expect(results.single.wordIndex, 0,
          reason: 'the reject is attributed to the current word (feeds '
              'struggle detection at the current index)');
      expect(results.single.phonemeDistance, isNotNull,
          reason: 'ticket: reject carries the failed distance');
      expect(m.currentIndex, 0);
    });

    test('POSITIVE: a hypothesis exactly matching the CURRENT word '
        'advances by one only — never skips via lookahead', () {
      final m = WordMatcher(sentence: [_cat, _sun, _fish]);

      final results = m.onHypothesis(_word('cat'));

      expect(results, hasLength(1));
      expect(results.single.wordIndex, 0);
      expect(results.single.kind, MatchKind.exact);
      expect(m.currentIndex, 1);
    });

    test('NEGATIVE: on the last word there is no next word — a wrong '
        'hypothesis is a plain reject, no crash, no advance', () {
      final m = WordMatcher(sentence: [_cat, _sun]);
      m.onHypothesis(_word('cat'));
      expect(m.currentIndex, 1);

      final results = m.onHypothesis(_word('zubzub'));

      expect(results.single.kind, MatchKind.reject);
      expect(results.single.wordIndex, 1);
      expect(m.currentIndex, 1);
      expect(m.isComplete, isFalse);
    });

    test('EDGE: multi-candidate hypothesis — a candidate matching the '
        'current word is preferred over a candidate matching the next '
        'word (["cat","sun"] advances one word, not two)', () {
      final m = WordMatcher(sentence: [_cat, _sun, _fish]);

      final results = m.onHypothesis(
        const Hypothesis(wordHypotheses: ['cat', 'sun'], phoneHypotheses: null),
      );

      expect(results, hasLength(1),
          reason: 'the burst is one production; matching the current '
              'target must win over jumping ahead');
      expect(results.single.wordIndex, 0);
      expect(results.single.kind, MatchKind.exact);
      expect(m.currentIndex, 1);
    });

    test('EDGE: back-fill never double-fires — repeating the next-word '
        'hypothesis after a back-fill does not advance again '
        '(it is a repeat of an already-accepted word)', () {
      final m = WordMatcher(sentence: [_cat, _sun, _fish]);
      m.onHypothesis(_word('sun')); // back-fill: currentIndex -> 2

      final repeat = m.onHypothesis(_word('sun'));

      expect(repeat.where((r) => r.kind != MatchKind.reject), isEmpty,
          reason: 'no new acceptance may be minted from the repeat');
      expect(repeat.where((r) => r.kind == MatchKind.reject), isEmpty,
          reason: 'a repeat of an accepted word is not a failed attempt at '
              'the current word — it must not feed struggle detection');
      expect(m.currentIndex, 2);
    });
  });
}

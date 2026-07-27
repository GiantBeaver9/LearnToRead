/// Contract tests for the word-mode hybrid matcher (PRD §8 Unit 4, ticket
/// word-matcher). This suite IS the matcher's specification.
///
/// Pinned API (implementation does not exist yet — red-for-right-reason):
///   - lib/features/listening/matcher/match_result.dart:
///       enum MatchKind { exact, nearMiss, reject }
///       class MatchResult { MatchKind kind; int wordIndex;
///                           int? phonemeDistance; }
///     phonemeDistance: 0 for a textual exact match, the measured distance
///     for a near-miss, and the failed distance for a reject (feeds struggle
///     detection). May be null only where no distance is meaningful (e.g.
///     a lookahead back-filled word that had no hypothesis of its own).
///   - lib/features/listening/matcher/word_matcher.dart:
///       class WordMatcher {
///         WordMatcher({required `List<WordToken>` sentence,
///           int shortWordMaxPhonemes = kWordModeShortWordMaxPhonemes,
///           int maxSubstitutedPhonemesShortWord =
///               kWordModeMaxSubstitutedPhonemesShortWord,
///           int maxSubstitutedPhonemesLongWord =
///               kWordModeMaxSubstitutedPhonemesLongWord});
///         `List<MatchResult>` onHypothesis(Hypothesis h); // emission order
///         int get currentIndex;   // next expected word; == length when done
///         bool get isComplete;
///         // threshold getters mirror the constructor parameters
///       }
///   - lib/features/listening/matcher/grapheme_to_phoneme.dart:
///       `List<String>` graphemesToPhonemes(String word);
///     Matcher-internal comparison G2P for hypothesis words that have no
///     authored map ("gat"). Only black-box behavior on the fixture
///     vocabulary is pinned here — it is not a linguistics project.
///
/// Fixture discipline: hypothesis words in threshold-boundary tests use only
/// letterwise-regular spellings AND carry redundant phoneHypotheses equal to
/// their pinned G2P output, so every distance assertion holds whether the
/// implementation scores engine phones or its own G2P of the hypothesis
/// text. The target side is always the authored graphemePhonemeMap.

library;

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/tuning.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/matcher/grapheme_to_phoneme.dart';
import 'package:learn_to_read/features/listening/matcher/match_result.dart';
import 'package:learn_to_read/features/listening/matcher/phoneme_distance.dart';
import 'package:learn_to_read/features/listening/matcher/word_matcher.dart';

WordToken _tok(String text, List<({String graphemes, String phonemeId})> map) =>
    WordToken(
      text: text,
      graphemePhonemeMap: map,
      pronunciationAudioRef: 'audio/$text.mp3',
    );

/// 'cat' = K,AE,T (3 phonemes, short word).
WordToken get _cat => _tok('cat', [
      (graphemes: 'c', phonemeId: 'K'),
      (graphemes: 'a', phonemeId: 'AE'),
      (graphemes: 't', phonemeId: 'T'),
    ]);

/// 'sun' = S,AH,N (3 phonemes; distance 3 from cat and fish).
WordToken get _sun => _tok('sun', [
      (graphemes: 's', phonemeId: 'S'),
      (graphemes: 'u', phonemeId: 'AH'),
      (graphemes: 'n', phonemeId: 'N'),
    ]);

/// 'fast' = F,AE,S,T — exactly kWordModeShortWordMaxPhonemes (4) phonemes:
/// the last "short" word (threshold boundary from tuning.dart).
WordToken get _fast => _tok('fast', [
      (graphemes: 'f', phonemeId: 'F'),
      (graphemes: 'a', phonemeId: 'AE'),
      (graphemes: 's', phonemeId: 'S'),
      (graphemes: 't', phonemeId: 'T'),
    ]);

/// 'stand' = S,T,AE,N,D — exactly 5 phonemes: the first "long" word.
WordToken get _stand => _tok('stand', [
      (graphemes: 's', phonemeId: 'S'),
      (graphemes: 't', phonemeId: 'T'),
      (graphemes: 'a', phonemeId: 'AE'),
      (graphemes: 'n', phonemeId: 'N'),
      (graphemes: 'd', phonemeId: 'D'),
    ]);

/// 'said' — authored map S,EH,D deliberately differs from a naive letterwise
/// reading of the spelling ('ai' is a single digraph entry). Used to pin
/// that closeness is measured against the AUTHORED map, never a G2P of the
/// target's own text.
WordToken get _said => _tok('said', [
      (graphemes: 's', phonemeId: 'S'),
      (graphemes: 'ai', phonemeId: 'EH'),
      (graphemes: 'd', phonemeId: 'D'),
    ]);

Hypothesis _word(String w, {List<String>? phones}) =>
    Hypothesis(wordHypotheses: [w], phoneHypotheses: phones);

void main() {
  // Guard the fixture premise once: the tuning constants these tests lean on.
  // If a pilot retunes them the boundary fixtures below must be re-derived,
  // so fail loudly here instead of mysteriously there.
  group('fixture premise — pinned tuning defaults (PRD §8 Unit 4)', () {
    test('POSITIVE: word-mode tuning constants hold their pinned values', () {
      expect(kWordModeShortWordMaxPhonemes, 4);
      expect(kWordModeMaxSubstitutedPhonemesShortWord, 1);
      expect(kWordModeMaxSubstitutedPhonemesLongWord, 2);
    });
  });

  group('WordMatcher — exact acceptance', () {
    test('POSITIVE: hypothesis equal to the target word is accepted as '
        'exact and advances', () {
      final m = WordMatcher(sentence: [_cat, _sun]);
      expect(m.currentIndex, 0);

      final results = m.onHypothesis(_word('cat'));

      expect(results, hasLength(1));
      expect(results.single.kind, MatchKind.exact);
      expect(results.single.wordIndex, 0);
      expect(results.single.phonemeDistance, 0,
          reason: 'a textual exact match has phoneme distance 0');
      expect(m.currentIndex, 1);
      expect(m.isComplete, isFalse);
    });

    test('POSITIVE: exact match is case-insensitive '
        '(Cat, CAT accept cat)', () {
      for (final heard in ['Cat', 'CAT', 'cAt']) {
        final m = WordMatcher(sentence: [_cat]);
        final results = m.onHypothesis(_word(heard));
        expect(results.single.kind, MatchKind.exact,
            reason: '"$heard" must exact-match target "cat"');
        expect(m.currentIndex, 1);
      }
    });

    test('POSITIVE: exact match is punctuation-insensitive on the '
        'hypothesis side ("cat!", "cat.")', () {
      for (final heard in ['cat!', 'cat.', '"cat,"']) {
        final m = WordMatcher(sentence: [_cat]);
        expect(m.onHypothesis(_word(heard)).single.kind, MatchKind.exact,
            reason: '"$heard" must exact-match target "cat"');
      }
    });

    test('POSITIVE: exact match is case/punctuation-insensitive on the '
        'target side (authored token "Sun." accepts "sun")', () {
      final capitalizedSun = _tok('Sun.', [
        (graphemes: 's', phonemeId: 'S'),
        (graphemes: 'u', phonemeId: 'AH'),
        (graphemes: 'n', phonemeId: 'N'),
      ]);
      final m = WordMatcher(sentence: [capitalizedSun]);
      expect(m.onHypothesis(_word('sun')).single.kind, MatchKind.exact);
      expect(m.isComplete, isTrue);
    });

    test('POSITIVE: accepting every word in order completes the '
        'sentence', () {
      final m = WordMatcher(sentence: [_cat, _sun]);
      m.onHypothesis(_word('cat'));
      m.onHypothesis(_word('sun'));
      expect(m.currentIndex, 2);
      expect(m.isComplete, isTrue);
    });
  });

  group('WordMatcher — close-enough near-miss acceptance (canonical)', () {
    test('POSITIVE: "gat" accepts "cat" as a near-miss (PRD canonical '
        'example) via the G2P fallback — no phones supplied', () {
      final m = WordMatcher(sentence: [_cat, _sun]);

      final results = m.onHypothesis(_word('gat'));

      expect(results, hasLength(1));
      expect(results.single.kind, MatchKind.nearMiss);
      expect(results.single.wordIndex, 0);
      expect(
        results.single.phonemeDistance,
        allOf(
          greaterThanOrEqualTo(1),
          lessThanOrEqualTo(kWordModeMaxSubstitutedPhonemesShortWord),
        ),
        reason: 'near-miss distance must be within the tuning threshold',
      );
      expect(m.currentIndex, 1, reason: 'near-miss acceptance advances');
    });

    test('POSITIVE: near-miss is distinguishable from exact in the '
        'MatchResult type (drives wordAcceptedNearMiss vs wordAccepted '
        'and the §5 correct/near_miss analytics split)', () {
      final exact = WordMatcher(sentence: [_cat])
          .onHypothesis(_word('cat'))
          .single;
      final near = WordMatcher(sentence: [_cat])
          .onHypothesis(_word('gat'))
          .single;

      expect(exact.kind, MatchKind.exact);
      expect(near.kind, MatchKind.nearMiss);
      expect(exact.kind, isNot(near.kind),
          reason: 'the two acceptance grades must never collapse');
    });

    test('POSITIVE: closeness is measured against the authored '
        'graphemePhonemeMap, never a G2P of the target text '
        '(irregular target "said" accepts a phonetic production)', () {
      final m = WordMatcher(sentence: [_said]);

      // 'sed' produced as S,EH,D — distance 0-or-1 from the authored map
      // S,EH,D, but far from any naive letterwise reading of 's-a-i-d'.
      final results = m.onHypothesis(_word('sed', phones: ['S', 'EH', 'D']));

      expect(results, hasLength(1));
      expect(results.single.kind, isNot(MatchKind.reject),
          reason: 'a production matching the authored phonemes must be '
              'accepted even when the target spelling is irregular');
      expect(m.currentIndex, 1);
    });
  });

  group('WordMatcher — rejection beyond threshold (canonical)', () {
    test('NEGATIVE: "dog" does not accept "cat" (PRD canonical example) — '
        'reject carries the failed distance for struggle detection', () {
      final m = WordMatcher(sentence: [_cat, _sun]);

      final results = m.onHypothesis(_word('dog'));

      expect(results, hasLength(1));
      expect(results.single.kind, MatchKind.reject);
      expect(results.single.wordIndex, 0);
      expect(results.single.phonemeDistance, isNotNull,
          reason: 'ticket: "result reject with the failed distance"');
      expect(
        results.single.phonemeDistance,
        greaterThan(kWordModeMaxSubstitutedPhonemesShortWord),
      );
      expect(m.currentIndex, 0, reason: 'a reject never advances');
      expect(m.isComplete, isFalse);
    });

    test('NEGATIVE: rejection does not corrupt state — the correct word '
        'still accepts afterwards', () {
      final m = WordMatcher(sentence: [_cat]);
      m.onHypothesis(_word('dog'));
      expect(m.onHypothesis(_word('cat')).single.kind, MatchKind.exact);
      expect(m.isComplete, isTrue);
    });
  });

  group('WordMatcher — length-dependent thresholds at the exact boundary '
      '(4-phoneme short vs 5-phoneme long, from tuning.dart)', () {
    test('POSITIVE: 4-phoneme target, distance exactly '
        'kWordModeMaxSubstitutedPhonemesShortWord (1) -> near-miss '
        '("fasp" F,AE,S,P vs fast F,AE,S,T)', () {
      final m = WordMatcher(sentence: [_fast]);
      final results =
          m.onHypothesis(_word('fasp', phones: ['F', 'AE', 'S', 'P']));

      expect(results.single.kind, MatchKind.nearMiss);
      expect(results.single.phonemeDistance,
          kWordModeMaxSubstitutedPhonemesShortWord,
          reason: 'this fixture sits exactly at the short-word threshold');
      expect(m.currentIndex, 1);
    });

    test('NEGATIVE: 4-phoneme target, distance 2 (threshold+1) -> reject '
        '("masp" M,AE,S,P vs fast F,AE,S,T)', () {
      final m = WordMatcher(sentence: [_fast]);
      final results =
          m.onHypothesis(_word('masp', phones: ['M', 'AE', 'S', 'P']));

      expect(results.single.kind, MatchKind.reject);
      expect(results.single.phonemeDistance, 2);
      expect(results.single.phonemeDistance,
          greaterThan(kWordModeMaxSubstitutedPhonemesShortWord));
      expect(m.currentIndex, 0);
    });

    test('POSITIVE: 5-phoneme target, distance exactly '
        'kWordModeMaxSubstitutedPhonemesLongWord (2) -> near-miss '
        '("spanb" S,P,AE,N,B vs stand S,T,AE,N,D)', () {
      final m = WordMatcher(sentence: [_stand]);
      final results = m
          .onHypothesis(_word('spanb', phones: ['S', 'P', 'AE', 'N', 'B']));

      expect(results.single.kind, MatchKind.nearMiss);
      expect(results.single.phonemeDistance,
          kWordModeMaxSubstitutedPhonemesLongWord,
          reason: 'this fixture sits exactly at the long-word threshold');
      expect(m.currentIndex, 1);
    });

    test('NEGATIVE: 5-phoneme target, distance 3 (threshold+1) -> reject '
        '("spamb" S,P,AE,M,B vs stand S,T,AE,N,D)', () {
      final m = WordMatcher(sentence: [_stand]);
      final results = m
          .onHypothesis(_word('spamb', phones: ['S', 'P', 'AE', 'M', 'B']));

      expect(results.single.kind, MatchKind.reject);
      expect(results.single.phonemeDistance, 3);
      expect(m.currentIndex, 0);
    });

    test('EDGE: the same distance-2 production flips verdict across the '
        'length boundary — rejected on a 4-phoneme word, accepted on a '
        '5-phoneme word', () {
      final shortResult = WordMatcher(sentence: [_fast])
          .onHypothesis(_word('masp', phones: ['M', 'AE', 'S', 'P']))
          .single;
      final longResult = WordMatcher(sentence: [_stand])
          .onHypothesis(_word('spanb', phones: ['S', 'P', 'AE', 'N', 'B']))
          .single;

      expect(shortResult.kind, MatchKind.reject);
      expect(longResult.kind, MatchKind.nearMiss);
    });
  });

  group('WordMatcher — thresholds come from tuning.dart '
      '(changing them changes behavior; never hardcoded)', () {
    test('POSITIVE: default thresholds equal the tuning constants', () {
      final m = WordMatcher(sentence: [_cat]);
      expect(m.shortWordMaxPhonemes, kWordModeShortWordMaxPhonemes);
      expect(m.maxSubstitutedPhonemesShortWord,
          kWordModeMaxSubstitutedPhonemesShortWord);
      expect(m.maxSubstitutedPhonemesLongWord,
          kWordModeMaxSubstitutedPhonemesLongWord);
    });

    test('NEGATIVE: tightening the short-word threshold to 0 rejects the '
        'canonical "gat"/"cat" near-miss', () {
      final m = WordMatcher(
        sentence: [_cat],
        maxSubstitutedPhonemesShortWord: 0,
      );
      final results = m.onHypothesis(_word('gat'));
      expect(results.single.kind, MatchKind.reject,
          reason: 'behavior must follow the injected threshold, proving the '
              'constant is read, not hardcoded');
      expect(m.currentIndex, 0);
    });

    test('POSITIVE: loosening the short-word threshold to 2 accepts the '
        'previously rejected distance-2 short-word production', () {
      final m = WordMatcher(
        sentence: [_fast],
        maxSubstitutedPhonemesShortWord: 2,
      );
      final results =
          m.onHypothesis(_word('masp', phones: ['M', 'AE', 'S', 'P']));
      expect(results.single.kind, MatchKind.nearMiss);
      expect(m.currentIndex, 1);
    });

    test('NEGATIVE: widening shortWordMaxPhonemes to 5 makes a 5-phoneme '
        'word use the (tighter) short threshold — distance 2 now '
        'rejects', () {
      final m = WordMatcher(
        sentence: [_stand],
        shortWordMaxPhonemes: 5,
      );
      final results = m
          .onHypothesis(_word('spanb', phones: ['S', 'P', 'AE', 'N', 'B']));
      expect(results.single.kind, MatchKind.reject);
    });

    test('POSITIVE: loosening the long-word threshold to 3 accepts the '
        'previously rejected distance-3 long-word production', () {
      final m = WordMatcher(
        sentence: [_stand],
        maxSubstitutedPhonemesLongWord: 3,
      );
      final results = m
          .onHypothesis(_word('spamb', phones: ['S', 'P', 'AE', 'M', 'B']));
      expect(results.single.kind, MatchKind.nearMiss);
    });
  });

  group('WordMatcher — hypothesis lists with multiple candidates '
      '(engine alternatives, ordered by confidence)', () {
    test('POSITIVE: an exact candidate anywhere in the list wins over an '
        'earlier near-miss candidate (["gat","cat"] -> exact)', () {
      final m = WordMatcher(sentence: [_cat]);
      final results = m.onHypothesis(
        Hypothesis(wordHypotheses: ['gat', 'cat'], phoneHypotheses: null),
      );
      expect(results.single.kind, MatchKind.exact,
          reason: 'the child said the word; a lower-confidence exact '
              'alternative must not be downgraded to near-miss');
      expect(m.currentIndex, 1);
    });

    test('POSITIVE: a near-miss candidate after a rejected candidate still '
        'accepts (["dog","gat"] -> nearMiss)', () {
      final m = WordMatcher(sentence: [_cat]);
      final results = m.onHypothesis(
        Hypothesis(wordHypotheses: ['dog', 'gat'], phoneHypotheses: null),
      );
      expect(results.single.kind, MatchKind.nearMiss);
      expect(m.currentIndex, 1);
    });

    test('NEGATIVE: all candidates beyond threshold -> single reject, '
        'no advance (["dog","zubzub"])', () {
      final m = WordMatcher(sentence: [_cat]);
      final results = m.onHypothesis(
        Hypothesis(wordHypotheses: ['dog', 'zubzub'], phoneHypotheses: null),
      );
      expect(results, hasLength(1));
      expect(results.single.kind, MatchKind.reject);
      expect(results.single.phonemeDistance,
          greaterThan(kWordModeMaxSubstitutedPhonemesShortWord));
      expect(m.currentIndex, 0);
    });
  });

  group('WordMatcher — empty and garbage hypotheses', () {
    test('EDGE: empty wordHypotheses list produces no results and no state '
        'change (not speech — must not feed struggle detection)', () {
      final m = WordMatcher(sentence: [_cat]);
      final results = m.onHypothesis(
        const Hypothesis(wordHypotheses: [], phoneHypotheses: null),
      );
      expect(results, isEmpty);
      expect(m.currentIndex, 0);
    });

    test('EDGE: empty-string and punctuation-only candidates are ignored, '
        'not rejected (["" ] and ["!!!"])', () {
      for (final junk in ['', '!!!', '   ']) {
        final m = WordMatcher(sentence: [_cat]);
        final results = m.onHypothesis(_word(junk));
        expect(results, isEmpty,
            reason: 'candidate "$junk" carries no speech content; a reject '
                'here would wrongly count toward struggleDetected (A-12a)');
        expect(m.currentIndex, 0);
      }
    });

    test('NEGATIVE: an out-of-vocabulary garbage word is a real reject '
        'with a failed distance ("zubzub" vs "cat")', () {
      final m = WordMatcher(sentence: [_cat]);
      final results = m.onHypothesis(_word('zubzub'));
      expect(results.single.kind, MatchKind.reject);
      expect(results.single.phonemeDistance,
          greaterThan(kWordModeMaxSubstitutedPhonemesShortWord));
      expect(m.currentIndex, 0);
    });

    test('EDGE: an empty sentence is complete from the start and consumes '
        'hypotheses without producing results or throwing', () {
      final m = WordMatcher(sentence: const []);
      expect(m.isComplete, isTrue);
      expect(m.currentIndex, 0);
      expect(m.onHypothesis(_word('cat')), isEmpty);
      expect(m.currentIndex, 0);
    });

    test('EDGE: hypotheses after sentence completion never throw, never '
        'move currentIndex past the sentence length', () {
      final m = WordMatcher(sentence: [_cat]);
      m.onHypothesis(_word('cat'));
      expect(m.isComplete, isTrue);
      expect(m.currentIndex, 1);

      m.onHypothesis(_word('dog'));
      m.onHypothesis(_word('cat'));

      expect(m.currentIndex, 1);
      expect(m.isComplete, isTrue);
    });
  });

  group('graphemesToPhonemes — matcher-internal comparison G2P '
      '(black-box on the fixture vocabulary only)', () {
    test('POSITIVE: deterministic — same input, same output', () {
      expect(graphemesToPhonemes('gat'), graphemesToPhonemes('gat'));
      expect(graphemesToPhonemes('zubzub'), graphemesToPhonemes('zubzub'));
    });

    test('POSITIVE: output uses only the pinned 44 phoneme ids', () {
      for (final w in ['gat', 'cat', 'dog', 'fasp', 'zubzub']) {
        for (final p in graphemesToPhonemes(w)) {
          expect(kEnglishPhonemeIds, contains(p),
              reason: 'G2P("$w") emitted unknown phoneme id "$p"');
        }
      }
    });

    test('POSITIVE: the canonical OOV word "gat" maps within one phoneme '
        'of the authored "cat" phonemes (the load-bearing PRD example)', () {
      expect(
        phonemeEditDistance(graphemesToPhonemes('gat'), ['K', 'AE', 'T']),
        1,
      );
    });

    test('NEGATIVE: "dog" maps beyond the short-word threshold from '
        '"cat" — G2P must not over-normalize distinct words together', () {
      expect(
        phonemeEditDistance(graphemesToPhonemes('dog'), ['K', 'AE', 'T']),
        greaterThan(kWordModeMaxSubstitutedPhonemesShortWord),
      );
    });

    test('POSITIVE: regular fixture-vocabulary words reproduce their '
        'authored phonemes exactly', () {
      expect(graphemesToPhonemes('cat'), ['K', 'AE', 'T']);
      expect(graphemesToPhonemes('sat'), ['S', 'AE', 'T']);
    });

    test('POSITIVE: letterwise-regular nonsense fixtures used by the '
        'boundary tests map to their supplied phones (keeps the phones '
        'path and the G2P path equivalent for this suite)', () {
      expect(graphemesToPhonemes('fasp'), ['F', 'AE', 'S', 'P']);
      expect(graphemesToPhonemes('masp'), ['M', 'AE', 'S', 'P']);
      expect(graphemesToPhonemes('spanb'), ['S', 'P', 'AE', 'N', 'B']);
      expect(graphemesToPhonemes('spamb'), ['S', 'P', 'AE', 'M', 'B']);
    });

    test('EDGE: empty input yields an empty phoneme sequence', () {
      expect(graphemesToPhonemes(''), isEmpty);
    });

    test('EDGE: G2P is total — arbitrary garbage never throws', () {
      expect(() => graphemesToPhonemes('xyzzq'), returnsNormally);
      expect(() => graphemesToPhonemes("!?'-"), returnsNormally);
    });
  });
}

/// Contract tests for the phoneme-level edit distance (PRD §8 Unit 4).
///
/// The match policy is pinned on "phoneme-level edit distance against the
/// word's graphemePhonemeMap phonemes". This suite pins that distance as a
/// standard Levenshtein edit distance over phoneme-id sequences: unit cost
/// for substitution, insertion, and deletion; symmetric; zero iff equal.
///
/// Imports the (not-yet-written) implementation — this file must fail
/// red-for-right-reason (missing lib/features/listening/matcher/
/// phoneme_distance.dart) until the implementation ticket lands.

library;

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/tuning.dart';
import 'package:learn_to_read/features/listening/matcher/phoneme_distance.dart';

void main() {
  group('phonemeEditDistance — phoneme-level edit distance (Unit 4)', () {
    group('POSITIVE: identity', () {
      test('identical sequences have distance 0', () {
        expect(phonemeEditDistance(['K', 'AE', 'T'], ['K', 'AE', 'T']), 0);
      });

      test('two empty sequences have distance 0', () {
        expect(phonemeEditDistance(<String>[], <String>[]), 0);
      });

      test('identical single-phoneme sequences have distance 0', () {
        expect(phonemeEditDistance(['SH'], ['SH']), 0);
      });
    });

    group('POSITIVE: single edit operations cost 1', () {
      test('one substituted phoneme costs 1 — the canonical gat/cat pair '
          '(G,AE,T vs K,AE,T)', () {
        // PRD §8 Unit 4: "gat" accepts "cat" — one substituted phoneme.
        // This distance must sit exactly at the short-word near-miss
        // threshold from the tuning file.
        expect(phonemeEditDistance(['G', 'AE', 'T'], ['K', 'AE', 'T']), 1);
        expect(
          phonemeEditDistance(['G', 'AE', 'T'], ['K', 'AE', 'T']),
          kWordModeMaxSubstitutedPhonemesShortWord,
          reason: 'the canonical near-miss must sit exactly at the pinned '
              'short-word threshold in lib/domain/tuning.dart',
        );
      });

      test('one trailing insertion costs 1 (K,AE,T vs K,AE,T,S)', () {
        expect(phonemeEditDistance(['K', 'AE', 'T'], ['K', 'AE', 'T', 'S']), 1);
      });

      test('one interior deletion costs 1 (S,T,AE,N,D vs S,AE,N,D)', () {
        expect(
          phonemeEditDistance(
            ['S', 'T', 'AE', 'N', 'D'],
            ['S', 'AE', 'N', 'D'],
          ),
          1,
        );
      });

      test('one leading substitution costs 1 regardless of position '
          '(S,AH,N vs F,AH,N)', () {
        expect(phonemeEditDistance(['S', 'AH', 'N'], ['F', 'AH', 'N']), 1);
      });

      test('single-phoneme sequences that differ have distance 1', () {
        expect(phonemeEditDistance(['S'], ['SH']), 1);
      });
    });

    group('POSITIVE: combined edits accumulate', () {
      test('substitution plus insertion costs 2 (B,AE,T vs K,AE,T,S)', () {
        expect(
          phonemeEditDistance(['B', 'AE', 'T'], ['K', 'AE', 'T', 'S']),
          2,
        );
      });

      test('two substitutions cost 2 (S,P,AE,N,B vs S,T,AE,N,D)', () {
        expect(
          phonemeEditDistance(
            ['S', 'P', 'AE', 'N', 'B'],
            ['S', 'T', 'AE', 'N', 'D'],
          ),
          2,
        );
      });

      test('three substitutions cost 3 — the canonical dog/cat reject pair '
          '(D,AO,G vs K,AE,T)', () {
        // PRD §8 Unit 4: "dog" does NOT accept "cat".
        expect(phonemeEditDistance(['D', 'AO', 'G'], ['K', 'AE', 'T']), 3);
      });
    });

    group('NEGATIVE: distance is never understated', () {
      test('completely disjoint equal-length sequences cost full length', () {
        expect(phonemeEditDistance(['D', 'AO', 'G'], ['K', 'AE', 'T']), 3);
        expect(
          phonemeEditDistance(['D', 'AO', 'G'], ['K', 'AE', 'T']),
          greaterThan(kWordModeMaxSubstitutedPhonemesShortWord),
          reason: 'dog/cat must land beyond the short-word tuning threshold '
              'or the canonical PRD reject example breaks',
        );
      });

      test('distance is at least the length difference', () {
        expect(
          phonemeEditDistance(['K'], ['K', 'AE', 'T', 'S', 'IH']),
          greaterThanOrEqualTo(4),
        );
      });
    });

    group('EDGE: empty and asymmetric-length inputs', () {
      test('empty vs non-empty costs the non-empty length', () {
        expect(phonemeEditDistance(<String>[], ['K', 'AE', 'T']), 3);
        expect(phonemeEditDistance(['K', 'AE', 'T'], <String>[]), 3);
      });

      test('distance is symmetric', () {
        final pairs = <(List<String>, List<String>)>[
          (['G', 'AE', 'T'], ['K', 'AE', 'T']),
          (['S', 'T', 'AE', 'N', 'D'], ['S', 'AE', 'N', 'D']),
          (['B', 'AE', 'T'], ['K', 'AE', 'T', 'S']),
          (<String>[], ['SH', 'IY']),
        ];
        for (final (a, b) in pairs) {
          expect(
            phonemeEditDistance(a, b),
            phonemeEditDistance(b, a),
            reason: 'distance($a, $b) must equal distance($b, $a)',
          );
        }
      });

      test('distance never exceeds the longer sequence length', () {
        expect(
          phonemeEditDistance(['D', 'AO', 'G'], ['K', 'AE', 'T', 'S']),
          lessThanOrEqualTo(4),
        );
      });
    });
  });
}

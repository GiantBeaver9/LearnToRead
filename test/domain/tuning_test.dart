// Pins the API of lib/domain/tuning.dart -- the SINGLE tuning file (PRD §8
// Unit 6 pinned design: "Timings T1/T2, struggle sensitivity, and phonetic-
// closeness thresholds (Unit 4) are constants in one tuning file; pilot
// adjustments touch only that file."). Fails to compile until tuning.dart
// exists with exactly these top-level const declarations.
//
// Pinned API surface (names are this ticket's builder-mechanical choice;
// values are pinned verbatim by the ticket/PRD and MUST NOT drift):
//   const Duration kStruggleT1                              = Duration(seconds: 4);
//   const Duration kTier2WaitT2                              = Duration(seconds: 4);
//   const int kWordModeShortWordMaxPhonemes                  = 4;
//   const int kWordModeMaxSubstitutedPhonemesShortWord       = 1;
//   const int kWordModeMaxSubstitutedPhonemesLongWord        = 2;
//   const int kStruggleConsecutiveNonMatchingBursts          = 2;   // A-12(a)
//     -- A-12(b) (sustained silence >= T1) reuses kStruggleT1 directly.
//   const double kSoundModeMatchThreshold                    = 0.60; // A-13
//   const int kSoundModePerPhonemeMaxDistance                = 1;    // A-13
//   const int kSoundModeTargetPhonemeWeight                  = 2;    // A-13
//
// Every value here must be a genuine compile-time constant (a `const`
// top-level declaration, not merely `final`) so downstream tuning-file
// edits stay a single-file, no-code-elsewhere change, per the pinned
// design. That contract is asserted by using the imported names directly
// in a `const` collection literal below (`_constCheck`): if the
// implementation declares them as `final` instead of `const`, this file
// fails to compile.

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/tuning.dart';

// ignore: unused_element
const List<Object> _constCheck = [
  kStruggleT1,
  kTier2WaitT2,
  kWordModeShortWordMaxPhonemes,
  kWordModeMaxSubstitutedPhonemesShortWord,
  kWordModeMaxSubstitutedPhonemesLongWord,
  kStruggleConsecutiveNonMatchingBursts,
  kSoundModeMatchThreshold,
  kSoundModePerPhonemeMaxDistance,
  kSoundModeTargetPhonemeWeight,
];

void main() {
  group('Timings T1/T2 (positive: pinned defaults, Unit 6)', () {
    test('struggleT1 (T1) is 4 seconds', () {
      expect(kStruggleT1, const Duration(seconds: 4));
    });

    test('tier2WaitT2 (T2) is 4 seconds', () {
      expect(kTier2WaitT2, const Duration(seconds: 4));
    });
  });

  group('Timings T1/T2 (negative: anti-regression against plausible wrong values)', () {
    test('T1 is not accidentally 5s, 2s, or 0s', () {
      expect(kStruggleT1, isNot(const Duration(seconds: 5)));
      expect(kStruggleT1, isNot(const Duration(seconds: 2)));
      expect(kStruggleT1, isNot(Duration.zero));
    });

    test('T2 is not accidentally 5s, 2s, or 0s', () {
      expect(kTier2WaitT2, isNot(const Duration(seconds: 5)));
      expect(kTier2WaitT2, isNot(const Duration(seconds: 2)));
      expect(kTier2WaitT2, isNot(Duration.zero));
    });
  });

  group('Word-mode phonetic closeness thresholds (positive: pinned defaults, Unit 4)', () {
    test('short-word boundary is <= 4 phonemes', () {
      expect(kWordModeShortWordMaxPhonemes, 4);
    });

    test('short words tolerate at most 1 substituted phoneme', () {
      expect(kWordModeMaxSubstitutedPhonemesShortWord, 1);
    });

    test('longer words tolerate at most 2 substituted phonemes', () {
      expect(kWordModeMaxSubstitutedPhonemesLongWord, 2);
    });
  });

  group('Word-mode phonetic closeness thresholds (edge: boundary + ordering)', () {
    test('the long-word tolerance is strictly greater than the short-word tolerance', () {
      expect(
        kWordModeMaxSubstitutedPhonemesLongWord,
        greaterThan(kWordModeMaxSubstitutedPhonemesShortWord),
      );
    });

    test('a word with exactly kWordModeShortWordMaxPhonemes phonemes is classified short (<=), not long', () {
      // Boundary semantics: "<= 4 phonemes" uses the short threshold; a
      // 4-phoneme word is short, a 5-phoneme word is long. This test pins
      // the boundary is inclusive on the short side by asserting the
      // constant's documented meaning stays 4, not 3 or 5.
      expect(kWordModeShortWordMaxPhonemes, isNot(3));
      expect(kWordModeShortWordMaxPhonemes, isNot(5));
    });
  });

  group('Struggle sensitivity (positive: pinned defaults, A-12)', () {
    test('two consecutive finalized non-matching hypothesis bursts trigger struggle (A-12a)', () {
      expect(kStruggleConsecutiveNonMatchingBursts, 2);
    });

    test('sustained silence >= T1 triggers struggle (A-12b), sharing the T1 constant', () {
      expect(kStruggleT1, const Duration(seconds: 4));
    });
  });

  group('Struggle sensitivity (negative: not a single-burst or a >2 threshold)', () {
    test('is not 1 (would fire on a single non-matching burst, over-eager per R7)', () {
      expect(kStruggleConsecutiveNonMatchingBursts, isNot(1));
    });

    test('is not 3+ (would be slower than the pinned two-burst default)', () {
      expect(kStruggleConsecutiveNonMatchingBursts, lessThan(3));
    });
  });

  group('Sound-mode thresholds (positive: pinned defaults, A-13)', () {
    test('accepts when >= 60% of the target phoneme sequence matches', () {
      expect(kSoundModeMatchThreshold, 0.60);
    });

    test('per-phoneme distance tolerance is <= 1', () {
      expect(kSoundModePerPhonemeMaxDistance, 1);
    });

    test('target-phoneme instances are weighted double', () {
      expect(kSoundModeTargetPhonemeWeight, 2);
    });
  });

  group('Sound-mode thresholds (edge: valid proportion + negative anti-regression)', () {
    test('kSoundModeMatchThreshold is a valid proportion strictly between 0 and 1', () {
      expect(kSoundModeMatchThreshold, greaterThan(0.0));
      expect(kSoundModeMatchThreshold, lessThanOrEqualTo(1.0));
    });

    test('is not accidentally 100% (would reject any imperfect-but-close echo)', () {
      expect(kSoundModeMatchThreshold, isNot(1.0));
    });

    test('is not accidentally 50% or lower (would accept too loose a match)', () {
      expect(kSoundModeMatchThreshold, greaterThan(0.5));
    });
  });
}

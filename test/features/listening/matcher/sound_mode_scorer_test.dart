/// Contract tests for sound-mode scoring (PRD §8 Unit 14, §8 Unit 4 sound
/// mode, §9 A-13; ticket word-matcher). Sound mode listens for the SOUNDS,
/// not word identity: the twister/echo target is a phoneme sequence, the
/// drilled phoneme's instances are weighted most, and thresholds are the
/// separate looser set in lib/domain/tuning.dart.
///
/// Pinned API (implementation does not exist yet — red-for-right-reason):
///   lib/features/listening/matcher/sound_mode_scorer.dart:
///     class SoundModeScorer {
///       SoundModeScorer({required `List<String>` targetPhonemeSequence,
///         required String targetPhonemeId,
///         double matchThreshold = kSoundModeMatchThreshold,
///         int perPhonemeMaxDistance = kSoundModePerPhonemeMaxDistance,
///         int targetPhonemeWeight = kSoundModeTargetPhonemeWeight});
///       void onHypothesis(Hypothesis h);   // incremental tracking
///       double get matchedFraction;        // weighted, in [0.0, 1.0]
///       bool get accepted;                 // matchedFraction >= threshold
///       // threshold getters mirror the constructor parameters
///     }
///
/// Pinned scoring formula (A-13, made exact by the ticket's requirement
/// that double-weighting can flip the verdict in BOTH directions — which
/// forces the weight into numerator AND denominator):
///   matchedFraction = sum(weight_i for matched positions i)
///                   / sum(weight_i for all positions i)
///   where weight_i = targetPhonemeWeight when targetPhonemeSequence[i] ==
///   targetPhonemeId, else 1; a position is matched when a produced phoneme
///   aligns to it within perPhonemeMaxDistance. accepted when
///   matchedFraction >= matchThreshold (inclusive).
///
/// Fixtures only ever rely on EXACT phoneme matches (per-phoneme distance
/// 0, matched under any distance metric) and OMISSIONS (never matched):
/// the inter-phoneme confusability metric behind "per-phoneme distance
/// <= 1" is not pinned by the PRD and is deliberately not asserted here.

library;

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/tuning.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/matcher/sound_mode_scorer.dart';

Hypothesis _phones(List<String> phones) =>
    Hypothesis(wordHypotheses: const ['<phones>'], phoneHypotheses: phones);

Hypothesis _wordOnly(String w) =>
    Hypothesis(wordHypotheses: [w], phoneHypotheses: null);

void main() {
  // Guard the fixture premise: every exact fraction below is derived from
  // these pinned A-13 defaults. Retuning requires re-deriving fixtures, so
  // fail loudly here.
  group('fixture premise — pinned A-13 tuning defaults', () {
    test('POSITIVE: sound-mode tuning constants hold their pinned '
        'values', () {
      expect(kSoundModeMatchThreshold, 0.60);
      expect(kSoundModePerPhonemeMaxDistance, 1);
      expect(kSoundModeTargetPhonemeWeight, 2);
    });
  });

  group('SoundModeScorer — configuration reads from tuning.dart', () {
    test('POSITIVE: default thresholds equal the tuning constants '
        '(single source of truth, never hardcoded)', () {
      final s = SoundModeScorer(
        targetPhonemeSequence: const ['S', 'IY'],
        targetPhonemeId: 'S',
      );
      expect(s.matchThreshold, kSoundModeMatchThreshold);
      expect(s.perPhonemeMaxDistance, kSoundModePerPhonemeMaxDistance);
      expect(s.targetPhonemeWeight, kSoundModeTargetPhonemeWeight);
    });
  });

  group('SoundModeScorer — full-sequence match (phone-hypothesis '
      'consumption)', () {
    // Twister-style sequence "cat sat" drilling T:
    // K,AE,T,S,AE,T — weights 1,1,2,1,1,2 (total 8).
    SoundModeScorer scorer() => SoundModeScorer(
          targetPhonemeSequence: const ['K', 'AE', 'T', 'S', 'AE', 'T'],
          targetPhonemeId: 'T',
        );

    test('POSITIVE: producing the whole sequence accepts with '
        'matchedFraction 1.0', () {
      final s = scorer();
      s.onHypothesis(_phones(['K', 'AE', 'T']));
      s.onHypothesis(_phones(['S', 'AE', 'T']));

      expect(s.matchedFraction, closeTo(1.0, 1e-9));
      expect(s.accepted, isTrue);
    });

    test('POSITIVE: tracking is incremental — below threshold after the '
        'first burst, accepted after the second', () {
      final s = scorer();

      s.onHypothesis(_phones(['K', 'AE', 'T']));
      // Matched K,AE,T = 1+1+2 = 4 of 8.
      expect(s.matchedFraction, closeTo(0.5, 1e-9));
      expect(s.accepted, isFalse);

      s.onHypothesis(_phones(['S', 'AE', 'T']));
      expect(s.matchedFraction, closeTo(1.0, 1e-9));
      expect(s.accepted, isTrue);
    });

    test('POSITIVE: phones drive scoring when present — a garbage word '
        'hypothesis carrying the right phones still accepts (the matcher '
        'listens for sounds, not word identity)', () {
      final s = scorer();
      s.onHypothesis(const Hypothesis(
        wordHypotheses: ['blah'],
        phoneHypotheses: ['K', 'AE', 'T', 'S', 'AE', 'T'],
      ));

      expect(s.accepted, isTrue,
          reason: 'Unit 14 pinned: producing the sounds advances even if '
              'word recognition would fail');
    });

    test('EDGE: re-producing already-matched sounds never pushes the '
        'fraction above 1.0 or revokes acceptance', () {
      final s = scorer();
      s.onHypothesis(_phones(['K', 'AE', 'T', 'S', 'AE', 'T']));
      s.onHypothesis(_phones(['S', 'AE', 'T']));

      expect(s.matchedFraction, lessThanOrEqualTo(1.0));
      expect(s.accepted, isTrue);
    });
  });

  group('SoundModeScorer — the 60% acceptance boundary (A-13, weighted)', () {
    // Sequence drilling S: S,IY,EH,L,AH,S,T,P — weights 2,1,1,1,1,2,1,1
    // (total 10). A produced prefix of 5 phonemes matches weight 6 -> 0.6
    // exactly; a prefix of 4 matches weight 5 -> 0.5.
    SoundModeScorer scorer({double? threshold}) => SoundModeScorer(
          targetPhonemeSequence: const [
            'S', 'IY', 'EH', 'L', 'AH', 'S', 'T', 'P',
          ],
          targetPhonemeId: 'S',
          matchThreshold: threshold ?? kSoundModeMatchThreshold,
        );

    test('POSITIVE: exactly 60% weighted coverage is accepted — the '
        'threshold is inclusive (>=)', () {
      final s = scorer();
      s.onHypothesis(_phones(['S', 'IY', 'EH', 'L', 'AH']));

      expect(s.matchedFraction, closeTo(kSoundModeMatchThreshold, 1e-9),
          reason: 'fixture is engineered to land exactly on the tuning '
              'threshold');
      expect(s.accepted, isTrue);
    });

    test('NEGATIVE: 50% weighted coverage (one phoneme short of the '
        'boundary fixture) is rejected', () {
      final s = scorer();
      s.onHypothesis(_phones(['S', 'IY', 'EH', 'L']));

      expect(s.matchedFraction, closeTo(0.5, 1e-9));
      expect(s.accepted, isFalse);
    });

    test('NEGATIVE: silence — no hypotheses at all — is fraction 0.0, '
        'not accepted', () {
      final s = scorer();
      expect(s.matchedFraction, 0.0);
      expect(s.accepted, isFalse);
    });

    test('POSITIVE: lowering matchThreshold to 0.5 accepts the previously '
        'rejected 50% coverage (threshold is tunable, not hardcoded)', () {
      final s = scorer(threshold: 0.5);
      s.onHypothesis(_phones(['S', 'IY', 'EH', 'L']));

      expect(s.matchedFraction, closeTo(0.5, 1e-9));
      expect(s.accepted, isTrue,
          reason: 'inclusive >= against the injected threshold');
    });

    test('NEGATIVE: raising matchThreshold to 0.7 rejects the exactly-60% '
        'coverage (behavior follows the constant)', () {
      final s = scorer(threshold: 0.7);
      s.onHypothesis(_phones(['S', 'IY', 'EH', 'L', 'AH']));

      expect(s.accepted, isFalse);
    });
  });

  group('SoundModeScorer — target-phoneme double weighting flips the '
      'verdict (both directions, A-13)', () {
    test('POSITIVE: weighting RESCUES — hitting both drilled-phoneme '
        'instances accepts where the unweighted count (3/6 = 0.5) would '
        'reject', () {
      // Sequence S,S,IY,EH,L,AH drilling S — weights 2,2,1,1,1,1 (total 8).
      // Produced S,S,IY matches weight 5 -> 0.625 >= 0.6.
      final s = SoundModeScorer(
        targetPhonemeSequence: const ['S', 'S', 'IY', 'EH', 'L', 'AH'],
        targetPhonemeId: 'S',
      );
      s.onHypothesis(_phones(['S', 'S', 'IY']));

      expect(s.matchedFraction, closeTo(0.625, 1e-9));
      expect(s.accepted, isTrue);
    });

    test('NEGATIVE: same production with targetPhonemeWeight forced to 1 '
        'is rejected — the double weight is what rescued it', () {
      final s = SoundModeScorer(
        targetPhonemeSequence: const ['S', 'S', 'IY', 'EH', 'L', 'AH'],
        targetPhonemeId: 'S',
        targetPhonemeWeight: 1,
      );
      s.onHypothesis(_phones(['S', 'S', 'IY']));

      expect(s.matchedFraction, closeTo(3 / 6, 1e-9));
      expect(s.accepted, isFalse);
    });

    test('NEGATIVE: weighting SINKS — missing every drilled-phoneme '
        'instance rejects where the unweighted count (4/6 = 0.67) would '
        'accept', () {
      // Sequence IY,EH,L,AH,S,S drilling S — weights 1,1,1,1,2,2 (total 8).
      // Produced IY,EH,L,AH matches weight 4 -> 0.5 < 0.6.
      final s = SoundModeScorer(
        targetPhonemeSequence: const ['IY', 'EH', 'L', 'AH', 'S', 'S'],
        targetPhonemeId: 'S',
      );
      s.onHypothesis(_phones(['IY', 'EH', 'L', 'AH']));

      expect(s.matchedFraction, closeTo(0.5, 1e-9));
      expect(s.accepted, isFalse,
          reason: 'skipping the drilled sound must hurt double — the whole '
              'point of the exercise is that phoneme');
    });

    test('POSITIVE: same production with targetPhonemeWeight forced to 1 '
        'is accepted — proving the double weight (from tuning.dart) is '
        'what sank it', () {
      final s = SoundModeScorer(
        targetPhonemeSequence: const ['IY', 'EH', 'L', 'AH', 'S', 'S'],
        targetPhonemeId: 'S',
        targetPhonemeWeight: 1,
      );
      s.onHypothesis(_phones(['IY', 'EH', 'L', 'AH']));

      expect(s.matchedFraction, closeTo(4 / 6, 1e-9));
      expect(s.accepted, isTrue);
    });
  });

  group('SoundModeScorer — word-hypothesis-only approximation path '
      '(engine exposes no phones; G2P phonetic-distance scoring)', () {
    // Same "cat sat" drilling-T fixture as the phone-path group; the
    // words' G2P is pinned in word_matcher_test.dart (cat -> K,AE,T,
    // sat -> S,AE,T), so both paths see identical sequences.
    SoundModeScorer scorer() => SoundModeScorer(
          targetPhonemeSequence: const ['K', 'AE', 'T', 'S', 'AE', 'T'],
          targetPhonemeId: 'T',
        );

    test('POSITIVE: word-only hypotheses covering the sequence accept', () {
      final s = scorer();
      s.onHypothesis(_wordOnly('cat'));
      s.onHypothesis(_wordOnly('sat'));

      expect(s.accepted, isTrue);
    });

    test('NEGATIVE: word-only hypotheses covering half the sequence '
        '(weight 4 of 8) reject', () {
      final s = scorer();
      s.onHypothesis(_wordOnly('cat'));

      expect(s.accepted, isFalse);
    });

    test('POSITIVE: approximation path produces verdicts equivalent to '
        'the phone path on the fixture cases', () {
      final fixtures = <({List<Hypothesis> phonePath, List<Hypothesis> wordPath})>[
        (
          phonePath: [_phones(['K', 'AE', 'T']), _phones(['S', 'AE', 'T'])],
          wordPath: [_wordOnly('cat'), _wordOnly('sat')],
        ),
        (
          phonePath: [_phones(['K', 'AE', 'T'])],
          wordPath: [_wordOnly('cat')],
        ),
        (
          phonePath: <Hypothesis>[],
          wordPath: <Hypothesis>[],
        ),
      ];

      for (final f in fixtures) {
        final phoneScorer = scorer();
        f.phonePath.forEach(phoneScorer.onHypothesis);
        final wordScorer = scorer();
        f.wordPath.forEach(wordScorer.onHypothesis);

        expect(wordScorer.accepted, phoneScorer.accepted,
            reason: 'the two paths must agree on fixture '
                '${f.wordPath.map((h) => h.wordHypotheses).toList()}');
      }
    });
  });

  group('SoundModeScorer — degenerate inputs', () {
    test('EDGE: an empty hypothesis (no words, no phones) neither throws '
        'nor changes the score', () {
      final s = SoundModeScorer(
        targetPhonemeSequence: const ['S', 'IY'],
        targetPhonemeId: 'S',
      );
      expect(
        () => s.onHypothesis(
            const Hypothesis(wordHypotheses: [], phoneHypotheses: null)),
        returnsNormally,
      );
      expect(s.matchedFraction, 0.0);
      expect(s.accepted, isFalse);
    });

    test('EDGE: an empty phone list on a hypothesis contributes nothing '
        'and never throws', () {
      final s = SoundModeScorer(
        targetPhonemeSequence: const ['S', 'IY'],
        targetPhonemeId: 'S',
      );
      expect(
        () => s.onHypothesis(const Hypothesis(
            wordHypotheses: ['blah'], phoneHypotheses: [])),
        returnsNormally,
      );
      expect(s.accepted, isFalse);
    });
  });
}

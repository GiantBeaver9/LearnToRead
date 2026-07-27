/// Contract tests for self-correction and repeat handling (PRD §8 Unit 4,
/// pinned: "Self-corrections and repeats always accepted").
///
/// Pinned semantics under test:
///   - Self-correction: a wrong attempt (reject) followed by a correct or
///     close-enough production accepts the word normally — earlier rejects
///     never poison the word.
///   - Repeat: a hypothesis re-producing the most recently accepted word is
///     neither a new acceptance (no double-advance) nor a reject (must not
///     feed struggle detection, A-12a). State never regresses.
///
/// Fixture sentence: cat sun fish — adjacent words are pairwise phoneme
/// distance 3, so a repeated previous word can never be mistaken for a
/// near-miss of the current word.
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

Hypothesis _word(String w) =>
    Hypothesis(wordHypotheses: [w], phoneHypotheses: null);

void main() {
  group('WordMatcher — self-correction', () {
    test('POSITIVE: wrong attempt then the correct word — the correction '
        'is accepted exact and advances', () {
      final m = WordMatcher(sentence: [_cat, _sun, _fish]);

      final wrong = m.onHypothesis(_word('dog'));
      expect(wrong.single.kind, MatchKind.reject);
      expect(m.currentIndex, 0);

      final corrected = m.onHypothesis(_word('cat'));
      expect(corrected.single.kind, MatchKind.exact);
      expect(corrected.single.wordIndex, 0);
      expect(m.currentIndex, 1,
          reason: 'the earlier reject must not poison the word');
    });

    test('POSITIVE: wrong attempt then a close-enough production — the '
        'near-miss self-correction is accepted', () {
      final m = WordMatcher(sentence: [_cat, _sun, _fish]);

      m.onHypothesis(_word('dog'));
      final corrected = m.onHypothesis(_word('gat'));

      expect(corrected.single.kind, MatchKind.nearMiss);
      expect(corrected.single.wordIndex, 0);
      expect(m.currentIndex, 1);
    });

    test('POSITIVE: multiple wrong attempts then the correct word — still '
        'accepted (each failed burst was reported reject for struggle '
        'detection, none blocks the correction)', () {
      final m = WordMatcher(sentence: [_cat, _sun, _fish]);

      expect(m.onHypothesis(_word('dog')).single.kind, MatchKind.reject);
      expect(m.onHypothesis(_word('zubzub')).single.kind, MatchKind.reject);
      expect(m.currentIndex, 0);

      expect(m.onHypothesis(_word('cat')).single.kind, MatchKind.exact);
      expect(m.currentIndex, 1);
    });
  });

  group('WordMatcher — repeats of an already-accepted word', () {
    test('POSITIVE: repeating the just-accepted word neither advances nor '
        'rejects (no double-advance, no struggle signal)', () {
      final m = WordMatcher(sentence: [_cat, _sun, _fish]);
      m.onHypothesis(_word('cat'));
      expect(m.currentIndex, 1);

      final repeat = m.onHypothesis(_word('cat'));

      expect(repeat.where((r) => r.kind == MatchKind.reject), isEmpty,
          reason: 'a repeat is not a failed attempt at the current word; a '
              'reject here would wrongly count toward struggleDetected');
      expect(repeat.where((r) => r.kind != MatchKind.reject), isEmpty,
          reason: 'a repeat must not mint a second acceptance');
      expect(m.currentIndex, 1, reason: 'no double-advance');
    });

    test('NEGATIVE: repeating the accepted word many times never '
        'double-advances', () {
      final m = WordMatcher(sentence: [_cat, _sun, _fish]);
      m.onHypothesis(_word('cat'));

      m.onHypothesis(_word('cat'));
      m.onHypothesis(_word('cat'));
      m.onHypothesis(_word('cat'));

      expect(m.currentIndex, 1);
    });

    test('NEGATIVE: state never regresses — currentIndex is monotonic '
        'across a mixed script of rejects, accepts, and repeats', () {
      final m = WordMatcher(sentence: [_cat, _sun, _fish]);
      final script = ['dog', 'cat', 'cat', 'zubzub', 'sun', 'sun', 'fish'];

      var lastIndex = m.currentIndex;
      for (final w in script) {
        m.onHypothesis(_word(w));
        expect(m.currentIndex, greaterThanOrEqualTo(lastIndex),
            reason: 'currentIndex regressed after "$w"');
        lastIndex = m.currentIndex;
      }
      expect(m.isComplete, isTrue);
    });

    test('POSITIVE: reading resumes normally after a repeat — the next '
        'target still accepts', () {
      final m = WordMatcher(sentence: [_cat, _sun, _fish]);
      m.onHypothesis(_word('cat'));
      m.onHypothesis(_word('cat')); // repeat, no-op

      final next = m.onHypothesis(_word('sun'));

      expect(next.single.kind, MatchKind.exact);
      expect(next.single.wordIndex, 1);
      expect(m.currentIndex, 2);
    });

    test('EDGE: repeating the final word after completion keeps the '
        'matcher complete and unchanged', () {
      final m = WordMatcher(sentence: [_cat, _sun, _fish]);
      m.onHypothesis(_word('cat'));
      m.onHypothesis(_word('sun'));
      m.onHypothesis(_word('fish'));
      expect(m.isComplete, isTrue);

      final repeat = m.onHypothesis(_word('fish'));

      expect(repeat.where((r) => r.kind != MatchKind.reject), isEmpty);
      expect(m.currentIndex, 3);
      expect(m.isComplete, isTrue);
    });
  });

  group('WordMatcher — full-flow integration (hesitant but successful '
      'read)', () {
    test('POSITIVE: script [dog, cat, cat, zubzub, sun, fish] completes '
        'with accepted indices [0, 1, 2] in order and exactly two '
        'rejects', () {
      final m = WordMatcher(sentence: [_cat, _sun, _fish]);
      final all = <MatchResult>[];
      for (final w in ['dog', 'cat', 'cat', 'zubzub', 'sun', 'fish']) {
        all.addAll(m.onHypothesis(_word(w)));
      }

      final acceptedIndices = all
          .where((r) => r.kind != MatchKind.reject)
          .map((r) => r.wordIndex)
          .toList();
      expect(acceptedIndices, [0, 1, 2],
          reason: 'each word accepted exactly once, in reading order — '
              'the repeated "cat" must not appear twice');

      final rejects = all.where((r) => r.kind == MatchKind.reject).toList();
      expect(rejects, hasLength(2),
          reason: '"dog" and "zubzub" are the only struggle-relevant '
              'bursts; the repeat must not have produced a third');
      for (final r in rejects) {
        expect(r.phonemeDistance, isNotNull);
      }

      expect(m.isComplete, isTrue);
    });
  });
}

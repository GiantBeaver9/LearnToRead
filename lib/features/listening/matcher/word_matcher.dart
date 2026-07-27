/// Word-mode hybrid matcher (PRD §8 Unit 4, ticket word-matcher).
///
/// The core close-enough matching layer: the matcher always knows the target
/// sentence (expected-text hybrid recognition, KidSpeak-style) and scores
/// engine hypotheses against the known next word — never open-ended
/// transcription. Fully headless: inputs are [Hypothesis] strings, outputs
/// are typed [MatchResult]s; emitting tracker events is listening-tracker's
/// job.
///
/// Policy summary (pinned; see docs/word-matcher.md for the full behavior
/// spec including the orchestrator-pinned defaults):
/// - Exact: hypothesis textually equal to the target (case/punctuation-
///   insensitive) — or phonetically identical (distance 0, homophones).
/// - Near-miss: phoneme edit distance vs the target's AUTHORED
///   `graphemePhonemeMap` phonemes within the tuning threshold (at most
///   [maxSubstitutedPhonemesShortWord] for words of up to
///   [shortWordMaxPhonemes] phonemes, [maxSubstitutedPhonemesLongWord] for
///   longer words). Accepted, distinguishable from exact.
/// - Lookahead 1 with back-fill: a hypothesis that fails the current word
///   but matches the next accepts BOTH — current emitted first, graded
///   exact with a null distance (it was never directly heard).
/// - Self-corrections always accepted; repeats of the most recently
///   accepted word are non-events (neither acceptance nor reject).
/// - Anything else is a reject carrying the failed distance (minimum
///   across hypothesis candidates) for struggle detection.
///
/// Thresholds default to the constants in lib/domain/tuning.dart and are
/// injectable for tests/pilot tuning — never hardcoded here.
library;

import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/tuning.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/matcher/grapheme_to_phoneme.dart';
import 'package:learn_to_read/features/listening/matcher/match_result.dart';
import 'package:learn_to_read/features/listening/matcher/phoneme_distance.dart';

/// Strips a word to its comparable core: lowercase letters only.
/// "Sun." → "sun", '"cat,"' → "cat", "!!!" → "".
String _normalize(String word) =>
    word.toLowerCase().replaceAll(RegExp('[^a-z]'), '');

/// One scoreable production extracted from a hypothesis burst.
class _Candidate {
  _Candidate({required this.text, required this.phonemes});

  /// Normalized (lowercase, letters-only) hypothesis text.
  final String text;

  /// Phoneme sequence to score with: engine phones when the engine supplied
  /// them for this candidate, else the comparison G2P of [text].
  final List<String> phonemes;
}

/// Internal grade of a burst against one target word.
class _Score {
  _Score({required this.kind, required this.distance});

  final MatchKind kind;
  final int distance;
}

/// Stateful word-mode matcher for one sentence read.
///
/// Feed every finalized engine [Hypothesis] to [onHypothesis]; consume the
/// returned [MatchResult]s in order. [currentIndex] is the next expected
/// word (== sentence length when [isComplete]).
class WordMatcher {
  /// Creates a matcher for [sentence]. Threshold parameters default to the
  /// tuning-file constants (single source of truth); inject overrides only
  /// for tests or pilot experiments.
  WordMatcher({
    required List<WordToken> sentence,
    this.shortWordMaxPhonemes = kWordModeShortWordMaxPhonemes,
    this.maxSubstitutedPhonemesShortWord =
        kWordModeMaxSubstitutedPhonemesShortWord,
    this.maxSubstitutedPhonemesLongWord =
        kWordModeMaxSubstitutedPhonemesLongWord,
  }) : _sentence = List.unmodifiable(sentence);

  final List<WordToken> _sentence;

  /// A target of at most this many phonemes is "short" (inclusive boundary)
  /// and uses [maxSubstitutedPhonemesShortWord]; longer targets use
  /// [maxSubstitutedPhonemesLongWord].
  final int shortWordMaxPhonemes;

  /// Near-miss distance ceiling for short targets.
  final int maxSubstitutedPhonemesShortWord;

  /// Near-miss distance ceiling for long targets.
  final int maxSubstitutedPhonemesLongWord;

  int _currentIndex = 0;

  /// Index of the next expected word; equals the sentence length once the
  /// read is complete. Monotonically non-decreasing.
  int get currentIndex => _currentIndex;

  /// True once every word in the sentence has been accepted (immediately
  /// true for an empty sentence).
  bool get isComplete => _currentIndex >= _sentence.length;

  /// Scores one finalized hypothesis burst.
  ///
  /// Returns results in emission order (a back-fill emits the confirmed
  /// current word before the heard next word). Returns an empty list for
  /// non-speech junk (empty/punctuation-only candidates), repeats of the
  /// most recently accepted word, and anything arriving after completion —
  /// none of which may feed struggle detection (A-12a).
  List<MatchResult> onHypothesis(Hypothesis h) {
    if (isComplete) return const [];

    final candidates = _extractCandidates(h);
    if (candidates.isEmpty) return const [];

    // 1. Current word first. Orchestrator-pinned default 2 (REVISED during
    //    listening-tracker integration): a current-word EXACT always wins;
    //    a current-word near-miss yields to an EXACT match of the next word
    //    (the PRD's ratified lookahead back-fill: an exact production of the
    //    next word is stronger evidence than a near-miss of the current one,
    //    e.g. "sat" while the cursor is on "cat"). A near-miss of the next
    //    word never outranks a near-miss of the current.
    final current = _score(_sentence[_currentIndex], candidates);
    if (current.kind == MatchKind.exact) {
      final index = _currentIndex;
      _currentIndex += 1;
      return [
        MatchResult(
          kind: current.kind,
          wordIndex: index,
          phonemeDistance: current.distance,
        ),
      ];
    }
    if (current.kind == MatchKind.nearMiss) {
      final hasNext = _currentIndex + 1 < _sentence.length;
      final nextExact = hasNext &&
          _score(_sentence[_currentIndex + 1], candidates).kind ==
              MatchKind.exact;
      if (!nextExact) {
        final index = _currentIndex;
        _currentIndex += 1;
        return [
          MatchResult(
            kind: current.kind,
            wordIndex: index,
            phonemeDistance: current.distance,
          ),
        ];
      }
      // Fall through to the lookahead branch: the next word matched exactly,
      // so back-fill the current word as correct.
    }

    // 2. Lookahead 1 with back-fill: hearing the next word confirms the
    //    current one. Depth is exactly 1 — currentIndex+2 is never consulted.
    if (_currentIndex + 1 < _sentence.length) {
      final next = _score(_sentence[_currentIndex + 1], candidates);
      if (next.kind != MatchKind.reject) {
        final index = _currentIndex;
        _currentIndex += 2;
        return [
          // Back-filled current word: graded exact (tracker routes it to
          // plain wordAccepted), distance null — it was never heard itself.
          MatchResult(kind: MatchKind.exact, wordIndex: index),
          MatchResult(
            kind: next.kind,
            wordIndex: index + 1,
            phonemeDistance: next.distance,
          ),
        ];
      }
    }

    // 3. Repeat of the most recently accepted word (orchestrator-pinned
    //    default 5: reaches back exactly one accepted word; near-miss-shaped
    //    repeats are likewise non-events). Not a new acceptance, not a
    //    reject — must not feed struggle detection.
    if (_currentIndex > 0) {
      final previous = _score(_sentence[_currentIndex - 1], candidates);
      if (previous.kind != MatchKind.reject) return const [];
    }

    // 4. Reject, attributed to the current word, carrying the failed
    //    distance (minimum across candidates — pinned default 4).
    return [
      MatchResult(
        kind: MatchKind.reject,
        wordIndex: _currentIndex,
        phonemeDistance: current.distance,
      ),
    ];
  }

  /// Splits a hypothesis burst into scoreable candidates.
  ///
  /// Every word hypothesis is whitespace-split into individual tokens
  /// (pinned default 7) and normalized; tokens with no letters are dropped
  /// (non-speech, not rejectable). Engine phones, when present, belong to
  /// the top word hypothesis — they are attached to its candidate only when
  /// that hypothesis is a single token; every other candidate is scored via
  /// the comparison G2P of its own text.
  List<_Candidate> _extractCandidates(Hypothesis h) {
    final candidates = <_Candidate>[];
    for (var wi = 0; wi < h.wordHypotheses.length; wi++) {
      final tokens = h.wordHypotheses[wi]
          .split(RegExp(r'\s+'))
          .map(_normalize)
          .where((t) => t.isNotEmpty)
          .toList();
      final phones = h.phoneHypotheses;
      final phonesApply =
          wi == 0 && tokens.length == 1 && phones != null && phones.isNotEmpty;
      for (final token in tokens) {
        candidates.add(
          _Candidate(
            text: token,
            // Flow analysis promotes `phones` to non-null through
            // `phonesApply` (it is only true when phones != null).
            phonemes: phonesApply
                ? List<String>.unmodifiable(phones)
                : graphemesToPhonemes(token),
          ),
        );
      }
    }
    return candidates;
  }

  /// Grades a burst against one target word: exact if any candidate is the
  /// target textually or at phoneme distance 0 (homophones — pinned default
  /// 3); near-miss if the best distance is within the target's threshold;
  /// else reject with the best (minimum) failed distance.
  _Score _score(WordToken target, List<_Candidate> candidates) {
    final targetText = _normalize(target.text);
    final targetPhonemes = [
      for (final entry in target.graphemePhonemeMap) entry.phonemeId,
    ];
    final threshold = targetPhonemes.length <= shortWordMaxPhonemes
        ? maxSubstitutedPhonemesShortWord
        : maxSubstitutedPhonemesLongWord;

    var best = -1;
    for (final candidate in candidates) {
      if (candidate.text == targetText) {
        return _Score(kind: MatchKind.exact, distance: 0);
      }
      final d = phonemeEditDistance(candidate.phonemes, targetPhonemes);
      if (d == 0) return _Score(kind: MatchKind.exact, distance: 0);
      if (best < 0 || d < best) best = d;
    }
    if (best >= 1 && best <= threshold) {
      return _Score(kind: MatchKind.nearMiss, distance: best);
    }
    return _Score(kind: MatchKind.reject, distance: best);
  }
}

/// Decodability linter (PRD §8 Unit 3 pinned design: "the decodability
/// linter ... rejects any story containing a word not decodable from the
/// cumulative grapheme set at its level, unless whitelisted as a heart word
/// for that level"; §6 content decodability constraint; §7 R5; §8 Unit 14
/// twister exemption; §5 `PhonicsSkill.introducesGraphemes`).
///
/// A build-time, pure-function lint: `Story`/`TongueTwister` plus
/// scope-&-sequence data (`levels`) and a heart-word whitelist in, findings
/// out -- no I/O in this file. Usable by both the pack-build CLI and tests.
/// Findings are aggregated across the whole input rather than failing fast
/// on the first problem, matching this codebase's existing
/// `PackManifestValidationResult` convention.
library;

import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/pipeline/cumulative_grapheme_set.dart';

/// The kind of lint problem a [DecodabilityFinding] reports.
enum DecodabilityFindingKind {
  /// A story word is not decodable from the cumulative grapheme set at its
  /// level and is not whitelisted as a heart word there.
  outOfLevelWord,

  /// A-8: the story's total word count falls outside the bound for its
  /// level's format.
  wordCountBounds,

  /// A-8: a paragraph-format story's page count falls outside
  /// `[kParagraphLevelMinPages, kParagraphLevelMaxPages]`.
  pageCountBounds,
}

/// One decodability-lint problem found in a story.
class DecodabilityFinding {
  const DecodabilityFinding({
    required this.kind,
    required this.storyId,
    required this.levelId,
    required this.message,
    this.word,
    this.outOfLevelGraphemes = const [],
  });

  final DecodabilityFindingKind kind;
  final String storyId;
  final String levelId;

  /// Set (== `WordToken.text`) for [DecodabilityFindingKind.outOfLevelWord]
  /// findings, `null` otherwise.
  final String? word;

  /// The grapheme units from the word's `graphemePhonemeMap` absent from the
  /// cumulative grapheme set. Set for
  /// [DecodabilityFindingKind.outOfLevelWord] findings, `[]` otherwise.
  final List<String> outOfLevelGraphemes;

  /// Human-readable description of the finding.
  final String message;

  @override
  String toString() =>
      'DecodabilityFinding(kind: $kind, storyId: $storyId, levelId: $levelId, '
      'word: $word, outOfLevelGraphemes: $outOfLevelGraphemes, message: $message)';
}

/// Resolves [levelId] against [levels] by `Level.id`, throwing
/// [ArgumentError] when no level matches.
Level _resolveLevel(List<Level> levels, String levelId) {
  for (final level in levels) {
    if (level.id == levelId) return level;
  }
  throw ArgumentError.value(
    levelId,
    'levelId',
    'does not match any Level.id in `levels`',
  );
}

/// The cumulative heart-word set at [target]'s level: the union of
/// `heartWordsByLevelId[level.id]` (defaulting to `[]` when a level has no
/// entry in the map) over every level in [levels] whose `ordinal <=
/// target.ordinal` -- so a heart word tagged at level N is honored at level
/// N and above, not below (mirrors the grapheme cumulative-union rule).
Set<String> _cumulativeHeartWords({
  required List<Level> levels,
  required Level target,
  required Map<String, List<String>> heartWordsByLevelId,
}) {
  final words = <String>{};
  for (final level in levels) {
    if (level.ordinal > target.ordinal) continue;
    words.addAll(heartWordsByLevelId[level.id] ?? const []);
  }
  return words;
}

/// Lints every word of every sentence of every page of [story] against the
/// cumulative grapheme set (and cumulative heart-word whitelist) at its
/// resolved level, and checks A-8 word/page length bounds for that level's
/// `format`. Findings are aggregated, never fail-fast.
///
/// Throws [ArgumentError] when `story.levelId` matches no level in [levels].
List<DecodabilityFinding> lintStory(
  Story story, {
  required List<Level> levels,
  required Map<String, List<String>> heartWordsByLevelId,
}) {
  final level = _resolveLevel(levels, story.levelId);
  final graphemeSet = cumulativeGraphemeSet(
    levels: levels,
    levelId: level.id,
  );
  final heartWords = _cumulativeHeartWords(
    levels: levels,
    target: level,
    heartWordsByLevelId: heartWordsByLevelId,
  );

  final findings = <DecodabilityFinding>[];

  var totalWords = 0;
  for (final page in story.pages) {
    for (final sentence in page.sentences) {
      for (final word in sentence.words) {
        totalWords++;
        if (heartWords.contains(word.text)) continue;

        final outOfLevel = <String>[];
        for (final entry in word.graphemePhonemeMap) {
          if (!graphemeSet.contains(entry.graphemes)) {
            outOfLevel.add(entry.graphemes);
          }
        }
        if (outOfLevel.isNotEmpty) {
          findings.add(
            DecodabilityFinding(
              kind: DecodabilityFindingKind.outOfLevelWord,
              storyId: story.id,
              levelId: story.levelId,
              word: word.text,
              outOfLevelGraphemes: outOfLevel,
              message:
                  'word "${word.text}" in story "${story.id}" uses '
                  'grapheme(s) ${outOfLevel.join(', ')} not yet introduced '
                  'at level "${story.levelId}" and not whitelisted as a '
                  'heart word there',
            ),
          );
        }
      }
    }
  }

  switch (level.format) {
    case LevelFormat.sentence:
      if (totalWords < kSentenceLevelMinWords ||
          totalWords > kSentenceLevelMaxWords) {
        findings.add(
          DecodabilityFinding(
            kind: DecodabilityFindingKind.wordCountBounds,
            storyId: story.id,
            levelId: story.levelId,
            message:
                'story "${story.id}" has $totalWords word(s); '
                'sentence-format levels require '
                '$kSentenceLevelMinWords-$kSentenceLevelMaxWords (A-8)',
          ),
        );
      }
    case LevelFormat.paragraph:
      if (totalWords < kParagraphLevelMinWords ||
          totalWords > kParagraphLevelMaxWords) {
        findings.add(
          DecodabilityFinding(
            kind: DecodabilityFindingKind.wordCountBounds,
            storyId: story.id,
            levelId: story.levelId,
            message:
                'story "${story.id}" has $totalWords word(s); '
                'paragraph-format levels require '
                '$kParagraphLevelMinWords-$kParagraphLevelMaxWords (A-8)',
          ),
        );
      }
      final pageCount = story.pages.length;
      if (pageCount < kParagraphLevelMinPages ||
          pageCount > kParagraphLevelMaxPages) {
        findings.add(
          DecodabilityFinding(
            kind: DecodabilityFindingKind.pageCountBounds,
            storyId: story.id,
            levelId: story.levelId,
            message:
                'story "${story.id}" has $pageCount page(s); '
                'paragraph-format levels require '
                '$kParagraphLevelMinPages-$kParagraphLevelMaxPages (A-8)',
          ),
        );
      }
    case LevelFormat.multiSentence:
      // No length bound is defined in the domain models for
      // multiSentence-format levels; no bounds finding is ever produced.
      break;
  }

  return findings;
}

/// TongueTwisters are wholly exempt from decodability and length-bounds
/// linting (Unit 14 pinned: "modeled-first content may use above-level
/// words"). Always returns `const []`, even when `twister.levelId` cannot be
/// resolved against [levels] at all.
List<DecodabilityFinding> lintTwister(
  TongueTwister twister, {
  required List<Level> levels,
  required Map<String, List<String>> heartWordsByLevelId,
}) {
  return const [];
}

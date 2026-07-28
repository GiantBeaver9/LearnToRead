/// Example-word filtering, highlighting, and the tappable word chip (PRD
/// §8 Unit 15 "Example words appear based on the student's capability
/// (ratified)"; ticket sound-garden accept entries 6, 7, 8).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';

/// Resolves [levelId] against [levels] by `Level.id`, same idiom as
/// `sound_card_controller.dart`'s `wakeStateFor`. Throws [ArgumentError]
/// when no level in [levels] carries that id.
Level _resolveLevel(List<Level> levels, String levelId) {
  return levels.firstWhere(
    (level) => level.id == levelId,
    orElse: () => throw ArgumentError.value(
      levelId,
      'levelId',
      'does not match any Level.id in `levels`',
    ),
  );
}

/// Filters `card.exampleWords`, preserving authored order, to exactly the
/// entries where BOTH:
///  - the word's `minLevelId` ordinal is <= `profile.currentLevelId`'s
///    ordinal (INCLUSIVE -- PRD: "a word appears on the card only when the
///    profile's level >= its minLevelId"), AND
///  - `downloadedAudioRefs.contains(entry.pronunciationAudioRef)` -- PRD:
///    "a card with no downloaded example-word audio shows the words it has
///    audio for."
List<({String wordText, String pronunciationAudioRef, String minLevelId})> visibleExampleWords({
  required GraphemeSound card,
  required Profile profile,
  required List<Level> levels,
  required Set<AudioRef> downloadedAudioRefs,
}) {
  final profileOrdinal = _resolveLevel(levels, profile.currentLevelId).ordinal;
  return [
    for (final word in card.exampleWords)
      if (_resolveLevel(levels, word.minLevelId).ordinal <= profileOrdinal &&
          downloadedAudioRefs.contains(word.pronunciationAudioRef))
        word,
  ];
}

/// The `[start, end)` character range within [wordText] where [grapheme]
/// FIRST occurs, case-insensitively; null if [grapheme] does not occur at
/// all. When [grapheme] occurs more than once, the FIRST occurrence (lowest
/// `start`) is pinned.
({int start, int end})? highlightRangeFor({
  required String wordText,
  required String grapheme,
}) {
  final index = wordText.toLowerCase().indexOf(grapheme.toLowerCase());
  if (index == -1) return null;
  return (start: index, end: index + grapheme.length);
}

/// Renders [wordText] with the [highlightRangeFor] span visually
/// distinguished; tapping plays [pronunciationAudioRef] via [audioService]
/// (channel: [AudioChannel.help], the same channel word pronunciation audio
/// uses elsewhere -- see `lib/features/help/near_miss_prompt.dart`).
///
/// Structural markers (id-free -- one chip per [wordText], which is unique
/// within one card's visible list):
///   - `ValueKey('example-word-<wordText>')`            the tap target.
///   - `ValueKey('example-word-highlight-<wordText>')`  wraps ONLY the
///     highlighted substring; its descendant `Text.data` == the substring
///     [highlightRangeFor] names (original casing preserved).
class ExampleWordChip extends StatelessWidget {
  const ExampleWordChip({
    super.key,
    required this.wordText,
    required this.grapheme,
    required this.pronunciationAudioRef,
    required this.audioService,
  });

  final String wordText;
  final String grapheme;
  final AudioRef pronunciationAudioRef;
  final AudioService audioService;

  static const TextStyle _wordStyle = TextStyle(
    fontFamily: DesignTokens.readingFontFamily,
    fontSize: 16,
    color: DesignTokens.wordUnreadInk,
  );

  static const TextStyle _highlightStyle = TextStyle(
    fontFamily: DesignTokens.readingFontFamily,
    fontSize: 16,
    fontWeight: FontWeight.bold,
    color: DesignTokens.wordVocabBlue,
  );

  @override
  Widget build(BuildContext context) {
    final range = highlightRangeFor(wordText: wordText, grapheme: grapheme);
    final children = <Widget>[];

    if (range == null) {
      children.add(Text(wordText, style: _wordStyle));
    } else {
      if (range.start > 0) {
        children.add(Text(wordText.substring(0, range.start), style: _wordStyle));
      }
      children.add(KeyedSubtree(
        key: ValueKey('example-word-highlight-$wordText'),
        child: Text(wordText.substring(range.start, range.end), style: _highlightStyle),
      ));
      if (range.end < wordText.length) {
        children.add(Text(wordText.substring(range.end), style: _wordStyle));
      }
    }

    return GestureDetector(
      key: ValueKey('example-word-$wordText'),
      onTap: () => unawaited(audioService.play(pronunciationAudioRef, channel: AudioChannel.help)),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingSm,
          vertical: DesignTokens.spacingXs,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

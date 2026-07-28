// Test suite for lib/features/sound_garden/example_words.dart (PRD §8 Unit
// 15 "Example words appear based on the student's capability (ratified)";
// ticket sound-garden accept entries 6, 7, 8).
//
// lib/features/sound_garden/example_words.dart does not exist yet: every
// import below fails to resolve, which is the expected red state.
//
// See sound_garden_screen_test.dart for the canonical pinned API. This file
// restates and is the authority for example_words.dart's own contract:
//
//   /// Filters `card.exampleWords`, preserving authored order, to exactly
//   /// the entries where BOTH:
//   ///   - the word's `minLevelId` ordinal <= `profile.currentLevelId`'s
//   ///     ordinal (INCLUSIVE -- PRD: "a word appears on the card only
//   ///     when the profile's level >= its minLevelId"), AND
//   ///   - `downloadedAudioRefs.contains(entry.pronunciationAudioRef)` --
//   ///     PRD: "a card with no downloaded example-word audio shows the
//   ///     words it has audio for."
//   /// Ordinals resolved via `levels.firstWhere((l) => l.id == ...)`,
//   /// same idiom as sound_card_controller.dart's wakeStateFor.
//   List<({String wordText, String pronunciationAudioRef, String minLevelId})>
//       visibleExampleWords({
//     required GraphemeSound card,
//     required Profile profile,
//     required List<Level> levels,
//     required Set<AudioRef> downloadedAudioRefs,
//   });
//
//   /// The [start, end) character range within `wordText` where `grapheme`
//   /// FIRST occurs, case-insensitively; null if `grapheme` does not occur
//   /// at all. When `grapheme` occurs more than once, the FIRST occurrence
//   /// (lowest `start`) is pinned.
//   ({int start, int end})? highlightRangeFor({
//     required String wordText,
//     required String grapheme,
//   });
//
//   /// Renders `wordText` with the `highlightRangeFor` span visually
//   /// distinguished; tapping plays `pronunciationAudioRef` via
//   /// `audioService` (channel: AudioChannel.help, same channel word
//   /// pronunciation audio uses elsewhere -- see
//   /// lib/features/help/near_miss_prompt.dart).
//   ///
//   /// Structural markers (id-free -- one chip per wordText, which is
//   /// unique within one card's visible list):
//   ///   - ValueKey('example-word-<wordText>')            the tap target
//   ///   - ValueKey('example-word-highlight-<wordText>')  wraps ONLY the
//   ///     highlighted substring; its descendant Text.data == the
//   ///     substring `highlightRangeFor` names (original casing preserved)
//   class ExampleWordChip extends StatelessWidget {
//     const ExampleWordChip({
//       super.key,
//       required String wordText,
//       required String grapheme,
//       required AudioRef pronunciationAudioRef,
//       required AudioService audioService,
//     });
//   }
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/sound_garden/example_words.dart';

List<Level> _levels() => [
      for (var i = 1; i <= 5; i++)
        Level(
          id: 'level.$i',
          ordinal: i,
          newSkills: const [],
          format: LevelFormat.sentence,
          vocabEnabled: false,
        ),
    ];

Profile _profile(String currentLevelId) => Profile(
      localId: 'profile.amara',
      displayName: 'Amara',
      ageBand: AgeBand.fiveToSix,
      currentLevelId: currentLevelId,
      micConsent: true,
      cloudAsrConsent: false,
      createdAt: DateTime(2026, 1, 1),
    );

GraphemeSound _cardWithWords(
  List<({String wordText, String pronunciationAudioRef, String minLevelId})> words,
) =>
    GraphemeSound(
      id: 'gs.sh',
      grapheme: 'sh',
      phonemeIds: const ['SH'],
      introducedAtLevelId: 'level.1',
      exampleWords: words,
    );

void main() {
  group('visibleExampleWords — level filtering exactness (accept 6)', () {
    final words = [
      (wordText: 'ship', pronunciationAudioRef: 'audio/words/ship.mp3', minLevelId: 'level.1'),
      (wordText: 'wish', pronunciationAudioRef: 'audio/words/wish.mp3', minLevelId: 'level.2'),
      (wordText: 'shrimp', pronunciationAudioRef: 'audio/words/shrimp.mp3', minLevelId: 'level.3'),
    ];
    final allAudioDownloaded = words.map((w) => w.pronunciationAudioRef).toSet();

    test('POSITIVE: at level.1, only the level.1 word is visible', () {
      final visible = visibleExampleWords(
        card: _cardWithWords(words),
        profile: _profile('level.1'),
        levels: _levels(),
        downloadedAudioRefs: allAudioDownloaded,
      );
      expect(visible.map((w) => w.wordText), ['ship']);
    });

    test('EDGE: at level.2, the level.2 word is visible (INCLUSIVE '
        'boundary: minLevelId == profile level)', () {
      final visible = visibleExampleWords(
        card: _cardWithWords(words),
        profile: _profile('level.2'),
        levels: _levels(),
        downloadedAudioRefs: allAudioDownloaded,
      );
      expect(visible.map((w) => w.wordText), ['ship', 'wish']);
    });

    test('POSITIVE: level-rise adds words -- level.3 shows all three, in '
        'authored order', () {
      final visible = visibleExampleWords(
        card: _cardWithWords(words),
        profile: _profile('level.3'),
        levels: _levels(),
        downloadedAudioRefs: allAudioDownloaded,
      );
      expect(visible.map((w) => w.wordText), ['ship', 'wish', 'shrimp']);
    });

    test('POSITIVE: level-rise is monotone -- every word visible at a '
        'lower level remains visible at a higher one', () {
      final atLevel2 = visibleExampleWords(
        card: _cardWithWords(words),
        profile: _profile('level.2'),
        levels: _levels(),
        downloadedAudioRefs: allAudioDownloaded,
      ).map((w) => w.wordText).toSet();
      final atLevel5 = visibleExampleWords(
        card: _cardWithWords(words),
        profile: _profile('level.5'),
        levels: _levels(),
        downloadedAudioRefs: allAudioDownloaded,
      ).map((w) => w.wordText).toSet();
      expect(atLevel5.containsAll(atLevel2), isTrue);
    });

    test('EDGE: an empty exampleWords list produces an empty visible list, '
        'not an error', () {
      final visible = visibleExampleWords(
        card: _cardWithWords(const []),
        profile: _profile('level.5'),
        levels: _levels(),
        downloadedAudioRefs: const {},
      );
      expect(visible, isEmpty);
    });
  });

  group('visibleExampleWords — audio-present filtering (accept 8)', () {
    final words = [
      (wordText: 'ship', pronunciationAudioRef: 'audio/words/ship.mp3', minLevelId: 'level.1'),
      (wordText: 'wish', pronunciationAudioRef: 'audio/words/wish.mp3', minLevelId: 'level.1'),
      (wordText: 'shrimp', pronunciationAudioRef: 'audio/words/shrimp.mp3', minLevelId: 'level.1'),
    ];

    test('NEGATIVE: a level-eligible word whose audio was never downloaded '
        'is excluded even though it passes the level filter', () {
      final visible = visibleExampleWords(
        card: _cardWithWords(words),
        profile: _profile('level.5'),
        levels: _levels(),
        downloadedAudioRefs: {'audio/words/ship.mp3', 'audio/words/shrimp.mp3'},
      );
      expect(visible.map((w) => w.wordText), ['ship', 'shrimp']);
    });

    test('EDGE: a card with NO downloaded example-word audio at all shows '
        'an empty list, not an error (fully offline / no pack downloaded '
        'yet)', () {
      final visible = visibleExampleWords(
        card: _cardWithWords(words),
        profile: _profile('level.5'),
        levels: _levels(),
        downloadedAudioRefs: const {},
      );
      expect(visible, isEmpty);
    });

    test('POSITIVE: a card whose audio is fully downloaded shows every '
        'level-eligible word', () {
      final visible = visibleExampleWords(
        card: _cardWithWords(words),
        profile: _profile('level.5'),
        levels: _levels(),
        downloadedAudioRefs: words.map((w) => w.pronunciationAudioRef).toSet(),
      );
      expect(visible.map((w) => w.wordText), ['ship', 'wish', 'shrimp']);
    });
  });

  group('highlightRangeFor — grapheme span within the word (accept 7)', () {
    test('POSITIVE: finds the grapheme substring at its exact index', () {
      expect(highlightRangeFor(wordText: 'wish', grapheme: 'sh'), (start: 2, end: 4));
    });

    test('POSITIVE: case-insensitive match, original casing preserved by '
        'the range (not the return value itself, which is index-only)', () {
      expect(highlightRangeFor(wordText: 'Sheep', grapheme: 'sh'), (start: 0, end: 2));
    });

    test('NEGATIVE: grapheme absent from the word -> null', () {
      expect(highlightRangeFor(wordText: 'cat', grapheme: 'sh'), isNull);
    });

    test('EDGE: grapheme occurs more than once -- the FIRST occurrence is '
        'pinned', () {
      expect(highlightRangeFor(wordText: 'shush', grapheme: 'sh'), (start: 0, end: 2));
    });

    test('EDGE: a single-character grapheme (short vowel "a" in "cat") '
        'resolves to a length-1 range', () {
      expect(highlightRangeFor(wordText: 'cat', grapheme: 'a'), (start: 1, end: 2));
    });
  });

  group('ExampleWordChip — tap plays audio and highlights the grapheme '
      '(accept 7)', () {
    testWidgets('POSITIVE: tapping the chip plays pronunciationAudioRef on '
        'AudioChannel.help', (tester) async {
      final audioService = FakeAudioService();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ExampleWordChip(
            wordText: 'wish',
            grapheme: 'sh',
            pronunciationAudioRef: 'audio/words/wish.mp3',
            audioService: audioService,
          ),
        ),
      ));

      await tester.tap(find.byKey(const ValueKey('example-word-wish')));
      await tester.pump();

      final plays = audioService.callLog.whereType<PlayLogEntry>().toList();
      expect(plays, hasLength(1));
      expect(plays.single.ref, 'audio/words/wish.mp3');
      expect(plays.single.channel, AudioChannel.help);
    });

    testWidgets('POSITIVE: the highlighted grapheme substring is findable '
        'and carries exactly the grapheme text', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ExampleWordChip(
            wordText: 'wish',
            grapheme: 'sh',
            pronunciationAudioRef: 'audio/words/wish.mp3',
            audioService: FakeAudioService(),
          ),
        ),
      ));
      await tester.pump();

      final highlightFinder = find.byKey(const ValueKey('example-word-highlight-wish'));
      expect(highlightFinder, findsOneWidget);
      final textWidget = tester.widget<Text>(find.descendant(
        of: highlightFinder,
        matching: find.byType(Text),
      ));
      expect(textWidget.data, 'sh');

      // The chip's Text descendants, concatenated in tree order, must
      // reconstruct the full word -- the highlight wraps only a substring,
      // it never drops the rest of the word ("wi" + "sh" == "wish").
      final allText = tester
          .widgetList<Text>(find.descendant(
            of: find.byKey(const ValueKey('example-word-wish')),
            matching: find.byType(Text),
          ))
          .map((t) => t.data ?? '')
          .join();
      expect(allText, 'wish');
    });
  });
}

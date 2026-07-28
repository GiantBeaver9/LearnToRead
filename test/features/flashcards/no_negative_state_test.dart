// Negative-space suite for the flashcards feature (PRD §8 Unit 16 "No
// failure state: 'practice again' is amber, never red; no scores or
// streaks in v1"; acceptance "No red/error/negative state reachable
// (grep-level + widget test)").
//
// Mirrors test/features/sound_garden/no_failure_state_test.dart's split:
//  (a) behaviorally, grading "practice again" produces no negative widget
//      — the card simply comes back later, in the same warm styling;
//  (b) structurally (grep-level), no file under lib/features/flashcards/
//      names a negative/scoring concept or reaches for a red token — plus
//      a scanner self-check proving the scan can detect what it bans.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/flashcards/flashcard_deck.dart';
import 'package:learn_to_read/features/flashcards/flashcards_screen.dart';

WordToken _cat() => WordToken(
      text: 'cat',
      graphemePhonemeMap: [
        (graphemes: 'c', phonemeId: 'K'),
        (graphemes: 'a', phonemeId: 'AE'),
        (graphemes: 't', phonemeId: 'T'),
      ],
      pronunciationAudioRef: 'audio/words/cat.mp3',
    );

/// Lexemes no flashcards source may contain (lowercased scan): negative /
/// judgment concepts and the v1-banned scoring concepts.
const List<String> _bannedWords = [
  'wrong',
  'incorrect',
  'failure',
  'penalty',
  'streak',
  // v1: "no scores or streaks" — no scoring concept by any name.
  'score',
  // No red anywhere: the only red tokens are the listening-waveform pair,
  // which this feature has no business referencing.
  'listeningred',
];

List<File> _flashcardsDartFiles() {
  final dir = Directory('lib/features/flashcards');
  if (!dir.existsSync()) return const [];
  return dir
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
}

void main() {
  group('behavioral: "practice again" is warm, never negative', () {
    testWidgets('NEGATIVE: after grading practice-again, no widget key or '
        'visible text names a negative concept, and the amber pill uses the '
        'app-wide amber', (tester) async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final clock = DateTime(2026, 7, 28, 9, 0, 0);

      await tester.pumpWidget(MaterialApp(
        home: FlashcardsScreen(
          profileId: 'profile.amara',
          deck: FlashcardDeck.fromWordTokens([_cat()]),
          audioService: FakeAudioService(),
          phonemeAudioRefs: const {
            'K': 'audio/phonemes/K.mp3',
            'AE': 'audio/phonemes/AE.mp3',
            'T': 'audio/phonemes/T.mp3',
          },
          dao: db.flashcardsDao,
          now: () => clock,
          confettiSeed: 7,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final cardKey = hashWord('cat');
      // Flip via the affordance (the card's center is the word).
      await tester.tap(find.byKey(ValueKey('flashcard-flip-$cardKey')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // The amber pill carries the app-wide "saying now" amber — the same
      // family as every other amber in the app, not a warning color.
      final pillFinder = find.descendant(
        of: find.byKey(const ValueKey('flashcard-grade-practice-again')),
        matching: find.byType(Container),
      );
      final decoration =
          tester.widget<Container>(pillFinder.first).decoration! as BoxDecoration;
      expect(decoration.color, DesignTokens.wordCurrentInk);

      await tester.tap(
          find.byKey(const ValueKey('flashcard-grade-practice-again')));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // The card simply comes back; nothing judgmental appears.
      expect(find.text('cat'), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final fragment in ['wrong', 'error', 'fail', 'negative', 'red-x']) {
        expect(
          find.byWidgetPredicate((w) =>
              w.key is ValueKey<String> &&
              (w.key! as ValueKey<String>).value.contains(fragment)),
          findsNothing,
          reason: 'no widget key may name the "$fragment" concept',
        );
      }
      expect(find.textContaining('wrong', findRichText: true), findsNothing);
      expect(find.textContaining('Wrong', findRichText: true), findsNothing);
      expect(find.textContaining('Oops', findRichText: true), findsNothing);
    });
  });

  group('structural: grep-level scan of lib/features/flashcards/', () {
    test('NEGATIVE: no flashcards source contains a banned negative/scoring '
        'lexeme or a red token reference', () {
      final violations = <String>[];
      for (final file in _flashcardsDartFiles()) {
        final lower = file.readAsStringSync().toLowerCase();
        for (final banned in _bannedWords) {
          if (lower.contains(banned)) {
            violations.add('${file.path} contains "$banned"');
          }
        }
      }
      expect(_flashcardsDartFiles(), isNotEmpty,
          reason: 'the feature exists; this scan must not be vacuous');
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('POSITIVE (scanner self-check): the scan flags a fixture that DOES '
        'contain a banned lexeme', () {
      final tempDir =
          Directory.systemTemp.createTempSync('no_negative_state_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      File('${tempDir.path}/oops.dart')
          .writeAsStringSync('const label = "That was wrong!";\n');

      var violationCount = 0;
      for (final file in tempDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final lower = file.readAsStringSync().toLowerCase();
        for (final banned in _bannedWords) {
          if (lower.contains(banned)) violationCount++;
        }
      }
      expect(violationCount, greaterThan(0));
    });
  });
}

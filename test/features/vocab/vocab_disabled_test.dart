/// Pins the "no quiz/check in v1" ratification (PRD §8 Unit 7 pinned
/// design: "Opening a card logs `vocab_card_opened`. No quiz/check in v1
/// (ratified: curated cards, no mini-check)"; ticket vocab-cards accept
/// entry 5's second half).
///
/// Two accepts from the PRD Unit 7 acceptance list -- "a story with zero
/// vocab words renders no blue styling" and "a vocabEnabled=false level
/// renders vocab-tagged words in normal ink" -- are NOT re-tested here: that
/// coloring logic lives entirely in `WordState.renderColor` /
/// `WordStateMachine` (merged reading-screen/word-state-machine tickets)
/// and is already pinned by test/features/reading/word_state_machine_test.dart
/// ("vocabTappable true only when BOTH vocabCardId is set AND
/// Level.vocabEnabled") and test/features/reading/word_states_render_test.dart.
/// This ticket owns the vocab CARD, not word coloring, so this file is
/// scoped to what only the card can prove: that no quiz/scoring mechanism
/// exists anywhere in lib/features/vocab/.
///
/// Follows test/features/reading/no_negative_feedback_test.dart's
/// established two-layer pattern exactly:
///  1. A static scanner over every `.dart` file under lib/features/vocab/,
///     flagging any STRING LITERAL (never comments/identifiers) that
///     case-insensitively contains a banned quiz/scoring phrase, or the
///     whole word 'quiz'/'score' (word-boundary matched).
///  2. A widget-tree sweep over a fully opened `VocabCardPopover`
///     (lib/features/vocab/vocab_card.dart, which does not exist yet: this
///     suite fails to compile/analyze until it does -- the expected red
///     state) asserting no quiz-shaped input widget (`Radio`, `Checkbox`,
///     `Switch`, `Slider`) is anywhere in the tree, no rendered `Text`
///     carries banned copy, and the only interactive affordances present
///     are exactly the three Unit 7 pins: word-tap, replay, close (plus the
///     tap-outside barrier) -- never a fourth "submit"/"check answer"
///     control.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart' show VocabCard;
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/vocab/vocab_card.dart';

// ---------------------------------------------------------------------------
// Layer 1: the static string-literal scanner.
// ---------------------------------------------------------------------------

final RegExp _stringLiteral = RegExp(
  r"'([^'\\]*(?:\\.[^'\\]*)*)'" // matches a '...' literal
  r'|"([^"\\]*(?:\\.[^"\\]*)*)"', // matches a "..." literal
);

const List<String> _bannedPhrases = <String>[
  'multiple choice',
  'correct answer',
  'wrong answer',
  'mini-check',
  'mini check',
  'check your answer',
  'check the answer',
  "let's check",
];

final RegExp _quizWholeWord = RegExp(r'\bquiz(?:zes|zed)?\b', caseSensitive: false);
final RegExp _scoreWholeWord = RegExp(r'\bscores?\b', caseSensitive: false);

class _QuizViolation {
  _QuizViolation(this.path, this.line, this.literal, this.reason);
  final String path;
  final int line;
  final String literal;
  final String reason;

  @override
  String toString() => '$path:$line: "$literal" ($reason)';
}

/// Scans [source] line-by-line for string literals containing banned
/// quiz/scoring vocabulary. Comments and identifiers are never inspected --
/// only literal string contents.
List<_QuizViolation> _scanSource(String path, String source) {
  final violations = <_QuizViolation>[];
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    for (final match in _stringLiteral.allMatches(line)) {
      final literal = match.group(1) ?? match.group(2) ?? '';
      final lower = literal.toLowerCase();
      for (final banned in _bannedPhrases) {
        if (lower.contains(banned)) {
          violations.add(_QuizViolation(path, i + 1, literal, 'contains "$banned"'));
        }
      }
      if (_quizWholeWord.hasMatch(literal)) {
        violations.add(_QuizViolation(path, i + 1, literal, 'contains the word "quiz"'));
      }
      if (_scoreWholeWord.hasMatch(literal)) {
        violations.add(_QuizViolation(path, i + 1, literal, 'contains the word "score"'));
      }
    }
  }
  return violations;
}

List<_QuizViolation> _scanDirectory(Directory dir) {
  final violations = <_QuizViolation>[];
  if (!dir.existsSync()) return violations;
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final normalized = entity.path.replaceAll(r'\', '/');
    violations.addAll(_scanSource(normalized, entity.readAsStringSync()));
  }
  return violations;
}

// ---------------------------------------------------------------------------
// Layer 2: widget-tree sweep fixtures.
// ---------------------------------------------------------------------------

VocabCard _card({String? illustrationRef}) => VocabCard(
      id: 'vocab.gigantic',
      word: 'gigantic',
      definitionText: 'Enormous — bigger than big.',
      definitionAudioRef: 'audio/vocab/gigantic_def.mp3',
      illustrationRef: illustrationRef,
    );

Widget _harness({required VocabCard card, VoidCallback? onClosed}) {
  return MaterialApp(
    home: Scaffold(
      body: VocabCardPopover(
        card: card,
        audioService: FakeAudioService(),
        pronunciationAudioRef: 'audio/words/gigantic.mp3',
        onClosed: onClosed ?? () {},
      ),
    ),
  );
}

void main() {
  group('scanner correctness (fixtures, in a throwaway temp dir) — POSITIVE', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('vocab_disabled_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('flags the whole word "quiz" inside a string literal', () {
      File('${tempDir.path}/a.dart').writeAsStringSync("const s = 'Ready for a quiz?';\n");
      final violations = _scanDirectory(tempDir);
      expect(violations, hasLength(1));
      expect(violations.single.reason, contains('quiz'));
    });

    test('flags the whole word "score" inside a string literal', () {
      File('${tempDir.path}/b.dart').writeAsStringSync("const s = 'Your score: 3';\n");
      final violations = _scanDirectory(tempDir);
      expect(violations, hasLength(1));
      expect(violations.single.reason, contains('score'));
    });

    test('flags "mini-check" as a phrase', () {
      File('${tempDir.path}/c.dart').writeAsStringSync('const s = "A quick mini-check!";\n');
      final violations = _scanDirectory(tempDir);
      expect(violations, hasLength(1));
      expect(violations.single.reason, contains('mini-check'));
    });

    test('flags "correct answer" as a phrase', () {
      File('${tempDir.path}/d.dart').writeAsStringSync("const s = 'Pick the correct answer';\n");
      final violations = _scanDirectory(tempDir);
      expect(violations, hasLength(1));
      expect(violations.single.reason, contains('correct answer'));
    });

    test('NEGATIVE: does not flag legitimate identifiers/params named '
        '"score" or "quiz" (only string literals are inspected)', () {
      File('${tempDir.path}/e.dart').writeAsStringSync(
        'int score = 0;\n'
        "void quiz() => throw UnimplementedError('unused');\n",
      );
      final violations = _scanDirectory(tempDir);
      expect(violations, isEmpty);
    });

    test('NEGATIVE: does not flag words that merely contain "score" as a '
        'substring ("underscore")', () {
      File('${tempDir.path}/f.dart')
          .writeAsStringSync("const s = 'an underscore character';\n");
      final violations = _scanDirectory(tempDir);
      expect(violations, isEmpty);
    });

    test('NEGATIVE: does not flag ordinary definition/card copy', () {
      File('${tempDir.path}/g.dart').writeAsStringSync(
        "const s1 = 'Really, really big.';\n"
        "const s2 = 'Tap to hear it again';\n"
        "const s3 = 'Close';\n",
      );
      final violations = _scanDirectory(tempDir);
      expect(violations, isEmpty);
    });

    test('EDGE: an empty file produces zero violations', () {
      File('${tempDir.path}/empty.dart').writeAsStringSync('');
      expect(_scanDirectory(tempDir), isEmpty);
    });

    test('EDGE: a missing directory produces zero violations rather than '
        'throwing (a no-op before lib/features/vocab/ exists)', () {
      expect(_scanDirectory(Directory('${tempDir.path}/does_not_exist')), isEmpty);
    });
  });

  group('real-repo CI gate — POSITIVE', () {
    test(
      'no .dart file under lib/features/vocab/ contains a banned '
      'quiz/scoring string literal (vacuously true until lib/features/vocab/ '
      'exists; becomes the enforced gate once it does)',
      () {
        final violations = _scanDirectory(Directory('lib/features/vocab'));
        expect(
          violations,
          isEmpty,
          reason: violations.map((v) => v.toString()).join('\n'),
        );
      },
    );
  });

  group('widget-tree sweep — no quiz-shaped input exists (POSITIVE)', () {
    testWidgets('an opened VocabCardPopover contains no Radio/Checkbox/'
        'Switch/Slider anywhere in its tree', (tester) async {
      await tester.pumpWidget(_harness(card: _card(illustrationRef: 'art/gigantic.png')));
      await tester.pump();

      expect(find.byType(Radio), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(find.byType(Slider), findsNothing);
      expect(find.byType(DropdownButton), findsNothing);
    });

    testWidgets('no rendered Text anywhere in the popover carries banned '
        'quiz/scoring copy', (tester) async {
      await tester.pumpWidget(_harness(card: _card()));
      await tester.pump();

      for (final textWidget in tester.widgetList<Text>(find.byType(Text))) {
        final content = textWidget.data ?? '';
        final lower = content.toLowerCase();
        for (final banned in _bannedPhrases) {
          expect(lower.contains(banned), isFalse,
              reason: 'Text "$content" contains banned phrase "$banned"');
        }
        expect(_quizWholeWord.hasMatch(content), isFalse,
            reason: 'Text "$content" contains the word "quiz"');
        expect(_scoreWholeWord.hasMatch(content), isFalse,
            reason: 'Text "$content" contains the word "score"');
      }
    });

    testWidgets('exactly the three pinned interactive affordances exist -- '
        'word-tap, replay, close -- never a fourth "submit"/"check answer" '
        'control', (tester) async {
      await tester.pumpWidget(_harness(card: _card()));
      await tester.pump();

      expect(find.byKey(const ValueKey('vocab-card-word-tap')), findsOneWidget);
      expect(find.byKey(const ValueKey('vocab-card-replay-button')), findsOneWidget);
      expect(find.byKey(const ValueKey('vocab-card-close-button')), findsOneWidget);
      // No submission/check control of any conventional shape.
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(find.widgetWithText(TextButton, 'Submit'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Check'), findsNothing);
    });
  });
}

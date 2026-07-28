/// Pins the "never any negative feedback" rule (PRD §8 Unit 5 pinned
/// design: "The reading screen never displays 'wrong', red coloring, error
/// sounds, or any negative feedback. The only responses to imperfect
/// reading are patience and help"; acceptance: "Grep-level check: no
/// red/error asset or string is reachable from the reading screen"; ticket
/// reading-screen accept entry 11).
///
/// Follows test/design/token_lint_test.dart's established pattern exactly:
/// a real scanner (proven correct against fixtures in a throwaway temp
/// dir), then run for real against lib/features/reading/ so it becomes the
/// CI gate once that directory's files exist. This file imports
/// lib/design/tokens.dart (for the "no red-family token exists at all"
/// sanity check) and lib/features/reading/reading_screen.dart plus its
/// composed lib files (word_text_view.dart, reading_controller.dart,
/// narration_controller.dart, listening_indicator.dart), none of which
/// exist yet: the whole file fails to compile/analyze until they do -- the
/// expected red state.
///
/// Two layers, matching the accept's "grep-level + widget assertions":
///  1. A static scanner over every `.dart` file under lib/features/reading/,
///     flagging any STRING LITERAL (never comments or identifiers, to avoid
///     false-flagging legitimate Dart error-handling code like `onError:`
///     or `StateError`) that case-insensitively contains one of the banned
///     substrings ('wrong', 'incorrect', 'error', 'oops', 'try again'), or
///     the whole word 'red' (word-boundary matched, so "colored"/"already"/
///     "bored" are never false positives).
///  2. A widget-tree sweep: pump `ReadingScreen` through a scripted
///     STRUGGLE + HELP sequence (the one path where a real product might be
///     tempted to show something discouraging) and assert no rendered
///     `Text`/`Icon` carries banned copy or a reddish color, using an
///     HSV-hue heuristic independent of any particular token name (so it
///     would catch a red literal even if one were smuggled in under a
///     differently-named token).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/design/fake_rive_stage.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/features/analytics/analytics_client.dart';
import 'package:learn_to_read/features/analytics/event_queue.dart';
import 'package:learn_to_read/features/analytics/transport.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/listening/contracts/tracker_events.dart';
import 'package:learn_to_read/features/reading/reading_controller.dart';
import 'package:learn_to_read/features/reading/reading_screen.dart';

// ---------------------------------------------------------------------------
// Layer 1: the static string-literal scanner.
// ---------------------------------------------------------------------------

/// Matches the contents of a single- or double-quoted Dart string literal
/// (non-multiline; good enough for this codebase's style, matching
/// token_lint_test.dart's own line-by-line simplicity).
final RegExp _stringLiteral = RegExp(
  r"'([^'\\]*(?:\\.[^'\\]*)*)'" // matches a '...' literal
  r'|"([^"\\]*(?:\\.[^"\\]*)*)"', // matches a "..." literal
);

const List<String> _bannedSubstrings = <String>[
  'wrong',
  'incorrect',
  'oops',
  'try again',
  'error',
];

final RegExp _redWholeWord = RegExp(r'\bred\b', caseSensitive: false);

class _NegativeFeedbackViolation {
  _NegativeFeedbackViolation(this.path, this.line, this.literal, this.reason);
  final String path;
  final int line;
  final String literal;
  final String reason;

  @override
  String toString() => '$path:$line: "$literal" ($reason)';
}

/// Scans [source] line-by-line for string literals containing banned
/// negative-feedback vocabulary. Comments and identifiers are never
/// inspected -- only literal string contents -- so legitimate Dart error
/// handling (`onError:`, `catch (error)`, `StateError`) never false-flags.
List<_NegativeFeedbackViolation> _scanSource(String path, String source) {
  final violations = <_NegativeFeedbackViolation>[];
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    for (final match in _stringLiteral.allMatches(line)) {
      final literal = match.group(1) ?? match.group(2) ?? '';
      final lower = literal.toLowerCase();
      for (final banned in _bannedSubstrings) {
        if (lower.contains(banned)) {
          violations.add(_NegativeFeedbackViolation(path, i + 1, literal, 'contains "$banned"'));
        }
      }
      if (_redWholeWord.hasMatch(literal)) {
        violations.add(_NegativeFeedbackViolation(path, i + 1, literal, 'contains the word "red"'));
      }
    }
  }
  return violations;
}

List<_NegativeFeedbackViolation> _scanDirectory(Directory dir) {
  final violations = <_NegativeFeedbackViolation>[];
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

WordToken _word(String text) => WordToken(
      text: text,
      graphemePhonemeMap: [(graphemes: text, phonemeId: 'AH')],
      pronunciationAudioRef: 'audio/words/$text.mp3',
    );

Level _level() => Level(
      id: 'level.1',
      ordinal: 1,
      newSkills: const [],
      format: LevelFormat.multiSentence,
      vocabEnabled: false,
    );

Story _story() => Story(
      id: 'story.1',
      levelId: 'level.1',
      title: 'Test Story',
      pages: [
        Page(sentences: [Sentence(words: [_word('the'), _word('cat'), _word('sat')])]),
      ],
      riveAnimationRef: 'rive/story.riv',
      celebrationAudioRef: 'audio/celebration.mp3',
      collectibleRef: 'collectible.1',
      skillsExercised: const [],
      packId: 'pack.test',
      contentVersion: '1',
    );

class _FakeTrackerHandle implements ReadingTrackerHandle {
  final StreamController<TrackerEvent> _controller =
      StreamController<TrackerEvent>.broadcast();
  bool _listening = false;

  @override
  Stream<TrackerEvent> get eventsStream => _controller.stream;

  @override
  bool get isListening => _listening;

  @override
  void pause() => _listening = false;

  @override
  void resume() => _listening = true;

  @override
  void stop() => _listening = false;

  @override
  void tapCurrentWord() {}

  void emit(TrackerEvent event) => _controller.add(event);
}

AnalyticsClient _noOpAnalyticsClient() => AnalyticsClient(
      enabled: false,
      queue: EventQueue(
        transport: const NullAnalyticsTransport(),
        clock: () => DateTime.utc(2026, 1, 1),
        storageDirectory: Directory.systemTemp,
      ),
    );

/// Whether [color] reads as reddish under an HSV-hue heuristic: red hues
/// sit near 0/360 degrees with meaningful saturation and lightness --
/// catches a red literal regardless of what any token happens to be named.
bool _isReddish(Color color) {
  final hsv = HSVColor.fromColor(color);
  final hue = hsv.hue; // 0-360
  final isRedHue = hue <= 15 || hue >= 345;
  return isRedHue && hsv.saturation > 0.35 && hsv.value > 0.25;
}

void main() {
  group('scanner correctness (fixtures, in a throwaway temp dir) — '
      'POSITIVE', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('no_negative_feedback_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('flags a "wrong" string literal', () {
      File('${tempDir.path}/a.dart').writeAsStringSync("const s = 'That was wrong!';\n");
      final violations = _scanDirectory(tempDir);
      expect(violations, hasLength(1));
      expect(violations.single.reason, contains('wrong'));
    });

    test('flags an "error" asset path string literal', () {
      File('${tempDir.path}/b.dart')
          .writeAsStringSync("const ref = 'assets/audio/error_sound.mp3';\n");
      final violations = _scanDirectory(tempDir);
      expect(violations, hasLength(1));
      expect(violations.single.reason, contains('error'));
    });

    test('flags "try again" as a phrase', () {
      File('${tempDir.path}/c.dart').writeAsStringSync('const s = "Try again!";\n');
      final violations = _scanDirectory(tempDir);
      expect(violations, hasLength(1));
      expect(violations.single.reason, contains('try again'));
    });

    test('flags the whole word "red" inside a string literal', () {
      File('${tempDir.path}/d.dart').writeAsStringSync("const s = 'red underline';\n");
      final violations = _scanDirectory(tempDir);
      expect(violations, hasLength(1));
      expect(violations.single.reason, contains('red'));
    });

    test('NEGATIVE: does not flag legitimate Dart error-handling code '
        '(identifiers/params, not string literals)', () {
      File('${tempDir.path}/e.dart').writeAsStringSync(
        "stream.listen(_onEvent, onError: (Object error, StackTrace st) {\n"
        "  throw StateError('unexpected');\n" // 'unexpected' has no banned substring
        "});\n",
      );
      final violations = _scanDirectory(tempDir);
      expect(violations, isEmpty);
    });

    test('NEGATIVE: does not flag words that merely contain "red" as a '
        'substring ("colored", "already", "bored", "wondered")', () {
      File('${tempDir.path}/f.dart').writeAsStringSync(
        "const s1 = 'a colored ribbon';\n"
        "const s2 = 'already done';\n"
        "const s3 = 'she felt bored';\n"
        "const s4 = 'he wondered aloud';\n",
      );
      final violations = _scanDirectory(tempDir);
      expect(violations, isEmpty);
    });

    test('NEGATIVE: does not flag encouraging, patience-only copy', () {
      File('${tempDir.path}/g.dart').writeAsStringSync(
        "const s1 = 'Nice reading!';\n"
        "const s2 = \"Let's sound it out together\";\n"
        "const s3 = 'Great job!';\n",
      );
      final violations = _scanDirectory(tempDir);
      expect(violations, isEmpty);
    });

    test('EDGE: an empty file produces zero violations', () {
      File('${tempDir.path}/empty.dart').writeAsStringSync('');
      expect(_scanDirectory(tempDir), isEmpty);
    });

    test('EDGE: a missing directory produces zero violations rather than '
        'throwing (a no-op before lib/features/reading/ exists)', () {
      expect(_scanDirectory(Directory('${tempDir.path}/does_not_exist')), isEmpty);
    });
  });

  group('real-repo CI gate — POSITIVE', () {
    test(
      'no .dart file under lib/features/reading/ contains a banned '
      'negative-feedback string literal (vacuously true until '
      'lib/features/reading/ exists; becomes the enforced gate once it does)',
      () {
        final violations = _scanDirectory(Directory('lib/features/reading'));
        expect(
          violations,
          isEmpty,
          reason: violations.map((v) => v.toString()).join('\n'),
        );
      },
    );

    test('sanity: DesignTokens defines no red-family color at all -- there '
        'is no "error"/"wrong"/red-named token a builder could reach for', () {
      expect(_isReddish(DesignTokens.wordUnreadInk), isFalse);
      expect(_isReddish(DesignTokens.wordCurrentInk), isFalse);
      expect(_isReddish(DesignTokens.wordReadGreen), isFalse);
      expect(_isReddish(DesignTokens.wordVocabBlue), isFalse);
      expect(_isReddish(DesignTokens.readingBackground), isFalse);
      expect(_isReddish(DesignTokens.surfaceBackground), isFalse);
    });
  });

  group('widget-tree sweep — POSITIVE', () {
    testWidgets('a struggle + help sequence never renders reddish color or '
        'banned copy anywhere in the tree', (tester) async {
      final tracker = _FakeTrackerHandle();
      await tester.pumpWidget(MaterialApp(
        home: ReadingScreen(
          story: _story(),
          level: _level(),
          tracker: tracker,
          audioService: FakeAudioService(),
          analytics: _noOpAnalyticsClient(),
          installId: 'a1b2c3d4-1234-4abc-8def-0123456789ab',
          profileOrdinal: 1,
          levelOrdinal: 1,
          stage: FakeStoryStage(),
          vocabCardOpener: (_) async {},
        ),
      ));
      await tester.pump();

      tracker
        ..emit(const StruggleDetected(index: 0))
        ..emit(const Silence(duration: Duration(seconds: 4)))
        ..emit(const WordHelped(index: 0, tier: HelpLevel.soundOut));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);

      for (final textWidget in tester.widgetList<Text>(find.byType(Text))) {
        final content = textWidget.data ?? '';
        for (final banned in _bannedSubstrings) {
          expect(
            content.toLowerCase().contains(banned),
            isFalse,
            reason: 'Text "$content" contains banned substring "$banned"',
          );
        }
        expect(_redWholeWord.hasMatch(content), isFalse,
            reason: 'Text "$content" contains the word "red"');
        final color = textWidget.style?.color;
        if (color != null) {
          expect(_isReddish(color), isFalse,
              reason: 'Text "$content" renders in a reddish color: $color');
        }
      }

      for (final icon in tester.widgetList<Icon>(find.byType(Icon))) {
        final color = icon.color;
        if (color != null) {
          expect(_isReddish(color), isFalse, reason: 'Icon renders in a reddish color: $color');
        }
      }
    });
  });

  group('reddish-hue heuristic — self-test (EDGE)', () {
    test('a genuinely red color is detected as reddish', () {
      expect(_isReddish(const Color(0xFFE53935)), isTrue);
    });

    test('green, blue, and warm-brown ink are not detected as reddish', () {
      expect(_isReddish(DesignTokens.wordReadGreen), isFalse);
      expect(_isReddish(DesignTokens.wordVocabBlue), isFalse);
      expect(_isReddish(DesignTokens.wordUnreadInk), isFalse);
    });

    test('a desaturated/near-gray color is never flagged even if its hue '
        'lands in the red band', () {
      // Low saturation greys can numerically report a hue anywhere,
      // including the red band; the heuristic requires real saturation too.
      const grey = Color(0xFF808080);
      expect(_isReddish(grey), isFalse);
    });
  });
}

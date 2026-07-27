// Pins the token-lint rule (accept #6, CI-enforceable): no child-facing
// widget may reference a color or inline font outside the single design
// token file, lib/design/tokens.dart. This test both (a) proves the
// scanning logic itself is correct against fixtures, and (b) runs the
// real scan against this repo's lib/ tree so it becomes the CI gate once
// lib/features/ exists.
//
// This file imports lib/design/tokens.dart, which does not exist yet:
// the whole file fails to compile/analyze until it is created (and until
// lib/design/layout.dart + lib/design/rive_stage.dart +
// lib/design/fake_rive_stage.dart exist, for the "single token file"
// checks below to have something real to scan) — the expected red state.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/design/tokens.dart';

final RegExp _colorLiteral = RegExp(r'Color\(0x[0-9A-Fa-f]{6,8}\)');
final RegExp _colorsDot = RegExp(r'\bColors\.[A-Za-z][A-Za-z0-9_]*');
final RegExp _inlineFont = RegExp(r'''TextStyle\([^)]*fontFamily\s*:\s*['"]''');

class _LintViolation {
  _LintViolation(this.path, this.line, this.rule);
  final String path;
  final int line;
  final String rule;

  @override
  String toString() => '$path:$line: $rule';
}

/// Scans [source] line-by-line for banned direct color/font usage.
List<_LintViolation> _scanSource(String path, String source) {
  final violations = <_LintViolation>[];
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (_colorLiteral.hasMatch(line)) {
      violations.add(_LintViolation(path, i + 1, 'inline Color(0x...) literal'));
    }
    if (_colorsDot.hasMatch(line)) {
      violations.add(_LintViolation(path, i + 1, 'Colors.* usage'));
    }
    if (_inlineFont.hasMatch(line)) {
      violations.add(_LintViolation(path, i + 1, 'inline TextStyle fontFamily literal'));
    }
  }
  return violations;
}

/// Recursively scans [dir] for *.dart files, skipping any whose normalized
/// (forward-slash) path satisfies [exclude].
List<_LintViolation> _scanDirectory(Directory dir, {required bool Function(String path) exclude}) {
  final violations = <_LintViolation>[];
  if (!dir.existsSync()) return violations;
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final normalized = entity.path.replaceAll(r'\', '/');
    if (exclude(normalized)) continue;
    violations.addAll(_scanSource(normalized, entity.readAsStringSync()));
  }
  return violations;
}

bool _underLibDesign(String path) => path.contains('/lib/design/');

void main() {
  test(
    'this suite depends on lib/design/tokens.dart existing '
    '(compliant code is expected to reference DesignTokens, not literals)',
    () {
      expect(DesignTokens.wordReadGreen, isNotNull);
    },
  );

  group('lint scanner correctness (fixtures, in a throwaway temp dir)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('token_lint_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('POSITIVE: flags a direct Color(0x...) literal', () {
      final file = File('${tempDir.path}/widget_a.dart')
        ..writeAsStringSync("final ink = Color(0xFF112233);\n");
      final violations = _scanDirectory(tempDir, exclude: (_) => false);
      expect(violations, hasLength(1));
      expect(violations.single.rule, contains('Color(0x'));
      expect(violations.single.path, equals(file.path.replaceAll(r'\', '/')));
    });

    test('POSITIVE: flags a Colors.* usage', () {
      File('${tempDir.path}/widget_b.dart').writeAsStringSync("color: Colors.red,\n");
      final violations = _scanDirectory(tempDir, exclude: (_) => false);
      expect(violations, hasLength(1));
      expect(violations.single.rule, contains('Colors.*'));
    });

    test('POSITIVE: flags a TextStyle with an inline font-family literal', () {
      File('${tempDir.path}/widget_c.dart')
        ..writeAsStringSync("const TextStyle(fontFamily: 'Arial')\n");
      final violations = _scanDirectory(tempDir, exclude: (_) => false);
      expect(violations, hasLength(1));
      expect(violations.single.rule, contains('fontFamily'));
    });

    test(
      'NEGATIVE: does NOT flag code that references a DesignTokens member '
      'instead of a literal',
      () {
        File('${tempDir.path}/widget_d.dart').writeAsStringSync(
          "color: DesignTokens.wordReadGreen,\n"
          "style: TextStyle(fontFamily: DesignTokens.readingFontFamily),\n",
        );
        final violations = _scanDirectory(tempDir, exclude: (_) => false);
        expect(violations, isEmpty);
      },
    );

    test('EDGE: an empty file produces zero violations', () {
      File('${tempDir.path}/empty.dart').writeAsStringSync('');
      final violations = _scanDirectory(tempDir, exclude: (_) => false);
      expect(violations, isEmpty);
    });

    test(
      'EDGE: a missing directory produces zero violations rather than '
      'throwing (so the CI check is a no-op before lib/features/ exists)',
      () {
        final missing = Directory('${tempDir.path}/does_not_exist');
        final violations = _scanDirectory(missing, exclude: (_) => false);
        expect(violations, isEmpty);
      },
    );

    test(
      'NEGATIVE: an excluded path (simulating lib/design/) is not scanned '
      'even though it contains a raw color literal',
      () {
        final designDir = Directory('${tempDir.path}/lib/design')..createSync(recursive: true);
        File('${designDir.path}/tokens.dart').writeAsStringSync(
          "static const wordReadGreen = Color(0xFF2E7D4F);\n",
        );
        final featuresDir = Directory('${tempDir.path}/lib/features')..createSync(recursive: true);
        File('${featuresDir.path}/story_widget.dart').writeAsStringSync(
          "final oops = Color(0xFF445566);\n",
        );

        final violations = _scanDirectory(Directory('${tempDir.path}/lib'), exclude: _underLibDesign);
        expect(violations, hasLength(1));
        expect(violations.single.path, contains('story_widget.dart'));
      },
    );
  });

  group('real-repo CI gate (accept #6: lib/features/ vs lib/design/)', () {
    test(
      'POSITIVE: no child-facing widget under lib/features/ references a '
      'raw Color/Colors literal or inline font outside lib/design/ '
      '(vacuously true until lib/features/ exists; becomes the enforced '
      'gate for every unit that adds child-facing widgets there)',
      () {
        final violations = _scanDirectory(Directory('lib/features'), exclude: (_) => false);
        expect(
          violations,
          isEmpty,
          reason: violations.map((v) => v.toString()).join('\n'),
        );
      },
    );

    test(
      'POSITIVE: the "single token file" rule holds within lib/design/ '
      'itself — layout.dart, rive_stage.dart, and fake_rive_stage.dart do '
      'not define their own raw color/font literals; only tokens.dart may',
      () {
        final violations = _scanDirectory(
          Directory('lib/design'),
          exclude: (path) => path.endsWith('/design/tokens.dart'),
        );
        expect(
          violations,
          isEmpty,
          reason: violations.map((v) => v.toString()).join('\n'),
        );
      },
    );
  });
}

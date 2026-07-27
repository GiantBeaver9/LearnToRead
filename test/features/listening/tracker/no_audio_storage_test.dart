// No-audio-storage static/dynamic check (PRD §8 Unit 4 pinned design: "No
// audio is ever stored -- not on device, not server-side"; PRD §8 Unit 10
// consent note reinforces the same guarantee). This mirrors the established
// grep-scanner pattern in test/design/token_lint_test.dart: (a) prove the
// scanner logic is correct against fixtures in a throwaway temp dir, then
// (b) run the real scan against this ticket's five tracker source files.
//
// This file imports lib/features/listening/tracker/reading_tracker.dart,
// which does not exist yet: the whole file fails to compile/analyze until
// the ticket's five tracker files exist -- the expected red state, exactly
// like the sibling suites in this directory.
//
// Two complementary checks:
//   1. Static: none of the five pinned tracker source files (see
//      docs/tickets/listening-tracker.json "files") touch the filesystem at
//      all -- no dart:io, no path_provider, no File(...)/Directory(...)
//      construction, no .writeAsBytes(Sync)/openWrite calls. The tracker's
//      job is an in-memory hypothesis-to-event pipeline; it has no
//      legitimate reason to write anything to disk, audio or otherwise, so
//      banning file I/O outright is a strictly stronger (and simpler,
//      Dart-lacks-mirrors-friendly) guarantee than only banning
//      "audio-shaped" writes.
//   2. Dynamic (best-effort -- Dart has no runtime reflection here): a live
//      ReadingTracker, driven end-to-end exactly as the other suites drive
//      it, only ever emits the five pinned TrackerEvent subtypes on
//      eventsStream -- nothing else, and in particular nothing carrying a
//      raw audio buffer, slips through the one channel this ticket exposes
//      to callers.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/contracts/fake_asr_engine.dart';
import 'package:learn_to_read/features/listening/contracts/tracker_events.dart';
import 'package:learn_to_read/features/listening/tracker/reading_tracker.dart';

/// The ticket's pinned implementation file set (docs/tickets/
/// listening-tracker.json "files") -- the exhaustive surface this check
/// covers.
const List<String> _trackerSourceFiles = [
  'lib/features/listening/tracker/reading_tracker.dart',
  'lib/features/listening/tracker/silence_detector.dart',
  'lib/features/listening/tracker/tap_engine.dart',
  'lib/features/listening/tracker/cloud_minute_cap.dart',
  'lib/features/listening/tracker/mic_session.dart',
];

final RegExp _dartIoImport = RegExp(r'''import\s+['"]dart:io['"]''');
final RegExp _pathProviderImport =
    RegExp(r'''import\s+['"]package:path_provider''');
final RegExp _fileConstruction = RegExp(r'\bFile\s*\(');
final RegExp _directoryConstruction = RegExp(r'\bDirectory\s*\(');
final RegExp _writeAsBytes = RegExp(r'\.writeAsBytes');
final RegExp _openWrite = RegExp(r'\.openWrite\s*\(');

class _Violation {
  _Violation(this.path, this.line, this.rule);
  final String path;
  final int line;
  final String rule;

  @override
  String toString() => '$path:$line: $rule';
}

/// Scans [source] line-by-line for banned filesystem/audio-write APIs.
List<_Violation> _scanSource(String path, String source) {
  final violations = <_Violation>[];
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (_dartIoImport.hasMatch(line)) {
      violations.add(_Violation(path, i + 1, 'dart:io import'));
    }
    if (_pathProviderImport.hasMatch(line)) {
      violations.add(_Violation(path, i + 1, 'package:path_provider import'));
    }
    if (_fileConstruction.hasMatch(line)) {
      violations.add(_Violation(path, i + 1, 'File(...) construction'));
    }
    if (_directoryConstruction.hasMatch(line)) {
      violations.add(_Violation(path, i + 1, 'Directory(...) construction'));
    }
    if (_writeAsBytes.hasMatch(line)) {
      violations.add(_Violation(path, i + 1, '.writeAsBytes(Sync) call'));
    }
    if (_openWrite.hasMatch(line)) {
      violations.add(_Violation(path, i + 1, '.openWrite() call'));
    }
  }
  return violations;
}

/// Scans exactly [paths] (skipping any that do not yet exist -- so the
/// check is a no-op before a given file is authored, mirroring
/// token_lint_test.dart's "missing directory" allowance) rather than an
/// entire directory tree, so this check is exhaustive over the ticket's
/// pinned file list even before every file exists.
List<_Violation> _scanPaths(Iterable<String> paths) {
  final violations = <_Violation>[];
  for (final path in paths) {
    final file = File(path);
    if (!file.existsSync()) continue;
    violations.addAll(_scanSource(path, file.readAsStringSync()));
  }
  return violations;
}

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

void main() {
  group('scanner correctness (fixtures, in a throwaway temp dir)', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('no_audio_storage_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('POSITIVE: flags a dart:io import', () {
      final f = File('${tempDir.path}/a.dart')
        ..writeAsStringSync("import 'dart:io';\n");
      final violations = _scanPaths([f.path]);
      expect(violations, hasLength(1));
      expect(violations.single.rule, contains('dart:io'));
    });

    test('POSITIVE: flags a package:path_provider import', () {
      final f = File('${tempDir.path}/b.dart')
        ..writeAsStringSync("import 'package:path_provider/path_provider.dart';\n");
      final violations = _scanPaths([f.path]);
      expect(violations, hasLength(1));
      expect(violations.single.rule, contains('path_provider'));
    });

    test('POSITIVE: flags File(...) construction', () {
      final f = File('${tempDir.path}/c.dart')
        ..writeAsStringSync("final f = File(p.join(dir, 'audio.pcm'));\n");
      final violations = _scanPaths([f.path]);
      expect(violations, hasLength(1));
      expect(violations.single.rule, contains('File('));
    });

    test('POSITIVE: flags .writeAsBytes / .writeAsBytesSync calls', () {
      final f = File('${tempDir.path}/d.dart')
        ..writeAsStringSync("await handle.writeAsBytes(buffer);\n"
            "handle.writeAsBytesSync(buffer);\n");
      final violations = _scanPaths([f.path]);
      expect(violations, hasLength(2));
    });

    test('POSITIVE: flags .openWrite() calls', () {
      final f = File('${tempDir.path}/e.dart')
        ..writeAsStringSync("final sink = handle.openWrite();\n");
      final violations = _scanPaths([f.path]);
      expect(violations, hasLength(1));
      expect(violations.single.rule, contains('openWrite'));
    });

    test('NEGATIVE: pure in-memory event-stream code raises no violation', () {
      final f = File('${tempDir.path}/clean.dart')
        ..writeAsStringSync(
          "import 'dart:async';\n"
          "class ReadingTracker {\n"
          "  final _controller = StreamController<int>.broadcast();\n"
          "  Stream<int> get eventsStream => _controller.stream;\n"
          "}\n",
        );
      final violations = _scanPaths([f.path]);
      expect(violations, isEmpty);
    });

    test('EDGE: a path that does not exist on disk produces zero '
        'violations rather than throwing (no-op before the file is '
        'authored)', () {
      final missing = '${tempDir.path}/does_not_exist.dart';
      final violations = _scanPaths([missing]);
      expect(violations, isEmpty);
    });

    test('EDGE: an empty file produces zero violations', () {
      final f = File('${tempDir.path}/empty.dart')..writeAsStringSync('');
      final violations = _scanPaths([f.path]);
      expect(violations, isEmpty);
    });
  });

  group('real-repo CI gate: the five pinned tracker source files never '
      'touch the filesystem', () {
    test(
      'POSITIVE: none of reading_tracker.dart, silence_detector.dart, '
      'tap_engine.dart, cloud_minute_cap.dart, mic_session.dart import '
      'dart:io/path_provider or construct File/Directory or write bytes '
      '(vacuously true until each file exists; becomes the enforced gate '
      'as each is authored)',
      () {
        final violations = _scanPaths(_trackerSourceFiles);
        expect(
          violations,
          isEmpty,
          reason: violations.map((v) => v.toString()).join('\n'),
        );
      },
    );
  });

  group('dynamic (best-effort) check: the tracker\'s only public channel '
      '(eventsStream) never carries anything but the five pinned '
      'TrackerEvent subtypes', () {
    test(
      'POSITIVE: a full scripted read only ever emits WordAccepted, '
      'WordAcceptedNearMiss, StruggleDetected, Silence, or WordHelped -- '
      'no undocumented event type (e.g. one smuggling a raw audio buffer) '
      'is ever observable through the pinned interface',
      () {
        final engine = FakeAsrEngine(
          script: [
            Hypothesis(wordHypotheses: const ['cat'], phoneHypotheses: null),
          ],
        );
        final tracker =
            ReadingTracker(engine: engine, sentence: [_cat], micConsent: true);
        final events = <TrackerEvent>[];
        tracker.eventsStream.listen(events.add);

        tracker.start();

        for (final e in events) {
          expect(
            e is WordAccepted ||
                e is WordAcceptedNearMiss ||
                e is StruggleDetected ||
                e is Silence ||
                e is WordHelped,
            isTrue,
            reason: 'unexpected event type on the tracker\'s single public '
                'channel: ${e.runtimeType}',
          );
        }
      },
    );
  });
}

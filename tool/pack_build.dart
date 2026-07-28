// Pack build CLI (PRD §8 Unit 3: "pipeline is CLI tooling in this repo").
//
// Usage:
//   dart run tool/pack_build.dart <content-dir> <out-file> [options]
//
// A deliberately thin argv/stdout/exit-code wrapper around `buildPack` in
// lib/pipeline/pack_builder.dart -- all of the build's judgement lives there,
// under test, and none of it lives here. This file only: reads argv, loads the
// scope-&-sequence levels and heart words it is pointed at, calls buildPack,
// prints the result, and writes the checksummed manifest out.
//
// Options:
//   --levels=<path>          JSON file of the scope-&-sequence levels this
//                            content is authored against (required: Level
//                            never travels inside a manifest -- PRD §5).
//   --heart-words=<path>     JSON file: {"<levelId>": ["said", ...]}.
//   --starter-levels=a,b,c   Declare this build a starter pack and request the
//                            A-9 composition check (warn-only).
//   --loudness-target=<lufs> Default -16.0 (Unit 13 pinned).
//   --loudness-tolerance=<lu> Default 1.0.
//
// Exit codes: 0 build succeeded, 1 build failed with content errors, 2 usage
// or input error.
//
// Levels JSON shape (a list, mirroring `Level`/`PhonicsSkill` in
// lib/domain/models/content_models.dart):
//
//   [{"id": "level.1", "ordinal": 1, "format": "sentence",
//     "vocabEnabled": false, "narrationEnabled": true,
//     "newSkills": [{"id": "skill.1", "name": "s a t", "sequenceOrder": 1,
//                    "introducesGraphemes": ["s", "a", "t"]}]}]

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/pipeline/pack_builder.dart';

const String _usage = 'usage: dart run tool/pack_build.dart <content-dir> <out-file> '
    '--levels=<levels.json> [--heart-words=<file>] [--starter-levels=a,b,c] '
    '[--loudness-target=-16.0] [--loudness-tolerance=1.0]';

LevelFormat _parseFormat(String raw) => switch (raw) {
      'sentence' => LevelFormat.sentence,
      'multiSentence' => LevelFormat.multiSentence,
      'paragraph' => LevelFormat.paragraph,
      _ => throw FormatException('unknown level format "$raw"'),
    };

List<Level> _readLevels(String path) {
  final raw = jsonDecode(File(path).readAsStringSync());
  if (raw is! List) throw const FormatException('levels file must contain a JSON list');
  return [
    for (final entry in raw.cast<Map<String, dynamic>>())
      Level(
        id: entry['id'] as String,
        ordinal: entry['ordinal'] as int,
        format: _parseFormat(entry['format'] as String),
        vocabEnabled: entry['vocabEnabled'] as bool? ?? false,
        narrationEnabled: entry['narrationEnabled'] as bool?,
        newSkills: [
          for (final skill in (entry['newSkills'] as List? ?? const []).cast<Map<String, dynamic>>())
            PhonicsSkill(
              id: skill['id'] as String,
              name: skill['name'] as String,
              sequenceOrder: skill['sequenceOrder'] as int,
              introducesGraphemes: (skill['introducesGraphemes'] as List).cast<String>(),
            ),
        ],
      ),
  ];
}

Map<String, List<String>> _readHeartWords(String path) {
  final raw = jsonDecode(File(path).readAsStringSync());
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('heart-words file must contain a JSON object');
  }
  return {
    for (final entry in raw.entries) entry.key: (entry.value as List).cast<String>(),
  };
}

Future<int> _run(List<String> args) async {
  final positional = args.where((a) => !a.startsWith('--')).toList();
  final options = <String, String>{
    for (final arg in args.where((a) => a.startsWith('--')))
      arg.substring(2).split('=').first: arg.contains('=') ? arg.split('=').sublist(1).join('=') : '',
  };

  if (positional.length != 2 || options['levels'] == null) {
    print(_usage);
    return 2;
  }
  final contentDir = positional[0];
  final outFile = positional[1];

  final List<Level> levels;
  final Map<String, List<String>> heartWords;
  try {
    levels = _readLevels(options['levels']!);
    final heartWordsPath = options['heart-words'];
    heartWords = heartWordsPath == null ? const {} : _readHeartWords(heartWordsPath);
  } on Object catch (e) {
    print('error: could not read build inputs: $e');
    return 2;
  }

  final result = await buildPack(
    contentDir: contentDir,
    levels: levels,
    heartWordsByLevelId: heartWords,
    starterCompositionLevelIds: options['starter-levels']?.split(','),
    loudnessTargetLufs: double.tryParse(options['loudness-target'] ?? '') ?? -16.0,
    loudnessToleranceLu: double.tryParse(options['loudness-tolerance'] ?? '') ?? 1.0,
  );

  for (final warning in result.compositionWarnings) {
    print('warning [composition] ${warning.message}');
  }
  for (final error in result.errors) {
    print('error [${error.stage}] ${error.entityType} "${error.entityId}" '
        'field "${error.field}": ${error.message}');
  }

  if (!result.success) {
    print('pack build FAILED with ${result.errors.length} error(s).');
    return 1;
  }

  final pack = result.pack!;
  File(outFile)
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(pack.toJson()));
  print('pack build OK: ${pack.id} v${pack.version} -> $outFile');
  print('  ${pack.stories.length} story/stories, ${pack.twisters.length} twister(s), '
      '${pack.vocabCards.length} vocab card(s), ${pack.assetRefs.length} asset ref(s)');
  print('  sha256 ${pack.checksum}');
  return 0;
}

Future<void> main(List<String> args) async {
  exitCode = await _run(args);
}

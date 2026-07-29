// Bundles the built demo starter content into ONE Flutter asset:
// assets/starter_content.bin (see lib/data/content/starter_archive.dart for
// the format). ~470 per-file pubspec asset entries become a single archive
// the app extracts into its support directory on first run.
//
// Usage:
//   dart run tool/bundle_content.dart [--manifest=build/starter_pack/manifest.json]
//       [--content=content/demo] [--out=assets/starter_content.bin]
//
// Inputs (the same staging list tool/sideload_android.sh used):
//   * <manifest>                          -> starter_pack/manifest.json
//   * <content>/{words,narration,celebrations,prompts,vocab,rive,phonemes,
//     audio}/**                           -> starter_pack/<dir>/...
//   * <content>/scope_sequence.json       -> scope_sequence.json
//
// Run `dart run tool/demo_content.dart` and the tool/pack_build.dart CLI
// first so the manifest and content are current. Entries are sorted by path,
// so the output (and its embedded checksum) is deterministic for identical
// inputs.
//
// Exit codes: 0 written, 2 usage/missing-input error.

// ignore_for_file: avoid_print

import 'dart:io';
import 'dart:typed_data';

import 'package:learn_to_read/data/content/starter_archive.dart';
import 'package:learn_to_read/data/content/starter_content_installer.dart'
    show kStarterPackDirectoryName;
import 'package:path/path.dart' as p;

const List<String> _contentDirectories = [
  'words',
  'narration',
  'celebrations',
  'prompts',
  'vocab',
  'rive',
  'phonemes',
  'audio',
];

void main(List<String> args) {
  var manifestPath = 'build/starter_pack/manifest.json';
  var contentPath = 'content/demo';
  var outPath = 'assets/starter_content.bin';
  for (final arg in args) {
    if (arg.startsWith('--manifest=')) {
      manifestPath = arg.substring('--manifest='.length);
    } else if (arg.startsWith('--content=')) {
      contentPath = arg.substring('--content='.length);
    } else if (arg.startsWith('--out=')) {
      outPath = arg.substring('--out='.length);
    } else {
      print('unknown option: $arg');
      print('usage: dart run tool/bundle_content.dart '
          '[--manifest=<manifest.json>] [--content=<dir>] [--out=<file>]');
      exit(2);
    }
  }

  final manifest = File(manifestPath);
  if (!manifest.existsSync()) {
    print('missing $manifestPath -- run the pack build first:');
    print('  dart run tool/demo_content.dart');
    print('  dart run tool/pack_build.dart content/demo '
        'build/starter_pack/manifest.json --levels=content/demo/levels.json '
        '--heart-words=content/demo/heart_words.json '
        '--starter-levels=level.demo.1,level.demo.2,level.demo.3');
    exit(2);
  }
  final scopeSequence = File(p.join(contentPath, 'scope_sequence.json'));
  if (!scopeSequence.existsSync()) {
    print('missing ${scopeSequence.path} -- run '
        '`dart run tool/demo_content.dart` first');
    exit(2);
  }

  final entries = <StarterArchiveEntry>[
    StarterArchiveEntry(
      path: '$kStarterPackDirectoryName/manifest.json',
      bytes: manifest.readAsBytesSync(),
    ),
    StarterArchiveEntry(
      path: 'scope_sequence.json',
      bytes: scopeSequence.readAsBytesSync(),
    ),
  ];

  for (final dir in _contentDirectories) {
    final directory = Directory(p.join(contentPath, dir));
    if (!directory.existsSync()) continue;
    for (final file
        in directory.listSync(recursive: true).whereType<File>()) {
      final relative = p
          .split(p.relative(file.path, from: contentPath))
          .join('/');
      entries.add(StarterArchiveEntry(
        path: '$kStarterPackDirectoryName/$relative',
        bytes: file.readAsBytesSync(),
      ));
    }
  }

  entries.sort((a, b) => a.path.compareTo(b.path));

  final Uint8List bytes;
  try {
    bytes = encodeStarterArchive(entries);
  } on StarterArchiveFormatException catch (e) {
    print('bundle failed: ${e.message}');
    exit(2);
  }

  final out = File(outPath);
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(bytes, flush: true);

  final archive = StarterArchive.decode(bytes); // self-check round-trip
  print('wrote $outPath: ${entries.length} files, ${bytes.length} bytes, '
      'checksum ${archive.checksum}');
}


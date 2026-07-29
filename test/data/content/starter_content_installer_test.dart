/// Pins the first-run extraction / coexistence rule in
/// `starter_content_installer.dart`:
///
///  1. no `manifest.json`            -> extract (fresh install);
///  2. manifest, no marker           -> preserve (sideloaded content wins);
///  3. manifest + marker == checksum -> up to date, nothing written;
///  4. manifest + marker != checksum -> extract (bundled content updated);
///  plus: a corrupt archive throws before touching anything on disk.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/content/starter_archive.dart';
import 'package:learn_to_read/data/content/starter_content_installer.dart';
import 'package:path/path.dart' as p;

Uint8List _archive({String manifestBody = '{"id":"pack.starter"}'}) =>
    encodeStarterArchive([
      StarterArchiveEntry(
        path: 'starter_pack/manifest.json',
        bytes: Uint8List.fromList(utf8.encode(manifestBody)),
      ),
      StarterArchiveEntry(
        path: 'starter_pack/audio/word.wav',
        bytes: Uint8List.fromList([1, 2, 3, 4]),
      ),
      StarterArchiveEntry(
        path: 'scope_sequence.json',
        bytes: Uint8List.fromList(utf8.encode('{"levels":[],"stories":[]}')),
      ),
    ]);

void main() {
  late Directory support;

  setUp(() {
    support = Directory.systemTemp.createTempSync('starter_content_test');
  });

  tearDown(() {
    if (support.existsSync()) support.deleteSync(recursive: true);
  });

  File file(String relative) =>
      File(p.joinAll([support.path, ...relative.split('/')]));

  test('fresh install (no manifest.json): extracts everything and writes '
      'the marker + scope sequence', () async {
    final bytes = _archive();
    final result = await syncBundledStarterContent(
      archiveBytes: bytes,
      supportDirectory: support,
    );

    expect(result, StarterContentSyncResult.extracted);
    expect(file('starter_pack/manifest.json').readAsStringSync(),
        '{"id":"pack.starter"}');
    expect(file('starter_pack/audio/word.wav').readAsBytesSync(),
        [1, 2, 3, 4]);
    expect(file('scope_sequence.json').readAsStringSync(),
        '{"levels":[],"stories":[]}');
    expect(
      file('starter_pack/$kBundledChecksumMarkerFileName').readAsStringSync(),
      StarterArchive.decode(bytes).checksum,
    );
    // No staging leftovers.
    expect(
      Directory(p.join(support.path, kStarterPackStagingDirectoryName))
          .existsSync(),
      isFalse,
    );
  });

  test('same archive again: up to date, nothing rewritten', () async {
    final bytes = _archive();
    await syncBundledStarterContent(
        archiveBytes: bytes, supportDirectory: support);

    // Simulate a later local mutation the no-op run must not undo.
    file('starter_pack/audio/word.wav').writeAsBytesSync([9, 9]);

    final result = await syncBundledStarterContent(
        archiveBytes: bytes, supportDirectory: support);

    expect(result, StarterContentSyncResult.upToDate);
    expect(file('starter_pack/audio/word.wav').readAsBytesSync(), [9, 9]);
  });

  test('updated archive over a previous extraction: re-extracts and '
      'replaces the whole starter_pack directory', () async {
    await syncBundledStarterContent(
        archiveBytes: _archive(manifestBody: '{"v":"old"}'),
        supportDirectory: support);
    // A file from the old extraction that the new archive does not carry
    // must not survive the swap.
    file('starter_pack/audio/stale.wav').writeAsBytesSync([5]);

    final newBytes = _archive(manifestBody: '{"v":"new"}');
    final result = await syncBundledStarterContent(
        archiveBytes: newBytes, supportDirectory: support);

    expect(result, StarterContentSyncResult.extracted);
    expect(file('starter_pack/manifest.json').readAsStringSync(), '{"v":"new"}');
    expect(file('starter_pack/audio/stale.wav').existsSync(), isFalse);
    expect(
      file('starter_pack/$kBundledChecksumMarkerFileName').readAsStringSync(),
      StarterArchive.decode(newBytes).checksum,
    );
  });

  test('sideloaded directory (manifest present, no marker) wins: nothing '
      'is written anywhere', () async {
    file('starter_pack/manifest.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{"sideloaded":true}');
    file('starter_pack/audio/sideloaded.wav')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync([42]);
    file('scope_sequence.json').writeAsStringSync('{"sideloaded":true}');

    final result = await syncBundledStarterContent(
        archiveBytes: _archive(), supportDirectory: support);

    expect(result, StarterContentSyncResult.preservedExistingContent);
    expect(file('starter_pack/manifest.json').readAsStringSync(),
        '{"sideloaded":true}');
    expect(file('starter_pack/audio/sideloaded.wav').readAsBytesSync(), [42]);
    expect(file('scope_sequence.json').readAsStringSync(),
        '{"sideloaded":true}');
    expect(file('starter_pack/$kBundledChecksumMarkerFileName').existsSync(),
        isFalse);
  });

  test('a sideload after an extraction (marker deleted with the directory) '
      'also wins against the same archive', () async {
    final bytes = _archive();
    await syncBundledStarterContent(
        archiveBytes: bytes, supportDirectory: support);

    // tool/sideload_android.sh: rm -rf starter_pack, then copy fresh
    // content in (no marker).
    Directory(p.join(support.path, kStarterPackDirectoryName))
        .deleteSync(recursive: true);
    file('starter_pack/manifest.json')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync('{"sideloaded":"newer"}');

    final result = await syncBundledStarterContent(
        archiveBytes: bytes, supportDirectory: support);

    expect(result, StarterContentSyncResult.preservedExistingContent);
    expect(file('starter_pack/manifest.json').readAsStringSync(),
        '{"sideloaded":"newer"}');
  });

  test('corrupt archive bytes: throws and leaves existing content intact',
      () async {
    final good = _archive();
    await syncBundledStarterContent(
        archiveBytes: good, supportDirectory: support);

    final corrupt = Uint8List.fromList(good)..[good.length - 1] ^= 0xFF;
    // Make the on-disk state re-extractable so only the corruption gate
    // stands between the bad bytes and the disk.
    file('starter_pack/$kBundledChecksumMarkerFileName')
        .writeAsStringSync('different-checksum');

    await expectLater(
      syncBundledStarterContent(
          archiveBytes: corrupt, supportDirectory: support),
      throwsA(isA<StarterArchiveFormatException>()),
    );
    expect(file('starter_pack/manifest.json').readAsStringSync(),
        '{"id":"pack.starter"}');
  });

  test('a stale staging directory from a crashed extraction is replaced, '
      'not merged', () async {
    final staging =
        Directory(p.join(support.path, kStarterPackStagingDirectoryName))
          ..createSync(recursive: true);
    File(p.join(staging.path, 'leftover.tmp')).writeAsBytesSync([1]);

    final result = await syncBundledStarterContent(
        archiveBytes: _archive(), supportDirectory: support);

    expect(result, StarterContentSyncResult.extracted);
    expect(staging.existsSync(), isFalse);
    expect(file('starter_pack/leftover.tmp').existsSync(), isFalse);
    expect(file('starter_pack/manifest.json').existsSync(), isTrue);
  });
}

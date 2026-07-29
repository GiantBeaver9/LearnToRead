/// Pins the starter-content archive format (`starter_archive.dart`): the
/// writer/reader round-trip, the embedded-checksum integrity gate, the
/// framing errors, and the entry-path safety rules. This is the same code
/// `tool/bundle_content.dart` writes with and boot extraction reads with,
/// so a green round-trip here is what makes the committed
/// `assets/starter_content.bin` trustworthy.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/content/starter_archive.dart';

StarterArchiveEntry _entry(String path, List<int> bytes) =>
    StarterArchiveEntry(path: path, bytes: Uint8List.fromList(bytes));

void main() {
  group('encode/decode round-trip', () {
    test('preserves every path and every byte exactly', () {
      final entries = [
        _entry('starter_pack/manifest.json', utf8.encode('{"id":"pack"}')),
        _entry('scope_sequence.json', utf8.encode('{"levels":[]}')),
        _entry('starter_pack/audio/a.wav', [0, 1, 2, 255, 254, 0, 7]),
        _entry('starter_pack/words/deep/nested/w.wav', []),
      ];

      final decoded = StarterArchive.decode(encodeStarterArchive(entries));

      expect(decoded.entries, hasLength(entries.length));
      for (var i = 0; i < entries.length; i++) {
        expect(decoded.entries[i].path, entries[i].path);
        expect(decoded.entries[i].bytes, entries[i].bytes);
      }
    });

    test('an empty archive round-trips with zero entries', () {
      final decoded = StarterArchive.decode(encodeStarterArchive([]));
      expect(decoded.entries, isEmpty);
      expect(decoded.checksum, hasLength(64));
    });

    test('handles non-ASCII paths and binary bytes', () {
      final bytes = Uint8List.fromList(List.generate(1024, (i) => i % 256));
      final decoded = StarterArchive.decode(
        encodeStarterArchive([_entry('starter_pack/ördbok/naïve.wav', bytes)]),
      );
      expect(decoded.entries.single.path, 'starter_pack/ördbok/naïve.wav');
      expect(decoded.entries.single.bytes, bytes);
    });

    test('identical inputs produce identical bytes and checksum '
        '(deterministic build)', () {
      final entries = [
        _entry('starter_pack/manifest.json', utf8.encode('{}')),
        _entry('starter_pack/audio/a.wav', [1, 2, 3]),
      ];
      final a = encodeStarterArchive(entries);
      final b = encodeStarterArchive(entries);
      expect(a, b);
      expect(StarterArchive.decode(a).checksum,
          StarterArchive.decode(b).checksum);
    });

    test('checksum changes when any content byte changes', () {
      final a = StarterArchive.decode(
        encodeStarterArchive([_entry('starter_pack/a.wav', [1, 2, 3])]),
      );
      final b = StarterArchive.decode(
        encodeStarterArchive([_entry('starter_pack/a.wav', [1, 2, 4])]),
      );
      expect(a.checksum, isNot(b.checksum));
    });
  });

  group('integrity + framing errors', () {
    test('rejects bytes that are not a starter archive (bad magic)', () {
      expect(
        () => StarterArchive.decode(
          Uint8List.fromList(utf8.encode('definitely not an archive at all')),
        ),
        throwsA(isA<StarterArchiveFormatException>()),
      );
    });

    test('rejects an archive shorter than its header', () {
      expect(
        () => StarterArchive.decode(Uint8List.fromList(utf8.encode('LTRC'))),
        throwsA(isA<StarterArchiveFormatException>()),
      );
    });

    test('rejects a flipped content byte (checksum mismatch)', () {
      final bytes =
          encodeStarterArchive([_entry('starter_pack/a.wav', [1, 2, 3])]);
      bytes[bytes.length - 1] ^= 0xFF;
      expect(
        () => StarterArchive.decode(bytes),
        throwsA(isA<StarterArchiveFormatException>()),
      );
    });

    test('rejects a truncated archive', () {
      final bytes = encodeStarterArchive(
        [_entry('starter_pack/a.wav', List.filled(100, 7))],
      );
      expect(
        () => StarterArchive.decode(
          Uint8List.sublistView(bytes, 0, bytes.length - 10),
        ),
        throwsA(isA<StarterArchiveFormatException>()),
      );
    });
  });

  group('entry-path safety', () {
    for (final bad in [
      '',
      '/etc/passwd',
      '../outside.wav',
      'starter_pack/../../outside.wav',
      'starter_pack/./a.wav',
      'starter_pack//a.wav',
      r'starter_pack\a.wav',
    ]) {
      test('encode rejects "$bad"', () {
        expect(
          () => encodeStarterArchive([_entry(bad, [1])]),
          throwsA(isA<StarterArchiveFormatException>()),
        );
      });
    }

    test('encode rejects duplicate paths', () {
      expect(
        () => encodeStarterArchive([
          _entry('starter_pack/a.wav', [1]),
          _entry('starter_pack/a.wav', [2]),
        ]),
        throwsA(isA<StarterArchiveFormatException>()),
      );
    });

    test('decode rejects a hand-forged archive with a traversal path', () {
      // Forge a record region containing "../evil" with a correct checksum,
      // to prove path safety is enforced at decode time too (defense in
      // depth against a tampered-but-recheck-summed asset).
      final path = utf8.encode('../evil');
      final records = BytesBuilder()
        ..add((ByteData(4)..setUint32(0, path.length)).buffer.asUint8List())
        ..add(path)
        ..add((ByteData(4)..setUint32(0, 1)).buffer.asUint8List())
        ..add([7]);
      final recordBytes = records.takeBytes();
      final forged = BytesBuilder()
        ..add(ascii.encode(kStarterArchiveMagic))
        ..add(sha256.convert(recordBytes).bytes)
        ..add(recordBytes);
      expect(
        () => StarterArchive.decode(forged.takeBytes()),
        throwsA(isA<StarterArchiveFormatException>()),
      );
    });
  });

  group('committed asset sanity', () {
    // flutter test runs with the package root as cwd, so the committed
    // archive (when present) is directly readable.
    final bin = File('assets/starter_content.bin');
    test(
      'assets/starter_content.bin decodes and contains the pack manifest '
      'and scope sequence',
      () {
        final archive = StarterArchive.decode(bin.readAsBytesSync());
        final paths = archive.entries.map((e) => e.path).toSet();
        expect(paths, contains('starter_pack/manifest.json'));
        expect(paths, contains('scope_sequence.json'));
        expect(
          jsonDecode(utf8.decode(archive.entries
              .firstWhere((e) => e.path == 'starter_pack/manifest.json')
              .bytes)),
          isA<Map<String, dynamic>>(),
        );
      },
      skip: bin.existsSync()
          ? false
          : 'assets/starter_content.bin not built yet '
              '(run: dart run tool/bundle_content.dart)',
    );
  });
}

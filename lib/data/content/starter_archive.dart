/// The bundled starter-content archive format (`assets/starter_content.bin`).
///
/// The demo starter pack is ~470 small files; declaring each one as a
/// Flutter asset would bloat pubspec and the asset manifest, so the content
/// build concatenates them into ONE self-describing archive that ships as a
/// single asset. `tool/bundle_content.dart` writes it at build time;
/// `starter_content_installer.dart` extracts it into the app-support
/// directory on first run (or when the bundled content changes).
///
/// ## Format (pinned)
///
///  1. Header: 8 ASCII magic bytes `LTRC0001`, then the raw 32-byte SHA-256
///     digest of every byte after the header (the record region).
///  2. Record region: zero or more records back-to-back until EOF, each
///     `uint32be pathLength | UTF-8 path | uint32be byteLength | bytes`,
///     where path is a `'/'`-separated relative path (no `..`/`.`/empty
///     segments, no leading `/`, no `\`).
///  3. The digest doubles as the archive's identity: its lowercase-hex form
///     is what the installer's marker file records to detect "the bundled
///     content changed since last extraction".
///
/// Deliberately Flutter-free (dart:io + crypto only) so the same code runs
/// in `dart run tool/bundle_content.dart`, in `Isolate.run` at boot, and in
/// plain `flutter test` VMs.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// The 8 magic bytes every starter archive begins with: `LTRC0001`.
const String kStarterArchiveMagic = 'LTRC0001';

/// Total header length: magic + raw SHA-256 digest.
const int kStarterArchiveHeaderLength = 8 + 32;

/// A starter archive that could not be decoded: wrong magic, truncated
/// framing, a checksum mismatch, or an unsafe entry path.
class StarterArchiveFormatException implements Exception {
  const StarterArchiveFormatException(this.message);

  final String message;

  @override
  String toString() => 'StarterArchiveFormatException: $message';
}

/// One file inside a starter archive: a safe `'/'`-separated relative
/// [path] and its exact [bytes].
class StarterArchiveEntry {
  StarterArchiveEntry({required this.path, required this.bytes});

  final String path;
  final Uint8List bytes;
}

/// True iff [path] is a safe archive entry path: relative, `'/'`-separated,
/// and unable to escape the extraction directory.
bool isSafeArchivePath(String path) {
  if (path.isEmpty || path.startsWith('/') || path.contains('\\')) {
    return false;
  }
  final segments = path.split('/');
  return !segments.any((s) => s.isEmpty || s == '.' || s == '..');
}

/// Encodes [entries] into the archive format above. Throws
/// [StarterArchiveFormatException] on an unsafe or duplicate entry path.
Uint8List encodeStarterArchive(List<StarterArchiveEntry> entries) {
  final seen = <String>{};
  final records = BytesBuilder(copy: false);
  for (final entry in entries) {
    if (!isSafeArchivePath(entry.path)) {
      throw StarterArchiveFormatException('unsafe entry path "${entry.path}"');
    }
    if (!seen.add(entry.path)) {
      throw StarterArchiveFormatException(
        'duplicate entry path "${entry.path}"',
      );
    }
    final pathBytes = utf8.encode(entry.path);
    records
      ..add(_uint32be(pathBytes.length))
      ..add(pathBytes)
      ..add(_uint32be(entry.bytes.length))
      ..add(entry.bytes);
  }
  final recordBytes = records.takeBytes();
  final out = BytesBuilder(copy: false)
    ..add(ascii.encode(kStarterArchiveMagic))
    ..add(sha256.convert(recordBytes).bytes)
    ..add(recordBytes);
  return out.takeBytes();
}

/// A decoded, integrity-verified starter archive.
class StarterArchive {
  StarterArchive._({required this.checksum, required this.entries});

  /// Lowercase hex of the embedded SHA-256 digest — the archive's identity.
  final String checksum;

  /// Every file in the archive, in written order. Entry byte lists are
  /// views into the decoded buffer (no copy).
  final List<StarterArchiveEntry> entries;

  /// Decodes and verifies [bytes]. Throws [StarterArchiveFormatException]
  /// if the magic is wrong, the embedded digest does not match the record
  /// region, any record is truncated, or any entry path is unsafe.
  static StarterArchive decode(Uint8List bytes) {
    if (bytes.length < kStarterArchiveHeaderLength ||
        ascii.decode(bytes.sublist(0, 8), allowInvalid: true) !=
            kStarterArchiveMagic) {
      throw const StarterArchiveFormatException(
        'not a starter archive (bad magic)',
      );
    }
    final embedded = bytes.sublist(8, kStarterArchiveHeaderLength);
    final records = Uint8List.sublistView(bytes, kStarterArchiveHeaderLength);
    final actual = sha256.convert(records).bytes;
    if (!_bytesEqual(embedded, actual)) {
      throw const StarterArchiveFormatException(
        'checksum mismatch (corrupt or truncated archive)',
      );
    }

    final data = ByteData.sublistView(records);
    final entries = <StarterArchiveEntry>[];
    var offset = 0;
    while (offset < records.length) {
      if (records.length - offset < 4) {
        throw const StarterArchiveFormatException('truncated record header');
      }
      final pathLength = data.getUint32(offset);
      offset += 4;
      if (records.length - offset < pathLength) {
        throw const StarterArchiveFormatException('truncated entry path');
      }
      final path =
          utf8.decode(Uint8List.sublistView(records, offset, offset + pathLength));
      offset += pathLength;
      if (!isSafeArchivePath(path)) {
        throw StarterArchiveFormatException('unsafe entry path "$path"');
      }
      if (records.length - offset < 4) {
        throw const StarterArchiveFormatException('truncated record header');
      }
      final byteLength = data.getUint32(offset);
      offset += 4;
      if (records.length - offset < byteLength) {
        throw const StarterArchiveFormatException('truncated entry bytes');
      }
      entries.add(StarterArchiveEntry(
        path: path,
        bytes: Uint8List.sublistView(records, offset, offset + byteLength),
      ));
      offset += byteLength;
    }

    return StarterArchive._(
      checksum: _hex(embedded),
      entries: entries,
    );
  }
}

Uint8List _uint32be(int value) {
  assert(value >= 0 && value <= 0xFFFFFFFF);
  return Uint8List(4)..buffer.asByteData().setUint32(0, value);
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

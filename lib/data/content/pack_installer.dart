/// Verified, atomic installation of downloaded pack bundles
/// (PRD §8 Unit 11: "verifies checksum before install… atomic install:
/// verify → swap"; §9 A-15; ticket `content-delivery` accept entries 4, 5).
///
/// This is the app's trust boundary for content. Bytes arrive from a CDN
/// over a network that can truncate, stall, or hand back something else
/// entirely; everything downstream of this file — `pack_loader.dart`,
/// `content_repository.dart`, every feature that renders a story — treats
/// installed content as trusted. That asymmetry is only safe because
/// nothing reaches the installed-packs directory without first being decoded
/// in full and checksum-verified in memory.
///
/// ## Wire bundle format (pinned)
///
/// ```text
/// bytes[0..4)               big-endian uint32 headerLength
/// bytes[4..4+headerLength)  UTF-8 JSON:
///     {"manifest": <StoryPack.toJson() map>,
///      "files": [{"ref": "<asset ref>", "length": <int>}, …]}
/// remaining bytes           each files[i]'s raw bytes, exactly `length`
///                           long, concatenated in list order
/// ```
///
/// A length-prefixed header followed by raw concatenated payloads means a
/// truncated download is *structurally* detectable — the declared lengths do
/// not add up to the bytes present — without needing to parse or decompress
/// anything. `pack_downloader.dart` knows none of this: it moves bytes, this
/// file gives them meaning.
///
/// A bundle may legitimately omit a ref the manifest lists (an optional or
/// not-yet-shipped asset); such a ref simply has no file behind it once
/// installed, and Unit 15's "shows only words it has audio for" filtering
/// handles the consequence. What a bundle may *not* do is declare bytes it
/// does not carry.
///
/// ## Integrity: what A-15 does and does not cover
///
/// A-15 pins integrity for v1 as "SHA-256 checksum listed in the catalog",
/// and that checksum — `computeManifestChecksum` in
/// `lib/pipeline/pack_builder.dart`, reused here, never redefined — is
/// **manifest-scoped**: it covers every byte of the manifest JSON (with its
/// own `checksum` field blanked) and therefore every story, word,
/// grapheme-phoneme mapping, and asset *ref* in the pack. It does not cover
/// the asset *bytes*. A bundle whose manifest is authentic but whose audio
/// payloads were swapped in flight would pass this check.
///
/// That gap is bounded and deliberate for the POC: bundles are served over
/// HTTPS from a static CDN, the payload substitution it admits requires
/// compromising that transport, and the realistic failure this scheme is
/// defending against — truncation, corruption, a half-written file — is
/// caught by the structural decode above. The post-POC hardening path is
/// pinned and small: add a per-file hash (`{"ref", "length", "sha256"}`) to
/// each `files` entry, verify each payload against it while staging, and
/// sign the manifest so the checksum itself is attested rather than merely
/// transported. Both are additive to this format — an old client ignores an
/// unknown header field, and a new client can require it — so neither
/// forces a bundle-format break. See `docs/content-delivery.md`.
///
/// ## Atomicity
///
/// Verify → stage → swap. Verification happens entirely in memory, so a
/// rejected bundle never creates a file at all. Staging writes the new pack
/// under a dot-prefixed scratch directory that is deleted whatever happens.
/// The swap moves the previous install aside, renames the staged tree into
/// place, and only then deletes what it displaced — so an interruption
/// leaves either the old pack or the new one, never a mixture, and a failed
/// or partial download can never corrupt installed content.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:learn_to_read/data/content/pack_loader.dart';
import 'package:learn_to_read/domain/models/pack_manifest.dart';
import 'package:learn_to_read/pipeline/pack_builder.dart'
    show computeManifestChecksum;
import 'package:path/path.dart' as p;

/// Why an install did or did not happen.
enum InstallOutcome {
  /// The bundle verified and is now the installed content for its pack id.
  installed,

  /// The bundle decoded, but its manifest's recomputed checksum did not
  /// equal the one the catalog listed.
  rejectedChecksumMismatch,

  /// The bytes are not a well-formed bundle: too short for the header, a
  /// header that is not the pinned JSON shape, or declared file lengths that
  /// do not match the payload actually present (the truncation signature).
  rejectedMalformedBundle,
}

/// The outcome of one [PackInstaller.installFromBytes] call.
class InstallResult {
  const InstallResult(this.outcome);

  final InstallOutcome outcome;
}

/// One installed pack, as read back off disk.
class InstalledPackInfo {
  const InstalledPackInfo({
    required this.id,
    required this.version,
    required this.checksum,
    required this.directory,
  });

  final String id;
  final String version;

  /// The manifest checksum this install was verified against (A-15).
  final String checksum;

  /// The bundle directory, in the shape `pack_loader.dart` loads.
  final Directory directory;
}

/// Installs verified pack bundles into, and enumerates them out of, a
/// caller-supplied directory.
///
/// The directory is injected rather than resolved via `path_provider` so
/// installation is exercisable headlessly against a temp directory; the app
/// passes its documents directory at composition time.
class PackInstaller {
  PackInstaller({required Directory installedPacksDirectory})
    : _root = installedPacksDirectory;

  final Directory _root;

  /// Prefix marking a directory as installer scratch (staging or
  /// about-to-be-deleted). Dot-prefixed so enumeration skips it even if a
  /// process death ever leaves one behind.
  static const String _scratchPrefix = '.';

  /// Decodes, verifies, and atomically installs [bundleBytes]. Never throws.
  ///
  /// [expectedChecksum] is the catalog's A-15 checksum for this pack; the
  /// bundle's manifest is re-checksummed with `computeManifestChecksum` and
  /// compared against it. Only on a match does anything touch the
  /// filesystem, and the write that follows either replaces the prior
  /// install of [packId] entirely or leaves it exactly as it was.
  ///
  /// [packId] is the identity being replaced. It is supplied by the caller
  /// (it came from the catalog entry the download was for) rather than read
  /// out of the bundle, so a bundle can never redirect an install at a pack
  /// id nobody asked for.
  Future<InstallResult> installFromBytes(
    Uint8List bundleBytes, {
    required String packId,
    required String expectedChecksum,
  }) async {
    final decoded = _decodeBundle(bundleBytes);
    if (decoded == null) {
      return const InstallResult(InstallOutcome.rejectedMalformedBundle);
    }

    // A-15: recompute, never trust the manifest's self-reported checksum.
    // Round-tripping through StoryPack.toJson() reproduces exactly the map
    // the build checksummed, independent of how the wire JSON happened to
    // order its keys.
    final manifestJson = decoded.pack.toJson();
    if (computeManifestChecksum(manifestJson) != expectedChecksum) {
      return const InstallResult(InstallOutcome.rejectedChecksumMismatch);
    }

    try {
      await _stageAndSwap(decoded, packId: packId, manifestJson: manifestJson);
    } on Object {
      // Staging is best-effort I/O against a directory the app owns; a
      // failure here (full disk, revoked permission) leaves the previous
      // install untouched by construction, and is reported as a bundle that
      // could not be materialized rather than as a thrown exception.
      return const InstallResult(InstallOutcome.rejectedMalformedBundle);
    }
    return const InstallResult(InstallOutcome.installed);
  }

  /// Every currently installed pack, in unspecified order.
  ///
  /// A directory whose manifest cannot be loaded is not reported: it is not
  /// content the app can serve, and the only way one can exist is outside
  /// tampering, since installs are atomic.
  Future<List<InstalledPackInfo>> installedPacks() async {
    if (!_root.existsSync()) return const [];
    final infos = <InstalledPackInfo>[];
    for (final entity in _root.listSync(followLinks: false)) {
      if (entity is! Directory) continue;
      if (p.basename(entity.path).startsWith(_scratchPrefix)) continue;
      try {
        final loaded = await loadPackFromDirectory(entity);
        infos.add(
          InstalledPackInfo(
            id: loaded.pack.id,
            version: loaded.pack.version,
            checksum: loaded.pack.checksum,
            directory: entity,
          ),
        );
      } on PackLoadException {
        continue;
      }
    }
    return infos;
  }

  /// Loads installed pack [packId], or null if it is not installed.
  Future<LoadedPack?> loadInstalled(String packId) async {
    final dir = _directoryFor(packId);
    if (!dir.existsSync()) return null;
    try {
      return await loadPackFromDirectory(dir);
    } on PackLoadException {
      return null;
    }
  }

  Directory _directoryFor(String packId) =>
      Directory(p.join(_root.path, _sanitize(packId)));

  Future<void> _stageAndSwap(
    _DecodedBundle decoded, {
    required String packId,
    required Map<String, dynamic> manifestJson,
  }) async {
    await _root.create(recursive: true);
    final name = _sanitize(packId);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final staging = Directory(
      p.join(_root.path, '${_scratchPrefix}staging-$name-$stamp'),
    );
    final displaced = Directory(
      p.join(_root.path, '${_scratchPrefix}trash-$name-$stamp'),
    );
    final target = _directoryFor(packId);

    try {
      if (staging.existsSync()) staging.deleteSync(recursive: true);
      await staging.create(recursive: true);

      await File(
        p.join(staging.path, kPackManifestFileName),
      ).writeAsString(jsonEncode(manifestJson), flush: true);
      for (final file in decoded.files) {
        final path = _resolveWithin(staging, file.ref);
        if (path == null) {
          throw FormatException('asset ref escapes the pack: "${file.ref}"');
        }
        final out = File(path);
        await out.parent.create(recursive: true);
        await out.writeAsBytes(file.bytes, flush: true);
      }

      // -- Swap. Move any prior install aside first, so the window in which
      // no directory sits at `target` spans a single rename rather than a
      // recursive delete, and so a failure part-way can put it back.
      final hadPrevious = target.existsSync();
      if (hadPrevious) target.renameSync(displaced.path);
      try {
        staging.renameSync(target.path);
      } on FileSystemException {
        if (hadPrevious && displaced.existsSync()) {
          displaced.renameSync(target.path);
        }
        rethrow;
      }
    } finally {
      if (staging.existsSync()) staging.deleteSync(recursive: true);
      if (displaced.existsSync()) displaced.deleteSync(recursive: true);
    }
  }

  /// Resolves a `'/'`-separated manifest ref inside [root], or null if the
  /// ref is absolute or would escape the directory (`..`) — a bundle must
  /// not be able to write anywhere but its own install directory.
  static String? _resolveWithin(Directory root, String ref) {
    if (ref.isEmpty) return null;
    final segments = ref.split('/');
    if (segments.any((s) => s.isEmpty || s == '.' || s == '..')) return null;
    if (p.isAbsolute(ref)) return null;
    return p.normalize(p.joinAll([root.path, ...segments]));
  }

  static String _sanitize(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

  /// Decodes the pinned wire format, or null if [bytes] are not a
  /// well-formed bundle. Structure only — the checksum comparison is the
  /// caller's next step.
  static _DecodedBundle? _decodeBundle(Uint8List bytes) {
    if (bytes.length < 4) return null;
    final headerLength = ByteData.sublistView(
      bytes,
      0,
      4,
    ).getUint32(0, Endian.big);
    final headerEnd = 4 + headerLength;
    if (headerEnd > bytes.length) return null;

    final Object? header;
    try {
      header = jsonDecode(utf8.decode(bytes.sublist(4, headerEnd)));
    } on FormatException {
      return null;
    }
    if (header is! Map<String, dynamic>) return null;

    final manifestJson = header['manifest'];
    if (manifestJson is! Map<String, dynamic>) return null;
    final filesRaw = header['files'];
    if (filesRaw is! List) return null;

    final entries = <({String ref, int length})>[];
    var declaredTotal = 0;
    for (final raw in filesRaw) {
      if (raw is! Map<String, dynamic>) return null;
      final ref = raw['ref'];
      final length = raw['length'];
      if (ref is! String || length is! int || length < 0) return null;
      entries.add((ref: ref, length: length));
      declaredTotal += length;
    }

    // The truncation check: the payload must be exactly as long as the
    // header says it is. Short means the transfer was cut off; long means
    // these are not the bytes this header describes.
    if (bytes.length - headerEnd != declaredTotal) return null;

    final StoryPack pack;
    try {
      pack = StoryPack.fromJson(manifestJson);
    } on Object {
      return null;
    }

    final files = <_BundleFile>[];
    var offset = headerEnd;
    for (final entry in entries) {
      files.add(
        _BundleFile(
          ref: entry.ref,
          bytes: Uint8List.sublistView(bytes, offset, offset + entry.length),
        ),
      );
      offset += entry.length;
    }
    return _DecodedBundle(pack: pack, files: files);
  }
}

class _BundleFile {
  const _BundleFile({required this.ref, required this.bytes});

  final String ref;
  final Uint8List bytes;
}

class _DecodedBundle {
  const _DecodedBundle({required this.pack, required this.files});

  final StoryPack pack;
  final List<_BundleFile> files;
}

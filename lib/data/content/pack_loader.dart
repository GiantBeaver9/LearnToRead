/// Loading an on-disk pack bundle directory into §5 content models
/// (PRD §8 Unit 11; ticket `content-delivery` accept entry 1).
///
/// A *pack bundle directory* is what both halves of the content pipeline
/// agree on: `<dir>/manifest.json` (the `StoryPack.toJson()` map the
/// `lib/pipeline` build emits) plus every asset the manifest references,
/// each at its `'/'`-separated ref path relative to `<dir>`. The starter
/// pack ships as one of these inside the binary; every CDN pack becomes one
/// when `pack_installer.dart` swaps it into place.
///
/// This loader deliberately does the *least* it can: decode, reconstruct,
/// resolve refs against the filesystem. It does not re-run
/// `validatePackManifest` and it does not verify the manifest checksum —
/// both belong upstream, at the trust boundary
/// (`PackInstaller.installFromBytes`, which refuses to put unverified bytes
/// on disk in the first place). By the time a directory reaches this loader
/// it is already trusted content, and re-verifying it on every launch would
/// buy nothing but startup latency.
library;

import 'dart:convert';
import 'dart:io';

import 'package:learn_to_read/domain/models/pack_manifest.dart';
import 'package:path/path.dart' as p;

/// The manifest file a pack bundle directory carries at its root.
///
/// Deliberately the same name `lib/pipeline`'s build expects of a content
/// directory (`kManifestFileName`): a built bundle and an installed bundle
/// are the same shape on disk, which is what makes "the pack build produces
/// a bundle the app loads end-to-end" (Unit 3 acceptance) a single format
/// rather than two that have to be kept in sync.
const String kPackManifestFileName = 'manifest.json';

/// A pack bundle directory could not be loaded: no `manifest.json`, a
/// manifest that is not valid JSON, a manifest whose root is not a JSON
/// object, or a manifest missing/mistyping a field `StoryPack.fromJson`
/// requires.
///
/// Never thrown for a *missing asset file* — an asset that is not on disk
/// is a resolution result ([LoadedPack.resolveAsset] returning null), not a
/// load failure, because a partially-populated pack must still render the
/// content it does have (Unit 15's "shows only words it has audio for").
class PackLoadException implements Exception {
  const PackLoadException(this.message);

  final String message;

  @override
  String toString() => 'PackLoadException: $message';
}

/// A `StoryPack` together with the directory its assets live in, so a ref
/// inside the manifest can be turned into something playable.
class LoadedPack {
  const LoadedPack({required this.pack, required this.directory});

  /// The manifest, reconstructed into §5 content models.
  final StoryPack pack;

  /// The bundle directory `pack`'s refs resolve against.
  final Directory directory;

  /// The absolute path of `<directory>/<ref>` iff that file exists on disk,
  /// else null. Never throws.
  ///
  /// [ref] is a `'/'`-separated path as authored in the manifest; it is
  /// re-joined with this platform's separator. A ref that tries to escape
  /// the bundle directory (absolute, or containing `..`) resolves to null
  /// rather than reaching outside it.
  String? resolveAsset(String ref) {
    final resolved = _resolve(ref);
    if (resolved == null) return null;
    return File(resolved).existsSync() ? resolved : null;
  }

  /// True iff [ref] has a real file behind it in this bundle.
  bool hasAsset(String ref) => resolveAsset(ref) != null;

  String? _resolve(String ref) {
    if (ref.isEmpty) return null;
    final segments = ref.split('/');
    if (segments.any((s) => s == '..' || s == '.' || s.isEmpty)) return null;
    if (p.isAbsolute(ref)) return null;
    return p.normalize(p.joinAll([directory.path, ...segments]));
  }
}

/// Reads `<directory>/manifest.json` and reconstructs the [StoryPack] it
/// describes.
///
/// Throws [PackLoadException] if the manifest is absent, unreadable, not
/// valid JSON, not a JSON object at its root, or missing a field
/// `StoryPack.fromJson` requires. Asset files are *not* required to exist:
/// the manifest is the source of truth for what the pack contains, and
/// [LoadedPack.resolveAsset] reports per-ref what is actually available.
Future<LoadedPack> loadPackFromDirectory(Directory directory) async {
  final manifestFile = File(p.join(directory.path, kPackManifestFileName));
  if (!manifestFile.existsSync()) {
    throw PackLoadException(
      'no $kPackManifestFileName in pack directory "${directory.path}"',
    );
  }

  final String text;
  try {
    text = await manifestFile.readAsString();
  } on FileSystemException catch (e) {
    throw PackLoadException(
      '$kPackManifestFileName in "${directory.path}" could not be read: '
      '${e.message}',
    );
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException catch (e) {
    throw PackLoadException(
      '$kPackManifestFileName in "${directory.path}" is not valid JSON: '
      '${e.message}',
    );
  }
  if (decoded is! Map<String, dynamic>) {
    throw PackLoadException(
      '$kPackManifestFileName in "${directory.path}" is not a JSON object',
    );
  }

  final StoryPack pack;
  try {
    pack = StoryPack.fromJson(decoded);
  } on Object catch (e) {
    throw PackLoadException(
      '$kPackManifestFileName in "${directory.path}" is not a readable '
      'story pack: $e',
    );
  }

  return LoadedPack(pack: pack, directory: directory);
}

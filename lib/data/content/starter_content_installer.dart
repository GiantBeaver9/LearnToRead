/// First-run extraction of the bundled starter content into the app-support
/// directory.
///
/// The APK ships `assets/starter_content.bin` (see `starter_archive.dart`).
/// At boot, [syncBundledStarterContent] decides whether to materialize it on
/// disk, so `loadPackFromDirectory` stays the single pack-load path — the
/// archive never gets loaded directly, it only produces the same on-disk
/// bundle directory a sideload or CDN install would.
///
/// ## The pinned extraction / coexistence rule
///
/// With `<support>/starter_pack/` as the target and
/// `.bundled_checksum` (the archive's checksum, written only by this
/// extractor, as the last file before the directory swap) as the marker:
///
///  1. `manifest.json` missing → **extract** (fresh install, or wiped/
///     half-written directory).
///  2. `manifest.json` present, marker missing → **leave untouched**: the
///     directory was put there by something other than this extractor
///     (`tool/sideload_android.sh` `rm -rf`s the whole directory, marker
///     included, before copying its own content in — so "manifest without
///     marker" is exactly the sideloaded-more-recently state, and the
///     sideload wins).
///  3. `manifest.json` and marker present, marker == archive checksum →
///     **skip** (this exact archive is already extracted).
///  4. `manifest.json` and marker present, marker != archive checksum →
///     **extract** (the app was updated with new bundled content on top of
///     a previous extraction).
///
/// Extraction is staged: content is written to
/// `<support>/starter_pack.staging/`, the marker written into the staging
/// directory, and only then is the old directory deleted and the staging
/// directory renamed into place. A crash mid-extraction therefore leaves
/// either the old directory fully intact (marker still stale → retried next
/// boot) or the new one fully in place — never a manifest-without-marker
/// state that rule 2 would wrongly pin.
///
/// Entries outside `starter_pack/` (today: `scope_sequence.json`) are
/// written directly under `<support>/` before the swap, so a crash between
/// the two still gets retried.
///
/// Deliberately Flutter-free so it can run inside `Isolate.run` and in
/// plain-VM tests with temp directories.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'starter_archive.dart';

/// Directory name of the bundled starter pack, under the app support
/// directory.
const String kStarterPackDirectoryName = 'starter_pack';

/// Marker file (inside the starter-pack directory) recording the checksum
/// of the archive that produced it. Written only by
/// [syncBundledStarterContent]; its absence next to a manifest means the
/// directory was sideloaded/installed by something else and must be
/// preserved.
const String kBundledChecksumMarkerFileName = '.bundled_checksum';

/// Staging directory name used during extraction, sibling of the target.
const String kStarterPackStagingDirectoryName = 'starter_pack.staging';

/// What [syncBundledStarterContent] decided to do.
enum StarterContentSyncResult {
  /// The archive was extracted (fresh install or updated bundled content).
  extracted,

  /// This exact archive is already on disk; nothing written.
  upToDate,

  /// A manifest without our marker is on disk (sideloaded content) — it
  /// wins; nothing written.
  preservedExistingContent,
}

/// Applies the extraction rule documented above. Throws
/// [StarterArchiveFormatException] on a corrupt archive (before touching
/// any existing on-disk content) and [FileSystemException] on IO failure —
/// callers own the degrade-gracefully posture.
Future<StarterContentSyncResult> syncBundledStarterContent({
  required Uint8List archiveBytes,
  required Directory supportDirectory,
}) async {
  // Decoding verifies the embedded SHA-256 first: a corrupt asset can never
  // clobber good on-disk content.
  final archive = StarterArchive.decode(archiveBytes);

  final starterDirectory =
      Directory(p.join(supportDirectory.path, kStarterPackDirectoryName));
  final manifest = File(p.join(starterDirectory.path, 'manifest.json'));
  final marker =
      File(p.join(starterDirectory.path, kBundledChecksumMarkerFileName));

  if (manifest.existsSync()) {
    if (!marker.existsSync()) {
      return StarterContentSyncResult.preservedExistingContent;
    }
    if (marker.readAsStringSync().trim() == archive.checksum) {
      return StarterContentSyncResult.upToDate;
    }
  }

  final staging = Directory(
    p.join(supportDirectory.path, kStarterPackStagingDirectoryName),
  );
  if (staging.existsSync()) staging.deleteSync(recursive: true);
  staging.createSync(recursive: true);

  const packPrefix = '$kStarterPackDirectoryName/';
  for (final entry in archive.entries) {
    final File target;
    if (entry.path.startsWith(packPrefix)) {
      target = File(p.joinAll(
        [staging.path, ...entry.path.substring(packPrefix.length).split('/')],
      ));
    } else {
      // e.g. scope_sequence.json — lives directly under <support>/.
      target =
          File(p.joinAll([supportDirectory.path, ...entry.path.split('/')]));
    }
    target.parent.createSync(recursive: true);
    target.writeAsBytesSync(entry.bytes, flush: false);
  }
  File(p.join(staging.path, kBundledChecksumMarkerFileName))
      .writeAsStringSync(archive.checksum, flush: true);

  // Swap: delete the old directory, move the fully-written one into place.
  if (starterDirectory.existsSync()) {
    starterDirectory.deleteSync(recursive: true);
  }
  staging.renameSync(starterDirectory.path);

  return StarterContentSyncResult.extracted;
}

/// Background, resumable pack downloads (PRD §8 Unit 11: "downloads new
/// packs in the background on Wi-Fi by default… Download resumes/retries
/// across app restarts"; ticket `content-delivery` accept entries 4, 7, 8).
///
/// This layer moves bytes and nothing else. It does not know the bundle
/// format (that is `pack_installer.dart`'s), it does not verify checksums
/// (same), and it never decides *which* packs to fetch (that is the
/// catalog's filtered entry list). Keeping it format-agnostic is what lets
/// the resume story be so small: a partial download is just a file that is
/// shorter than it will eventually be.
///
/// ## Resume state is the partial file
///
/// There is no download database, no journal, no in-memory queue that has to
/// survive a kill. The staged file `<packId>-<checksum>.part` **is** the
/// persisted state: its length on disk is the resume offset. A brand-new
/// [PackDownloader] pointed at the same staging directory after an app
/// restart therefore resumes exactly where the last attempt stopped, with no
/// recovery code to get wrong — the only way to lose progress is to lose the
/// file itself.
///
/// The checksum in the file name is load-bearing: a pack that gets a new
/// revision gets a new checksum, so a stale partial from the previous
/// revision can never be mistaken for a prefix of the new bytes. It ages out
/// as an orphan file instead of corrupting an install.
///
/// ## Wi-Fi by default
///
/// Unit 11 pins background downloads to Wi-Fi by default. Offline always
/// defers; cellular defers unless the caller explicitly opts in
/// (`allowCellular: true`, the shape a "download over cellular" parental
/// setting would take). Deferring touches neither the network nor the
/// staging directory — a deferred download leaves no trace at all.
///
/// ## No user data flows upward
///
/// [PackFetcher.fetch] takes a URL and a byte offset. That is the entire
/// request surface: there is no header map, no body, no options object, and
/// therefore nowhere a profile id, install id, or usage signal could ride
/// along. Downloads are strictly download-only.
library;

import 'dart:io';

import 'package:learn_to_read/data/content/catalog_client.dart';
import 'package:path/path.dart' as p;

/// The kind of network the device is on right now.
enum ConnectivityType { wifi, cellular, offline }

/// Reports the current connectivity. Injected so tests (and airplane-mode
/// scenarios) need no platform channel.
abstract class ConnectivityInfo {
  Future<ConnectivityType> current();
}

/// How a single byte-fetch attempt ended.
enum PackFetchOutcome {
  /// The fetch reached the end of the resource.
  completed,

  /// The fetch stopped partway. Whatever was already handed to `onBytes` is
  /// real and durable, and a later attempt resumes from after it.
  interrupted,

  /// Nothing could be fetched at all (no connection, DNS, non-200).
  failed,
}

/// Fetches raw bytes for a URL, optionally starting partway in.
///
/// The production implementation is a `dart:io` `HttpClient` adapter issuing
/// a `Range: bytes=<startByte>-` request (no new pub dependency) and must
/// never throw — network trouble is reported as
/// [PackFetchOutcome.interrupted] or [PackFetchOutcome.failed], never as an
/// exception crossing this boundary.
abstract class PackFetcher {
  /// Fetches [url] from byte [startByte], invoking [onBytes] with each chunk
  /// received, in order, as it arrives. Chunks already delivered are never
  /// re-delivered by a later resumed call.
  Future<PackFetchOutcome> fetch(
    Uri url, {
    required int startByte,
    required void Function(List<int> chunk) onBytes,
  });
}

/// How one [PackDownloader.download] call ended.
enum DownloadOutcome {
  /// The bundle is fully staged and ready for `PackInstaller`.
  completed,

  /// Some bytes arrived; the staged prefix grew. A later call resumes.
  interrupted,

  /// Nothing arrived. A later call retries from the same offset.
  failed,

  /// Policy declined to use the current network. Nothing was attempted.
  deferredNoConnectivity,
}

/// Downloads pack bundles into a staging directory, resumably.
class PackDownloader {
  PackDownloader({
    required PackFetcher fetcher,
    required ConnectivityInfo connectivity,
    required Directory stagingDirectory,
  }) : _fetcher = fetcher,
       _connectivity = connectivity,
       _stagingDirectory = stagingDirectory;

  final PackFetcher _fetcher;
  final ConnectivityInfo _connectivity;
  final Directory _stagingDirectory;

  /// The staged (partial or complete) bytes file for ([packId], [checksum]).
  ///
  /// Deterministic across instances and app runs — that is what makes it
  /// usable as resume state. The file may not exist yet; its length when it
  /// does is the resume offset.
  File stagedFile({required String packId, required String checksum}) => File(
    p.join(
      _stagingDirectory.path,
      '${_sanitize(packId)}-${_sanitize(checksum)}.part',
    ),
  );

  /// Downloads (or resumes) [entry]'s bundle into its staged file.
  ///
  /// Returns [DownloadOutcome.deferredNoConnectivity] without touching the
  /// network or the staging directory when the device is offline, or on
  /// cellular with [allowCellular] false (Wi-Fi by default). Otherwise the
  /// fetcher is asked for the bytes after whatever is already staged, and
  /// each chunk is appended and flushed as it arrives, so an app kill at any
  /// instant leaves a valid, resumable prefix rather than a half-written
  /// buffer.
  ///
  /// Re-downloading an already-complete pack is safe: the fetcher is asked
  /// to resume at the full length, has nothing to add, and reports
  /// completed — the staged bytes are never duplicated.
  Future<DownloadOutcome> download(
    CatalogPackEntry entry, {
    bool allowCellular = false,
  }) async {
    final connectivity = await _connectivity.current();
    final permitted = switch (connectivity) {
      ConnectivityType.wifi => true,
      ConnectivityType.cellular => allowCellular,
      ConnectivityType.offline => false,
    };
    if (!permitted) return DownloadOutcome.deferredNoConnectivity;

    final file = stagedFile(packId: entry.id, checksum: entry.checksum);
    await file.parent.create(recursive: true);
    if (!file.existsSync()) file.createSync();
    final startByte = file.lengthSync();

    final PackFetchOutcome outcome;
    final sink = file.openSync(mode: FileMode.writeOnlyAppend);
    try {
      outcome = await _fetcher.fetch(
        entry.downloadUrl,
        startByte: startByte,
        onBytes: (chunk) {
          sink.writeFromSync(chunk);
          sink.flushSync();
        },
      );
    } finally {
      sink.closeSync();
    }

    return switch (outcome) {
      PackFetchOutcome.completed => DownloadOutcome.completed,
      PackFetchOutcome.interrupted => DownloadOutcome.interrupted,
      PackFetchOutcome.failed => DownloadOutcome.failed,
    };
  }

  /// Keeps a pack id or checksum usable as one path segment. Ids are dotted
  /// (`pack.forest`) and checksums are hex today, but a file name is a
  /// filesystem concern and must not inherit whatever a future catalog puts
  /// in an id.
  static String _sanitize(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}

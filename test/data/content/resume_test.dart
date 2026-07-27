// Pins the API of lib/data/content/pack_downloader.dart (PRD §8 Unit 11:
// "downloads new packs in the background on Wi-Fi by default... Download
// resumes/retries across app restarts"; ticket content-delivery accept
// entries 4 and 7). The ticket's test_files list has no dedicated
// pack_downloader_test.dart, so this file -- named for the acceptance it
// exists to prove ("Download resumes/retries across app restarts") -- is
// pack_downloader.dart's full test suite: connectivity/Wi-Fi-default
// policy, interrupted-download resume, retry-after-failure, and the
// download-only no-identifiers request shape all live here.
//
// This suite is authored before the implementation exists, so it is
// EXPECTED to fail to compile until pack_downloader.dart is written with
// exactly the shapes exercised below.
//
// Pinned API surface this suite requires:
//
//   enum ConnectivityType { wifi, cellular, offline }
//   abstract class ConnectivityInfo {
//     Future<ConnectivityType> current();
//   }
//   enum PackFetchOutcome { completed, interrupted, failed }
//   /// Fetches raw bytes for [url] starting at byte [startByte] (0 for a
//   /// fresh download -- a Range-style resume), invoking [onBytes] with
//   /// each chunk received, in order, as it arrives. `completed` means the
//   /// fetch reached the end of the resource; `interrupted` means it
//   /// stopped partway (chunks already delivered via onBytes are real and
//   /// are not re-delivered by a later resumed call); `failed` means
//   /// nothing could be fetched at all. Must never throw in the
//   /// production implementation (a dart:io HttpClient adapter, no new pub
//   /// dependency); carries no argument beyond the URL and the resume
//   /// offset -- no user/profile identifier has anywhere to go.
//   abstract class PackFetcher {
//     Future<PackFetchOutcome> fetch(
//       Uri url, {
//       required int startByte,
//       required void Function(List<int> chunk) onBytes,
//     });
//   }
//   enum DownloadOutcome { completed, interrupted, failed, deferredNoConnectivity }
//   class PackDownloader {
//     PackDownloader({
//       required PackFetcher fetcher,
//       required ConnectivityInfo connectivity,
//       required Directory stagingDirectory,
//     });
//
//     /// The staged (partial or complete) bytes file for (packId,
//     /// checksum) -- this file IS the persisted download-resume state: a
//     /// freshly constructed PackDownloader pointed at the same
//     /// stagingDirectory resumes from however many bytes already sit on
//     /// disk here, with no separate metadata file. Naming includes the
//     /// checksum so a version bump (different checksum) never resumes
//     /// from a stale, unrelated partial file.
//     File stagedFile({required String packId, required String checksum});
//
//     /// Wi-Fi-by-default (PRD Unit 11): if connectivity is
//     /// ConnectivityType.offline, always returns deferredNoConnectivity
//     /// without touching the network or staging file. If
//     /// ConnectivityType.cellular and !allowCellular, same. Otherwise
//     /// calls fetcher.fetch(entry.downloadUrl, startByte: <current length
//     /// of stagedFile(...) on disk>, onBytes: <append each chunk to that
//     /// file, flushed>) and returns completed/interrupted/failed per the
//     /// fetcher's outcome.
//     Future<DownloadOutcome> download(CatalogPackEntry entry, {bool allowCellular = false});
//   }
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/content/catalog_client.dart';
import 'package:learn_to_read/data/content/pack_downloader.dart';

// ---------------------------------------------------------------------------
// Fakes.
// ---------------------------------------------------------------------------

class _FixedConnectivity implements ConnectivityInfo {
  _FixedConnectivity(this.type);
  final ConnectivityType type;

  @override
  Future<ConnectivityType> current() async => type;
}

class _FetchCall {
  _FetchCall({required this.url, required this.startByte});
  final Uri url;
  final int startByte;
}

class _FetchStep {
  _FetchStep({required this.chunks, required this.outcome});
  final List<List<int>> chunks;
  final PackFetchOutcome outcome;
}

/// Delivers each scripted step's bytes/outcome in order, one step per call.
/// Records every call's (url, startByte) -- and nothing else -- to prove
/// the download-only request shape.
class _ScriptedFetcher implements PackFetcher {
  _ScriptedFetcher(this.steps);
  final List<_FetchStep> steps;
  final List<_FetchCall> calls = [];
  int _next = 0;

  @override
  Future<PackFetchOutcome> fetch(
    Uri url, {
    required int startByte,
    required void Function(List<int> chunk) onBytes,
  }) async {
    calls.add(_FetchCall(url: url, startByte: startByte));
    if (_next >= steps.length) {
      throw StateError('test bug: _ScriptedFetcher ran out of scripted steps');
    }
    final step = steps[_next++];
    for (final chunk in step.chunks) {
      onBytes(chunk);
    }
    return step.outcome;
  }
}

// ---------------------------------------------------------------------------
// Fixture bytes: format-agnostic (pack_downloader moves raw bytes only --
// decoding the pack bundle format is pack_installer's job, covered
// elsewhere).
// ---------------------------------------------------------------------------

Uint8List _payload(int length, {int seed = 0}) =>
    Uint8List.fromList(List.generate(length, (i) => (i + seed) % 256));

String _sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

CatalogPackEntry _entry({
  String id = 'pack.forest',
  String checksum = 'checksum-forest',
  Uri? downloadUrl,
}) => CatalogPackEntry(
  id: id,
  version: '1.0.0',
  minAppVersion: '1.0.0',
  checksum: checksum,
  downloadUrl:
      downloadUrl ?? Uri.parse('https://cdn.example.com/packs/$id.bundle'),
  sizeBytes: null,
);

void main() {
  late Directory stagingDir;

  setUp(() {
    stagingDir = Directory.systemTemp.createTempSync('resume_test_staging_');
  });

  tearDown(() {
    if (stagingDir.existsSync()) stagingDir.deleteSync(recursive: true);
  });

  group('POSITIVE: a single-shot download on Wi-Fi completes', () {
    test(
      'fetcher is called once with startByte 0 and the staged file matches the delivered bytes',
      () async {
        final full = _payload(2000);
        final fetcher = _ScriptedFetcher([
          _FetchStep(chunks: [full], outcome: PackFetchOutcome.completed),
        ]);
        final downloader = PackDownloader(
          fetcher: fetcher,
          connectivity: _FixedConnectivity(ConnectivityType.wifi),
          stagingDirectory: stagingDir,
        );
        final entry = _entry(checksum: _sha256Hex(full));

        final outcome = await downloader.download(entry);

        expect(outcome, DownloadOutcome.completed);
        expect(fetcher.calls, hasLength(1));
        expect(fetcher.calls.single.startByte, 0);
        final staged = downloader.stagedFile(
          packId: entry.id,
          checksum: entry.checksum,
        );
        expect(staged.readAsBytesSync(), full);
      },
    );
  });

  group('NEGATIVE/POSITIVE: Wi-Fi-default connectivity policy', () {
    test(
      'cellular connectivity with default allowCellular=false defers without touching the network',
      () async {
        final fetcher = _ScriptedFetcher([]);
        final downloader = PackDownloader(
          fetcher: fetcher,
          connectivity: _FixedConnectivity(ConnectivityType.cellular),
          stagingDirectory: stagingDir,
        );

        final outcome = await downloader.download(_entry());

        expect(outcome, DownloadOutcome.deferredNoConnectivity);
        expect(fetcher.calls, isEmpty);
        expect(stagingDir.listSync(), isEmpty);
      },
    );

    test(
      'cellular connectivity with allowCellular=true proceeds and calls the fetcher',
      () async {
        final full = _payload(500);
        final fetcher = _ScriptedFetcher([
          _FetchStep(chunks: [full], outcome: PackFetchOutcome.completed),
        ]);
        final downloader = PackDownloader(
          fetcher: fetcher,
          connectivity: _FixedConnectivity(ConnectivityType.cellular),
          stagingDirectory: stagingDir,
        );

        final outcome = await downloader.download(
          _entry(checksum: _sha256Hex(full)),
          allowCellular: true,
        );

        expect(outcome, DownloadOutcome.completed);
        expect(fetcher.calls, hasLength(1));
      },
    );

    test(
      'offline connectivity always defers, even with allowCellular=true',
      () async {
        final fetcher = _ScriptedFetcher([]);
        final downloader = PackDownloader(
          fetcher: fetcher,
          connectivity: _FixedConnectivity(ConnectivityType.offline),
          stagingDirectory: stagingDir,
        );

        final outcome = await downloader.download(
          _entry(),
          allowCellular: true,
        );

        expect(outcome, DownloadOutcome.deferredNoConnectivity);
        expect(fetcher.calls, isEmpty);
      },
    );

    test(
      'plain Wi-Fi connectivity proceeds without needing allowCellular',
      () async {
        final full = _payload(300);
        final fetcher = _ScriptedFetcher([
          _FetchStep(chunks: [full], outcome: PackFetchOutcome.completed),
        ]);
        final downloader = PackDownloader(
          fetcher: fetcher,
          connectivity: _FixedConnectivity(ConnectivityType.wifi),
          stagingDirectory: stagingDir,
        );

        final outcome = await downloader.download(
          _entry(checksum: _sha256Hex(full)),
        );

        expect(outcome, DownloadOutcome.completed);
      },
    );
  });

  group('CORE: interrupted download resumes across a simulated app restart', () {
    test(
      'an interruption leaves exactly the delivered prefix staged, and a fresh downloader '
      'instance resumes from that offset to completion',
      () async {
        final full = _payload(10000, seed: 7);
        final prefix = full.sublist(0, 4000);
        final suffix = full.sublist(4000);
        final entry = _entry(checksum: _sha256Hex(full));

        // -- "Before restart": the connection drops after 4000 of 10000 bytes.
        final fetcherBeforeRestart = _ScriptedFetcher([
          _FetchStep(chunks: [prefix], outcome: PackFetchOutcome.interrupted),
        ]);
        final downloaderBeforeRestart = PackDownloader(
          fetcher: fetcherBeforeRestart,
          connectivity: _FixedConnectivity(ConnectivityType.wifi),
          stagingDirectory: stagingDir,
        );

        final firstOutcome = await downloaderBeforeRestart.download(entry);

        expect(firstOutcome, DownloadOutcome.interrupted);
        final stagedAfterInterruption = downloaderBeforeRestart.stagedFile(
          packId: entry.id,
          checksum: entry.checksum,
        );
        expect(stagedAfterInterruption.readAsBytesSync(), prefix);

        // -- "App restarts": a brand-new PackDownloader instance, brand-new
        // fetcher, same staging directory -- no in-memory state survives, the
        // staged file on disk IS the persisted resume state.
        final fetcherAfterRestart = _ScriptedFetcher([
          _FetchStep(chunks: [suffix], outcome: PackFetchOutcome.completed),
        ]);
        final downloaderAfterRestart = PackDownloader(
          fetcher: fetcherAfterRestart,
          connectivity: _FixedConnectivity(ConnectivityType.wifi),
          stagingDirectory: stagingDir,
        );

        final secondOutcome = await downloaderAfterRestart.download(entry);

        expect(secondOutcome, DownloadOutcome.completed);
        expect(
          fetcherAfterRestart.calls.single.startByte,
          4000,
          reason:
              'resume must ask for bytes starting exactly where the interrupted attempt left off',
        );
        final stagedAfterResume = downloaderAfterRestart.stagedFile(
          packId: entry.id,
          checksum: entry.checksum,
        );
        expect(
          stagedAfterResume.readAsBytesSync(),
          full,
          reason:
              'resumed bytes must concatenate to the original content exactly',
        );
      },
    );

    test(
      'a download interrupted twice resumes correctly a second time from the accumulated offset',
      () async {
        final full = _payload(9000, seed: 3);
        final part1 = full.sublist(0, 2000);
        final part2 = full.sublist(2000, 5000);
        final part3 = full.sublist(5000);
        final entry = _entry(checksum: _sha256Hex(full));

        final downloader1 = PackDownloader(
          fetcher: _ScriptedFetcher([
            _FetchStep(chunks: [part1], outcome: PackFetchOutcome.interrupted),
          ]),
          connectivity: _FixedConnectivity(ConnectivityType.wifi),
          stagingDirectory: stagingDir,
        );
        expect(await downloader1.download(entry), DownloadOutcome.interrupted);

        final fetcher2 = _ScriptedFetcher([
          _FetchStep(chunks: [part2], outcome: PackFetchOutcome.interrupted),
        ]);
        final downloader2 = PackDownloader(
          fetcher: fetcher2,
          connectivity: _FixedConnectivity(ConnectivityType.wifi),
          stagingDirectory: stagingDir,
        );
        expect(await downloader2.download(entry), DownloadOutcome.interrupted);
        expect(fetcher2.calls.single.startByte, 2000);

        final fetcher3 = _ScriptedFetcher([
          _FetchStep(chunks: [part3], outcome: PackFetchOutcome.completed),
        ]);
        final downloader3 = PackDownloader(
          fetcher: fetcher3,
          connectivity: _FixedConnectivity(ConnectivityType.wifi),
          stagingDirectory: stagingDir,
        );
        expect(await downloader3.download(entry), DownloadOutcome.completed);
        expect(fetcher3.calls.single.startByte, 5000);

        expect(
          downloader3
              .stagedFile(packId: entry.id, checksum: entry.checksum)
              .readAsBytesSync(),
          full,
        );
      },
    );
  });

  group('NEGATIVE/POSITIVE: retry after outright failure', () {
    test(
      'a failed fetch (nothing delivered) leaves no staged bytes and a later retry succeeds',
      () async {
        final full = _payload(1200, seed: 11);
        final entry = _entry(checksum: _sha256Hex(full));

        final failingFetcher = _ScriptedFetcher([
          _FetchStep(chunks: const [], outcome: PackFetchOutcome.failed),
        ]);
        final downloader = PackDownloader(
          fetcher: failingFetcher,
          connectivity: _FixedConnectivity(ConnectivityType.wifi),
          stagingDirectory: stagingDir,
        );

        final firstOutcome = await downloader.download(entry);
        expect(firstOutcome, DownloadOutcome.failed);
        final staged = downloader.stagedFile(
          packId: entry.id,
          checksum: entry.checksum,
        );
        expect(
          staged.existsSync() ? staged.readAsBytesSync() : const <int>[],
          isEmpty,
        );

        final succeedingFetcher = _ScriptedFetcher([
          _FetchStep(chunks: [full], outcome: PackFetchOutcome.completed),
        ]);
        final retryDownloader = PackDownloader(
          fetcher: succeedingFetcher,
          connectivity: _FixedConnectivity(ConnectivityType.wifi),
          stagingDirectory: stagingDir,
        );

        final retryOutcome = await retryDownloader.download(entry);
        expect(retryOutcome, DownloadOutcome.completed);
        expect(
          retryDownloader
              .stagedFile(packId: entry.id, checksum: entry.checksum)
              .readAsBytesSync(),
          full,
        );
      },
    );
  });

  group(
    'EDGE: re-downloading an already-complete pack is safe and does not duplicate bytes',
    () {
      test(
        'calling download again after completion re-queries at the full offset and stays correct',
        () async {
          final full = _payload(800, seed: 5);
          final entry = _entry(checksum: _sha256Hex(full));

          final downloader = PackDownloader(
            fetcher: _ScriptedFetcher([
              _FetchStep(chunks: [full], outcome: PackFetchOutcome.completed),
            ]),
            connectivity: _FixedConnectivity(ConnectivityType.wifi),
            stagingDirectory: stagingDir,
          );
          expect(await downloader.download(entry), DownloadOutcome.completed);

          // A second downloader instance (as if invoked again on a later
          // launch) finds the staged file already complete: the fetcher is
          // asked to resume from the full length and reports completed with
          // nothing left to add.
          final secondFetcher = _ScriptedFetcher([
            _FetchStep(chunks: const [], outcome: PackFetchOutcome.completed),
          ]);
          final secondDownloader = PackDownloader(
            fetcher: secondFetcher,
            connectivity: _FixedConnectivity(ConnectivityType.wifi),
            stagingDirectory: stagingDir,
          );

          final outcome = await secondDownloader.download(entry);

          expect(outcome, DownloadOutcome.completed);
          expect(secondFetcher.calls.single.startByte, full.length);
          expect(
            secondDownloader
                .stagedFile(packId: entry.id, checksum: entry.checksum)
                .readAsBytesSync(),
            full,
          );
        },
      );
    },
  );

  group('POSITIVE: no user data flows upward -- download request shape', () {
    test(
      'each fetch call carries only (url, startByte) -- no identifier of any kind',
      () async {
        final full = _payload(1000);
        final entry = _entry(
          checksum: _sha256Hex(full),
          downloadUrl: Uri.parse(
            'https://cdn.example.com/packs/pack.forest.bundle',
          ),
        );
        final fetcher = _ScriptedFetcher([
          _FetchStep(
            chunks: [full.sublist(0, 400)],
            outcome: PackFetchOutcome.interrupted,
          ),
        ]);
        final downloader = PackDownloader(
          fetcher: fetcher,
          connectivity: _FixedConnectivity(ConnectivityType.wifi),
          stagingDirectory: stagingDir,
        );

        await downloader.download(entry);

        final call = fetcher.calls.single;
        expect(call.url, entry.downloadUrl);
        expect(call.startByte, 0);
        // The PackFetcher interface itself has no parameter through which a
        // profile id, install id, or any other identifier could be passed --
        // url and startByte are the entire request. Downloading a second
        // time confirms the shape never grows a hidden identifier either.
        final fetcher2 = _ScriptedFetcher([
          _FetchStep(
            chunks: [full.sublist(400)],
            outcome: PackFetchOutcome.completed,
          ),
        ]);
        final downloader2 = PackDownloader(
          fetcher: fetcher2,
          connectivity: _FixedConnectivity(ConnectivityType.wifi),
          stagingDirectory: stagingDir,
        );
        await downloader2.download(entry);
        expect(fetcher2.calls.single.url, entry.downloadUrl);
        expect(fetcher2.calls.single.startByte, 400);
      },
    );
  });
}

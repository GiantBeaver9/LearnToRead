// Pins the API of lib/data/content/catalog_client.dart (PRD §8 Unit 11:
// "App checks a static catalog.json on launch (when online)... Pack/catalog
// versioning respects minAppVersion -- a pack requiring a newer app is
// hidden, never downloaded-and-broken"; ticket content-delivery accept
// entries 3, 6, 8). This suite is authored before the implementation
// exists, so it is EXPECTED to fail to compile until catalog_client.dart is
// written with exactly the shapes exercised below.
//
// This file covers general catalog parsing, fetch-failure silence, and the
// download-only request-shape contract. The minAppVersion boundary matrix
// (equal/older/newer, multi-segment version comparison) is the DEDICATED
// subject of test/data/content/min_app_version_test.dart -- this file only
// asserts the filtering exists, not its full boundary behavior.
//
// Pinned API surface this suite requires:
//
//   class CatalogPackEntry {
//     final String id;
//     final String version;
//     final String minAppVersion;
//     final String checksum;       // A-15: SHA-256 hex, == the pack's own
//                                   // StoryPack.checksum as produced by
//                                   // pack_builder's computeManifestChecksum
//     final Uri downloadUrl;
//     final int? sizeBytes;
//   }
//   class CatalogFetchResult {
//     final bool success;
//     final List<CatalogPackEntry> entries; // already minAppVersion-filtered; empty when !success
//   }
//   /// Fetches raw catalog.json text over the network. Takes NO arguments --
//   /// by construction there is nowhere to thread a user/profile identifier
//   /// through a catalog check (download-only contract, PRD §8 Unit 11 "no
//   /// user data flows upward"). Returns null on ANY failure (offline, DNS,
//   /// timeout, non-200); must never throw.
//   abstract class CatalogFetcher {
//     Future<String?> fetchCatalogJson();
//   }
//   class CatalogClient {
//     CatalogClient({required CatalogFetcher fetcher});
//     /// Never throws. Fetcher failure (null) or a catalog body that is not
//     /// a JSON object, has no list-typed "packs" key, or contains a pack
//     /// entry missing any required field => CatalogFetchResult(success:
//     /// false, entries: const []) -- catalog fetch failure is silent,
//     /// installed content is a concern for content_repository, not this
//     /// client. On success, entries excludes every pack whose
//     /// minAppVersion is newer than currentAppVersion.
//     Future<CatalogFetchResult> checkCatalog({required String currentAppVersion});
//   }
//
// catalog.json wire shape (pinned):
//   { "packs": [ { "id", "version", "minAppVersion", "checksum",
//                  "downloadUrl", "sizeBytes"? }, ... ] }
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/content/catalog_client.dart';

class _FakeCatalogFetcher implements CatalogFetcher {
  _FakeCatalogFetcher({this.response});
  String? response;
  int callCount = 0;

  @override
  Future<String?> fetchCatalogJson() async {
    callCount++;
    return response;
  }
}

String _catalogJson(List<Map<String, Object?>> packs) =>
    jsonEncode({'packs': packs});

Map<String, Object?> _entryJson({
  String id = 'pack.forest',
  String version = '1.0.0',
  String minAppVersion = '1.0.0',
  String checksum = 'deadbeef',
  String downloadUrl = 'https://cdn.example.com/packs/pack.forest-1.0.0.bundle',
  int? sizeBytes = 4096,
}) => {
  'id': id,
  'version': version,
  'minAppVersion': minAppVersion,
  'checksum': checksum,
  'downloadUrl': downloadUrl,
  if (sizeBytes != null) 'sizeBytes': sizeBytes,
};

void main() {
  group(
    'POSITIVE: a well-formed catalog parses into CatalogPackEntry values',
    () {
      test('a single-pack catalog parses every field correctly', () async {
        final fetcher = _FakeCatalogFetcher(
          response: _catalogJson([_entryJson()]),
        );
        final client = CatalogClient(fetcher: fetcher);

        final result = await client.checkCatalog(currentAppVersion: '1.0.0');

        expect(result.success, isTrue);
        final entry = result.entries.single;
        expect(entry.id, 'pack.forest');
        expect(entry.version, '1.0.0');
        expect(entry.minAppVersion, '1.0.0');
        expect(entry.checksum, 'deadbeef');
        expect(
          entry.downloadUrl,
          Uri.parse('https://cdn.example.com/packs/pack.forest-1.0.0.bundle'),
        );
        expect(entry.sizeBytes, 4096);
      });

      test(
        'sizeBytes is optional and null when absent from the wire JSON',
        () async {
          final fetcher = _FakeCatalogFetcher(
            response: _catalogJson([_entryJson(sizeBytes: null)]),
          );
          final client = CatalogClient(fetcher: fetcher);

          final result = await client.checkCatalog(currentAppVersion: '1.0.0');

          expect(result.entries.single.sizeBytes, isNull);
        },
      );

      test('multiple packs all parse, order preserved', () async {
        final fetcher = _FakeCatalogFetcher(
          response: _catalogJson([
            _entryJson(id: 'pack.a'),
            _entryJson(id: 'pack.b'),
            _entryJson(id: 'pack.c'),
          ]),
        );
        final client = CatalogClient(fetcher: fetcher);

        final result = await client.checkCatalog(currentAppVersion: '1.0.0');

        expect(result.entries.map((e) => e.id).toList(), [
          'pack.a',
          'pack.b',
          'pack.c',
        ]);
      });

      test(
        'a pack whose minAppVersion equals the current app version is included (boundary)',
        () async {
          final fetcher = _FakeCatalogFetcher(
            response: _catalogJson([_entryJson(minAppVersion: '2.3.0')]),
          );
          final client = CatalogClient(fetcher: fetcher);

          final result = await client.checkCatalog(currentAppVersion: '2.3.0');

          expect(result.entries, hasLength(1));
        },
      );
    },
  );

  group('NEGATIVE: minAppVersion filtering hides too-new packs', () {
    test('a pack requiring a newer app is excluded from entries', () async {
      final fetcher = _FakeCatalogFetcher(
        response: _catalogJson([
          _entryJson(id: 'pack.old', minAppVersion: '1.0.0'),
          _entryJson(id: 'pack.new', minAppVersion: '9.9.9'),
        ]),
      );
      final client = CatalogClient(fetcher: fetcher);

      final result = await client.checkCatalog(currentAppVersion: '1.0.0');

      expect(result.success, isTrue);
      expect(result.entries.map((e) => e.id), ['pack.old']);
      expect(result.entries.any((e) => e.id == 'pack.new'), isFalse);
    });
  });

  group('NEGATIVE: catalog fetch failure is silent', () {
    test(
      'a fetcher returning null (offline/timeout) yields a silent, empty failure result',
      () async {
        final fetcher = _FakeCatalogFetcher(response: null);
        final client = CatalogClient(fetcher: fetcher);

        final result = await client.checkCatalog(currentAppVersion: '1.0.0');

        expect(result.success, isFalse);
        expect(result.entries, isEmpty);
      },
    );

    test('checkCatalog never throws even when the fetcher fails', () async {
      final fetcher = _FakeCatalogFetcher(response: null);
      final client = CatalogClient(fetcher: fetcher);

      await expectLater(
        client.checkCatalog(currentAppVersion: '1.0.0'),
        completes,
      );
    });
  });

  group('EDGE: malformed catalog bodies fail silently rather than throwing', () {
    test(
      'non-JSON body yields success:false, entries empty, no throw',
      () async {
        final fetcher = _FakeCatalogFetcher(response: 'not json at all {{{');
        final client = CatalogClient(fetcher: fetcher);

        final result = await client.checkCatalog(currentAppVersion: '1.0.0');

        expect(result.success, isFalse);
        expect(result.entries, isEmpty);
      },
    );

    test('a JSON array instead of an object yields a silent failure', () async {
      final fetcher = _FakeCatalogFetcher(response: jsonEncode([1, 2, 3]));
      final client = CatalogClient(fetcher: fetcher);

      final result = await client.checkCatalog(currentAppVersion: '1.0.0');

      expect(result.success, isFalse);
      expect(result.entries, isEmpty);
    });

    test('a JSON object with no "packs" key yields a silent failure', () async {
      final fetcher = _FakeCatalogFetcher(
        response: jsonEncode({'notPacks': []}),
      );
      final client = CatalogClient(fetcher: fetcher);

      final result = await client.checkCatalog(currentAppVersion: '1.0.0');

      expect(result.success, isFalse);
      expect(result.entries, isEmpty);
    });

    test(
      'a "packs" value that is not a list yields a silent failure',
      () async {
        final fetcher = _FakeCatalogFetcher(
          response: jsonEncode({'packs': 'nope'}),
        );
        final client = CatalogClient(fetcher: fetcher);

        final result = await client.checkCatalog(currentAppVersion: '1.0.0');

        expect(result.success, isFalse);
        expect(result.entries, isEmpty);
      },
    );

    test(
      'a pack entry missing a required field yields a silent failure for the whole catalog',
      () async {
        final entry = _entryJson()..remove('checksum');
        final fetcher = _FakeCatalogFetcher(response: _catalogJson([entry]));
        final client = CatalogClient(fetcher: fetcher);

        final result = await client.checkCatalog(currentAppVersion: '1.0.0');

        expect(result.success, isFalse);
        expect(result.entries, isEmpty);
      },
    );

    test(
      'an empty "packs" list is a successful, empty catalog (not a failure)',
      () async {
        final fetcher = _FakeCatalogFetcher(response: _catalogJson(const []));
        final client = CatalogClient(fetcher: fetcher);

        final result = await client.checkCatalog(currentAppVersion: '1.0.0');

        expect(result.success, isTrue);
        expect(result.entries, isEmpty);
      },
    );
  });

  group('POSITIVE: no user data flows upward -- request shape', () {
    test(
      'fetchCatalogJson is called with zero arguments -- no identifier can be threaded through it',
      () async {
        final fetcher = _FakeCatalogFetcher(
          response: _catalogJson([_entryJson()]),
        );
        final client = CatalogClient(fetcher: fetcher);

        await client.checkCatalog(currentAppVersion: '1.0.0');

        // The fake's fetchCatalogJson() takes no parameters at all (matching
        // the pinned CatalogFetcher interface): there is no argument list to
        // inspect for a profile id, install id, or any other identifier --
        // the call count alone is everything observable about this request.
        expect(fetcher.callCount, 1);
      },
    );

    test(
      'checking the catalog twice makes exactly two fetch calls, each carrying no data',
      () async {
        final fetcher = _FakeCatalogFetcher(
          response: _catalogJson([_entryJson()]),
        );
        final client = CatalogClient(fetcher: fetcher);

        await client.checkCatalog(currentAppVersion: '1.0.0');
        await client.checkCatalog(currentAppVersion: '1.0.0');

        expect(fetcher.callCount, 2);
      },
    );
  });
}

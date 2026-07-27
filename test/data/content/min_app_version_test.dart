// Dedicated boundary-matrix suite for minAppVersion filtering in
// lib/data/content/catalog_client.dart (PRD §8 Unit 11 pinned: "Pack/catalog
// versioning respects minAppVersion -- a pack requiring a newer app is
// hidden, never downloaded-and-broken"; ticket content-delivery accept
// entry 6, and the outer task instruction calling out "minAppVersion
// filtering (equal/older/newer boundaries)" as its own dedicated coverage).
// General catalog parsing/fetch-failure behavior lives in
// catalog_client_test.dart; this file exists solely to nail down the
// version-comparison semantics precisely, including the case that breaks a
// naive string comparison.
//
// Pinned comparison semantics this suite locks in (dotted-numeric, not
// lexicographic): split each version on '.', compare corresponding
// segments as integers left-to-right, a missing trailing segment on either
// side counts as 0; a catalog pack is offered (kept in
// CatalogFetchResult.entries) iff currentAppVersion >= pack.minAppVersion
// under this comparison -- so equal versions are offered, and e.g.
// "1.0.10" is numerically greater than "1.0.9" even though it sorts before
// it as a string.
//
// This file imports only lib/data/content/catalog_client.dart, which does
// not exist yet -- EXPECTED red (compile failure) until it is written.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/content/catalog_client.dart';

class _FakeCatalogFetcher implements CatalogFetcher {
  _FakeCatalogFetcher(this.response);
  final String response;

  @override
  Future<String?> fetchCatalogJson() async => response;
}

Map<String, Object?> _entry({
  required String id,
  required String minAppVersion,
}) => {
  'id': id,
  'version': '1.0.0',
  'minAppVersion': minAppVersion,
  'checksum': 'checksum-$id',
  'downloadUrl': 'https://cdn.example.com/$id.bundle',
};

Future<Set<String>> _offeredIds({
  required String currentAppVersion,
  required List<Map<String, Object?>> entries,
}) async {
  final client = CatalogClient(
    fetcher: _FakeCatalogFetcher(jsonEncode({'packs': entries})),
  );
  final result = await client.checkCatalog(
    currentAppVersion: currentAppVersion,
  );
  return result.entries.map((e) => e.id).toSet();
}

void main() {
  group(
    'POSITIVE/EDGE: equal boundary -- minAppVersion == currentAppVersion is offered',
    () {
      test('exact three-segment match', () async {
        final ids = await _offeredIds(
          currentAppVersion: '1.4.2',
          entries: [_entry(id: 'p', minAppVersion: '1.4.2')],
        );
        expect(ids, {'p'});
      });

      test(
        'short-form minAppVersion equal to a longer currentAppVersion ("1.2" == "1.2.0")',
        () async {
          final ids = await _offeredIds(
            currentAppVersion: '1.2.0',
            entries: [_entry(id: 'p', minAppVersion: '1.2')],
          );
          expect(ids, {'p'});
        },
      );

      test(
        'short-form currentAppVersion equal to a longer minAppVersion ("1.2" == "1.2.0")',
        () async {
          final ids = await _offeredIds(
            currentAppVersion: '1.2',
            entries: [_entry(id: 'p', minAppVersion: '1.2.0')],
          );
          expect(ids, {'p'});
        },
      );
    },
  );

  group('POSITIVE: older minAppVersion than the current app is offered', () {
    test('a pack requiring an older major version is offered', () async {
      final ids = await _offeredIds(
        currentAppVersion: '2.0.0',
        entries: [_entry(id: 'p', minAppVersion: '1.9.9')],
      );
      expect(ids, {'p'});
    });

    test('a pack requiring an older patch version is offered', () async {
      final ids = await _offeredIds(
        currentAppVersion: '1.0.5',
        entries: [_entry(id: 'p', minAppVersion: '1.0.4')],
      );
      expect(ids, {'p'});
    });
  });

  group('NEGATIVE: newer minAppVersion than the current app is hidden', () {
    test('a pack requiring a newer major version is hidden', () async {
      final ids = await _offeredIds(
        currentAppVersion: '1.9.9',
        entries: [_entry(id: 'p', minAppVersion: '2.0.0')],
      );
      expect(ids, isEmpty);
    });

    test('a pack requiring a newer minor version is hidden', () async {
      final ids = await _offeredIds(
        currentAppVersion: '1.4.0',
        entries: [_entry(id: 'p', minAppVersion: '1.5.0')],
      );
      expect(ids, isEmpty);
    });

    test('a pack requiring a newer patch version is hidden', () async {
      final ids = await _offeredIds(
        currentAppVersion: '1.4.0',
        entries: [_entry(id: 'p', minAppVersion: '1.4.1')],
      );
      expect(ids, isEmpty);
    });
  });

  group('EDGE: numeric, not lexicographic, segment comparison', () {
    test(
      '"1.0.10" (app) is newer than minAppVersion "1.0.9" -- offered despite losing a string compare',
      () async {
        final ids = await _offeredIds(
          currentAppVersion: '1.0.10',
          entries: [_entry(id: 'p', minAppVersion: '1.0.9')],
        );
        expect(
          ids,
          {'p'},
          reason:
              'numeric compare: 10 > 9, even though "1.0.10" < "1.0.9" lexicographically',
        );
      },
    );

    test(
      '"1.0.9" (app) is older than minAppVersion "1.0.10" -- hidden',
      () async {
        final ids = await _offeredIds(
          currentAppVersion: '1.0.9',
          entries: [_entry(id: 'p', minAppVersion: '1.0.10')],
        );
        expect(ids, isEmpty);
      },
    );
  });

  group(
    'POSITIVE: mixed catalog -- exactly the eligible packs are offered, never the too-new one',
    () {
      test(
        'a catalog with older, equal, and newer packs offers only the non-newer ones',
        () async {
          final ids = await _offeredIds(
            currentAppVersion: '1.5.0',
            entries: [
              _entry(id: 'pack.older', minAppVersion: '1.0.0'),
              _entry(id: 'pack.equal', minAppVersion: '1.5.0'),
              _entry(id: 'pack.newer', minAppVersion: '1.6.0'),
              _entry(id: 'pack.way-newer', minAppVersion: '9.0.0'),
            ],
          );

          // The too-new packs are not merely flagged -- they are absent from
          // the result entirely, so any caller that iterates entries to decide
          // what to download can never reach, and therefore can never attempt
          // to download, a pack requiring a newer app (PRD: "never
          // downloaded-and-broken").
          expect(ids, {'pack.older', 'pack.equal'});
        },
      );
    },
  );
}

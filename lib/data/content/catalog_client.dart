/// The static CDN catalog check (PRD §8 Unit 11; ticket `content-delivery`
/// accept entries 3, 6, 8).
///
/// Unit 11 pins packs as *static, versioned, checksummed bundles on a CDN* —
/// there is no dynamic backend to talk to. The whole client/server protocol
/// is one GET of a static `catalog.json`, and the response is a list of
/// packs the app may choose to download. That shape is why "no user data
/// flows upward" is enforced by *construction* here rather than by a policy
/// comment: [CatalogFetcher.fetchCatalogJson] takes no arguments at all, so
/// there is nowhere for a profile id, install id, or any other identifier to
/// be threaded through a catalog check even by accident.
///
/// Failure is silent by design (§6 Offline): a device in airplane mode, on a
/// captive-portal Wi-Fi, or facing a CDN outage gets
/// `CatalogFetchResult(success: false, entries: [])` and nothing else
/// happens. Installed content and the bundled starter pack are untouched —
/// `content_repository.dart` never consults this client at all.
///
/// ## catalog.json wire shape (pinned)
///
/// ```json
/// { "packs": [ { "id": "pack.forest",
///                "version": "1.0.0",
///                "minAppVersion": "1.0.0",
///                "checksum": "<sha-256 hex>",
///                "downloadUrl": "https://cdn.example.com/…bundle",
///                "sizeBytes": 4096 } ] }
/// ```
///
/// `checksum` is A-15's integrity token: the SHA-256 the pack's own
/// `StoryPack.checksum` carries, as produced by `computeManifestChecksum`
/// in `lib/pipeline/pack_builder.dart`. It is what
/// `PackInstaller.installFromBytes` verifies a downloaded bundle against
/// before anything touches installed content. `sizeBytes` is advisory
/// (progress UI, "download over Wi-Fi?" copy) and optional.
///
/// The CDN base URL and catalog hosting are OQ-6 — unresolved, and a pilot
/// distribution question rather than a build one. Nothing in this file names
/// a host: the URL lives entirely inside whichever [CatalogFetcher] the app
/// composes at startup.
library;

import 'dart:convert';

/// One pack offered by the catalog.
///
/// A catalog entry is *not* a pack: it is the metadata needed to decide
/// whether to download one and how to verify it when the bytes arrive.
class CatalogPackEntry {
  const CatalogPackEntry({
    required this.id,
    required this.version,
    required this.minAppVersion,
    required this.checksum,
    required this.downloadUrl,
    required this.sizeBytes,
  });

  /// Stable pack id — the same `StoryPack.id` the bundle's manifest carries,
  /// and the identity an install replaces on upgrade.
  final String id;

  /// This pack revision's version (`StoryPack.version`).
  final String version;

  /// The oldest app version that may load this pack. Compared against the
  /// running app's version with dotted-numeric semantics; a pack requiring a
  /// newer app never appears in [CatalogFetchResult.entries] at all.
  final String minAppVersion;

  /// A-15 integrity: the SHA-256 hex of the pack manifest, as
  /// `computeManifestChecksum` computes it. Verified before install.
  final String checksum;

  /// Where the bundle bytes live. Carries no query parameters of ours — the
  /// downloader sends this URL and a resume offset, nothing else.
  final Uri downloadUrl;

  /// Advisory download size, or null when the catalog omits it.
  final int? sizeBytes;
}

/// The outcome of one catalog check.
///
/// [entries] is already `minAppVersion`-filtered, and is empty whenever
/// [success] is false. There is no error field: a failed catalog check is
/// not an event the app reports, reacts to, or retries specially — it simply
/// learned nothing new this launch.
class CatalogFetchResult {
  const CatalogFetchResult({required this.success, required this.entries});

  const CatalogFetchResult.failure()
    : success = false,
      entries = const <CatalogPackEntry>[];

  final bool success;

  /// Packs this app build may install, in catalog order.
  final List<CatalogPackEntry> entries;
}

/// Fetches the raw `catalog.json` text over the network.
///
/// Takes no arguments and returns null on *any* failure (offline, DNS,
/// timeout, non-200, malformed body): implementations must never throw. The
/// production implementation is a `dart:io` `HttpClient` adapter (no new pub
/// dependency); tests inject fakes, including one that fails every call to
/// stand in for airplane mode.
abstract class CatalogFetcher {
  /// The catalog body, or null if it could not be fetched.
  Future<String?> fetchCatalogJson();
}

/// Checks the static catalog and reports the packs this app build may
/// install.
class CatalogClient {
  const CatalogClient({required CatalogFetcher fetcher}) : _fetcher = fetcher;

  final CatalogFetcher _fetcher;

  /// Fetches and parses the catalog. Never throws.
  ///
  /// A null fetch, a body that is not a JSON object, a missing or
  /// non-list `packs` key, or any pack entry missing/mistyping a required
  /// field yields `CatalogFetchResult(success: false, entries: [])` — a
  /// partially-understood catalog is treated as no catalog, because acting
  /// on half of a malformed manifest of downloads is strictly worse than
  /// waiting for the next launch. An empty `packs` list, by contrast, is a
  /// perfectly successful catalog that happens to offer nothing.
  ///
  /// On success, every entry whose [CatalogPackEntry.minAppVersion] is newer
  /// than [currentAppVersion] is *excluded*, not flagged: a caller iterating
  /// `entries` to decide what to download can never reach a pack this build
  /// could not load, so "never downloaded-and-broken" holds without every
  /// call site having to remember the rule.
  Future<CatalogFetchResult> checkCatalog({
    required String currentAppVersion,
  }) async {
    final String? body;
    try {
      body = await _fetcher.fetchCatalogJson();
    } on Object {
      // Belt and braces: the interface forbids throwing, but a fetch failure
      // must stay silent even when an implementation misbehaves.
      return const CatalogFetchResult.failure();
    }
    if (body == null) return const CatalogFetchResult.failure();

    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return const CatalogFetchResult.failure();
    }
    if (decoded is! Map<String, dynamic>) {
      return const CatalogFetchResult.failure();
    }

    final packsRaw = decoded['packs'];
    if (packsRaw is! List) return const CatalogFetchResult.failure();

    final entries = <CatalogPackEntry>[];
    for (final raw in packsRaw) {
      if (raw is! Map<String, dynamic>) {
        return const CatalogFetchResult.failure();
      }
      final entry = _entryFromJson(raw);
      if (entry == null) return const CatalogFetchResult.failure();
      entries.add(entry);
    }

    return CatalogFetchResult(
      success: true,
      entries: List.unmodifiable(
        entries.where(
          (e) => compareDottedVersions(currentAppVersion, e.minAppVersion) >= 0,
        ),
      ),
    );
  }

  static CatalogPackEntry? _entryFromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final version = json['version'];
    final minAppVersion = json['minAppVersion'];
    final checksum = json['checksum'];
    final downloadUrl = json['downloadUrl'];
    final sizeBytes = json['sizeBytes'];
    if (id is! String ||
        version is! String ||
        minAppVersion is! String ||
        checksum is! String ||
        downloadUrl is! String) {
      return null;
    }
    if (sizeBytes != null && sizeBytes is! int) return null;
    final url = Uri.tryParse(downloadUrl);
    if (url == null) return null;
    return CatalogPackEntry(
      id: id,
      version: version,
      minAppVersion: minAppVersion,
      checksum: checksum,
      downloadUrl: url,
      sizeBytes: sizeBytes as int?,
    );
  }
}

/// Compares two dotted-numeric version strings, returning a negative number
/// if [a] is older than [b], zero if they are equal, positive if newer.
///
/// Segments are split on `'.'` and compared as **integers**, left to right;
/// a missing trailing segment on either side counts as 0, so `"1.2"` and
/// `"1.2.0"` are equal. Numeric comparison is the whole point: a
/// lexicographic compare would call `"1.0.10"` older than `"1.0.9"` and
/// hide packs from an app new enough to run them. A non-numeric segment
/// (e.g. a `-beta` suffix) counts as 0 rather than throwing — version
/// filtering must never be the reason a catalog check fails.
int compareDottedVersions(String a, String b) {
  final aParts = a.split('.');
  final bParts = b.split('.');
  final length = aParts.length > bParts.length ? aParts.length : bParts.length;
  for (var i = 0; i < length; i++) {
    final aSegment = i < aParts.length ? (int.tryParse(aParts[i]) ?? 0) : 0;
    final bSegment = i < bParts.length ? (int.tryParse(bParts[i]) ?? 0) : 0;
    if (aSegment != bSegment) return aSegment < bSegment ? -1 : 1;
  }
  return 0;
}

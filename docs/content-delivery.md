# Content delivery (Unit: content-delivery)

How story content reaches the app: the starter pack that ships in the binary,
the static CDN catalog, resumable background downloads, and the verified,
atomic install that turns downloaded bytes into content the app can read.
Every piece is headless-testable — the network is two small interfaces with
fakes, and every directory is injected (no `path_provider`, no device).

Source: `lib/data/content/{pack_loader,catalog_client,pack_downloader,pack_installer,content_repository}.dart`.
PRD refs: §8 Unit 11 (CDN pack delivery), §8 Unit 3 (pack format), §8 Unit 15
(grapheme inventory), §5 (`StoryPack`, `GraphemeSound`), §6 (Offline),
§9 A-9 (starter pack), §9 A-15 (integrity).
Ticket: `docs/tickets/content-delivery.json`. Pinned by
`test/data/content/*.dart` (7 files, 64 tests — each test file's header
comment states its exact pinned API surface).

## Shape

```text
catalog.json ──► CatalogClient ──► CatalogPackEntry (minAppVersion-filtered)
                                        │
                                        ▼
                                  PackDownloader ──► <packId>-<checksum>.part
                                        │                (resume state)
                                        ▼
                                  PackInstaller ──► installedPacks/<packId>/
                                        │                manifest.json + assets
                                        ▼
starter pack (binary) ──────────► ContentRepository ──► stories/twisters/
                                                        vocabCards/collectibles/
                                                        graphemeInventory
```

| File | Owns |
|---|---|
| `pack_loader.dart` | Reading a bundle **directory** into §5 models; resolving refs to files. |
| `catalog_client.dart` | Fetching/parsing `catalog.json`; `minAppVersion` filtering; silent failure. |
| `pack_downloader.dart` | Moving bytes, resumably, under a Wi-Fi-by-default policy. Format-agnostic. |
| `pack_installer.dart` | Decoding the wire bundle, verifying its checksum, atomic verify → stage → swap. |
| `content_repository.dart` | Merging starter + installed packs into one read surface. No network dependency of any kind. |

The layering is deliberate: only `pack_installer.dart` sits on the trust
boundary. The downloader never learns what a pack is, and the repository never
learns that a network exists.

## Wire formats

### `catalog.json` (static, on a CDN)

```json
{ "packs": [ { "id": "pack.forest",
               "version": "1.0.0",
               "minAppVersion": "1.0.0",
               "checksum": "<sha-256 hex>",
               "downloadUrl": "https://…/pack.forest-1.0.0.bundle",
               "sizeBytes": 4096 } ] }
```

`sizeBytes` is optional and advisory. Any other malformation — non-JSON, a
non-object root, a missing/non-list `packs`, an entry missing a required field
— yields `CatalogFetchResult(success: false, entries: [])`. A
partially-understood catalog is treated as no catalog: acting on half a list
of downloads is strictly worse than waiting for the next launch. An empty
`packs` list, by contrast, is a *successful* catalog offering nothing.

The CDN base URL is OQ-6 (open, and a pilot-distribution question rather than
a build one). Nothing in this unit names a host: the URL lives entirely inside
whichever `CatalogFetcher` the app composes at startup.

### Pack bundle (the downloaded artifact)

```text
bytes[0..4)               big-endian uint32 headerLength
bytes[4..4+headerLength)  UTF-8 JSON:
    {"manifest": <StoryPack.toJson() map>,
     "files": [{"ref": "<asset ref>", "length": <int>}, …]}
remaining bytes           each files[i]'s raw bytes, exactly `length` long,
                          concatenated in list order
```

A length-prefixed header followed by raw concatenated payloads makes a
truncated download *structurally* detectable — the declared lengths do not add
up to the bytes present — with no parsing, decompression, or trial install
needed. A bundle may legitimately omit a ref the manifest lists (an optional
or not-yet-shipped asset); it may not declare bytes it does not carry.

### Installed pack (on disk)

`<installedPacks>/<packId>/manifest.json` plus every asset at its
`'/'`-separated ref path. This is the same shape the content pipeline builds
from, which is what makes Unit 3's "the pack build produces a bundle the app
loads end-to-end" one format rather than two kept in sync. The bundled starter
pack is a directory of exactly this shape shipped inside the binary.

## Integrity (A-15) — and the gap this scheme leaves

A-15 pins v1 integrity as "SHA-256 checksum listed in the catalog", and
`PackInstaller` verifies exactly that: it recomputes the manifest checksum
with `computeManifestChecksum` from `lib/pipeline/pack_builder.dart` — reused,
never redefined, so the app and the build can never disagree about what a
checksum *is* — and compares it to the catalog's value. The manifest's own
self-reported `checksum` field is never trusted; it is blanked before hashing,
per that function's contract.

**Scope: the checksum is manifest-scoped.** It covers every byte of the
manifest JSON — every story, sentence, word, grapheme-phoneme mapping, and
asset *ref* — and therefore catches any tampering with pack content or
structure. It does **not** cover the asset *bytes*. A bundle carrying an
authentic manifest with substituted audio payloads would pass verification.

That gap is bounded and accepted for the POC:

- bundles are served over HTTPS from a static CDN, so the substitution it
  admits requires compromising that transport;
- the realistic failure modes this layer actually faces — truncation,
  corruption, a connection dropped mid-download, a half-written file — are all
  caught by the structural decode, independently of the checksum;
- nothing downstream executes pack payloads: they are audio and Rive assets.

**Post-POC hardening path** (pinned, additive, no format break):

1. **Per-file hashes.** Extend each `files` entry to
   `{"ref", "length", "sha256"}` and verify each payload against its hash
   while staging, before the swap. Old clients ignore the unknown field; a
   hardened client requires it. This closes the payload gap end-to-end.
2. **Signing.** A-15 defers cryptographic signing past v1. Signing the
   manifest (and, with (1) in place, transitively the payloads) upgrades the
   checksum from *transported* to *attested*, so a compromised CDN cannot
   publish a self-consistent malicious pack + catalog pair.

## Atomic install: verify → stage → swap

1. **Verify** — decode and checksum entirely in memory. A rejected bundle
   never creates a file at all, so a rejected *fresh* install leaves the
   installed-packs directory untouched, with no orphaned temp artifacts.
2. **Stage** — write the manifest and every payload into a dot-prefixed
   scratch directory, deleted in a `finally` whatever happens. Dot-prefixed so
   enumeration skips it even if a process death ever leaves one behind.
3. **Swap** — move any prior install aside with one rename, rename the staged
   tree into place, then delete what was displaced. The window in which no
   directory sits at the target spans a single rename, not a recursive delete,
   and a failure part-way puts the previous install back.

The invariant this buys, and the one the corrupt/truncated-bundle suite
asserts byte-for-byte: **a failed or partial download never corrupts installed
content.** A tampered manifest, a truncated bundle, garbage bytes, or a
checksum that simply does not match the catalog's are each rejected with the
prior install byte-identical afterwards.

Asset refs are resolved *within* the install directory: an absolute ref, or
one containing `..`, is rejected rather than followed. A bundle can only ever
write inside its own pack directory.

Installs are idempotent (installing the same bundle twice leaves one entry)
and upgrades replace by pack id, not by version — the caller supplies the
`packId` being replaced (it came from the catalog entry the download was for),
so a bundle can never redirect an install at a pack id nobody asked for.

## Resume: the partial file *is* the state

There is no download database, journal, or in-memory queue to survive a kill.
`<staging>/<packId>-<checksum>.part` is the persisted state: its length on
disk is the resume offset. A brand-new `PackDownloader` pointed at the same
staging directory after an app restart resumes exactly where the last attempt
stopped, because there is no recovery code that could get it wrong. Chunks are
appended and flushed as they arrive, so a kill at any instant leaves a valid,
resumable prefix.

The checksum in the file name is load-bearing: a new pack revision has a new
checksum, so a stale partial from the previous revision can never be mistaken
for a prefix of the new bytes — it ages out as an orphan file instead of
corrupting an install. Re-downloading an already-complete pack is safe: the
fetcher is asked to resume at the full length, has nothing to add, and reports
completed.

**Wi-Fi by default**: offline always defers; cellular defers unless the caller
opts in (`allowCellular: true` — the shape a parental "download over cellular"
setting would take). A deferred download touches neither the network nor the
staging directory.

## `minAppVersion`: dotted-numeric, and *hidden* rather than flagged

Versions compare segment-by-segment as **integers**, left to right, with a
missing trailing segment counting as 0 (`"1.2" == "1.2.0"`). A pack is offered
iff `currentAppVersion >= minAppVersion` under that comparison. Numeric
comparison is the whole point: a lexicographic compare would call `"1.0.10"`
older than `"1.0.9"` and hide packs from an app new enough to run them.

Too-new packs are **absent** from `CatalogFetchResult.entries`, not flagged in
them. Any caller iterating entries to decide what to download therefore cannot
reach — and so cannot attempt to download — a pack this build could not load.
"Never downloaded-and-broken" holds without every call site remembering the
rule.

## No user data flows upward

Unit 11 pins packs as static, versioned, checksummed bundles on a CDN: there
is no dynamic backend, and the whole protocol is GETs of static files. That is
enforced by *construction*, not by policy comments:

- `CatalogFetcher.fetchCatalogJson()` takes **no arguments**. There is nowhere
  to thread a profile id, install id, or any other identifier through a
  catalog check, even accidentally.
- `PackFetcher.fetch(url, startByte:, onBytes:)` has no header map, no body,
  no options object. The URL and a byte offset are the entire request.

## Offline (§6) and the starter pack (A-9)

`ContentRepository`'s constructor takes a loaded starter pack and a
`PackInstaller` — no fetcher, no catalog client, no connectivity probe.
Reading content *cannot* touch the network because the repository holds
nothing that could. A fresh install in airplane mode serves the full starter
experience with no offline mode, no cache warming, and no first-run fetch to
fail; the launch-time catalog check fails silently beside it and changes
nothing. CDN packs, once installed, are equally local.

Merge order is starter first, then installed packs ordered by id. Determinism
matters beyond tidiness: it decides which pack wins a collision, and content
reordering itself between launches is a bug even when the content is
identical. Installed packs are re-read per call rather than cached, so an
install that lands while the app is running becomes visible without a restart.

## Unit 15: grapheme inventory, extension merge, partial-audio filtering

- **The starter pack owns the id set.** The inventory ships in the binary; an
  installed pack may only *extend* an existing card's example words, never
  introduce a new card. The Sound Garden's shape is a property of the app
  build, so a content drop cannot reshape the phonics progression.
- **Example words are filtered to locally available audio.** Each candidate is
  kept only if its `pronunciationAudioRef` resolves to a real file inside
  *that contributing pack's own* directory. A pack whose manifest lists more
  than the bytes present (an optional asset, a partial install) contributes
  only what it can actually play — the Sound Garden shows only words it has
  audio for, rather than offering a card that would fail to speak when tapped.
- **Deduped by `wordText`, first survivor wins.** In merge order that means
  the starter's own recording wins a collision with an installed pack's, and
  the same word never appears twice on a card.

## Composition notes for the app shell

- `CatalogFetcher` and `PackFetcher` are implemented over `dart:io`
  `HttpClient` (a `Range: bytes=<startByte>-` request for the latter) — no new
  pub dependency — and must never throw: failure is a return value.
- Directories (`installedPacksDirectory`, `stagingDirectory`) come from
  `path_provider` at composition time; nothing in this unit resolves a path
  itself, which is why the whole unit runs headlessly.
- A launch-time catalog check is fire-and-forget: its failure is silent and
  affects nothing the child can see.

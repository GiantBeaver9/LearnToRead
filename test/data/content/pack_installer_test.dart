// Pins the API of lib/data/content/pack_installer.dart (PRD §8 Unit 11:
// "verifies checksum before install... atomic install: verify -> swap";
// ticket content-delivery accept entries 4, 5). This file covers the
// POSITIVE install path: a well-formed, checksum-correct bundle installs,
// enumerates, loads, and re-installs/upgrades idempotently and atomically.
// The NEGATIVE path (corrupt/truncated bundles, "installed content
// untouched") is the dedicated subject of corrupt_pack_test.dart.
//
// This suite is authored before the implementation exists, so it is
// EXPECTED to fail to compile until pack_installer.dart is written with
// exactly the shapes exercised below.
//
// Pinned wire format for a downloaded pack bundle (produced by whatever
// downloads bytes -- pack_downloader.dart is bundle-format-agnostic and
// just moves bytes; pack_installer.dart owns decoding this format):
//
//   bytes[0..4)              big-endian uint32 headerLength
//   bytes[4..4+headerLength) UTF-8 JSON:
//       {"manifest": <StoryPack.toJson() map>,
//        "files": [{"ref": "<asset ref>", "length": <int>}, ...]}
//   remaining bytes          each files[i]'s raw bytes, exactly `length`
//                            long, concatenated in list order
//
// Pinned API surface this suite requires:
//
//   enum InstallOutcome { installed, rejectedChecksumMismatch, rejectedMalformedBundle }
//   class InstallResult { final InstallOutcome outcome; }
//   class InstalledPackInfo {
//     final String id;
//     final String version;
//     final String checksum;
//     final Directory directory;
//   }
//   class PackInstaller {
//     PackInstaller({required Directory installedPacksDirectory});
//
//     /// Decodes [bundleBytes] per the wire format above. Verifies
//     /// `computeManifestChecksum` (lib/pipeline/pack_builder.dart, reused
//     /// not redefined) of the decoded manifest (with its own `checksum`
//     /// field blanked, per that function's contract) equals
//     /// [expectedChecksum] -- A-15's "checksum listed in the catalog" is
//     /// this comparison. On success, atomically installs (verify -> stage
//     /// in a temp location -> swap into place), replacing any prior
//     /// install of [packId] entirely. Never throws.
//     Future<InstallResult> installFromBytes(
//       Uint8List bundleBytes, {
//       required String packId,
//       required String expectedChecksum,
//     });
//
//     /// Every currently installed pack (order unspecified -- tests sort).
//     Future<List<InstalledPackInfo>> installedPacks();
//
//     /// Loads installed pack [packId] via pack_loader.dart's
//     /// loadPackFromDirectory, or null if [packId] is not installed.
//     Future<LoadedPack?> loadInstalled(String packId);
//   }
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/content/pack_installer.dart';
import 'package:learn_to_read/data/content/pack_loader.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/pack_manifest.dart';
import 'package:learn_to_read/pipeline/loudness_check.dart';
import 'package:learn_to_read/pipeline/pack_builder.dart';
import 'package:path/path.dart' as p;

// ---------------------------------------------------------------------------
// Fixture generation (file-local per this codebase's convention).
// ---------------------------------------------------------------------------

Uint8List _pcm16MonoWav(Int16List samples, {int sampleRate = 44100}) {
  final dataLength = samples.length * 2;
  final builder = BytesBuilder();
  void s(String v) => builder.add(ascii.encode(v));
  void u32(int v) {
    final b = ByteData(4)..setUint32(0, v, Endian.little);
    builder.add(b.buffer.asUint8List());
  }

  void u16(int v) {
    final b = ByteData(2)..setUint16(0, v, Endian.little);
    builder.add(b.buffer.asUint8List());
  }

  s('RIFF');
  u32(36 + dataLength);
  s('WAVE');
  s('fmt ');
  u32(16);
  u16(1);
  u16(1);
  u32(sampleRate);
  u32(sampleRate * 2);
  u16(2);
  u16(16);
  s('data');
  u32(dataLength);
  final sampleBytes = ByteData(dataLength);
  for (var i = 0; i < samples.length; i++) {
    sampleBytes.setInt16(i * 2, samples[i], Endian.little);
  }
  builder.add(sampleBytes.buffer.asUint8List());
  return builder.toBytes();
}

Uint8List _sineWavBytes({double amplitude = 0.3, double frequencyHz = 997}) {
  const sampleRate = 44100;
  final n = sampleRate;
  final samples = Int16List(n);
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final v = amplitude * math.sin(2 * math.pi * frequencyHz * t);
    samples[i] = (v * 32767).round().clamp(-32768, 32767);
  }
  return _pcm16MonoWav(samples, sampleRate: sampleRate);
}

Uint8List _goodAudioBytes() =>
    normalizeToTargetLoudness(_sineWavBytes(), targetLufs: -16.0);

final _level1 = Level(
  id: 'level.1',
  ordinal: 1,
  format: LevelFormat.sentence,
  vocabEnabled: false,
  newSkills: [
    PhonicsSkill(
      id: 'skill.1',
      name: 'starter',
      sequenceOrder: 1,
      introducesGraphemes: const ['s', 'a', 't'],
    ),
  ],
);

WordToken _wordSat() => WordToken(
  text: 'sat',
  graphemePhonemeMap: const [
    (graphemes: 's', phonemeId: 'S'),
    (graphemes: 'a', phonemeId: 'AE'),
    (graphemes: 't', phonemeId: 'T'),
  ],
  pronunciationAudioRef: 'audio/words/sat.wav',
);

/// A minimal, always-valid fixture pack; `id`, `version`, and `title` are
/// overridable so tests can build "the same pack again" or "a v2 upgrade"
/// or "a second, distinct pack" from one factory.
StoryPack _fixturePack({
  String id = 'pack.fixture',
  String version = '1.0.0',
  String title = 'Sat',
}) {
  final story = Story(
    id: 'story.1',
    levelId: 'level.1',
    title: title,
    pages: [
      Page(
        sentences: [
          Sentence(
            words: [_wordSat(), _wordSat(), _wordSat()],
            narrationAudioRef: 'audio/narration/story.1.wav',
          ),
        ],
      ),
    ],
    riveAnimationRef: 'rive/story.1.riv',
    celebrationAudioRef: 'audio/celebration/story.1.wav',
    collectibleRef: 'collectible.story.1',
    skillsExercised: const [],
    packId: id,
    contentVersion: '1',
  );
  final collectible = Collectible(
    id: 'collectible.story.1',
    storyId: 'story.1',
    riveRef: 'rive/collectibles/sat.riv',
    sceneSlot: 'shelf.1',
  );

  return StoryPack(
    id: id,
    version: version,
    minAppVersion: '1.0.0',
    stories: [story],
    twisters: const [],
    vocabCards: const [],
    collectibles: [collectible],
    graphemeSounds: const [],
    assetRefs: const [],
    checksum: '',
  );
}

Set<String> _audioRefs(StoryPack pack) {
  final refs = <String>{};
  for (final story in pack.stories) {
    refs.add(story.celebrationAudioRef);
    for (final page in story.pages) {
      for (final sentence in page.sentences) {
        if (sentence.narrationAudioRef != null)
          refs.add(sentence.narrationAudioRef!);
        for (final word in sentence.words) {
          refs.add(word.pronunciationAudioRef);
        }
      }
    }
  }
  return refs;
}

Set<String> _riveRefs(StoryPack pack) => <String>{
  for (final story in pack.stories) story.riveAnimationRef,
  for (final c in pack.collectibles) c.riveRef,
};

/// Builds and returns a real, checksummed StoryPack together with the
/// on-disk content directory `buildPack` produced it from (so the caller
/// can read the asset bytes back out to encode a wire bundle).
Future<(StoryPack, Directory)> _buildRealPack({
  String id = 'pack.fixture',
  String version = '1.0.0',
  String title = 'Sat',
}) async {
  final dir = Directory.systemTemp.createTempSync('pack_installer_test_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  final draft = _fixturePack(id: id, version: version, title: title);
  await File(
    p.join(dir.path, 'manifest.json'),
  ).writeAsString(jsonEncode(draft.toJson()));
  for (final ref in _audioRefs(draft)) {
    final f = File(p.join(dir.path, ref));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(_goodAudioBytes());
  }
  for (final riveRef in _riveRefs(draft)) {
    // Orchestrator test-fix: buildPack lists .riv files in assetRefs, but
    // the fixture wrote only the A-16 sidecar - the tests' own bundle
    // encoder then threw PathNotFoundException before any implementation
    // code ran. Write a placeholder Rive binary alongside the sidecar.
    await (await File(p.join(dir.path, riveRef)).create(recursive: true)).writeAsBytes([82, 73, 86, 69]);
    final f = File(p.join(dir.path, '$riveRef.inputs.json'));
    await f.parent.create(recursive: true);
    await f.writeAsString(
      jsonEncode({
        'inputs': ['idle', 'celebrate', 'collect'],
      }),
    );
  }

  final result = await buildPack(contentDir: dir.path, levels: [_level1]);
  if (!result.success) {
    throw StateError('fixture pack failed to build: ${result.errors}');
  }
  return (result.pack!, dir);
}

/// Encodes [pack] (whose asset bytes live under [contentDir]) into the
/// pinned wire bundle format pack_installer.dart must decode.
Uint8List _encodeBundle(
  StoryPack pack,
  Directory contentDir, {
  Set<String> omitAssetRefs = const {},
}) {
  final files = <Map<String, Object?>>[];
  final chunks = <List<int>>[];
  for (final ref in pack.assetRefs) {
    if (omitAssetRefs.contains(ref)) continue;
    final bytes = File(p.join(contentDir.path, ref)).readAsBytesSync();
    files.add({'ref': ref, 'length': bytes.length});
    chunks.add(bytes);
  }
  final headerBytes = utf8.encode(
    jsonEncode({'manifest': pack.toJson(), 'files': files}),
  );
  final out = BytesBuilder();
  final lenPrefix = ByteData(4)..setUint32(0, headerBytes.length, Endian.big);
  out.add(lenPrefix.buffer.asUint8List());
  out.add(headerBytes);
  for (final c in chunks) {
    out.add(c);
  }
  return out.toBytes();
}

void main() {
  late Directory installedPacksDir;

  setUp(() {
    installedPacksDir = Directory.systemTemp.createTempSync(
      'pack_installer_test_installed_',
    );
  });

  tearDown(() {
    if (installedPacksDir.existsSync())
      installedPacksDir.deleteSync(recursive: true);
  });

  group('POSITIVE: a well-formed, checksum-correct bundle installs', () {
    test('installFromBytes reports InstallOutcome.installed', () async {
      final (pack, contentDir) = await _buildRealPack();
      final bundleBytes = _encodeBundle(pack, contentDir);
      final installer = PackInstaller(
        installedPacksDirectory: installedPacksDir,
      );

      final result = await installer.installFromBytes(
        bundleBytes,
        packId: pack.id,
        expectedChecksum: pack.checksum,
      );

      expect(result.outcome, InstallOutcome.installed);
    });

    test('installed pack enumerates via installedPacks()', () async {
      final (pack, contentDir) = await _buildRealPack();
      final bundleBytes = _encodeBundle(pack, contentDir);
      final installer = PackInstaller(
        installedPacksDirectory: installedPacksDir,
      );
      await installer.installFromBytes(
        bundleBytes,
        packId: pack.id,
        expectedChecksum: pack.checksum,
      );

      final infos = await installer.installedPacks();

      expect(infos, hasLength(1));
      expect(infos.single.id, pack.id);
      expect(infos.single.version, '1.0.0');
      expect(infos.single.checksum, pack.checksum);
    });

    test(
      'installed pack loads into content models via loadInstalled',
      () async {
        final (pack, contentDir) = await _buildRealPack(title: 'Sat In A Hat');
        final bundleBytes = _encodeBundle(pack, contentDir);
        final installer = PackInstaller(
          installedPacksDirectory: installedPacksDir,
        );
        await installer.installFromBytes(
          bundleBytes,
          packId: pack.id,
          expectedChecksum: pack.checksum,
        );

        final loaded = await installer.loadInstalled(pack.id);

        expect(loaded, isNotNull);
        expect(loaded!.pack.stories.single.title, 'Sat In A Hat');
        final wordRef = loaded
            .pack
            .stories
            .single
            .pages
            .single
            .sentences
            .single
            .words
            .first
            .pronunciationAudioRef;
        expect(loaded.resolveAsset(wordRef), isNotNull);
        expect(File(loaded.resolveAsset(wordRef)!).existsSync(), isTrue);
      },
    );

    test(
      'loadInstalled returns null for a pack id that was never installed',
      () async {
        final installer = PackInstaller(
          installedPacksDirectory: installedPacksDir,
        );

        final loaded = await installer.loadInstalled('pack.never-installed');

        expect(loaded, isNull);
      },
    );
  });

  group('POSITIVE: enumeration across multiple distinct packs', () {
    test(
      'two different installed packs both enumerate and both load independently',
      () async {
        final (packA, dirA) = await _buildRealPack(
          id: 'pack.a',
          title: 'Story A',
        );
        final (packB, dirB) = await _buildRealPack(
          id: 'pack.b',
          title: 'Story B',
        );
        final installer = PackInstaller(
          installedPacksDirectory: installedPacksDir,
        );

        await installer.installFromBytes(
          _encodeBundle(packA, dirA),
          packId: packA.id,
          expectedChecksum: packA.checksum,
        );
        await installer.installFromBytes(
          _encodeBundle(packB, dirB),
          packId: packB.id,
          expectedChecksum: packB.checksum,
        );

        final infos = await installer.installedPacks();
        expect(infos.map((i) => i.id).toSet(), {'pack.a', 'pack.b'});

        final loadedA = await installer.loadInstalled('pack.a');
        final loadedB = await installer.loadInstalled('pack.b');
        expect(loadedA!.pack.stories.single.title, 'Story A');
        expect(loadedB!.pack.stories.single.title, 'Story B');
      },
    );
  });

  group('POSITIVE: double-install idempotence', () {
    test(
      'installing the identical bundle twice leaves exactly one installed entry',
      () async {
        final (pack, contentDir) = await _buildRealPack();
        final bundleBytes = _encodeBundle(pack, contentDir);
        final installer = PackInstaller(
          installedPacksDirectory: installedPacksDir,
        );

        final first = await installer.installFromBytes(
          bundleBytes,
          packId: pack.id,
          expectedChecksum: pack.checksum,
        );
        final second = await installer.installFromBytes(
          bundleBytes,
          packId: pack.id,
          expectedChecksum: pack.checksum,
        );

        expect(first.outcome, InstallOutcome.installed);
        expect(second.outcome, InstallOutcome.installed);
        final infos = await installer.installedPacks();
        expect(infos.where((i) => i.id == pack.id), hasLength(1));

        final loaded = await installer.loadInstalled(pack.id);
        expect(loaded!.pack.stories.single.title, 'Sat');
      },
    );
  });

  group('POSITIVE: version upgrade replaces atomically', () {
    test(
      'installing a v2 bundle for the same pack id replaces v1 entirely',
      () async {
        final (packV1, dirV1) = await _buildRealPack(
          version: '1.0.0',
          title: 'Sat v1',
        );
        final (packV2, dirV2) = await _buildRealPack(
          version: '2.0.0',
          title: 'Sat v2',
        );
        final installer = PackInstaller(
          installedPacksDirectory: installedPacksDir,
        );

        await installer.installFromBytes(
          _encodeBundle(packV1, dirV1),
          packId: packV1.id,
          expectedChecksum: packV1.checksum,
        );
        final upgrade = await installer.installFromBytes(
          _encodeBundle(packV2, dirV2),
          packId: packV2.id,
          expectedChecksum: packV2.checksum,
        );

        expect(upgrade.outcome, InstallOutcome.installed);
        final infos = await installer.installedPacks();
        expect(infos.where((i) => i.id == 'pack.fixture'), hasLength(1));
        expect(infos.single.version, '2.0.0');

        final loaded = await installer.loadInstalled('pack.fixture');
        expect(loaded!.pack.stories.single.title, 'Sat v2');
        expect(loaded.pack.version, '2.0.0');
      },
    );
  });
}

// Dedicated negative/atomicity suite for lib/data/content/pack_installer.dart
// (PRD §8 Unit 11 pinned: "a failed/partial download never corrupts
// installed content (atomic install: verify -> swap)"; ticket
// content-delivery accept entry 5: "corrupt/truncated pack fixture ->
// rejected, installed content untouched -- test tampers bytes and asserts
// prior pack intact"). Positive install/enumerate/upgrade flows live in
// pack_installer_test.dart; this file exists to make corruption and
// truncation first-class, well-isolated failure modes.
//
// See pack_installer_test.dart's header comment for the full pinned API
// surface and wire bundle format -- reproduced here only where this file's
// tests need to construct a deliberately broken bundle. This suite imports
// lib/data/content/pack_installer.dart, which does not exist yet: EXPECTED
// red (compile failure) until it is written.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/content/pack_installer.dart';
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
  final samples = Int16List(sampleRate);
  for (var i = 0; i < sampleRate; i++) {
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

Future<(StoryPack, Directory)> _buildRealPack({
  String id = 'pack.fixture',
  String version = '1.0.0',
  String title = 'Sat',
}) async {
  final dir = Directory.systemTemp.createTempSync('corrupt_pack_test_');
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

/// Tampers a bundle's manifest JSON content (the story title) without
/// touching the manifest's own `checksum` field or the length prefix --
/// the shape of corruption a naive "does the embedded checksum field still
/// equal itself" check would miss, but a real recompute-and-compare catches.
Uint8List _tamperManifestContent(Uint8List bundleBytes) {
  final headerLength = ByteData.sublistView(
    bundleBytes,
    0,
    4,
  ).getUint32(0, Endian.big);
  final headerBytes = bundleBytes.sublist(4, 4 + headerLength);
  final header = jsonDecode(utf8.decode(headerBytes)) as Map<String, dynamic>;
  final manifest = header['manifest'] as Map<String, dynamic>;
  (manifest['stories'] as List).cast<Map<String, dynamic>>().first['title'] =
      'TAMPERED';
  final newHeaderBytes = utf8.encode(jsonEncode(header));

  final out = BytesBuilder();
  final lenPrefix = ByteData(4)
    ..setUint32(0, newHeaderBytes.length, Endian.big);
  out.add(lenPrefix.buffer.asUint8List());
  out.add(newHeaderBytes);
  out.add(bundleBytes.sublist(4 + headerLength));
  return out.toBytes();
}

/// Recursively snapshots every file under [dir] as relative-path -> bytes,
/// so a before/after comparison proves byte-for-byte equality.
Map<String, List<int>> _snapshot(Directory dir) {
  if (!dir.existsSync()) return const {};
  final snapshot = <String, List<int>>{};
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File) {
      final relative = p.relative(entity.path, from: dir.path);
      snapshot[relative] = entity.readAsBytesSync();
    }
  }
  return snapshot;
}

void main() {
  late Directory installedPacksDir;

  setUp(() {
    installedPacksDir = Directory.systemTemp.createTempSync(
      'corrupt_pack_test_installed_',
    );
  });

  tearDown(() {
    if (installedPacksDir.existsSync())
      installedPacksDir.deleteSync(recursive: true);
  });

  group(
    'NEGATIVE: a prior good install survives a corrupt "update" attempt untouched',
    () {
      test(
        'tampered manifest content is rejected on checksum mismatch, prior pack byte-identical after',
        () async {
          final (packV1, dirV1) = await _buildRealPack(title: 'Sat v1');
          final installer = PackInstaller(
            installedPacksDirectory: installedPacksDir,
          );
          await installer.installFromBytes(
            _encodeBundle(packV1, dirV1),
            packId: packV1.id,
            expectedChecksum: packV1.checksum,
          );
          final before = _snapshot(installedPacksDir);
          expect(
            before,
            isNotEmpty,
            reason: 'sanity: v1 actually installed something',
          );

          final (packV2, dirV2) = await _buildRealPack(
            version: '2.0.0',
            title: 'Sat v2',
          );
          final tampered = _tamperManifestContent(_encodeBundle(packV2, dirV2));

          final result = await installer.installFromBytes(
            tampered,
            packId: packV2.id,
            expectedChecksum: packV2.checksum,
          );

          expect(result.outcome, InstallOutcome.rejectedChecksumMismatch);
          final after = _snapshot(installedPacksDir);
          expect(
            after,
            before,
            reason:
                'the v1 install must be byte-for-byte untouched by the rejected v2 attempt',
          );

          final infos = await installer.installedPacks();
          expect(infos, hasLength(1));
          expect(infos.single.version, '1.0.0');
          final loaded = await installer.loadInstalled('pack.fixture');
          expect(loaded!.pack.stories.single.title, 'Sat v1');
        },
      );

      test(
        'a truncated bundle (connection dropped mid-download) is rejected, prior pack byte-identical after',
        () async {
          final (packV1, dirV1) = await _buildRealPack(title: 'Sat v1');
          final installer = PackInstaller(
            installedPacksDirectory: installedPacksDir,
          );
          await installer.installFromBytes(
            _encodeBundle(packV1, dirV1),
            packId: packV1.id,
            expectedChecksum: packV1.checksum,
          );
          final before = _snapshot(installedPacksDir);

          final (packV2, dirV2) = await _buildRealPack(
            version: '2.0.0',
            title: 'Sat v2',
          );
          final fullBundle = _encodeBundle(packV2, dirV2);
          final truncated = fullBundle.sublist(0, fullBundle.length ~/ 2);

          final result = await installer.installFromBytes(
            truncated,
            packId: packV2.id,
            expectedChecksum: packV2.checksum,
          );

          expect(result.outcome, InstallOutcome.rejectedMalformedBundle);
          expect(_snapshot(installedPacksDir), before);
          expect((await installer.installedPacks()).single.version, '1.0.0');
        },
      );

      test(
        'garbage bytes (not the bundle format at all) are rejected without throwing, prior pack untouched',
        () async {
          final (packV1, dirV1) = await _buildRealPack(title: 'Sat v1');
          final installer = PackInstaller(
            installedPacksDirectory: installedPacksDir,
          );
          await installer.installFromBytes(
            _encodeBundle(packV1, dirV1),
            packId: packV1.id,
            expectedChecksum: packV1.checksum,
          );
          final before = _snapshot(installedPacksDir);

          final garbage = Uint8List.fromList(
            List.generate(500, (i) => (i * 37) % 256),
          );

          final result = await installer.installFromBytes(
            garbage,
            packId: 'pack.fixture',
            expectedChecksum: 'anything',
          );

          expect(result.outcome, InstallOutcome.rejectedMalformedBundle);
          expect(_snapshot(installedPacksDir), before);
        },
      );

      test(
        'a well-formed bundle whose checksum simply does not match the caller-supplied expectation is rejected',
        () async {
          final (packV1, dirV1) = await _buildRealPack(title: 'Sat v1');
          final installer = PackInstaller(
            installedPacksDirectory: installedPacksDir,
          );
          await installer.installFromBytes(
            _encodeBundle(packV1, dirV1),
            packId: packV1.id,
            expectedChecksum: packV1.checksum,
          );
          final before = _snapshot(installedPacksDir);

          final (packV2, dirV2) = await _buildRealPack(
            version: '2.0.0',
            title: 'Sat v2',
          );
          final wellFormedButWrongChecksum = _encodeBundle(packV2, dirV2);

          final result = await installer.installFromBytes(
            wellFormedButWrongChecksum,
            packId: packV2.id,
            expectedChecksum: 'not-the-real-checksum-at-all',
          );

          expect(result.outcome, InstallOutcome.rejectedChecksumMismatch);
          expect(_snapshot(installedPacksDir), before);
        },
      );
    },
  );

  group('EDGE: a rejected install of a brand-new pack id leaves no trace', () {
    test(
      'installedPacksDirectory has no entry and no orphaned temp artifacts after a rejected fresh install',
      () async {
        final installer = PackInstaller(
          installedPacksDirectory: installedPacksDir,
        );
        final (pack, dir) = await _buildRealPack();
        final truncated = _encodeBundle(
          pack,
          dir,
        ).sublist(0, 3); // shorter than even the length prefix

        final result = await installer.installFromBytes(
          truncated,
          packId: pack.id,
          expectedChecksum: pack.checksum,
        );

        expect(result.outcome, InstallOutcome.rejectedMalformedBundle);
        expect(await installer.installedPacks(), isEmpty);
        // No stray files/directories of any kind under the installed-packs
        // root -- a rejected install must not leak partial state onto disk.
        expect(installedPacksDir.listSync(recursive: true), isEmpty);
      },
    );
  });
}

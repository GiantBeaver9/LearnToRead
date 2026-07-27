// Pins the API of lib/data/content/content_repository.dart and exercises it
// end-to-end against real pack_loader/pack_installer output (PRD §8 Unit 11:
// "Starter pack always present from the binary; the app is fully functional
// having never seen the network... Fresh install in airplane mode: full
// starter-pack experience end-to-end"; §8 Unit 15 grapheme inventory +
// example-word extension merge + partial-audio filtering; ticket
// content-delivery accept entries 2 and 9). This suite is authored before
// the implementation exists, so it is EXPECTED to fail to compile until
// content_repository.dart is written with exactly the shapes exercised
// below.
//
// Pinned API surface this suite requires (content_repository.dart):
//
//   class ContentRepository {
//     ContentRepository({required LoadedPack starterPack, required PackInstaller installer});
//
//     /// Starter pack's stories first, then every installed pack's
//     /// stories, installed packs ordered by id (deterministic).
//     Future<List<Story>> stories();
//     Future<List<TongueTwister>> twisters();
//     Future<List<VocabCard>> vocabCards();
//     Future<List<Collectible>> collectibles();
//
//     /// Unit 15: the id set is exactly the starter pack's GraphemeSound
//     /// ids (the fixed inventory ships in the binary; installed packs
//     /// never introduce a new id, only extend an existing one's
//     /// exampleWords). For each id, exampleWords are collected from every
//     /// contributing pack (starter, then installed packs by id) that
//     /// declares a GraphemeSound with that id, FILTERED to only the
//     /// entries whose pronunciationAudioRef resolves to a real file
//     /// within that contributing pack's own directory (a word with no
//     /// locally available audio is silently dropped -- "shows only words
//     /// it has audio for"), then DEDUPED by wordText keeping the first
//     /// surviving entry in merge order (starter wins any collision).
//     Future<List<GraphemeSound>> graphemeInventory();
//   }
//
// content_repository.dart has no network-shaped dependency anywhere in its
// constructor or methods -- that absence is itself the proof that reading
// content can never touch the network; catalog_client.dart's silent-failure
// contract (exercised here too) is what keeps a launch-time catalog check
// from disturbing this repository even when it fails.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/content/catalog_client.dart';
import 'package:learn_to_read/data/content/content_repository.dart';
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

/// Builds a real, on-disk StoryPack via `buildPack` with one story and one
/// GraphemeSound (id `graphemeId`), whose `exampleWords` are exactly
/// [exampleWords]. Every exampleWord's audio ref is written as a real file
/// UNLESS its wordText is in [missingAudioForWords] -- in which case the
/// pack still builds successfully (buildPack requires the file to exist at
/// build time) but the file is deleted afterward, simulating a locally
/// partial/never-downloaded asset.
Future<(StoryPack, Directory)> _buildRealPack({
  required String id,
  String storyTitle = 'Sat',
  String graphemeId = 'grapheme.s',
  required List<({String wordText, String pronunciationAudioRef})> exampleWords,
  Set<String> missingAudioForWords = const {},
}) async {
  final dir = Directory.systemTemp.createTempSync('offline_e2e_test_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  final story = Story(
    id: 'story.$id',
    levelId: 'level.1',
    title: storyTitle,
    pages: [
      Page(
        sentences: [
          Sentence(
            words: [_wordSat(), _wordSat(), _wordSat()],
            narrationAudioRef: 'audio/narration/$id.wav',
          ),
        ],
      ),
    ],
    riveAnimationRef: 'rive/$id.riv',
    celebrationAudioRef: 'audio/celebration/$id.wav',
    collectibleRef: 'collectible.$id',
    skillsExercised: const [],
    packId: id,
    contentVersion: '1',
  );
  final collectible = Collectible(
    id: 'collectible.$id',
    storyId: 'story.$id',
    riveRef: 'rive/collectibles/$id.riv',
    sceneSlot: 'shelf.$id',
  );
  final graphemeSound = GraphemeSound(
    id: graphemeId,
    grapheme: 's',
    phonemeIds: const ['S'],
    introducedAtLevelId: 'level.1',
    exampleWords: [
      for (final ew in exampleWords)
        (
          wordText: ew.wordText,
          pronunciationAudioRef: ew.pronunciationAudioRef,
          minLevelId: 'level.1',
        ),
    ],
  );

  final draft = StoryPack(
    id: id,
    version: '1.0.0',
    minAppVersion: '1.0.0',
    stories: [story],
    twisters: const [],
    vocabCards: const [],
    collectibles: [collectible],
    graphemeSounds: [graphemeSound],
    assetRefs: const [],
    checksum: '',
  );

  await File(
    p.join(dir.path, 'manifest.json'),
  ).writeAsString(jsonEncode(draft.toJson()));

  final audioRefs = <String>{
    story.celebrationAudioRef,
    story.pages.single.sentences.single.narrationAudioRef!,
    for (final w in story.pages.single.sentences.single.words)
      w.pronunciationAudioRef,
    for (final ew in graphemeSound.exampleWords) ew.pronunciationAudioRef,
  };
  for (final ref in audioRefs) {
    final f = File(p.join(dir.path, ref));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(_goodAudioBytes());
  }
  for (final riveRef in {story.riveAnimationRef, collectible.riveRef}) {
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
  await File(
    p.join(dir.path, 'manifest.json'),
  ).writeAsString(jsonEncode(result.pack!.toJson()));

  for (final ew in exampleWords) {
    if (missingAudioForWords.contains(ew.wordText)) {
      final f = File(p.join(dir.path, ew.pronunciationAudioRef));
      if (f.existsSync()) f.deleteSync();
    }
  }

  return (result.pack!, dir);
}

Uint8List _encodeBundle(StoryPack pack, Directory contentDir) {
  final files = <Map<String, Object?>>[];
  final chunks = <List<int>>[];
  for (final ref in pack.assetRefs) {
    final file = File(p.join(contentDir.path, ref));
    // Assets deliberately deleted post-build (simulating a locally missing
    // download) are simply omitted from the bundle -- exactly what a real
    // partial/optional-asset pack would ship.
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
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

/// A CatalogFetcher that fails every call, exactly as a device would while
/// truly offline (airplane mode) -- see catalog_client_test.dart for the
/// contract this exercises: fetch failure is silent.
class _AirplaneModeCatalogFetcher implements CatalogFetcher {
  int callCount = 0;

  @override
  Future<String?> fetchCatalogJson() async {
    callCount++;
    return null;
  }
}

void main() {
  group(
    'POSITIVE: fresh install in airplane mode -- starter pack alone is a full experience',
    () {
      test(
        'a repository built over only the starter pack serves its full content graph',
        () async {
          final (starterPack, starterDir) = await _buildRealPack(
            id: 'starter',
            storyTitle: 'Starter Story',
            exampleWords: const [
              (
                wordText: 'sat',
                pronunciationAudioRef: 'audio/words/sat-example.wav',
              ),
            ],
          );
          final starterLoaded = await loadPackFromDirectory(starterDir);
          final installer = PackInstaller(
            installedPacksDirectory: Directory.systemTemp.createTempSync(
              'offline_e2e_installed_',
            ),
          );
          addTearDown(() => installer.installedPacks());

          final repository = ContentRepository(
            starterPack: starterLoaded,
            installer: installer,
          );

          expect((await repository.stories()).map((s) => s.title), [
            'Starter Story',
          ]);
          expect(
            (await repository.collectibles()).single.id,
            'collectible.starter',
          );
          final inventory = await repository.graphemeInventory();
          expect(inventory.single.id, 'grapheme.s');
          expect(inventory.single.exampleWords.map((w) => w.wordText), ['sat']);
          expect(starterPack.id, 'starter');
        },
      );

      test(
        'the launch catalog check fails silently (airplane mode) and the starter experience is unaffected',
        () async {
          final (_, starterDir) = await _buildRealPack(
            id: 'starter',
            exampleWords: const [
              (
                wordText: 'sat',
                pronunciationAudioRef: 'audio/words/sat-example.wav',
              ),
            ],
          );
          final starterLoaded = await loadPackFromDirectory(starterDir);
          final installer = PackInstaller(
            installedPacksDirectory: Directory.systemTemp.createTempSync(
              'offline_e2e_installed_',
            ),
          );
          final repository = ContentRepository(
            starterPack: starterLoaded,
            installer: installer,
          );

          final airplaneModeFetcher = _AirplaneModeCatalogFetcher();
          final catalogClient = CatalogClient(fetcher: airplaneModeFetcher);
          final catalogResult = await catalogClient.checkCatalog(
            currentAppVersion: '1.0.0',
          );

          expect(catalogResult.success, isFalse);
          expect(catalogResult.entries, isEmpty);
          expect(airplaneModeFetcher.callCount, 1);
          // The failed catalog check touches nothing about the repository --
          // content is still fully available.
          expect((await repository.stories()), hasLength(1));
          expect((await repository.graphemeInventory()), hasLength(1));
        },
      );

      test(
        'a never-installed installer directory (truly fresh install) still yields the full starter graph',
        () async {
          final (_, starterDir) = await _buildRealPack(
            id: 'starter',
            exampleWords: const [],
          );
          final starterLoaded = await loadPackFromDirectory(starterDir);
          final freshDir = Directory.systemTemp.createTempSync(
            'offline_e2e_never_installed_',
          );
          addTearDown(() {
            if (freshDir.existsSync()) freshDir.deleteSync(recursive: true);
          });
          final installer = PackInstaller(installedPacksDirectory: freshDir);

          final repository = ContentRepository(
            starterPack: starterLoaded,
            installer: installer,
          );

          expect(await installer.installedPacks(), isEmpty);
          expect((await repository.stories()), hasLength(1));
          expect((await repository.twisters()), isEmpty);
          expect((await repository.vocabCards()), isEmpty);
        },
      );
    },
  );

  group(
    'POSITIVE: installed CDN packs enumerate and merge with the starter pack',
    () {
      test(
        'an installed pack\'s story appears in the repository alongside the starter\'s',
        () async {
          final (starterPack, starterDir) = await _buildRealPack(
            id: 'starter',
            storyTitle: 'Starter Story',
            exampleWords: const [],
          );
          final starterLoaded = await loadPackFromDirectory(starterDir);
          final installedDir = Directory.systemTemp.createTempSync(
            'offline_e2e_installed_',
          );
          addTearDown(() {
            if (installedDir.existsSync())
              installedDir.deleteSync(recursive: true);
          });
          final installer = PackInstaller(
            installedPacksDirectory: installedDir,
          );

          final (packB, dirB) = await _buildRealPack(
            id: 'pack.b',
            storyTitle: 'Forest Story',
            exampleWords: const [],
          );
          final installResult = await installer.installFromBytes(
            _encodeBundle(packB, dirB),
            packId: packB.id,
            expectedChecksum: packB.checksum,
          );
          expect(installResult.outcome, InstallOutcome.installed);

          final repository = ContentRepository(
            starterPack: starterLoaded,
            installer: installer,
          );

          final titles = (await repository.stories())
              .map((s) => s.title)
              .toSet();
          expect(titles, {'Starter Story', 'Forest Story'});
          expect(starterPack.stories.single.title, 'Starter Story');
        },
      );
    },
  );

  group('POSITIVE: Unit 15 example-word extension merge across packs', () {
    test(
      'an installed pack extending the starter\'s grapheme card contributes its own example words',
      () async {
        final (_, starterDir) = await _buildRealPack(
          id: 'starter',
          exampleWords: const [
            (
              wordText: 'sat',
              pronunciationAudioRef: 'audio/words/sat-example.wav',
            ),
          ],
        );
        final starterLoaded = await loadPackFromDirectory(starterDir);
        final installedDir = Directory.systemTemp.createTempSync(
          'offline_e2e_installed_',
        );
        addTearDown(() {
          if (installedDir.existsSync())
            installedDir.deleteSync(recursive: true);
        });
        final installer = PackInstaller(installedPacksDirectory: installedDir);

        final (packB, dirB) = await _buildRealPack(
          id: 'pack.b',
          exampleWords: const [
            (
              wordText: 'sun',
              pronunciationAudioRef: 'audio/words/sun-example.wav',
            ),
          ],
        );
        await installer.installFromBytes(
          _encodeBundle(packB, dirB),
          packId: packB.id,
          expectedChecksum: packB.checksum,
        );

        final repository = ContentRepository(
          starterPack: starterLoaded,
          installer: installer,
        );
        final inventory = await repository.graphemeInventory();

        expect(
          inventory,
          hasLength(1),
          reason:
              'the extension pack must not introduce a second inventory entry',
        );
        expect(inventory.single.id, 'grapheme.s');
        expect(inventory.single.exampleWords.map((w) => w.wordText).toSet(), {
          'sat',
          'sun',
        });
      },
    );

    test(
      'a card shows only words it has downloaded audio for -- partial-pack audio filtering',
      () async {
        final (_, starterDir) = await _buildRealPack(
          id: 'starter',
          exampleWords: const [
            (
              wordText: 'sat',
              pronunciationAudioRef: 'audio/words/sat-example.wav',
            ),
          ],
        );
        final starterLoaded = await loadPackFromDirectory(starterDir);
        final installedDir = Directory.systemTemp.createTempSync(
          'offline_e2e_installed_',
        );
        addTearDown(() {
          if (installedDir.existsSync())
            installedDir.deleteSync(recursive: true);
        });
        final installer = PackInstaller(installedPacksDirectory: installedDir);

        final (packB, dirB) = await _buildRealPack(
          id: 'pack.b',
          exampleWords: const [
            (
              wordText: 'sun',
              pronunciationAudioRef: 'audio/words/sun-example.wav',
            ),
            (
              wordText: 'sit',
              pronunciationAudioRef: 'audio/words/sit-example.wav',
            ),
          ],
          missingAudioForWords: const {'sit'},
        );
        final install = await installer.installFromBytes(
          _encodeBundle(packB, dirB),
          packId: packB.id,
          expectedChecksum: packB.checksum,
        );
        expect(install.outcome, InstallOutcome.installed);

        final repository = ContentRepository(
          starterPack: starterLoaded,
          installer: installer,
        );
        final inventory = await repository.graphemeInventory();

        final words = inventory.single.exampleWords
            .map((w) => w.wordText)
            .toSet();
        expect(words, {'sat', 'sun'});
        expect(
          words.contains('sit'),
          isFalse,
          reason:
              '"sit" has no locally available audio and must not be surfaced',
        );
      },
    );

    test(
      'the same word contributed by two packs appears exactly once (no duplicate cards/entries)',
      () async {
        final (_, starterDir) = await _buildRealPack(
          id: 'starter',
          exampleWords: const [
            (
              wordText: 'sat',
              pronunciationAudioRef: 'audio/words/sat-example.wav',
            ),
          ],
        );
        final starterLoaded = await loadPackFromDirectory(starterDir);
        final installedDir = Directory.systemTemp.createTempSync(
          'offline_e2e_installed_',
        );
        addTearDown(() {
          if (installedDir.existsSync())
            installedDir.deleteSync(recursive: true);
        });
        final installer = PackInstaller(installedPacksDirectory: installedDir);

        final (packB, dirB) = await _buildRealPack(
          id: 'pack.b',
          // Re-declares "sat" (a collision with the starter's own entry) via
          // a distinct audio ref, plus a genuinely new word.
          exampleWords: const [
            (
              wordText: 'sat',
              pronunciationAudioRef: 'audio/words/sat-example-b.wav',
            ),
            (
              wordText: 'sun',
              pronunciationAudioRef: 'audio/words/sun-example.wav',
            ),
          ],
        );
        await installer.installFromBytes(
          _encodeBundle(packB, dirB),
          packId: packB.id,
          expectedChecksum: packB.checksum,
        );

        final repository = ContentRepository(
          starterPack: starterLoaded,
          installer: installer,
        );
        final inventory = await repository.graphemeInventory();

        final satEntries = inventory.single.exampleWords
            .where((w) => w.wordText == 'sat')
            .toList();
        expect(satEntries, hasLength(1));
        // Pinned tie-break: the starter's entry wins a collision (first in
        // merge order), never the installed pack's.
        expect(
          satEntries.single.pronunciationAudioRef,
          'audio/words/sat-example.wav',
        );
        expect(inventory.single.exampleWords.map((w) => w.wordText).toSet(), {
          'sat',
          'sun',
        });
      },
    );
  });
}

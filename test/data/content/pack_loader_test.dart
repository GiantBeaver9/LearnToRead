// Pins the API of lib/data/content/pack_loader.dart (PRD §8 Unit 11; ticket
// content-delivery accept entry 1: "pack_loader loads a pack bundle (built
// by lib/pipeline/pack_builder code in a test setup) into §5 content models
// end-to-end: text renders (models parse), audio refs resolve to files,
// Rive refs resolve"). This suite is authored before the implementation
// exists, so it is EXPECTED to fail to compile until pack_loader.dart is
// written with exactly the shapes exercised below.
//
// Per this ticket's notes, fixture packs are BUILT BY the real pipeline
// (lib/pipeline/pack_builder.dart's `buildPack`, merged dep -- never
// hand-rolled) inside test setup: a content directory is assembled exactly
// as pack_builder_test.dart does, `buildPack` is run against it to produce
// a real checksummed StoryPack, and the checksummed manifest is written
// back to the same directory (the CLI step of "write the built bundle to
// disk" that tool/pack_build.dart would otherwise do -- out of scope here
// per the pack-build-cli ticket, so this suite performs that one write
// itself) -- producing a genuine, on-disk pack bundle directory for
// pack_loader to load.
//
// Pinned API surface this suite requires:
//
//   class PackLoadException implements Exception {
//     final String message;
//   }
//   class LoadedPack {
//     final StoryPack pack;
//     final Directory directory;
//     /// Absolute path to `<directory>/<ref>` (ref is a '/'-separated path,
//     /// resolved with this platform's separator) iff that file exists on
//     /// disk, else null. Never throws.
//     String? resolveAsset(String ref);
//     bool hasAsset(String ref); // == resolveAsset(ref) != null
//   }
//   /// Reads `<directory>/manifest.json`, decodes it, and reconstructs a
//   /// StoryPack via `StoryPack.fromJson` (pack_manifest.dart, merged dep).
//   /// Throws PackLoadException if manifest.json is missing, is not valid
//   /// JSON, its root is not a JSON object, or a field StoryPack.fromJson
//   /// requires is missing/mistyped. Does NOT itself re-run
//   /// validatePackManifest or verify the manifest checksum -- this loader
//   /// trusts its input directory (checksum verification is
//   /// pack_installer's job, upstream of this call).
//   Future<LoadedPack> loadPackFromDirectory(Directory directory);
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/content/pack_loader.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/pack_manifest.dart';
import 'package:learn_to_read/pipeline/loudness_check.dart';
import 'package:learn_to_read/pipeline/pack_builder.dart';
import 'package:path/path.dart' as p;

// ---------------------------------------------------------------------------
// Fixture generation (file-local per this codebase's convention; see
// test/pipeline/pack_builder_test.dart for the shared rationale).
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

Uint8List _sineWavBytes({
  double amplitude = 0.3,
  double frequencyHz = 997,
  double durationSeconds = 1.0,
  int sampleRate = 44100,
}) {
  final n = (sampleRate * durationSeconds).round();
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

WordToken _wordSat({String ref = 'audio/words/sat.wav'}) => WordToken(
  text: 'sat',
  graphemePhonemeMap: const [
    (graphemes: 's', phonemeId: 'S'),
    (graphemes: 'a', phonemeId: 'AE'),
    (graphemes: 't', phonemeId: 'T'),
  ],
  pronunciationAudioRef: ref,
);

StoryPack _fixturePack() {
  final story = Story(
    id: 'story.1',
    levelId: 'level.1',
    title: 'Sat',
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
    packId: 'pack.fixture',
    contentVersion: '1',
  );
  final twister = TongueTwister(
    id: 'twister.1',
    levelId: 'level.1',
    words: [_wordSat()],
    targetPhonemeId: 'S',
    narrationAudioRef: 'audio/twisters/1.wav',
    packId: 'pack.fixture',
  );
  final vocabCard = VocabCard(
    id: 'vocab.sat',
    word: 'sat',
    definitionText: 'To have sat down.',
    definitionAudioRef: 'audio/defs/sat.wav',
  );
  final collectible = Collectible(
    id: 'collectible.story.1',
    storyId: 'story.1',
    riveRef: 'rive/collectibles/sat.riv',
    sceneSlot: 'shelf.1',
  );
  final graphemeSound = GraphemeSound(
    id: 'grapheme.s',
    grapheme: 's',
    phonemeIds: const ['S'],
    introducedAtLevelId: 'level.1',
    exampleWords: const [
      (
        wordText: 'sat',
        pronunciationAudioRef: 'audio/words/sat-example.wav',
        minLevelId: 'level.1',
      ),
    ],
  );

  return StoryPack(
    id: 'pack.fixture',
    version: '1.0.0',
    minAppVersion: '1.0.0',
    stories: [story],
    twisters: [twister],
    vocabCards: [vocabCard],
    collectibles: [collectible],
    graphemeSounds: [graphemeSound],
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
  for (final twister in pack.twisters) {
    refs.add(twister.narrationAudioRef);
    for (final word in twister.words) {
      refs.add(word.pronunciationAudioRef);
    }
  }
  for (final card in pack.vocabCards) {
    refs.add(card.definitionAudioRef);
  }
  for (final gs in pack.graphemeSounds) {
    for (final ew in gs.exampleWords) {
      refs.add(ew.pronunciationAudioRef);
    }
  }
  return refs;
}

Set<String> _riveRefs(StoryPack pack) => <String>{
  for (final story in pack.stories) story.riveAnimationRef,
  for (final c in pack.collectibles) c.riveRef,
};

/// Builds a real, on-disk pack bundle directory: assembles a content
/// directory, runs it through the real `buildPack` pipeline, then writes
/// the resulting checksummed manifest back to disk -- so `pack_loader`
/// loads exactly what the real pipeline would ship. [deleteAssetsAfterBuild]
/// removes asset files from disk only *after* a successful build (so the
/// build itself always sees a fully valid content directory), simulating a
/// directory pack_installer left partially populated.
Future<Directory> _buildRealPackBundleDir({
  Set<String> deleteAssetsAfterBuild = const {},
}) async {
  final dir = Directory.systemTemp.createTempSync('pack_loader_test_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  final draft = _fixturePack();
  await File(
    p.join(dir.path, 'manifest.json'),
  ).writeAsString(jsonEncode(draft.toJson()));

  for (final ref in _audioRefs(draft)) {
    final f = File(p.join(dir.path, ref));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(_goodAudioBytes());
  }
  for (final riveRef in _riveRefs(draft)) {
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
  // Write the final checksummed manifest back -- this is the on-disk bundle
  // pack_loader is contracted to read.
  await File(
    p.join(dir.path, 'manifest.json'),
  ).writeAsString(jsonEncode(result.pack!.toJson()));

  for (final ref in deleteAssetsAfterBuild) {
    final f = File(p.join(dir.path, ref));
    if (f.existsSync()) f.deleteSync();
  }

  return dir;
}

void main() {
  group(
    'POSITIVE: loadPackFromDirectory loads a real built bundle end-to-end',
    () {
      test(
        'the loaded StoryPack matches the built pack (text renders -- models parse)',
        () async {
          final dir = await _buildRealPackBundleDir();

          final loaded = await loadPackFromDirectory(dir);

          expect(loaded.pack.id, 'pack.fixture');
          expect(loaded.pack.stories.single.title, 'Sat');
          expect(
            loaded.pack.stories.single.pages.single.sentences.single.words.map(
              (w) => w.text,
            ),
            ['sat', 'sat', 'sat'],
          );
          expect(loaded.pack.twisters.single.id, 'twister.1');
          expect(loaded.pack.vocabCards.single.word, 'sat');
          expect(loaded.pack.collectibles.single.id, 'collectible.story.1');
          expect(loaded.pack.graphemeSounds.single.grapheme, 's');
          expect(loaded.pack.checksum, isNotEmpty);
        },
      );

      test('audio refs resolve to real files on disk', () async {
        final dir = await _buildRealPackBundleDir();
        final loaded = await loadPackFromDirectory(dir);

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
        final resolved = loaded.resolveAsset(wordRef);

        expect(resolved, isNotNull);
        expect(File(resolved!).existsSync(), isTrue);
        expect(
          File(resolved).readAsBytesSync(),
          File(p.join(dir.path, wordRef)).readAsBytesSync(),
        );
        expect(loaded.hasAsset(wordRef), isTrue);
      });

      test(
        'vocab card, twister, and grapheme example-word audio refs all resolve',
        () async {
          final dir = await _buildRealPackBundleDir();
          final loaded = await loadPackFromDirectory(dir);

          expect(
            loaded.resolveAsset(
              loaded.pack.vocabCards.single.definitionAudioRef,
            ),
            isNotNull,
          );
          expect(
            loaded.resolveAsset(loaded.pack.twisters.single.narrationAudioRef),
            isNotNull,
          );
          expect(
            loaded.resolveAsset(
              loaded
                  .pack
                  .graphemeSounds
                  .single
                  .exampleWords
                  .single
                  .pronunciationAudioRef,
            ),
            isNotNull,
          );
          expect(
            loaded.resolveAsset(
              loaded
                  .pack
                  .stories
                  .single
                  .pages
                  .single
                  .sentences
                  .single
                  .narrationAudioRef!,
            ),
            isNotNull,
          );
          expect(
            loaded.resolveAsset(loaded.pack.stories.single.celebrationAudioRef),
            isNotNull,
          );
        },
      );

      test('Rive refs resolve (story animation and collectible)', () async {
        final dir = await _buildRealPackBundleDir();
        final loaded = await loadPackFromDirectory(dir);

        expect(
          loaded.resolveAsset(loaded.pack.stories.single.riveAnimationRef),
          isNotNull,
        );
        expect(
          loaded.resolveAsset(loaded.pack.collectibles.single.riveRef),
          isNotNull,
        );
        expect(
          File(
            loaded.resolveAsset(loaded.pack.collectibles.single.riveRef)!,
          ).existsSync(),
          isTrue,
        );
      });
    },
  );

  group('NEGATIVE: unresolvable refs and malformed bundle directories', () {
    test(
      'resolveAsset returns null for a ref with no file behind it',
      () async {
        final dir = await _buildRealPackBundleDir();
        final loaded = await loadPackFromDirectory(dir);

        expect(loaded.resolveAsset('audio/does/not/exist.wav'), isNull);
        expect(loaded.hasAsset('audio/does/not/exist.wav'), isFalse);
      },
    );

    test(
      'a directory with no manifest.json throws PackLoadException',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'pack_loader_test_empty_',
        );
        addTearDown(() {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        });

        expect(
          () => loadPackFromDirectory(dir),
          throwsA(isA<PackLoadException>()),
        );
      },
    );

    test(
      'a manifest.json that is not valid JSON throws PackLoadException',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'pack_loader_test_badjson_',
        );
        addTearDown(() {
          if (dir.existsSync()) dir.deleteSync(recursive: true);
        });
        await File(
          p.join(dir.path, 'manifest.json'),
        ).writeAsString('{ not json');

        expect(
          () => loadPackFromDirectory(dir),
          throwsA(isA<PackLoadException>()),
        );
      },
    );

    test(
      'a manifest.json missing a field StoryPack.fromJson requires throws PackLoadException',
      () async {
        final dir = await _buildRealPackBundleDir();
        final manifestFile = File(p.join(dir.path, 'manifest.json'));
        final json =
            jsonDecode(await manifestFile.readAsString())
                as Map<String, dynamic>;
        json.remove('stories');
        await manifestFile.writeAsString(jsonEncode(json));

        expect(
          () => loadPackFromDirectory(dir),
          throwsA(isA<PackLoadException>()),
        );
      },
    );
  });

  group('EDGE: a pack directory with an asset genuinely absent from disk', () {
    test(
      'the pack still loads (manifest is trusted) but the missing ref does not resolve',
      () async {
        final dir = await _buildRealPackBundleDir(
          deleteAssetsAfterBuild: {'audio/words/sat-example.wav'},
        );
        // buildPack itself would have refused a content dir missing this file
        // (assetPresence/graphemeSound stage), so the deletion happens only
        // after a successful build -- this is the shape the loader must
        // tolerate when handed a partially-installed directory.
        final loaded = await loadPackFromDirectory(dir);

        expect(
          loaded.pack.graphemeSounds.single.exampleWords.single.wordText,
          'sat',
        );
        expect(loaded.resolveAsset('audio/words/sat-example.wav'), isNull);
      },
    );
  });
}

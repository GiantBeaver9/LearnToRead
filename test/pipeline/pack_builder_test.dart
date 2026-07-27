// Pins the API of lib/pipeline/pack_builder.dart, the pure library layer
// `tool/pack_build.dart`'s CLI wraps (PRD §8 Unit 3 accept: "pack build
// produces a bundle... round-trip manifest schema validates all launch
// stories... fails with a per-field error"; §9 A-9/A-11/A-15/A-16; ticket
// pack-build-cli accept entries 1-4, 9-10). This suite is authored before
// the implementation exists, so it is EXPECTED to fail to compile until
// pack_builder.dart is written with exactly the shapes exercised below.
//
// SCOPE NOTE (per this ticket's build-loop instructions): `tool/pack_build.
// dart` itself -- CLI arg parsing, reading a content dir from argv, writing
// the built bundle to an output path on disk -- is a thin, near-untestable
// process wrapper around `buildPack` below; it is not exercised headlessly
// by this suite. The cross-ticket "bundle is loadable by content-delivery's
// loader" integration test explicitly lives in the content-delivery ticket
// per the ticket's own accept-entry-1 text. This suite instead fully
// exercises the pure orchestration function the CLI wraps.
//
// Pinned API surface this suite requires:
//
//   class PackBuildError {
//     final String stage;      // 'schema' | 'decodability' | 'assetPresence'
//                               // | 'loudness' | 'riveInputs' | 'graphemeSound'
//     final String entityType; // 'pack' | 'story' | 'twister' | 'vocabCard'
//                               // | 'collectible' | 'graphemeSound' | 'level'
//                               // | 'wordToken' | 'asset' | 'rive'
//     final String entityId;
//     final String field;
//     final String message;
//   }
//   class PackBuildResult {
//     final bool success;                                    // true iff errors is empty
//     final List<PackBuildError> errors;                      // aggregated, never fail-fast
//     final StoryPack? pack;                                  // non-null iff success
//     final List<StarterPackCompositionWarning> compositionWarnings; // never fails the build
//   }
//   Future<PackBuildResult> buildPack({
//     required String contentDir,
//     required List<Level> levels,
//     Map<String, List<String>> heartWordsByLevelId = const {},
//     List<String>? starterCompositionLevelIds,
//     double loudnessTargetLufs = -16.0,
//     double loudnessToleranceLu = 1.0,
//   });
//
//   /// A-15: SHA-256 checksum of a manifest map, computed over the UTF-8
//   /// bytes of `jsonEncode(manifestJson)` where `manifestJson`'s own
//   /// `checksum` field has been forced to `''` before encoding (so the
//   /// checksum never depends on itself). `buildPack` sets the built pack's
//   /// `checksum` to this value.
//   String computeManifestChecksum(Map<String, dynamic> manifestJson);
//
//   /// True iff `manifestJson['checksum']` equals
//   /// `computeManifestChecksum` of `manifestJson` with its `checksum` field
//   /// forced to `''`.
//   bool verifyManifestChecksum(Map<String, dynamic> manifestJson);
//
// Content-directory contract pinned by this suite:
//   <contentDir>/manifest.json  -- the raw manifest JSON (as produced by
//     `StoryPack.toJson()`); its `checksum` field is ignored by `buildPack`
//     (recomputed) but must be present as a string (possibly `''`) to pass
//     the schema's field-presence check.
//   Every audio/rive ref used anywhere in the manifest is a '/'-separated
//     path relative to `contentDir`; asset presence / loudness checks read
//     `<contentDir>/<ref>`.
//   Rive sidecar: a riveRef `"rive/foo.riv"` is validated against the
//     sidecar JSON at `"<contentDir>/rive/foo.riv.inputs.json"` (A-16;
//     missing file == missing sidecar).
//   Loudness is checked for exactly the audio-ref fields the domain model
//     defines as audio: WordToken.pronunciationAudioRef,
//     VocabCard.definitionAudioRef, Sentence.narrationAudioRef,
//     Story.celebrationAudioRef, TongueTwister.narrationAudioRef,
//     GraphemeSound.exampleWords[].pronunciationAudioRef.
//
// Contract this suite locks in (builder-mechanical): errors from every
// stage are aggregated into one flat `errors` list (never fail-fast); a
// decodability `outOfLevelWord` finding becomes exactly one PackBuildError
// per finding, with `message` containing both the offending word text and
// the story id (ticket instruction: "decodability findings fail the build
// naming word+story"); `success` is false iff `errors` is non-empty
// regardless of `compositionWarnings` (composition is warn-only, per A-9).

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/pack_manifest.dart';
import 'package:learn_to_read/pipeline/loudness_check.dart';
import 'package:learn_to_read/pipeline/pack_builder.dart';
import 'package:path/path.dart' as p;

// ---------------------------------------------------------------------------
// WAV fixture generation (programmatic PCM16 sine waves; see loudness_check_
// test.dart for the shared rationale -- duplicated here per this codebase's
// file-local fixture convention).
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

Uint8List _sineWavBytes({required double amplitude, double frequencyHz = 997, double durationSeconds = 1.0, int sampleRate = 44100}) {
  final n = (sampleRate * durationSeconds).round();
  final samples = Int16List(n);
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final v = amplitude * math.sin(2 * math.pi * frequencyHz * t);
    samples[i] = (v * 32767).round().clamp(-32768, 32767);
  }
  return _pcm16MonoWav(samples, sampleRate: sampleRate);
}

/// -16 LUFS normalized audio, suitable as a default "everything passes"
/// fixture asset -- built via the pipeline's own loudness_check.dart (the
/// real implementation both files will share once built).
Uint8List _goodAudioBytes() => normalizeToTargetLoudness(_sineWavBytes(amplitude: 0.3), targetLufs: -16.0);

// ---------------------------------------------------------------------------
// Content-model fixtures (file-local per this codebase's fixture convention).
// ---------------------------------------------------------------------------

final _level1 = Level(
  id: 'level.1',
  ordinal: 1,
  format: LevelFormat.sentence,
  vocabEnabled: false,
  newSkills: [
    PhonicsSkill(id: 'skill.1', name: 'starter', sequenceOrder: 1, introducesGraphemes: const ['s', 'a', 't']),
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

GraphemeSound _validGraphemeSound({List<String> phonemeIds = const ['S']}) => GraphemeSound(
      id: 'grapheme.s',
      grapheme: 's',
      phonemeIds: phonemeIds,
      introducedAtLevelId: 'level.1',
      exampleWords: const [
        (wordText: 'sat', pronunciationAudioRef: 'audio/words/sat-example.wav', minLevelId: 'level.1'),
      ],
    );

/// A fully valid fixture StoryPack: one sentence-format story (3 decodable
/// "sat" words, satisfying A-8's 3-8 word band), one twister, one vocab
/// card, one collectible, one grapheme sound -- every field overridable so
/// individual tests can introduce exactly one problem at a time.
StoryPack _validPack({
  String? narrationAudioRef = 'audio/narration/story.1.wav',
  List<WordToken>? storyWords,
  List<GraphemeSound>? graphemeSounds,
}) {
  final words = storyWords ?? [_wordSat(), _wordSat(), _wordSat()];
  final story = Story(
    id: 'story.1',
    levelId: 'level.1',
    title: 'Sat',
    pages: [
      Page(sentences: [Sentence(words: words, narrationAudioRef: narrationAudioRef)]),
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

  return StoryPack(
    id: 'pack.fixture',
    version: '1.0.0',
    minAppVersion: '1.0.0',
    stories: [story],
    twisters: [twister],
    vocabCards: [vocabCard],
    collectibles: [collectible],
    graphemeSounds: graphemeSounds ?? [_validGraphemeSound()],
    assetRefs: const [],
    checksum: '',
  );
}

Set<String> _collectAudioRefs(StoryPack pack) {
  final refs = <String>{};
  for (final story in pack.stories) {
    refs.add(story.celebrationAudioRef);
    for (final page in story.pages) {
      for (final sentence in page.sentences) {
        if (sentence.narrationAudioRef != null) refs.add(sentence.narrationAudioRef!);
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

Set<String> _collectRiveRefs(StoryPack pack) {
  final refs = <String>{};
  for (final story in pack.stories) {
    refs.add(story.riveAnimationRef);
  }
  for (final c in pack.collectibles) {
    refs.add(c.riveRef);
  }
  return refs;
}

/// Materializes [pack] as a content directory: manifest.json + every
/// referenced audio asset (default: -16-LUFS-normalized, so an unmodified
/// fixture passes every stage) + every rive sidecar (default: declares
/// idle/celebrate/collect). Individual tests punch exactly one hole via the
/// override parameters. Registers its own cleanup via `addTearDown`.
Future<Directory> _buildFixtureContentDir(
  StoryPack pack, {
  Set<String> skipAssetRefs = const {},
  Map<String, Uint8List> assetBytesOverride = const {},
  Set<String> skipSidecarRiveRefs = const {},
  Map<String, Map<String, dynamic>> sidecarOverride = const {},
}) async {
  final dir = Directory.systemTemp.createTempSync('pack_builder_test_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  await File(p.join(dir.path, 'manifest.json')).writeAsString(jsonEncode(pack.toJson()));

  for (final ref in _collectAudioRefs(pack)) {
    if (skipAssetRefs.contains(ref)) continue;
    final bytes = assetBytesOverride[ref] ?? _goodAudioBytes();
    final f = File(p.join(dir.path, ref));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes);
  }

  for (final riveRef in _collectRiveRefs(pack)) {
    if (skipSidecarRiveRefs.contains(riveRef)) continue;
    final sidecarJson = sidecarOverride[riveRef] ??
        const {
          'inputs': ['idle', 'celebrate', 'collect'],
        };
    final f = File(p.join(dir.path, '$riveRef.inputs.json'));
    await f.parent.create(recursive: true);
    await f.writeAsString(jsonEncode(sidecarJson));
  }

  return dir;
}

void main() {
  group('buildPack (positive baseline, accept 1 & 2: valid fixture builds successfully)', () {
    test('a fully valid fixture content directory builds a checksummed StoryPack', () async {
      final pack = _validPack();
      final dir = await _buildFixtureContentDir(pack);

      final result = await buildPack(contentDir: dir.path, levels: [_level1]);

      expect(result.success, isTrue);
      expect(result.errors, isEmpty);
      expect(result.pack, isNotNull);
      expect(result.pack!.stories.single.id, 'story.1');
      expect(result.pack!.twisters.single.id, 'twister.1');
      expect(result.pack!.vocabCards.single.id, 'vocab.sat');
      expect(result.pack!.graphemeSounds.single.id, 'grapheme.s');
      expect(result.pack!.checksum, isNotEmpty);
      expect(verifyManifestChecksum(result.pack!.toJson()), isTrue);
    });
  });

  group('buildPack (negative, accept 2 & 4: schema failure fails build with per-field error)', () {
    test('a story missing riveAnimationRef fails, naming the field and story id', () async {
      final pack = _validPack();
      final dir = await _buildFixtureContentDir(pack);
      final manifestJson = pack.toJson();
      (manifestJson['stories'] as List).cast<Map<String, dynamic>>().first.remove('riveAnimationRef');
      await File(p.join(dir.path, 'manifest.json')).writeAsString(jsonEncode(manifestJson));

      final result = await buildPack(contentDir: dir.path, levels: [_level1]);

      expect(result.success, isFalse);
      expect(result.pack, isNull);
      final error = result.errors.firstWhere(
        (e) => e.stage == 'schema' && e.field == 'riveAnimationRef' && e.entityId == 'story.1',
        orElse: () => throw StateError('expected a schema/riveAnimationRef error'),
      );
      expect(error.entityType, 'story');
    });
  });

  group('buildPack (negative, accept 4: A-11 -- missing narration fails sentence-format story)', () {
    test('a sentence-format story missing narrationAudioRef fails the build', () async {
      final pack = _validPack(narrationAudioRef: null);
      final dir = await _buildFixtureContentDir(pack);

      final result = await buildPack(contentDir: dir.path, levels: [_level1]);

      expect(result.success, isFalse);
      expect(
        result.errors.any(
          (e) => e.field == 'narrationAudioRef' && e.entityType == 'story' && e.entityId == 'story.1',
        ),
        isTrue,
      );
    });
  });

  group('buildPack (negative+positive, accept 3: decodability wiring, out-of-level word / heart-word whitelist)', () {
    final shipWord = WordToken(
      text: 'ship',
      graphemePhonemeMap: const [
        (graphemes: 'sh', phonemeId: 'SH'),
        (graphemes: 'i', phonemeId: 'IH'),
        (graphemes: 'p', phonemeId: 'P'),
      ],
      pronunciationAudioRef: 'audio/words/ship.wav',
    );

    test('a story with an out-of-level word fails, naming the word and the story', () async {
      final pack = _validPack(storyWords: [_wordSat(), _wordSat(), _wordSat(), shipWord]);
      final dir = await _buildFixtureContentDir(pack);

      final result = await buildPack(contentDir: dir.path, levels: [_level1]);

      expect(result.success, isFalse);
      final error = result.errors.firstWhere(
        (e) => e.stage == 'decodability',
        orElse: () => throw StateError('expected a decodability error'),
      );
      expect(error.message, contains('ship'));
      expect(error.message, contains('story.1'));
    });

    test('the same story passes once "ship" is whitelisted as a heart word at level.1', () async {
      final pack = _validPack(storyWords: [_wordSat(), _wordSat(), _wordSat(), shipWord]);
      final dir = await _buildFixtureContentDir(pack);

      final result = await buildPack(
        contentDir: dir.path,
        levels: [_level1],
        heartWordsByLevelId: const {
          'level.1': ['ship'],
        },
      );

      expect(result.success, isTrue);
    });
  });

  group('buildPack (negative, accept 5: asset presence)', () {
    test('a missing WordToken pronunciationAudioRef file fails, naming the ref', () async {
      final pack = _validPack();
      final dir = await _buildFixtureContentDir(pack, skipAssetRefs: {'audio/words/sat.wav'});

      final result = await buildPack(contentDir: dir.path, levels: [_level1]);

      expect(result.success, isFalse);
      expect(
        result.errors.any((e) => e.stage == 'assetPresence' && e.message.contains('audio/words/sat.wav')),
        isTrue,
      );
    });

    test('a missing VocabCard definitionAudioRef file fails, naming the ref', () async {
      final pack = _validPack();
      final dir = await _buildFixtureContentDir(pack, skipAssetRefs: {'audio/defs/sat.wav'});

      final result = await buildPack(contentDir: dir.path, levels: [_level1]);

      expect(result.success, isFalse);
      expect(
        result.errors.any((e) => e.stage == 'assetPresence' && e.message.contains('audio/defs/sat.wav')),
        isTrue,
      );
    });
  });

  group('buildPack (negative, accept 6: loudness)', () {
    test('an audio asset far too quiet fails the build, naming the asset ref', () async {
      final pack = _validPack();
      final dir = await _buildFixtureContentDir(
        pack,
        assetBytesOverride: {'audio/words/sat.wav': _sineWavBytes(amplitude: 0.003)},
      );

      final result = await buildPack(contentDir: dir.path, levels: [_level1]);

      expect(result.success, isFalse);
      expect(
        result.errors.any((e) => e.stage == 'loudness' && e.message.contains('audio/words/sat.wav')),
        isTrue,
      );
    });

    test('an audio asset far too loud fails the build', () async {
      final pack = _validPack();
      final dir = await _buildFixtureContentDir(
        pack,
        assetBytesOverride: {'audio/words/sat.wav': _sineWavBytes(amplitude: 0.99)},
      );

      final result = await buildPack(contentDir: dir.path, levels: [_level1]);

      expect(result.success, isFalse);
      expect(result.errors.any((e) => e.stage == 'loudness'), isTrue);
    });
  });

  group('buildPack (negative, accept 7: Rive sidecar wiring, A-16)', () {
    test('a story riveRef missing its sidecar file fails the build, naming the ref', () async {
      final pack = _validPack();
      final dir = await _buildFixtureContentDir(pack, skipSidecarRiveRefs: {'rive/story.1.riv'});

      final result = await buildPack(contentDir: dir.path, levels: [_level1]);

      expect(result.success, isFalse);
      expect(
        result.errors.any((e) => e.stage == 'riveInputs' && e.message.contains('rive/story.1.riv')),
        isTrue,
      );
    });

    test('a collectible riveRef whose sidecar lacks a required input fails the build', () async {
      final pack = _validPack();
      final dir = await _buildFixtureContentDir(
        pack,
        sidecarOverride: {
          'rive/collectibles/sat.riv': const {
            'inputs': ['idle', 'celebrate'],
          },
        },
      );

      final result = await buildPack(contentDir: dir.path, levels: [_level1]);

      expect(result.success, isFalse);
      expect(result.errors.any((e) => e.stage == 'riveInputs'), isTrue);
    });
  });

  group('buildPack (negative, accept 11: GraphemeSound content validation wiring)', () {
    test('a GraphemeSound with a phonemeId outside the 44-phoneme set fails the build', () async {
      final pack = _validPack(graphemeSounds: [_validGraphemeSound(phonemeIds: const ['NOT-REAL'])]);
      final dir = await _buildFixtureContentDir(pack);

      final result = await buildPack(contentDir: dir.path, levels: [_level1]);

      expect(result.success, isFalse);
      expect(
        result.errors.any((e) => e.stage == 'graphemeSound' && e.entityId == 'grapheme.s'),
        isTrue,
      );
    });
  });

  group('buildPack (positive, accept 9: starter composition is warn-only)', () {
    test('a declared starter composition lacking coverage warns but does not fail the build', () async {
      final pack = _validPack();
      final dir = await _buildFixtureContentDir(pack);

      final result = await buildPack(
        contentDir: dir.path,
        levels: [_level1],
        starterCompositionLevelIds: const ['level.1', 'level.5', 'level.10'],
      );

      expect(result.success, isTrue);
      expect(result.compositionWarnings.map((w) => w.startingLevelId).toSet(), {'level.5', 'level.10'});
    });
  });

  group('computeManifestChecksum / verifyManifestChecksum (positive+negative, accept 10, A-15)', () {
    test('identical manifest content produces identical checksums (determinism)', () {
      final json1 = _validPack().toJson()..['checksum'] = '';
      final json2 = _validPack().toJson()..['checksum'] = '';
      expect(computeManifestChecksum(json1), computeManifestChecksum(json2));
    });

    test('changing one field of the manifest changes the checksum (tamper detection)', () {
      final json = _validPack().toJson()..['checksum'] = '';
      final checksum1 = computeManifestChecksum(json);

      final tampered = jsonDecode(jsonEncode(json)) as Map<String, dynamic>;
      (tampered['stories'] as List).cast<Map<String, dynamic>>().first['title'] = 'Sat!';
      final checksum2 = computeManifestChecksum(tampered);

      expect(checksum2, isNot(equals(checksum1)));
    });

    test('checksum equals SHA-256 (crypto package) of the checksum-blanked manifest JSON text', () {
      final json = _validPack().toJson()..['checksum'] = '';
      final expected = sha256.convert(utf8.encode(jsonEncode(json))).toString();
      expect(computeManifestChecksum(json), expected);
    });

    test('verifyManifestChecksum is true when signed correctly and false after tampering a byte', () {
      final json = _validPack().toJson()..['checksum'] = '';
      final checksum = computeManifestChecksum(json);
      final signed = {...json, 'checksum': checksum};
      expect(verifyManifestChecksum(signed), isTrue);

      final tampered = {...signed, 'version': '1.0.1'};
      expect(verifyManifestChecksum(tampered), isFalse);
    });
  });
}

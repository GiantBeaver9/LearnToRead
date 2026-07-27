// Pins Unit 14 (Tongue-twister boosters) pack-build behavior (PRD §8 Unit 14
// pinned: "pack build requires the narration file and targetPhonemeId";
// accept: "Pack validation: twister without narration audio or target
// phoneme fails build; decodability linter skips twisters"; ticket
// pack-build-cli accept entry 8). This suite is authored before the
// implementation exists, so it is EXPECTED to fail to compile until
// lib/pipeline/pack_builder.dart is written (this file wires the same
// `buildPack` pinned in pack_builder_test.dart -- see that file for the full
// PackBuildResult/PackBuildError shape and content-directory contract this
// suite relies on).
//
// This suite additionally exercises the twister-specific rules at the
// domain/decodability-linter layer directly (validatePackManifest +
// lintTwister, both already implemented by the merged domain-models /
// decodability-linter dependencies) to pin the exact contract pack_builder's
// twister wiring must preserve:
//  - required-field enforcement (narrationAudioRef, targetPhonemeId) is
//    schema-level (validatePackManifest's existing _validateTwister), not a
//    bespoke twister-only code path;
//  - decodability exemption is total: lintTwister always returns `const []`
//    for a TongueTwister, regardless of its words' graphemes.
// Import of pack_builder.dart alongside these already-green lower-layer
// imports is why this whole file fails to compile pre-implementation.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/pack_manifest.dart';
import 'package:learn_to_read/pipeline/decodability_linter.dart';
import 'package:learn_to_read/pipeline/loudness_check.dart';
import 'package:learn_to_read/pipeline/pack_builder.dart';
import 'package:path/path.dart' as p;

// ---------------------------------------------------------------------------
// Fixtures (file-local; see pack_builder_test.dart for the same shapes used
// with the same rationale).
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

Uint8List _sineWavBytes({double amplitude = 0.3, double frequencyHz = 997, double durationSeconds = 1.0, int sampleRate = 44100}) {
  final n = (sampleRate * durationSeconds).round();
  final samples = Int16List(n);
  for (var i = 0; i < n; i++) {
    final t = i / sampleRate;
    final v = amplitude * math.sin(2 * math.pi * frequencyHz * t);
    samples[i] = (v * 32767).round().clamp(-32768, 32767);
  }
  return _pcm16MonoWav(samples, sampleRate: sampleRate);
}

Uint8List _goodAudioBytes() => normalizeToTargetLoudness(_sineWavBytes(), targetLufs: -16.0);

final _level1 = Level(
  id: 'level.1',
  ordinal: 1,
  format: LevelFormat.sentence,
  vocabEnabled: false,
  newSkills: [
    PhonicsSkill(id: 'skill.1', name: 'starter', sequenceOrder: 1, introducesGraphemes: const ['s', 'a', 't']),
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

/// An out-of-level word (needs 'sh'/'i' graphemes level.1 never introduces)
/// -- used to prove decodability exemption for twisters, not to trigger a
/// finding.
WordToken _wordShip() => WordToken(
      text: 'ship',
      graphemePhonemeMap: const [
        (graphemes: 'sh', phonemeId: 'SH'),
        (graphemes: 'i', phonemeId: 'IH'),
        (graphemes: 'p', phonemeId: 'P'),
      ],
      pronunciationAudioRef: 'audio/words/ship.wav',
    );

Story _validStory() => Story(
      id: 'story.1',
      levelId: 'level.1',
      title: 'Sat',
      pages: [
        Page(sentences: [
          Sentence(words: [_wordSat(), _wordSat(), _wordSat()], narrationAudioRef: 'audio/narration/story.1.wav'),
        ]),
      ],
      riveAnimationRef: 'rive/story.1.riv',
      celebrationAudioRef: 'audio/celebration/story.1.wav',
      collectibleRef: 'collectible.story.1',
      skillsExercised: const [],
      packId: 'pack.fixture',
      contentVersion: '1',
    );

Collectible _validCollectible() => Collectible(
      id: 'collectible.story.1',
      storyId: 'story.1',
      riveRef: 'rive/collectibles/sat.riv',
      sceneSlot: 'shelf.1',
    );

StoryPack _packWithTwister(TongueTwister twister) => StoryPack(
      id: 'pack.fixture',
      version: '1.0.0',
      minAppVersion: '1.0.0',
      stories: [_validStory()],
      twisters: [twister],
      vocabCards: const [],
      collectibles: [_validCollectible()],
      graphemeSounds: const [],
      assetRefs: const [],
      checksum: '',
    );

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

Future<Directory> _buildFixtureContentDir(StoryPack pack, {Map<String, dynamic>? manifestJsonOverride}) async {
  final dir = Directory.systemTemp.createTempSync('twister_validation_test_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  final manifestJson = manifestJsonOverride ?? pack.toJson();
  await File(p.join(dir.path, 'manifest.json')).writeAsString(jsonEncode(manifestJson));

  for (final ref in _collectAudioRefs(pack)) {
    final f = File(p.join(dir.path, ref));
    await f.parent.create(recursive: true);
    await f.writeAsBytes(_goodAudioBytes());
  }

  for (final riveRef in _collectRiveRefs(pack)) {
    final f = File(p.join(dir.path, '$riveRef.inputs.json'));
    await f.parent.create(recursive: true);
    await f.writeAsString(
      jsonEncode(const {
        'inputs': ['idle', 'celebrate', 'collect'],
      }),
    );
  }

  return dir;
}

void main() {
  // ---------------------------------------------------------------------
  // Domain-layer contract this ticket's twister wiring relies on (already
  // implemented by merged deps -- pinned here as the base the pack-builder
  // wiring tests below must not regress).
  // ---------------------------------------------------------------------
  group('domain contract: required twister fields (schema layer, accept 8)', () {
    test('validatePackManifest rejects a twister missing narrationAudioRef', () {
      final json = _packWithTwister(
        TongueTwister(
          id: 'twister.1',
          levelId: 'level.1',
          words: [_wordSat()],
          targetPhonemeId: 'S',
          narrationAudioRef: 'audio/twisters/1.wav',
          packId: 'pack.fixture',
        ),
      ).toJson();
      (json['twisters'] as List).cast<Map<String, dynamic>>().first.remove('narrationAudioRef');

      final result = validatePackManifest(json, levelsById: {'level.1': _level1});

      expect(result.isValid, isFalse);
      expect(
        result.errors.any(
          (e) => e.field == 'narrationAudioRef' && e.entityType == 'twister' && e.entityId == 'twister.1',
        ),
        isTrue,
      );
    });

    test('validatePackManifest rejects a twister missing targetPhonemeId', () {
      final json = _packWithTwister(
        TongueTwister(
          id: 'twister.1',
          levelId: 'level.1',
          words: [_wordSat()],
          targetPhonemeId: 'S',
          narrationAudioRef: 'audio/twisters/1.wav',
          packId: 'pack.fixture',
        ),
      ).toJson();
      (json['twisters'] as List).cast<Map<String, dynamic>>().first.remove('targetPhonemeId');

      final result = validatePackManifest(json, levelsById: {'level.1': _level1});

      expect(result.isValid, isFalse);
      expect(
        result.errors.any(
          (e) => e.field == 'targetPhonemeId' && e.entityType == 'twister' && e.entityId == 'twister.1',
        ),
        isTrue,
      );
    });
  });

  group('domain contract: decodability exemption (lintTwister, accept 8)', () {
    test('lintTwister produces zero findings for a twister full of out-of-level words', () {
      final twister = TongueTwister(
        id: 'twister.1',
        levelId: 'level.1',
        words: [_wordShip(), _wordShip()],
        targetPhonemeId: 'SH',
        narrationAudioRef: 'audio/twisters/1.wav',
        packId: 'pack.fixture',
      );
      final findings = lintTwister(twister, levels: [_level1], heartWordsByLevelId: const {});
      expect(findings, isEmpty);
    });
  });

  // ---------------------------------------------------------------------
  // pack_builder.dart wiring (the actual new implementation this file's
  // import of pack_builder.dart is red for).
  // ---------------------------------------------------------------------
  group('buildPack (negative, accept 8: twister missing narrationAudioRef fails build)', () {
    test('a twister missing narrationAudioRef fails, naming the field and twister id', () async {
      final pack = _packWithTwister(
        TongueTwister(
          id: 'twister.1',
          levelId: 'level.1',
          words: [_wordSat()],
          targetPhonemeId: 'S',
          narrationAudioRef: 'audio/twisters/1.wav',
          packId: 'pack.fixture',
        ),
      );
      final manifestJson = pack.toJson();
      (manifestJson['twisters'] as List).cast<Map<String, dynamic>>().first.remove('narrationAudioRef');
      final dir = await _buildFixtureContentDir(pack, manifestJsonOverride: manifestJson);

      final result = await buildPack(contentDir: dir.path, levels: [_level1]);

      expect(result.success, isFalse);
      expect(
        result.errors.any(
          (e) => e.field == 'narrationAudioRef' && e.entityType == 'twister' && e.entityId == 'twister.1',
        ),
        isTrue,
      );
    });
  });

  group('buildPack (negative, accept 8: twister missing targetPhonemeId fails build)', () {
    test('a twister missing targetPhonemeId fails, naming the field and twister id', () async {
      final pack = _packWithTwister(
        TongueTwister(
          id: 'twister.1',
          levelId: 'level.1',
          words: [_wordSat()],
          targetPhonemeId: 'S',
          narrationAudioRef: 'audio/twisters/1.wav',
          packId: 'pack.fixture',
        ),
      );
      final manifestJson = pack.toJson();
      (manifestJson['twisters'] as List).cast<Map<String, dynamic>>().first.remove('targetPhonemeId');
      final dir = await _buildFixtureContentDir(pack, manifestJsonOverride: manifestJson);

      final result = await buildPack(contentDir: dir.path, levels: [_level1]);

      expect(result.success, isFalse);
      expect(
        result.errors.any(
          (e) => e.field == 'targetPhonemeId' && e.entityType == 'twister' && e.entityId == 'twister.1',
        ),
        isTrue,
      );
    });
  });

  group('buildPack (positive, accept 8: decodability linter skips twisters end-to-end)', () {
    test('a twister full of out-of-level words does not fail the build', () async {
      final pack = _packWithTwister(
        TongueTwister(
          id: 'twister.1',
          levelId: 'level.1',
          words: [_wordShip(), _wordShip(), _wordShip()],
          targetPhonemeId: 'SH',
          narrationAudioRef: 'audio/twisters/1.wav',
          packId: 'pack.fixture',
        ),
      );
      final dir = await _buildFixtureContentDir(pack);

      final result = await buildPack(contentDir: dir.path, levels: [_level1]);

      expect(result.success, isTrue);
      expect(result.errors.where((e) => e.stage == 'decodability' && e.entityId == 'twister.1'), isEmpty);
    });
  });

  group('buildPack (positive, accept 8: a fully valid twister builds)', () {
    test('a twister with narrationAudioRef and targetPhonemeId present builds successfully', () async {
      final pack = _packWithTwister(
        TongueTwister(
          id: 'twister.1',
          levelId: 'level.1',
          words: [_wordSat()],
          targetPhonemeId: 'S',
          narrationAudioRef: 'audio/twisters/1.wav',
          packId: 'pack.fixture',
        ),
      );
      final dir = await _buildFixtureContentDir(pack);

      final result = await buildPack(contentDir: dir.path, levels: [_level1]);

      expect(result.success, isTrue);
      expect(result.pack!.twisters.single.targetPhonemeId, 'S');
    });
  });
}

// Pins the API of lib/domain/models/pack_manifest.dart (PRD §5 StoryPack,
// §8 Unit 3 pack format, §9 A-11/A-15, ticket domain-models accept entries
// 3-6). Fails to compile until pack_manifest.dart exists with exactly these
// shapes. This file imports content_models.dart too, since manifests are
// built from those types.
//
// Pinned API surface:
//   class StoryPack {
//     id, version, minAppVersion,
//     stories: List<Story>, twisters: List<TongueTwister>,
//     vocabCards: List<VocabCard>, collectibles: List<Collectible>,
//     graphemeSounds: List<GraphemeSound>, assetRefs: List<String>,
//     checksum,
//     Map<String, dynamic> toJson(),
//     factory StoryPack.fromJson(Map<String, dynamic> json), // trusts
//       well-formed input; validation happens separately (below), so
//       fromJson is only exercised here on output of toJson().
//   }
//   NOTE ON SCOPE: Phoneme is a fixed 44-entry set shipped in the app
//   binary (§5: "fixed set shipped in binary") and PhonicsSkill/Level are
//   the scope-&-sequence, loaded from separate data files by the
//   phonics-engine unit (§8 Unit 2: "stored as data not code") -- neither
//   travels inside a StoryPack manifest. Everything else authored per-story
//   (Story, TongueTwister, VocabCard, Collectible, GraphemeSound) does.
//
//   class PackManifestValidationError {
//     field: String, entityType: String, entityId: String, message: String
//   }
//   class PackManifestValidationResult {
//     isValid: bool, errors: List<PackManifestValidationError>
//   }
//   PackManifestValidationResult validatePackManifest(
//     Map<String, dynamic> manifestJson, {
//     required Map<String, Level> levelsById,
//   })
//
// WHY VALIDATION OPERATES ON RAW JSON, NOT ON A CONSTRUCTED StoryPack:
// Story.riveAnimationRef, TongueTwister.targetPhonemeId/narrationAudioRef
// etc. are non-nullable `required` fields on the Dart types -- you cannot
// construct an in-memory Story that is "missing" one, by design (that IS
// the immutability/shape guarantee content_models_test.dart pins). So the
// "manifest missing a required field" scenario the ticket requires can only
// be simulated realistically at the raw-JSON layer (as if a pack's JSON
// file were hand-edited or corrupted before being trusted). validatePack
// Manifest is therefore the gate a pack must pass BEFORE StoryPack.fromJson
// is ever called on it in the real pipeline (see pack-build-cli, which
// composes this validator with its own asset/loudness/decodability checks).

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/pack_manifest.dart';

WordToken _word(String text, {String? vocabCardId}) => WordToken(
      text: text,
      graphemePhonemeMap: [(graphemes: text, phonemeId: kEnglishPhonemeIds.first)],
      pronunciationAudioRef: 'audio/words/$text.wav',
      vocabCardId: vocabCardId,
    );

Level _sentenceLevel({String id = 'level.1', bool? narrationEnabled}) => Level(
      id: id,
      ordinal: 1,
      newSkills: const [],
      format: LevelFormat.sentence,
      vocabEnabled: false,
      narrationEnabled: narrationEnabled,
    );

Level _multiLevel({String id = 'level.5', bool? narrationEnabled}) => Level(
      id: id,
      ordinal: 5,
      newSkills: const [],
      format: LevelFormat.multiSentence,
      vocabEnabled: true,
      narrationEnabled: narrationEnabled,
    );

Story _sentenceFormatStory({
  String id = 'story.sentence.1',
  String levelId = 'level.1',
  String? narrationAudioRef = 'audio/narration/story.sentence.1.wav',
  List<Page>? pagesOverride,
  String riveAnimationRef = 'rive/story.sentence.1.riv',
  String packId = 'pack.starter',
}) =>
    Story(
      id: id,
      levelId: levelId,
      title: 'The Cat',
      pages: pagesOverride ??
          [
            Page(sentences: [Sentence(words: [_word('cat')], narrationAudioRef: narrationAudioRef)]),
          ],
      riveAnimationRef: riveAnimationRef,
      celebrationAudioRef: 'audio/celebration/$id.wav',
      collectibleRef: 'collectible.1',
      skillsExercised: const [],
      packId: packId,
      contentVersion: '1',
    );

TongueTwister _twister({
  String id = 'twister.1',
  String levelId = 'level.1',
  String targetPhonemeId = '',
  String narrationAudioRef = 'audio/twisters/1.wav',
}) =>
    TongueTwister(
      id: id,
      levelId: levelId,
      words: [_word('she'), _word('sells')],
      targetPhonemeId: targetPhonemeId.isEmpty ? kEnglishPhonemeIds.first : targetPhonemeId,
      narrationAudioRef: narrationAudioRef,
      packId: 'pack.starter',
    );

VocabCard _vocabCard({String id = 'vocab.cat'}) => VocabCard(
      id: id,
      word: 'cat',
      definitionText: 'A small furry pet that says meow.',
      definitionAudioRef: 'audio/defs/cat.wav',
      illustrationRef: 'art/cat.png',
    );

Collectible _collectible({String id = 'collectible.1'}) => Collectible(
      id: id,
      storyId: 'story.sentence.1',
      riveRef: 'rive/collectibles/cat.riv',
      sceneSlot: 'shelf.1',
    );

GraphemeSound _graphemeSound({String id = 'grapheme.sh'}) => GraphemeSound(
      id: id,
      grapheme: 'sh',
      phonemeIds: const ['SH'],
      introducedAtLevelId: 'level.1',
      exampleWords: const [
        (wordText: 'ship', pronunciationAudioRef: 'audio/words/ship.wav', minLevelId: 'level.1'),
      ],
    );

StoryPack _pack({
  String id = 'pack.starter',
  List<Story>? stories,
  List<TongueTwister>? twisters,
  List<VocabCard>? vocabCards,
  List<Collectible>? collectibles,
  List<GraphemeSound>? graphemeSounds,
  List<String>? assetRefs,
  String checksum = 'deadbeefcafebabe',
}) =>
    StoryPack(
      id: id,
      version: '1.0.0',
      minAppVersion: '1.0.0',
      stories: stories ?? [_sentenceFormatStory()],
      twisters: twisters ?? [_twister()],
      vocabCards: vocabCards ?? [_vocabCard()],
      collectibles: collectibles ?? [_collectible()],
      graphemeSounds: graphemeSounds ?? [_graphemeSound()],
      assetRefs: assetRefs ?? const ['audio/words/cat.wav', 'rive/story.sentence.1.riv'],
      checksum: checksum,
    );

/// Round-trips a StoryPack through actual JSON text (not just the raw Dart
/// Map from toJson()), producing a deeply-mutable Map<String, dynamic> --
/// exactly what a real manifest.json file loads into.
Map<String, dynamic> _asJson(StoryPack pack) => jsonDecode(jsonEncode(pack.toJson())) as Map<String, dynamic>;

PackManifestValidationError? _findError(
  PackManifestValidationResult result, {
  required String field,
  required String entityType,
  String? entityId,
}) {
  for (final e in result.errors) {
    if (e.field == field && e.entityType == entityType && (entityId == null || e.entityId == entityId)) {
      return e;
    }
  }
  return null;
}

void main() {
  group('StoryPack (positive)', () {
    test('constructs with exactly the pinned top-level fields', () {
      final pack = _pack();
      expect(pack.id, 'pack.starter');
      expect(pack.version, '1.0.0');
      expect(pack.minAppVersion, '1.0.0');
      expect(pack.stories, hasLength(1));
      expect(pack.twisters, hasLength(1));
      expect(pack.vocabCards, hasLength(1));
      expect(pack.collectibles, hasLength(1));
      expect(pack.graphemeSounds, hasLength(1));
      expect(pack.checksum, 'deadbeefcafebabe');
    });
  });

  group('Pack manifest JSON round-trip (positive, accept entry 3)', () {
    test('a fixture StoryPack serializes and deserializes to an equal object', () {
      final pack = _pack();
      final decoded = StoryPack.fromJson(pack.toJson());
      expect(decoded, equals(pack));
    });

    test('round-trip survives real JSON text encode/decode (not just the raw Map)', () {
      final pack = _pack();
      final jsonText = jsonEncode(pack.toJson());
      final decoded = StoryPack.fromJson(jsonDecode(jsonText) as Map<String, dynamic>);
      expect(decoded, equals(pack));
    });

    test('every content model authored per-story is representable in the manifest', () {
      final pack = _pack();
      final json = _asJson(pack);
      expect(json['stories'], isA<List>());
      expect(json['twisters'], isA<List>());
      expect(json['vocabCards'], isA<List>());
      expect(json['collectibles'], isA<List>());
      expect(json['graphemeSounds'], isA<List>());
      expect(json['assetRefs'], isA<List>());

      final decoded = StoryPack.fromJson(json);
      expect(decoded.stories.single.title, 'The Cat');
      expect(decoded.twisters.single.targetPhonemeId, kEnglishPhonemeIds.first);
      expect(decoded.vocabCards.single.word, 'cat');
      expect(decoded.collectibles.single.sceneSlot, 'shelf.1');
      expect(decoded.graphemeSounds.single.grapheme, 'sh');
    });

    test('nested Page/Sentence/WordToken structure round-trips exactly, including graphemePhonemeMap order', () {
      final pack = _pack(
        stories: [
          _sentenceFormatStory(
            pagesOverride: [
              Page(sentences: [
                Sentence(
                  words: [
                    WordToken(
                      text: 'ship',
                      graphemePhonemeMap: const [
                        (graphemes: 'sh', phonemeId: 'SH'),
                        (graphemes: 'i', phonemeId: 'IH'),
                        (graphemes: 'p', phonemeId: 'P'),
                      ],
                      pronunciationAudioRef: 'audio/words/ship.wav',
                    ),
                  ],
                  narrationAudioRef: 'audio/narration/story.sentence.1.wav',
                ),
              ]),
            ],
          ),
        ],
      );
      final decoded = StoryPack.fromJson(pack.toJson());
      final map = decoded.stories.single.pages.single.sentences.single.words.single.graphemePhonemeMap;
      expect(map.map((e) => e.graphemes).toList(), ['sh', 'i', 'p']);
      expect(map.map((e) => e.phonemeId).toList(), ['SH', 'IH', 'P']);
    });

    test('audio refs serialize as plain JSON strings, not nested objects (source-agnostic, opaque)', () {
      final json = _asJson(_pack());
      final storyJson = (json['stories'] as List).first as Map<String, dynamic>;
      expect(storyJson['riveAnimationRef'], isA<String>());
      final twisterJson = (json['twisters'] as List).first as Map<String, dynamic>;
      expect(twisterJson['narrationAudioRef'], isA<String>());
    });
  });

  group('validatePackManifest (positive baseline)', () {
    test('a well-formed manifest with matching level context is valid with no errors', () {
      final levelsById = {'level.1': _sentenceLevel()};
      final result = validatePackManifest(_asJson(_pack()), levelsById: levelsById);
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('an empty manifest (no stories/twisters/cards/collectibles/sounds) is valid if required top-level fields are present', () {
      final pack = StoryPack(
        id: 'pack.empty',
        version: '1.0.0',
        minAppVersion: '1.0.0',
        stories: const [],
        twisters: const [],
        vocabCards: const [],
        collectibles: const [],
        graphemeSounds: const [],
        assetRefs: const [],
        checksum: 'abc123',
      );
      final result = validatePackManifest(_asJson(pack), levelsById: const {});
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });
  });

  group('validatePackManifest (negative: missing required Story fields, accept entry 4)', () {
    test('Story missing riveAnimationRef fails with a per-field error naming the field and story id', () {
      final json = _asJson(_pack());
      final storyJson = (json['stories'] as List).first as Map<String, dynamic>;
      storyJson.remove('riveAnimationRef');

      final result = validatePackManifest(json, levelsById: {'level.1': _sentenceLevel()});

      expect(result.isValid, isFalse);
      final error = _findError(result, field: 'riveAnimationRef', entityType: 'story', entityId: 'story.sentence.1');
      expect(error, isNotNull);
      expect(error!.message, isNotEmpty);
    });

    test('Story missing packId fails with a per-field error naming the field and story id', () {
      final json = _asJson(_pack());
      final storyJson = (json['stories'] as List).first as Map<String, dynamic>;
      storyJson.remove('packId');

      final result = validatePackManifest(json, levelsById: {'level.1': _sentenceLevel()});

      expect(result.isValid, isFalse);
      expect(_findError(result, field: 'packId', entityType: 'story', entityId: 'story.sentence.1'), isNotNull);
    });

    test('Story referencing an unknown levelId fails with a per-field error naming levelId and story id', () {
      final json = _asJson(_pack(stories: [_sentenceFormatStory(levelId: 'level.does-not-exist')]));

      final result = validatePackManifest(json, levelsById: {'level.1': _sentenceLevel()});

      expect(result.isValid, isFalse);
      expect(
        _findError(result, field: 'levelId', entityType: 'story', entityId: 'story.sentence.1'),
        isNotNull,
      );
    });
  });

  group('validatePackManifest (negative: missing required TongueTwister fields, accept entry 4)', () {
    test('TongueTwister missing targetPhonemeId fails, naming the field and twister id', () {
      final json = _asJson(_pack());
      final twisterJson = (json['twisters'] as List).first as Map<String, dynamic>;
      twisterJson.remove('targetPhonemeId');

      final result = validatePackManifest(json, levelsById: {'level.1': _sentenceLevel()});

      expect(result.isValid, isFalse);
      expect(_findError(result, field: 'targetPhonemeId', entityType: 'twister', entityId: 'twister.1'), isNotNull);
    });

    test('TongueTwister missing narrationAudioRef fails, naming the field and twister id', () {
      final json = _asJson(_pack());
      final twisterJson = (json['twisters'] as List).first as Map<String, dynamic>;
      twisterJson.remove('narrationAudioRef');

      final result = validatePackManifest(json, levelsById: {'level.1': _sentenceLevel()});

      expect(result.isValid, isFalse);
      expect(_findError(result, field: 'narrationAudioRef', entityType: 'twister', entityId: 'twister.1'), isNotNull);
    });
  });

  group('validatePackManifest (negative: missing required top-level pack field)', () {
    test('StoryPack missing checksum fails, naming the field and the pack id', () {
      final json = _asJson(_pack());
      json.remove('checksum');

      final result = validatePackManifest(json, levelsById: {'level.1': _sentenceLevel()});

      expect(result.isValid, isFalse);
      expect(_findError(result, field: 'checksum', entityType: 'pack', entityId: 'pack.starter'), isNotNull);
    });
  });

  group('validatePackManifest (negative: missing required GraphemeSound field)', () {
    test('GraphemeSound missing grapheme fails, naming the field and its id', () {
      final json = _asJson(_pack());
      final soundJson = (json['graphemeSounds'] as List).first as Map<String, dynamic>;
      soundJson.remove('grapheme');

      final result = validatePackManifest(json, levelsById: {'level.1': _sentenceLevel()});

      expect(result.isValid, isFalse);
      expect(_findError(result, field: 'grapheme', entityType: 'graphemeSound', entityId: 'grapheme.sh'), isNotNull);
    });
  });

  group('A-11 narration requirement (negative: sentence-format story, accept entry 4)', () {
    test('a sentence at a sentence-format level missing narrationAudioRef fails, naming the story', () {
      final pack = _pack(
        stories: [_sentenceFormatStory(narrationAudioRef: null)],
      );
      final result = validatePackManifest(_asJson(pack), levelsById: {'level.1': _sentenceLevel()});

      expect(result.isValid, isFalse);
      expect(
        _findError(result, field: 'narrationAudioRef', entityType: 'story', entityId: 'story.sentence.1'),
        isNotNull,
      );
    });
  });

  group('A-11 narration requirement (positive: scoped correctly)', () {
    test('a multiSentence-format story with narrationEnabled=false may omit narrationAudioRef', () {
      final pack = _pack(
        stories: [
          _sentenceFormatStory(levelId: 'level.5', narrationAudioRef: null),
        ],
      );
      final levelsById = {'level.5': _multiLevel(narrationEnabled: false)};
      final result = validatePackManifest(_asJson(pack), levelsById: levelsById);
      expect(result.isValid, isTrue);
    });

    test('the A-11 hard requirement is scoped to sentence-format stories only, even if a higher level opts narrationEnabled in', () {
      // Level.narrationEnabled=true on a multiSentence level is a UI opt-in
      // signal for Unit 5 (per §5), not a pack-build hard requirement --
      // A-11 only pins the requirement for sentence-format stories.
      final pack = _pack(
        stories: [_sentenceFormatStory(levelId: 'level.5', narrationAudioRef: null)],
      );
      final levelsById = {'level.5': _multiLevel(narrationEnabled: true)};
      final result = validatePackManifest(_asJson(pack), levelsById: levelsById);
      expect(result.isValid, isTrue);
    });
  });

  group('Sentence-format story invariant (negative, accept entry 5)', () {
    test('a sentence-format story with two pages fails validation', () {
      final pack = _pack(
        stories: [
          _sentenceFormatStory(
            pagesOverride: [
              Page(sentences: [Sentence(words: [_word('cat')], narrationAudioRef: 'a')]),
              Page(sentences: [Sentence(words: [_word('sat')], narrationAudioRef: 'b')]),
            ],
          ),
        ],
      );
      final result = validatePackManifest(_asJson(pack), levelsById: {'level.1': _sentenceLevel()});

      expect(result.isValid, isFalse);
      expect(_findError(result, field: 'pages', entityType: 'story', entityId: 'story.sentence.1'), isNotNull);
    });

    test('a sentence-format story with one page but two sentences fails validation', () {
      final pack = _pack(
        stories: [
          _sentenceFormatStory(
            pagesOverride: [
              Page(sentences: [
                Sentence(words: [_word('cat')], narrationAudioRef: 'a'),
                Sentence(words: [_word('sat')], narrationAudioRef: 'b'),
              ]),
            ],
          ),
        ],
      );
      final result = validatePackManifest(_asJson(pack), levelsById: {'level.1': _sentenceLevel()});

      expect(result.isValid, isFalse);
      expect(_findError(result, field: 'sentences', entityType: 'story', entityId: 'story.sentence.1'), isNotNull);
    });
  });

  group('Sentence-format story invariant (positive)', () {
    test('a sentence-format story with exactly one page and one sentence passes', () {
      final result = validatePackManifest(_asJson(_pack()), levelsById: {'level.1': _sentenceLevel()});
      expect(result.isValid, isTrue);
    });

    test('multiSentence/paragraph stories are exempt from the one-page-one-sentence invariant', () {
      final pack = _pack(
        stories: [
          _sentenceFormatStory(
            levelId: 'level.5',
            narrationAudioRef: null,
            pagesOverride: [
              Page(sentences: [Sentence(words: [_word('cat')]), Sentence(words: [_word('sat')])]),
              Page(sentences: [Sentence(words: [_word('mat')])]),
            ],
          ),
        ],
      );
      final result = validatePackManifest(_asJson(pack), levelsById: {'level.5': _multiLevel(narrationEnabled: false)});
      expect(result.isValid, isTrue);
    });
  });

  group('narrationEnabled default rule enforced by validation (negative, accept entry 6)', () {
    test('a sentence-format Level with narrationEnabled=false in the level context fails validation', () {
      final levelsById = {'level.1': _sentenceLevel(narrationEnabled: false)};
      // Story itself supplies narrationAudioRef so it would otherwise pass;
      // the failure is purely the Level-level rule violation.
      final result = validatePackManifest(_asJson(_pack()), levelsById: levelsById);

      expect(result.isValid, isFalse);
      expect(_findError(result, field: 'narrationEnabled', entityType: 'level', entityId: 'level.1'), isNotNull);
    });
  });

  group('narrationEnabled default rule enforced by validation (positive)', () {
    test('a sentence-format Level with narrationEnabled=true (the default) passes', () {
      final levelsById = {'level.1': _sentenceLevel(narrationEnabled: true)};
      final result = validatePackManifest(_asJson(_pack()), levelsById: levelsById);
      expect(result.isValid, isTrue);
    });

    test('a multiSentence Level may opt narrationEnabled in without failing validation', () {
      final pack = _pack(stories: [_sentenceFormatStory(levelId: 'level.5')]);
      final levelsById = {'level.5': _multiLevel(narrationEnabled: true)};
      final result = validatePackManifest(_asJson(pack), levelsById: levelsById);
      expect(result.isValid, isTrue);
    });
  });

  group('validatePackManifest (edge: aggregates multiple independent errors, does not fail-fast)', () {
    test('two unrelated missing fields both appear in the result', () {
      final json = _asJson(_pack());
      final storyJson = (json['stories'] as List).first as Map<String, dynamic>;
      storyJson.remove('riveAnimationRef');
      final twisterJson = (json['twisters'] as List).first as Map<String, dynamic>;
      twisterJson.remove('targetPhonemeId');

      final result = validatePackManifest(json, levelsById: {'level.1': _sentenceLevel()});

      expect(result.isValid, isFalse);
      expect(result.errors.length, greaterThanOrEqualTo(2));
      expect(_findError(result, field: 'riveAnimationRef', entityType: 'story', entityId: 'story.sentence.1'), isNotNull);
      expect(_findError(result, field: 'targetPhonemeId', entityType: 'twister', entityId: 'twister.1'), isNotNull);
    });
  });

  group('PackManifestValidationError / Result (positive: shape sanity)', () {
    test('exposes exactly field, entityType, entityId, message', () {
      const error = PackManifestValidationError(
        field: 'riveAnimationRef',
        entityType: 'story',
        entityId: 'story.1',
        message: 'riveAnimationRef is required',
      );
      expect(error.field, 'riveAnimationRef');
      expect(error.entityType, 'story');
      expect(error.entityId, 'story.1');
      expect(error.message, 'riveAnimationRef is required');
    });

    test('a valid result carries isValid=true and an empty errors list', () {
      const result = PackManifestValidationResult(isValid: true, errors: []);
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });
  });
}

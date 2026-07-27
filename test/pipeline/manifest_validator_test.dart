// Pins the API of lib/pipeline/manifest_validator.dart (PRD §8 Unit 3 pack
// build accept entries 2 & 4; §9 A-9 starter-pack composition; §8 Unit 15 /
// §5 GraphemeSound content validation; ticket pack-build-cli accept entries
// 2, 9, 11). This suite is authored before the implementation exists, so it
// is EXPECTED to fail to compile until manifest_validator.dart is written
// with exactly the shapes exercised below.
//
// Pinned API surface this suite requires:
//
//   // Pipeline-level schema validation: a thin pass-through to domain's
//   // `validatePackManifest` (lib/domain/models/pack_manifest.dart), reusing
//   // its exact `PackManifestValidationResult`/`PackManifestValidationError`
//   // types rather than redefining a parallel shape (pack-build-cli composes
//   // this validator with its own asset/loudness/decodability/rive checks --
//   // it does not reimplement schema validation).
//   PackManifestValidationResult validateManifest(
//     Map<String, dynamic> manifestJson, {
//     required Map<String, Level> levelsById,
//   });
//
//   // A-9: warn-only (never fails the build) -- the ~8-story starter pack
//   // must include at least one story at each of the three age-band
//   // starting levels (level 1, the first multiSentence level, the first
//   // paragraph level). `startingLevelIds` is the composition spec the
//   // builder is handed; one warning is emitted per starting level with zero
//   // matching stories.
//   class StarterPackCompositionWarning {
//     final String startingLevelId;
//     final String message;
//   }
//   List<StarterPackCompositionWarning> validateStarterPackComposition({
//     required List<Story> stories,
//     required List<String> startingLevelIds,
//   });
//
//   // Unit 15 / §5 GraphemeSound content validation: every GraphemeSound's
//   // phonemeIds must exist in the fixed 44-phoneme set
//   // (`kEnglishPhonemeIds`), introducedAtLevelId must resolve in
//   // `levelsById`, and every exampleWord must have a non-empty wordText, a
//   // pronunciationAudioRef present in `availableAssetRefs`, and a minLevelId
//   // that resolves in `levelsById`. Packs may EXTEND an existing grapheme's
//   // exampleWords -- an extension is validated by the exact same rules as a
//   // base entry (no separate code path), which this suite locks in by
//   // exercising a GraphemeSound shaped like an extension-pack contribution
//   // through the same function.
//   class GraphemeSoundValidationError {
//     final String field;      // 'phonemeIds' | 'introducedAtLevelId' | 'wordText' | 'pronunciationAudioRef' | 'minLevelId'
//     final String entityType; // always 'graphemeSound'
//     final String entityId;   // GraphemeSound.id
//     final String message;
//   }
//   class GraphemeSoundValidationResult {
//     final bool isValid;
//     final List<GraphemeSoundValidationError> errors;
//   }
//   GraphemeSoundValidationResult validateGraphemeSoundInventory(
//     List<GraphemeSound> graphemeSounds, {
//     required Map<String, Level> levelsById,
//     required Set<String> availableAssetRefs,
//   });
//
// Contract this suite locks in (builder-mechanical, since the ticket pins
// behavior, not exact shapes):
//  - validateManifest errors are pixel-identical in field/entityType/entityId
//    to what domain's validatePackManifest would produce for the same input
//    (this suite asserts the delegation, not a reimplementation).
//  - validateGraphemeSoundInventory aggregates every independent problem
//    across the whole inventory rather than failing fast (matches this
//    codebase's PackManifestValidationResult convention).
//  - `availableAssetRefs` membership is exact-string match against
//    `exampleWord.pronunciationAudioRef` -- no path normalization is assumed
//    beyond what the caller already put in the set.

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/pipeline/manifest_validator.dart';

// ---------------------------------------------------------------------------
// Fixtures (file-local per this codebase's existing test-fixture convention).
// ---------------------------------------------------------------------------

WordToken _word(String text) => WordToken(
      text: text,
      graphemePhonemeMap: [(graphemes: text, phonemeId: kEnglishPhonemeIds.first)],
      pronunciationAudioRef: 'audio/words/$text.wav',
    );

Level _sentenceLevel({String id = 'level.1', int ordinal = 1}) => Level(
      id: id,
      ordinal: ordinal,
      newSkills: const [],
      format: LevelFormat.sentence,
      vocabEnabled: false,
    );

Level _multiLevel({String id = 'level.5', int ordinal = 5}) => Level(
      id: id,
      ordinal: ordinal,
      newSkills: const [],
      format: LevelFormat.multiSentence,
      vocabEnabled: true,
    );

Level _paragraphLevel({String id = 'level.10', int ordinal = 10}) => Level(
      id: id,
      ordinal: ordinal,
      newSkills: const [],
      format: LevelFormat.paragraph,
      vocabEnabled: true,
    );

Story _sentenceFormatStory({
  String id = 'story.1',
  String levelId = 'level.1',
  String? narrationAudioRef = 'audio/narration/story.1.wav',
  String riveAnimationRef = 'rive/story.1.riv',
}) =>
    Story(
      id: id,
      levelId: levelId,
      title: 'A Story',
      pages: [
        Page(sentences: [Sentence(words: [_word('sat')], narrationAudioRef: narrationAudioRef)]),
      ],
      riveAnimationRef: riveAnimationRef,
      celebrationAudioRef: 'audio/celebration/$id.wav',
      collectibleRef: 'collectible.$id',
      skillsExercised: const [],
      packId: 'pack.fixture',
      contentVersion: '1',
    );

Map<String, dynamic> _storyJson(Story story, {String? narrationAudioRef = 'audio/narration/x.wav'}) => {
      'id': story.id,
      'levelId': story.levelId,
      'title': story.title,
      'pages': [
        {
          'sentences': [
            {
              'words': [
                {
                  'text': 'sat',
                  'graphemePhonemeMap': [
                    {'graphemes': 'sat', 'phonemeId': kEnglishPhonemeIds.first},
                  ],
                  'pronunciationAudioRef': 'audio/words/sat.wav',
                  'vocabCardId': null,
                },
              ],
              'narrationAudioRef': narrationAudioRef,
            },
          ],
        },
      ],
      'riveAnimationRef': story.riveAnimationRef,
      'celebrationAudioRef': story.celebrationAudioRef,
      'collectibleRef': story.collectibleRef,
      'skillsExercised': const [],
      'packId': story.packId,
      'contentVersion': story.contentVersion,
    };

Map<String, dynamic> _minimalManifestJson({
  required Map<String, dynamic> storyJson,
  bool omitRiveAnimationRef = false,
}) {
  final json = {..._storyJsonBase(), 'stories': [storyJson]};
  if (omitRiveAnimationRef) {
    (json['stories'] as List<Map<String, dynamic>>).first.remove('riveAnimationRef');
  }
  return json;
}

Map<String, dynamic> _storyJsonBase() => {
      'id': 'pack.fixture',
      'version': '1.0.0',
      'minAppVersion': '1.0.0',
      'stories': const [],
      'twisters': const [],
      'vocabCards': const [],
      'collectibles': const [],
      'graphemeSounds': const [],
      'assetRefs': const ['audio/words/sat.wav'],
      'checksum': '',
    };

GraphemeSound _validGraphemeSound({
  String id = 'grapheme.s',
  String grapheme = 's',
  List<String> phonemeIds = const ['S'],
  String introducedAtLevelId = 'level.1',
  List<({String wordText, String pronunciationAudioRef, String minLevelId})> exampleWords = const [
    (wordText: 'sat', pronunciationAudioRef: 'audio/words/sat.wav', minLevelId: 'level.1'),
  ],
}) =>
    GraphemeSound(
      id: id,
      grapheme: grapheme,
      phonemeIds: phonemeIds,
      introducedAtLevelId: introducedAtLevelId,
      exampleWords: exampleWords,
    );

GraphemeSoundValidationError? _findGraphemeError(
  GraphemeSoundValidationResult result, {
  required String field,
  String? entityId,
}) {
  for (final e in result.errors) {
    if (e.field == field && (entityId == null || e.entityId == entityId)) return e;
  }
  return null;
}

void main() {
  // ---------------------------------------------------------------------
  // validateManifest (accept 2 & 4: pipeline-level schema validation
  // delegates to domain's validatePackManifest).
  // ---------------------------------------------------------------------
  group('validateManifest (positive, accept 2)', () {
    test('a well-formed manifest with matching level context is valid', () {
      final story = _sentenceFormatStory();
      final json = _minimalManifestJson(storyJson: _storyJson(story));
      final result = validateManifest(json, levelsById: {'level.1': _sentenceLevel()});
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });
  });

  group('validateManifest (negative, accept 2 & 4: per-field error naming story id + field)', () {
    test('a story missing riveAnimationRef fails, naming the field and story id', () {
      final story = _sentenceFormatStory();
      final json = _minimalManifestJson(storyJson: _storyJson(story), omitRiveAnimationRef: true);
      final result = validateManifest(json, levelsById: {'level.1': _sentenceLevel()});

      expect(result.isValid, isFalse);
      final error = result.errors.firstWhere(
        (e) => e.field == 'riveAnimationRef' && e.entityType == 'story' && e.entityId == 'story.1',
        orElse: () => throw StateError('expected riveAnimationRef error not found'),
      );
      expect(error.message, isNotEmpty);
    });

    test('a sentence-format story missing narrationAudioRef fails (A-11)', () {
      final story = _sentenceFormatStory();
      final json = _minimalManifestJson(storyJson: _storyJson(story, narrationAudioRef: null));
      final result = validateManifest(json, levelsById: {'level.1': _sentenceLevel()});

      expect(result.isValid, isFalse);
      expect(
        result.errors.any(
          (e) => e.field == 'narrationAudioRef' && e.entityType == 'story' && e.entityId == 'story.1',
        ),
        isTrue,
      );
    });
  });

  // ---------------------------------------------------------------------
  // validateStarterPackComposition (A-9, accept 9).
  // ---------------------------------------------------------------------
  group('validateStarterPackComposition (positive, accept 9)', () {
    test('a composition covering all three starting levels produces zero warnings', () {
      final stories = [
        _sentenceFormatStory(id: 's1', levelId: 'level.1'),
        _sentenceFormatStory(id: 's2', levelId: 'level.5'),
        _sentenceFormatStory(id: 's3', levelId: 'level.10'),
      ];
      final warnings = validateStarterPackComposition(
        stories: stories,
        startingLevelIds: ['level.1', 'level.5', 'level.10'],
      );
      expect(warnings, isEmpty);
    });
  });

  group('validateStarterPackComposition (negative, accept 9)', () {
    test('a composition lacking stories at one starting level warns, naming that level', () {
      final stories = [
        _sentenceFormatStory(id: 's1', levelId: 'level.1'),
        _sentenceFormatStory(id: 's2', levelId: 'level.5'),
        // no story at level.10
      ];
      final warnings = validateStarterPackComposition(
        stories: stories,
        startingLevelIds: ['level.1', 'level.5', 'level.10'],
      );
      expect(warnings, hasLength(1));
      expect(warnings.single.startingLevelId, 'level.10');
      expect(warnings.single.message, isNotEmpty);
    });

    test('a composition lacking stories at two starting levels warns for both, independently', () {
      final stories = [_sentenceFormatStory(id: 's1', levelId: 'level.1')];
      final warnings = validateStarterPackComposition(
        stories: stories,
        startingLevelIds: ['level.1', 'level.5', 'level.10'],
      );
      expect(warnings.map((w) => w.startingLevelId).toSet(), {'level.5', 'level.10'});
    });
  });

  // ---------------------------------------------------------------------
  // validateGraphemeSoundInventory (Unit 15 / §5, accept 11).
  // ---------------------------------------------------------------------
  final levelsById = {'level.1': _sentenceLevel()};
  final availableAssetRefs = {'audio/words/sat.wav'};

  group('validateGraphemeSoundInventory (positive baseline, accept 11)', () {
    test('a fully valid GraphemeSound passes with zero errors', () {
      final result = validateGraphemeSoundInventory(
        [_validGraphemeSound()],
        levelsById: levelsById,
        availableAssetRefs: availableAssetRefs,
      );
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test(
      'an extension-pack-style GraphemeSound (same id/grapheme as a base entry, new exampleWords) '
      'validates through the exact same rules and passes when valid',
      () {
        // Simulates a pack that EXTENDS an existing grapheme's example words:
        // same id/grapheme/phonemeIds/introducedAtLevelId as the "base" entry,
        // but a distinct exampleWords contribution. No special-casing exists
        // in the validator -- it is exercised via the same function/shape as
        // any other GraphemeSound.
        final extension = _validGraphemeSound(
          exampleWords: const [
            (wordText: 'sit', pronunciationAudioRef: 'audio/words/sit.wav', minLevelId: 'level.1'),
          ],
        );
        final result = validateGraphemeSoundInventory(
          [extension],
          levelsById: levelsById,
          availableAssetRefs: {'audio/words/sit.wav'},
        );
        expect(result.isValid, isTrue);
      },
    );
  });

  group('validateGraphemeSoundInventory (negative: bad phonemeId, accept 11)', () {
    test('a phonemeId outside the 44-phoneme set fails, naming the field and grapheme id', () {
      final result = validateGraphemeSoundInventory(
        [_validGraphemeSound(phonemeIds: const ['NOT-A-REAL-PHONEME'])],
        levelsById: levelsById,
        availableAssetRefs: availableAssetRefs,
      );
      expect(result.isValid, isFalse);
      final error = _findGraphemeError(result, field: 'phonemeIds', entityId: 'grapheme.s');
      expect(error, isNotNull);
      expect(error!.entityType, 'graphemeSound');
    });
  });

  group('validateGraphemeSoundInventory (negative: dangling introducedAtLevelId, accept 11)', () {
    test('an introducedAtLevelId not present in levelsById fails, naming the field and grapheme id', () {
      final result = validateGraphemeSoundInventory(
        [_validGraphemeSound(introducedAtLevelId: 'level.does-not-exist')],
        levelsById: levelsById,
        availableAssetRefs: availableAssetRefs,
      );
      expect(result.isValid, isFalse);
      expect(_findGraphemeError(result, field: 'introducedAtLevelId', entityId: 'grapheme.s'), isNotNull);
    });
  });

  group('validateGraphemeSoundInventory (negative: missing example-word audio, accept 11)', () {
    test('an exampleWord.pronunciationAudioRef absent from availableAssetRefs fails', () {
      final result = validateGraphemeSoundInventory(
        [_validGraphemeSound()],
        levelsById: levelsById,
        availableAssetRefs: const {}, // sat.wav not present
      );
      expect(result.isValid, isFalse);
      expect(_findGraphemeError(result, field: 'pronunciationAudioRef', entityId: 'grapheme.s'), isNotNull);
    });
  });

  group('validateGraphemeSoundInventory (negative: dangling exampleWord.minLevelId, accept 11)', () {
    test('an exampleWord.minLevelId not present in levelsById fails', () {
      final result = validateGraphemeSoundInventory(
        [
          _validGraphemeSound(
            exampleWords: const [
              (wordText: 'sat', pronunciationAudioRef: 'audio/words/sat.wav', minLevelId: 'level.nope'),
            ],
          ),
        ],
        levelsById: levelsById,
        availableAssetRefs: availableAssetRefs,
      );
      expect(result.isValid, isFalse);
      expect(_findGraphemeError(result, field: 'minLevelId', entityId: 'grapheme.s'), isNotNull);
    });
  });

  group('validateGraphemeSoundInventory (negative: empty wordText, accept 11)', () {
    test('an exampleWord with empty wordText fails', () {
      final result = validateGraphemeSoundInventory(
        [
          _validGraphemeSound(
            exampleWords: const [
              (wordText: '', pronunciationAudioRef: 'audio/words/sat.wav', minLevelId: 'level.1'),
            ],
          ),
        ],
        levelsById: levelsById,
        availableAssetRefs: availableAssetRefs,
      );
      expect(result.isValid, isFalse);
      expect(_findGraphemeError(result, field: 'wordText', entityId: 'grapheme.s'), isNotNull);
    });
  });

  group('validateGraphemeSoundInventory (edge: aggregates multiple independent errors, accept 11)', () {
    test('bad phonemeId AND dangling introducedAtLevelId on the same entry both appear', () {
      final result = validateGraphemeSoundInventory(
        [
          _validGraphemeSound(
            phonemeIds: const ['BOGUS'],
            introducedAtLevelId: 'level.missing',
          ),
        ],
        levelsById: levelsById,
        availableAssetRefs: availableAssetRefs,
      );
      expect(result.isValid, isFalse);
      expect(result.errors.length, greaterThanOrEqualTo(2));
      expect(_findGraphemeError(result, field: 'phonemeIds'), isNotNull);
      expect(_findGraphemeError(result, field: 'introducedAtLevelId'), isNotNull);
    });

    test('two independent GraphemeSounds each with a distinct problem both report', () {
      final result = validateGraphemeSoundInventory(
        [
          _validGraphemeSound(id: 'grapheme.a', phonemeIds: const ['BOGUS']),
          _validGraphemeSound(id: 'grapheme.b', introducedAtLevelId: 'level.missing'),
        ],
        levelsById: levelsById,
        availableAssetRefs: availableAssetRefs,
      );
      expect(_findGraphemeError(result, field: 'phonemeIds', entityId: 'grapheme.a'), isNotNull);
      expect(_findGraphemeError(result, field: 'introducedAtLevelId', entityId: 'grapheme.b'), isNotNull);
    });
  });

  // Sanity: the level fixtures above are exercised so the multi/paragraph
  // level builders aren't dead code subject to lint removal.
  test('fixture level builders produce the expected formats', () {
    expect(_multiLevel().format, LevelFormat.multiSentence);
    expect(_paragraphLevel().format, LevelFormat.paragraph);
  });
}

/// Story pack manifest (PRD §5 StoryPack, §8 Unit 3 pack format, §9 A-11).
///
/// A `StoryPack` is the versioned, checksummed bundle a pack ships as: a
/// JSON manifest (per §5 models) plus Rive and audio assets. `PhonicsSkill`
/// (scope & sequence) and `Level` do not travel inside a manifest -- they
/// are loaded separately by the phonics-engine unit (§8 Unit 2: "stored as
/// data not code") and passed into [validatePackManifest] as out-of-band
/// context (`levelsById`) instead. `Phoneme` is a fixed 44-entry set shipped
/// in the app binary and likewise never travels in a manifest. Everything
/// else authored per-story -- `Story`, `TongueTwister`, `VocabCard`,
/// `Collectible`, `GraphemeSound` -- does travel in the manifest.
///
/// [validatePackManifest] operates on raw, untyped JSON
/// (`Map<String, dynamic>`), not on a constructed `StoryPack`: the content
/// model constructors in `content_models.dart` make a "missing required
/// field" story impossible to construct in memory by design, so the only
/// place a corrupted/hand-edited/partial manifest can be represented -- and
/// therefore validated -- is at the raw-JSON layer. This is the gate a pack
/// must pass before `StoryPack.fromJson` is trusted with it in the real
/// build pipeline (pack-build-cli composes this validator with its own
/// asset/loudness/decodability checks).
library;

import 'content_models.dart';

// ---------------------------------------------------------------------------
// JSON conversion helpers (private). StoryPack is the only content-adjacent
// type in this ticket with a public toJson/fromJson; everything nested below
// it is converted via these private helpers so content_models.dart itself
// stays free of any JSON/encoding concerns.
// ---------------------------------------------------------------------------

Map<String, dynamic> _phonicsSkillToJson(PhonicsSkill skill) => {
      'id': skill.id,
      'name': skill.name,
      'sequenceOrder': skill.sequenceOrder,
      'introducesGraphemes': skill.introducesGraphemes,
    };

PhonicsSkill _phonicsSkillFromJson(Map<String, dynamic> json) => PhonicsSkill(
      id: json['id'] as String,
      name: json['name'] as String,
      sequenceOrder: json['sequenceOrder'] as int,
      introducesGraphemes: (json['introducesGraphemes'] as List).cast<String>(),
    );

Map<String, dynamic> _wordTokenToJson(WordToken token) => {
      'text': token.text,
      'graphemePhonemeMap': token.graphemePhonemeMap
          .map((e) => {'graphemes': e.graphemes, 'phonemeId': e.phonemeId})
          .toList(),
      'pronunciationAudioRef': token.pronunciationAudioRef,
      'vocabCardId': token.vocabCardId,
    };

WordToken _wordTokenFromJson(Map<String, dynamic> json) => WordToken(
      text: json['text'] as String,
      graphemePhonemeMap: (json['graphemePhonemeMap'] as List)
          .map((e) => (
                graphemes: (e as Map<String, dynamic>)['graphemes'] as String,
                phonemeId: e['phonemeId'] as String,
              ))
          .toList(),
      pronunciationAudioRef: json['pronunciationAudioRef'] as String,
      vocabCardId: json['vocabCardId'] as String?,
    );

Map<String, dynamic> _sentenceToJson(Sentence sentence) => {
      'words': sentence.words.map(_wordTokenToJson).toList(),
      'narrationAudioRef': sentence.narrationAudioRef,
    };

Sentence _sentenceFromJson(Map<String, dynamic> json) => Sentence(
      words: (json['words'] as List)
          .map((e) => _wordTokenFromJson(e as Map<String, dynamic>))
          .toList(),
      narrationAudioRef: json['narrationAudioRef'] as String?,
    );

Map<String, dynamic> _pageToJson(Page page) => {
      'sentences': page.sentences.map(_sentenceToJson).toList(),
    };

Page _pageFromJson(Map<String, dynamic> json) => Page(
      sentences: (json['sentences'] as List)
          .map((e) => _sentenceFromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _storyToJson(Story story) => {
      'id': story.id,
      'levelId': story.levelId,
      'title': story.title,
      'pages': story.pages.map(_pageToJson).toList(),
      'riveAnimationRef': story.riveAnimationRef,
      'celebrationAudioRef': story.celebrationAudioRef,
      'collectibleRef': story.collectibleRef,
      'skillsExercised': story.skillsExercised.map(_phonicsSkillToJson).toList(),
      'packId': story.packId,
      'contentVersion': story.contentVersion,
    };

Story _storyFromJson(Map<String, dynamic> json) => Story(
      id: json['id'] as String,
      levelId: json['levelId'] as String,
      title: json['title'] as String,
      pages: (json['pages'] as List)
          .map((e) => _pageFromJson(e as Map<String, dynamic>))
          .toList(),
      riveAnimationRef: json['riveAnimationRef'] as String,
      celebrationAudioRef: json['celebrationAudioRef'] as String,
      collectibleRef: json['collectibleRef'] as String,
      skillsExercised: (json['skillsExercised'] as List)
          .map((e) => _phonicsSkillFromJson(e as Map<String, dynamic>))
          .toList(),
      packId: json['packId'] as String,
      contentVersion: json['contentVersion'] as String,
    );

Map<String, dynamic> _twisterToJson(TongueTwister twister) => {
      'id': twister.id,
      'levelId': twister.levelId,
      'words': twister.words.map(_wordTokenToJson).toList(),
      'targetPhonemeId': twister.targetPhonemeId,
      'narrationAudioRef': twister.narrationAudioRef,
      'packId': twister.packId,
    };

TongueTwister _twisterFromJson(Map<String, dynamic> json) => TongueTwister(
      id: json['id'] as String,
      levelId: json['levelId'] as String,
      words: (json['words'] as List)
          .map((e) => _wordTokenFromJson(e as Map<String, dynamic>))
          .toList(),
      targetPhonemeId: json['targetPhonemeId'] as String,
      narrationAudioRef: json['narrationAudioRef'] as String,
      packId: json['packId'] as String,
    );

Map<String, dynamic> _vocabCardToJson(VocabCard card) => {
      'id': card.id,
      'word': card.word,
      'definitionText': card.definitionText,
      'definitionAudioRef': card.definitionAudioRef,
      'illustrationRef': card.illustrationRef,
    };

VocabCard _vocabCardFromJson(Map<String, dynamic> json) => VocabCard(
      id: json['id'] as String,
      word: json['word'] as String,
      definitionText: json['definitionText'] as String,
      definitionAudioRef: json['definitionAudioRef'] as String,
      illustrationRef: json['illustrationRef'] as String?,
    );

Map<String, dynamic> _collectibleToJson(Collectible collectible) => {
      'id': collectible.id,
      'storyId': collectible.storyId,
      'riveRef': collectible.riveRef,
      'sceneSlot': collectible.sceneSlot,
    };

Collectible _collectibleFromJson(Map<String, dynamic> json) => Collectible(
      id: json['id'] as String,
      storyId: json['storyId'] as String,
      riveRef: json['riveRef'] as String,
      sceneSlot: json['sceneSlot'] as String,
    );

Map<String, dynamic> _graphemeSoundToJson(GraphemeSound sound) => {
      'id': sound.id,
      'grapheme': sound.grapheme,
      'phonemeIds': sound.phonemeIds,
      'introducedAtLevelId': sound.introducedAtLevelId,
      'exampleWords': sound.exampleWords
          .map((e) => {
                'wordText': e.wordText,
                'pronunciationAudioRef': e.pronunciationAudioRef,
                'minLevelId': e.minLevelId,
              })
          .toList(),
    };

GraphemeSound _graphemeSoundFromJson(Map<String, dynamic> json) => GraphemeSound(
      id: json['id'] as String,
      grapheme: json['grapheme'] as String,
      phonemeIds: (json['phonemeIds'] as List).cast<String>(),
      introducedAtLevelId: json['introducedAtLevelId'] as String,
      exampleWords: (json['exampleWords'] as List)
          .map((e) => (
                wordText: (e as Map<String, dynamic>)['wordText'] as String,
                pronunciationAudioRef: e['pronunciationAudioRef'] as String,
                minLevelId: e['minLevelId'] as String,
              ))
          .toList(),
    );

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A versioned, checksummed story-pack bundle: the JSON manifest of stories,
/// tongue twisters, vocab cards, collectibles, and grapheme sounds authored
/// for this pack, plus the list of asset refs the bundle carries alongside
/// the manifest (Rive files, audio clips). `minAppVersion` gates whether an
/// installed app build may load this pack.
class StoryPack {
  StoryPack({
    required this.id,
    required this.version,
    required this.minAppVersion,
    required List<Story> stories,
    required List<TongueTwister> twisters,
    required List<VocabCard> vocabCards,
    required List<Collectible> collectibles,
    required List<GraphemeSound> graphemeSounds,
    required List<String> assetRefs,
    required this.checksum,
  })  : stories = List.unmodifiable(stories),
        twisters = List.unmodifiable(twisters),
        vocabCards = List.unmodifiable(vocabCards),
        collectibles = List.unmodifiable(collectibles),
        graphemeSounds = List.unmodifiable(graphemeSounds),
        assetRefs = List.unmodifiable(assetRefs);

  final String id;
  final String version;
  final String minAppVersion;
  final List<Story> stories;
  final List<TongueTwister> twisters;
  final List<VocabCard> vocabCards;
  final List<Collectible> collectibles;
  final List<GraphemeSound> graphemeSounds;
  final List<String> assetRefs;
  final String checksum;

  /// Serializes this pack to a plain `Map<String, dynamic>` suitable for
  /// `jsonEncode`.
  Map<String, dynamic> toJson() => {
        'id': id,
        'version': version,
        'minAppVersion': minAppVersion,
        'stories': stories.map(_storyToJson).toList(),
        'twisters': twisters.map(_twisterToJson).toList(),
        'vocabCards': vocabCards.map(_vocabCardToJson).toList(),
        'collectibles': collectibles.map(_collectibleToJson).toList(),
        'graphemeSounds': graphemeSounds.map(_graphemeSoundToJson).toList(),
        'assetRefs': assetRefs,
        'checksum': checksum,
      };

  /// Reconstructs a pack from a well-formed manifest map (as produced by
  /// [toJson], or its `jsonDecode`d JSON-text form). Trusts its input --
  /// callers must run [validatePackManifest] first on any manifest that did
  /// not come straight out of [toJson].
  factory StoryPack.fromJson(Map<String, dynamic> json) => StoryPack(
        id: json['id'] as String,
        version: json['version'] as String,
        minAppVersion: json['minAppVersion'] as String,
        stories: (json['stories'] as List)
            .map((e) => _storyFromJson(e as Map<String, dynamic>))
            .toList(),
        twisters: (json['twisters'] as List)
            .map((e) => _twisterFromJson(e as Map<String, dynamic>))
            .toList(),
        vocabCards: (json['vocabCards'] as List)
            .map((e) => _vocabCardFromJson(e as Map<String, dynamic>))
            .toList(),
        collectibles: (json['collectibles'] as List)
            .map((e) => _collectibleFromJson(e as Map<String, dynamic>))
            .toList(),
        graphemeSounds: (json['graphemeSounds'] as List)
            .map((e) => _graphemeSoundFromJson(e as Map<String, dynamic>))
            .toList(),
        assetRefs: (json['assetRefs'] as List).cast<String>(),
        checksum: json['checksum'] as String,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoryPack &&
          other.id == id &&
          other.version == version &&
          other.minAppVersion == minAppVersion &&
          _listEquals(other.stories, stories) &&
          _listEquals(other.twisters, twisters) &&
          _listEquals(other.vocabCards, vocabCards) &&
          _listEquals(other.collectibles, collectibles) &&
          _listEquals(other.graphemeSounds, graphemeSounds) &&
          _listEquals(other.assetRefs, assetRefs) &&
          other.checksum == checksum);

  @override
  int get hashCode => Object.hash(
        id,
        version,
        minAppVersion,
        Object.hashAll(stories),
        Object.hashAll(twisters),
        Object.hashAll(vocabCards),
        Object.hashAll(collectibles),
        Object.hashAll(graphemeSounds),
        Object.hash(Object.hashAll(assetRefs), checksum),
      );
}

/// A single manifest-validation failure: `field` is the offending field
/// name, `entityType` names the kind of entity it belongs to (`'pack'`,
/// `'story'`, `'twister'`, `'vocabCard'`, `'collectible'`, `'graphemeSound'`,
/// or `'level'`), `entityId` is that entity's id, and `message` is a
/// human-readable description.
class PackManifestValidationError {
  const PackManifestValidationError({
    required this.field,
    required this.entityType,
    required this.entityId,
    required this.message,
  });

  final String field;
  final String entityType;
  final String entityId;
  final String message;

  @override
  String toString() =>
      'PackManifestValidationError(field: $field, entityType: $entityType, '
      'entityId: $entityId, message: $message)';
}

/// The outcome of [validatePackManifest]: `isValid` is true iff [errors] is
/// empty. Validation aggregates every independent failure it finds rather
/// than failing fast on the first one.
class PackManifestValidationResult {
  const PackManifestValidationResult({
    required this.isValid,
    required this.errors,
  });

  final bool isValid;
  final List<PackManifestValidationError> errors;
}

void _requireField(
  Map<String, dynamic> json,
  String field, {
  required String entityType,
  required String entityId,
  required List<PackManifestValidationError> errors,
}) {
  if (json[field] == null) {
    errors.add(PackManifestValidationError(
      field: field,
      entityType: entityType,
      entityId: entityId,
      message: '$field is required on $entityType "$entityId"',
    ));
  }
}

String _entityId(Map<String, dynamic> json) => (json['id'] as String?) ?? '';

void _validateStory(
  Map<String, dynamic> json, {
  required Map<String, Level> levelsById,
  required List<PackManifestValidationError> errors,
}) {
  final entityId = _entityId(json);
  for (final field in const [
    'id',
    'levelId',
    'title',
    'pages',
    'riveAnimationRef',
    'celebrationAudioRef',
    'collectibleRef',
    'skillsExercised',
    'packId',
    'contentVersion',
  ]) {
    _requireField(json, field, entityType: 'story', entityId: entityId, errors: errors);
  }

  final levelIdRaw = json['levelId'];
  Level? level;
  if (levelIdRaw is String) {
    level = levelsById[levelIdRaw];
    if (level == null) {
      errors.add(PackManifestValidationError(
        field: 'levelId',
        entityType: 'story',
        entityId: entityId,
        message: 'unknown levelId "$levelIdRaw"',
      ));
    }
  }

  // A-11 / sentence-format-story invariant: both only apply when this
  // story's level is sentence-format (PRD A-11: "pack build requires
  // narrationAudioRef for every sentence-format story" -- scoped to level
  // format, not to Level.narrationEnabled, which above sentence-format is
  // purely a Unit 5 UI opt-in signal).
  final pagesRaw = json['pages'];
  if (level != null && level.format == LevelFormat.sentence && pagesRaw is List) {
    if (pagesRaw.length != 1) {
      errors.add(PackManifestValidationError(
        field: 'pages',
        entityType: 'story',
        entityId: entityId,
        message: 'sentence-format stories must have exactly one page',
      ));
    } else {
      final firstPage = pagesRaw[0];
      if (firstPage is Map<String, dynamic>) {
        final sentencesRaw = firstPage['sentences'];
        if (sentencesRaw is List && sentencesRaw.length != 1) {
          errors.add(PackManifestValidationError(
            field: 'sentences',
            entityType: 'story',
            entityId: entityId,
            message: 'sentence-format stories must have exactly one sentence',
          ));
        }
      }
    }

    for (final pageRaw in pagesRaw) {
      if (pageRaw is! Map<String, dynamic>) continue;
      final sentencesRaw = pageRaw['sentences'];
      if (sentencesRaw is! List) continue;
      for (final sentenceRaw in sentencesRaw) {
        if (sentenceRaw is! Map<String, dynamic>) continue;
        if (sentenceRaw['narrationAudioRef'] == null) {
          errors.add(PackManifestValidationError(
            field: 'narrationAudioRef',
            entityType: 'story',
            entityId: entityId,
            message: 'narrationAudioRef is required at sentence-format levels (A-11)',
          ));
        }
      }
    }
  }
}

void _validateTwister(
  Map<String, dynamic> json, {
  required List<PackManifestValidationError> errors,
}) {
  final entityId = _entityId(json);
  for (final field in const ['id', 'levelId', 'words', 'targetPhonemeId', 'narrationAudioRef', 'packId']) {
    _requireField(json, field, entityType: 'twister', entityId: entityId, errors: errors);
  }
}

void _validateVocabCard(
  Map<String, dynamic> json, {
  required List<PackManifestValidationError> errors,
}) {
  final entityId = _entityId(json);
  for (final field in const ['id', 'word', 'definitionText', 'definitionAudioRef']) {
    _requireField(json, field, entityType: 'vocabCard', entityId: entityId, errors: errors);
  }
}

void _validateCollectible(
  Map<String, dynamic> json, {
  required List<PackManifestValidationError> errors,
}) {
  final entityId = _entityId(json);
  for (final field in const ['id', 'storyId', 'riveRef', 'sceneSlot']) {
    _requireField(json, field, entityType: 'collectible', entityId: entityId, errors: errors);
  }
}

void _validateGraphemeSound(
  Map<String, dynamic> json, {
  required List<PackManifestValidationError> errors,
}) {
  final entityId = _entityId(json);
  for (final field in const ['id', 'grapheme', 'phonemeIds', 'introducedAtLevelId', 'exampleWords']) {
    _requireField(json, field, entityType: 'graphemeSound', entityId: entityId, errors: errors);
  }
}

/// Validates a raw pack manifest JSON map against the pinned schema (PRD §5
/// StoryPack, §8 Unit 3, §9 A-11).
///
/// `levelsById` supplies the phonics-engine's Level context (loaded
/// separately -- Level does not travel inside a manifest) that stories
/// reference by `levelId`; it also drives two checks:
///  - every sentence-format `Level` in `levelsById` must have
///    `narrationEnabled == true` (field `narrationEnabled`, entityType
///    `'level'`);
///  - every story whose resolved level is sentence-format must have exactly
///    one page with one sentence, and every sentence at a sentence-format
///    level must carry `narrationAudioRef` (A-11).
///
/// Errors are aggregated across the whole manifest rather than failing fast
/// on the first problem found.
PackManifestValidationResult validatePackManifest(
  Map<String, dynamic> manifestJson, {
  required Map<String, Level> levelsById,
}) {
  final errors = <PackManifestValidationError>[];

  final packId = _entityId(manifestJson);
  for (final field in const [
    'id',
    'version',
    'minAppVersion',
    'stories',
    'twisters',
    'vocabCards',
    'collectibles',
    'graphemeSounds',
    'assetRefs',
    'checksum',
  ]) {
    _requireField(manifestJson, field, entityType: 'pack', entityId: packId, errors: errors);
  }

  for (final level in levelsById.values) {
    if (level.format == LevelFormat.sentence && !level.narrationEnabled) {
      errors.add(PackManifestValidationError(
        field: 'narrationEnabled',
        entityType: 'level',
        entityId: level.id,
        message: 'sentence-format levels must have narrationEnabled=true (A-11)',
      ));
    }
  }

  final storiesRaw = manifestJson['stories'];
  if (storiesRaw is List) {
    for (final raw in storiesRaw) {
      if (raw is Map<String, dynamic>) {
        _validateStory(raw, levelsById: levelsById, errors: errors);
      }
    }
  }

  final twistersRaw = manifestJson['twisters'];
  if (twistersRaw is List) {
    for (final raw in twistersRaw) {
      if (raw is Map<String, dynamic>) {
        _validateTwister(raw, errors: errors);
      }
    }
  }

  final vocabCardsRaw = manifestJson['vocabCards'];
  if (vocabCardsRaw is List) {
    for (final raw in vocabCardsRaw) {
      if (raw is Map<String, dynamic>) {
        _validateVocabCard(raw, errors: errors);
      }
    }
  }

  final collectiblesRaw = manifestJson['collectibles'];
  if (collectiblesRaw is List) {
    for (final raw in collectiblesRaw) {
      if (raw is Map<String, dynamic>) {
        _validateCollectible(raw, errors: errors);
      }
    }
  }

  final graphemeSoundsRaw = manifestJson['graphemeSounds'];
  if (graphemeSoundsRaw is List) {
    for (final raw in graphemeSoundsRaw) {
      if (raw is Map<String, dynamic>) {
        _validateGraphemeSound(raw, errors: errors);
      }
    }
  }

  return PackManifestValidationResult(
    isValid: errors.isEmpty,
    errors: List.unmodifiable(errors),
  );
}

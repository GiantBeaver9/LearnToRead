/// Pipeline-level manifest validation (PRD §8 Unit 3 accept "round-trip test:
/// manifest schema validates all launch stories; a story failing schema
/// validation fails the pack build with a per-field error"; §9 A-9 starter
/// pack composition; §8 Unit 15 / §5 GraphemeSound content validation; ticket
/// pack-build-cli accept entries 2, 9, 11).
///
/// This file deliberately owns *only* what the pipeline adds on top of the
/// domain layer:
///
///  - [validateManifest] is a thin pass-through to
///    `validatePackManifest` (`lib/domain/models/pack_manifest.dart`),
///    re-exporting its result types rather than defining a parallel error
///    shape. The pipeline **composes** schema validation with its own
///    asset/loudness/decodability/Rive checks; it never reimplements it, so
///    there is exactly one place where "what a valid manifest is" lives.
///  - [validateStarterPackComposition] implements A-9, which has no
///    domain-layer home because composition is a property of a *pack
///    selection*, not of any single entity.
///  - [validateGraphemeSoundInventory] implements Unit 15's cross-referencing
///    rules (phoneme set, level refs, example-word audio), which need the
///    out-of-band `levelsById` and asset-ref context the domain validator has
///    no access to.
///
/// Pure functions throughout — no I/O; the pack builder does the reading.
library;

import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/pack_manifest.dart';

/// Validates a raw pack manifest against the pinned §5 schema, including the
/// A-11 narration rule, by delegating wholesale to the domain layer's
/// [validatePackManifest].
///
/// The delegation is the point: errors are pixel-identical in
/// `field`/`entityType`/`entityId`/`message` to what the domain validator
/// produces, so a manifest rejected by the app's loader is rejected by the
/// pack build for exactly the same stated reason.
PackManifestValidationResult validateManifest(
  Map<String, dynamic> manifestJson, {
  required Map<String, Level> levelsById,
}) =>
    validatePackManifest(manifestJson, levelsById: levelsById);

/// A-9 composition shortfall: the declared starter pack has no story at
/// [startingLevelId].
///
/// Warn-only by design — never an error, never fails a build. A-9 is a
/// *content-planning* guarantee ("any new profile has offline content at its
/// own starting level on first run"), and the build that flags it is often
/// the build of a single work-in-progress pack that was never meant to cover
/// all three bands. The signal belongs in the build log; the decision belongs
/// to the product owner.
class StarterPackCompositionWarning {
  const StarterPackCompositionWarning({
    required this.startingLevelId,
    required this.message,
  });

  /// The age-band starting level with zero matching stories.
  final String startingLevelId;

  final String message;

  @override
  String toString() =>
      'StarterPackCompositionWarning(startingLevelId: $startingLevelId, message: $message)';
}

/// Checks that [stories] include at least one story at each of
/// [startingLevelIds] — per A-9, the three age-band starting levels (level 1,
/// the first multiSentence level, the first paragraph level) the ~8-story
/// starter pack must cover.
///
/// Emits one warning per starting level with no matching story, independently:
/// a pack short at two bands warns twice. Returns an empty list when coverage
/// is complete (or when no composition was declared).
List<StarterPackCompositionWarning> validateStarterPackComposition({
  required List<Story> stories,
  required List<String> startingLevelIds,
}) {
  final coveredLevelIds = {for (final story in stories) story.levelId};
  return List.unmodifiable([
    for (final levelId in startingLevelIds)
      if (!coveredLevelIds.contains(levelId))
        StarterPackCompositionWarning(
          startingLevelId: levelId,
          message: 'declared starter pack has no story at starting level '
              '"$levelId"; A-9 asks for stories at all three age-band starting '
              'levels so every new profile has offline content on first run',
        ),
  ]);
}

/// One GraphemeSound content problem (Unit 15 / §5).
class GraphemeSoundValidationError {
  const GraphemeSoundValidationError({
    required this.field,
    required this.entityType,
    required this.entityId,
    required this.message,
  });

  /// `'phonemeIds'`, `'introducedAtLevelId'`, `'wordText'`,
  /// `'pronunciationAudioRef'` or `'minLevelId'`.
  final String field;

  /// Always `'graphemeSound'`.
  final String entityType;

  /// The offending `GraphemeSound.id`.
  final String entityId;

  final String message;

  @override
  String toString() => 'GraphemeSoundValidationError(field: $field, '
      'entityType: $entityType, entityId: $entityId, message: $message)';
}

/// The outcome of [validateGraphemeSoundInventory]: `isValid` is true iff
/// [errors] is empty.
class GraphemeSoundValidationResult {
  const GraphemeSoundValidationResult({required this.isValid, required this.errors});

  final bool isValid;
  final List<GraphemeSoundValidationError> errors;
}

GraphemeSoundValidationError _graphemeError(
  GraphemeSound sound,
  String field,
  String message,
) =>
    GraphemeSoundValidationError(
      field: field,
      entityType: 'graphemeSound',
      entityId: sound.id,
      message: message,
    );

/// Validates the Sound Garden grapheme inventory (Unit 15 / §5): every
/// `phonemeId` must exist in the fixed 44-phoneme set
/// ([kEnglishPhonemeIds]), `introducedAtLevelId` must resolve in
/// [levelsById], and every example word must have a non-empty `wordText`, a
/// `pronunciationAudioRef` present in [availableAssetRefs], and a
/// `minLevelId` that resolves in [levelsById].
///
/// Packs may EXTEND an existing grapheme's example words. There is
/// deliberately **no separate code path** for extensions: an extension pack's
/// contribution is a `GraphemeSound` like any other and is validated by these
/// same rules, so a pack cannot smuggle in an example word the binary starter
/// inventory would have rejected.
///
/// Every independent problem is aggregated — one bad phoneme id does not mask
/// a dangling level ref on the same entry, nor problems on later entries.
///
/// `availableAssetRefs` membership is an exact string match; no path
/// normalization is applied beyond what the caller put in the set.
GraphemeSoundValidationResult validateGraphemeSoundInventory(
  List<GraphemeSound> graphemeSounds, {
  required Map<String, Level> levelsById,
  required Set<String> availableAssetRefs,
}) {
  const validPhonemeIds = kEnglishPhonemeIds;
  final errors = <GraphemeSoundValidationError>[];

  for (final sound in graphemeSounds) {
    for (final phonemeId in sound.phonemeIds) {
      if (validPhonemeIds.contains(phonemeId)) continue;
      errors.add(_graphemeError(
        sound,
        'phonemeIds',
        'phonemeId "$phonemeId" on graphemeSound "${sound.id}" is not one of '
            'the 44 English phonemes',
      ));
    }

    if (!levelsById.containsKey(sound.introducedAtLevelId)) {
      errors.add(_graphemeError(
        sound,
        'introducedAtLevelId',
        'introducedAtLevelId "${sound.introducedAtLevelId}" on graphemeSound '
            '"${sound.id}" does not match any known level',
      ));
    }

    for (final exampleWord in sound.exampleWords) {
      if (exampleWord.wordText.isEmpty) {
        errors.add(_graphemeError(
          sound,
          'wordText',
          'exampleWord on graphemeSound "${sound.id}" has an empty wordText',
        ));
      }
      if (!availableAssetRefs.contains(exampleWord.pronunciationAudioRef)) {
        errors.add(_graphemeError(
          sound,
          'pronunciationAudioRef',
          'exampleWord "${exampleWord.wordText}" on graphemeSound '
              '"${sound.id}" references missing audio asset '
              '"${exampleWord.pronunciationAudioRef}"',
        ));
      }
      if (!levelsById.containsKey(exampleWord.minLevelId)) {
        errors.add(_graphemeError(
          sound,
          'minLevelId',
          'exampleWord "${exampleWord.wordText}" on graphemeSound '
              '"${sound.id}" has minLevelId "${exampleWord.minLevelId}", which '
              'does not match any known level',
        ));
      }
    }
  }

  return GraphemeSoundValidationResult(
    isValid: errors.isEmpty,
    errors: List.unmodifiable(errors),
  );
}

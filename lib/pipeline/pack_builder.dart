/// Pack build orchestration (PRD §8 Unit 3 pinned design step 6, "pack
/// build"; §9 A-9/A-11/A-15/A-16; ticket pack-build-cli accept entries 1-11).
///
/// [buildPack] is the pure library layer the `tool/pack_build.dart` CLI wraps:
/// content directory in, either a checksummed [StoryPack] or a flat list of
/// [PackBuildError]s out. Everything the CLI adds on top is argv parsing and
/// writing bytes to disk, so the whole of the build's *judgement* is testable
/// headlessly.
///
/// ## Stages
///
/// A build runs these in order, and **aggregates rather than fails fast** — a
/// content author gets every problem in one pass, not one problem per
/// re-run:
///
/// | stage            | what it checks                                        |
/// |------------------|-------------------------------------------------------|
/// | `schema`         | §5 manifest schema + A-11 narration (delegated to the domain validator) |
/// | `decodability`   | every story word decodable at its level, or whitelisted as a heart word |
/// | `assetPresence`  | every audio ref has a file behind it                  |
/// | `loudness`       | every audio asset measures the target integrated loudness (BS.1770) |
/// | `riveInputs`     | every `.riv` declares idle/celebrate/collect (A-16 sidecar) |
/// | `graphemeSound`  | Unit 15 inventory: phoneme set, level refs, example-word audio |
///
/// The one exception to aggregation is a manifest too broken to parse into a
/// [StoryPack] at all: the later stages take typed content models as input, so
/// when `schema` rejects a manifest *and* the raw JSON cannot be
/// reconstructed, the build returns the schema errors alone rather than
/// guessing at content that isn't there.
///
/// ## What deliberately does not fail a build
///
/// A-9 starter-pack composition. It is reported as
/// [StarterPackCompositionWarning]s on the result and never touches
/// `success`, because composition is a property of a pack *selection* the
/// build has no authority over (see `manifest_validator.dart`).
///
/// ## Twisters (Unit 14)
///
/// Twisters are exempt from decodability entirely — `lintTwister` is still
/// called (so the exemption stays a decision made in one place, not a missing
/// call site here), and it returns no findings by contract. Their required
/// fields (`narrationAudioRef`, `targetPhonemeId`) are enforced by the
/// *schema* stage, not by a bespoke twister code path, and their narration
/// audio flows through presence and loudness like any other asset.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/pack_manifest.dart';
import 'package:learn_to_read/pipeline/asset_presence_check.dart';
import 'package:learn_to_read/pipeline/decodability_linter.dart';
import 'package:learn_to_read/pipeline/loudness_check.dart';
import 'package:learn_to_read/pipeline/manifest_validator.dart';
import 'package:learn_to_read/pipeline/rive_input_validator.dart';
import 'package:path/path.dart' as p;

export 'package:learn_to_read/pipeline/manifest_validator.dart'
    show StarterPackCompositionWarning;

/// The manifest file a content directory is required to carry at its root.
const String kManifestFileName = 'manifest.json';

/// One reason a pack build failed, tagged with the stage that found it and
/// the content entity it belongs to, so the CLI can print a per-field,
/// per-entity error an author can act on without reading the build's source.
class PackBuildError {
  const PackBuildError({
    required this.stage,
    required this.entityType,
    required this.entityId,
    required this.field,
    required this.message,
  });

  /// `'schema'`, `'decodability'`, `'assetPresence'`, `'loudness'`,
  /// `'riveInputs'` or `'graphemeSound'`.
  final String stage;

  /// `'pack'`, `'story'`, `'twister'`, `'vocabCard'`, `'collectible'`,
  /// `'graphemeSound'`, `'level'`, `'wordToken'`, `'asset'` or `'rive'`.
  final String entityType;

  /// The offending entity's id (a `WordToken` has no id, so its text stands
  /// in; an asset's id is its ref).
  final String entityId;

  /// The offending field name.
  final String field;

  final String message;

  @override
  String toString() => 'PackBuildError(stage: $stage, entityType: $entityType, '
      'entityId: $entityId, field: $field, message: $message)';
}

/// The outcome of [buildPack].
class PackBuildResult {
  const PackBuildResult({
    required this.success,
    required this.errors,
    required this.pack,
    required this.compositionWarnings,
  });

  /// True iff [errors] is empty. Independent of [compositionWarnings], which
  /// are advisory (A-9).
  final bool success;

  /// Every problem found, across every stage, aggregated.
  final List<PackBuildError> errors;

  /// The built, checksummed pack — non-null iff [success].
  final StoryPack? pack;

  /// A-9 shortfalls in the declared starter composition. Never fails a build.
  final List<StarterPackCompositionWarning> compositionWarnings;
}

/// A-15: the SHA-256 checksum of a manifest, computed over the UTF-8 bytes of
/// `jsonEncode(manifestJson)` with the manifest's own `checksum` field forced
/// to `''` first — so the checksum never depends on itself, and re-checksumming
/// a signed manifest reproduces the same value.
///
/// Determinism rests on `jsonEncode` preserving map insertion order, which
/// `StoryPack.toJson()` fixes: two builds of identical content produce
/// byte-identical manifest text and therefore an identical checksum, and any
/// single changed byte of content changes it.
///
/// §5's "signed checksum" is satisfied by this in v1; cryptographic signing is
/// recorded post-POC hardening (A-15), not built here.
String computeManifestChecksum(Map<String, dynamic> manifestJson) {
  final blanked = Map<String, dynamic>.from(manifestJson)..['checksum'] = '';
  return sha256.convert(utf8.encode(jsonEncode(blanked))).toString();
}

/// True iff `manifestJson['checksum']` matches [computeManifestChecksum] of
/// the same manifest. Tampering with any byte of content — or with the
/// checksum itself — makes this false.
bool verifyManifestChecksum(Map<String, dynamic> manifestJson) =>
    manifestJson['checksum'] == computeManifestChecksum(manifestJson);

/// Resolves a '/'-separated manifest ref against [contentDir] using this
/// platform's path separator.
String _resolveRef(String contentDir, String ref) =>
    p.joinAll([contentDir, ...ref.split('/')]);

/// One audio ref together with the content entity that owns it, so presence
/// and loudness failures can name a field on an entity rather than a bare
/// path.
typedef _AudioRefSite = ({String ref, String entityType, String entityId, String field});

List<_AudioRefSite> _collectAudioRefSites(StoryPack pack) {
  final sites = <_AudioRefSite>[];
  for (final story in pack.stories) {
    sites.add((
      ref: story.celebrationAudioRef,
      entityType: 'story',
      entityId: story.id,
      field: 'celebrationAudioRef',
    ));
    for (final page in story.pages) {
      for (final sentence in page.sentences) {
        final narration = sentence.narrationAudioRef;
        if (narration != null) {
          sites.add((
            ref: narration,
            entityType: 'story',
            entityId: story.id,
            field: 'narrationAudioRef',
          ));
        }
        for (final word in sentence.words) {
          sites.add((
            ref: word.pronunciationAudioRef,
            entityType: 'wordToken',
            entityId: word.text,
            field: 'pronunciationAudioRef',
          ));
        }
      }
    }
  }
  for (final twister in pack.twisters) {
    sites.add((
      ref: twister.narrationAudioRef,
      entityType: 'twister',
      entityId: twister.id,
      field: 'narrationAudioRef',
    ));
    for (final word in twister.words) {
      sites.add((
        ref: word.pronunciationAudioRef,
        entityType: 'wordToken',
        entityId: word.text,
        field: 'pronunciationAudioRef',
      ));
    }
  }
  for (final card in pack.vocabCards) {
    sites.add((
      ref: card.definitionAudioRef,
      entityType: 'vocabCard',
      entityId: card.id,
      field: 'definitionAudioRef',
    ));
  }
  for (final sound in pack.graphemeSounds) {
    for (final exampleWord in sound.exampleWords) {
      sites.add((
        ref: exampleWord.pronunciationAudioRef,
        entityType: 'graphemeSound',
        entityId: sound.id,
        field: 'pronunciationAudioRef',
      ));
    }
  }
  return sites;
}

Set<String> _collectRiveRefs(StoryPack pack) => <String>{
      for (final story in pack.stories) story.riveAnimationRef,
      for (final collectible in pack.collectibles) collectible.riveRef,
    };

PackBuildResult _failure(List<PackBuildError> errors) => PackBuildResult(
      success: false,
      errors: List.unmodifiable(errors),
      pack: null,
      compositionWarnings: const [],
    );

/// Builds a pack from an authored content directory.
///
/// `<contentDir>/manifest.json` is the raw manifest (as produced by
/// `StoryPack.toJson()`); every audio and Rive ref inside it is a
/// '/'-separated path relative to `contentDir`, and each `<ref>.riv` is
/// validated against the sidecar at `<ref>.riv.inputs.json` (A-16).
///
/// [levels] is the scope-&-sequence context loaded out of band (Level never
/// travels inside a manifest); [heartWordsByLevelId] whitelists per-level
/// heart words for the decodability linter. Passing
/// [starterCompositionLevelIds] declares this build as a starter pack and
/// requests the A-9 composition check, whose warnings never fail the build.
/// [loudnessTargetLufs]/[loudnessToleranceLu] default to the Unit 13 pinned
/// -16 LUFS ±1 LU.
///
/// The manifest's own `checksum` field is ignored on input and recomputed on
/// output (A-15), as is `assetRefs`, which the build fills in from the refs
/// the manifest actually uses — the bundle's asset list is a build product,
/// not something an author hand-maintains.
Future<PackBuildResult> buildPack({
  required String contentDir,
  required List<Level> levels,
  Map<String, List<String>> heartWordsByLevelId = const {},
  List<String>? starterCompositionLevelIds,
  double loudnessTargetLufs = -16.0,
  double loudnessToleranceLu = 1.0,
}) async {
  final levelsById = {for (final level in levels) level.id: level};
  final errors = <PackBuildError>[];

  // -- Read the manifest. -------------------------------------------------
  final manifestFile = File(p.join(contentDir, kManifestFileName));
  if (!manifestFile.existsSync()) {
    return _failure([
      PackBuildError(
        stage: 'schema',
        entityType: 'pack',
        entityId: '',
        field: kManifestFileName,
        message: 'no $kManifestFileName found in content directory "$contentDir"',
      ),
    ]);
  }

  Map<String, dynamic> manifestJson;
  try {
    final decoded = jsonDecode(await manifestFile.readAsString());
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('manifest root is not a JSON object');
    }
    manifestJson = decoded;
  } on FormatException catch (e) {
    return _failure([
      PackBuildError(
        stage: 'schema',
        entityType: 'pack',
        entityId: '',
        field: kManifestFileName,
        message: '$kManifestFileName is not a readable manifest: ${e.message}',
      ),
    ]);
  }

  // -- Stage: schema (delegated to the domain validator). -----------------
  final schemaResult = validateManifest(manifestJson, levelsById: levelsById);
  for (final error in schemaResult.errors) {
    errors.add(PackBuildError(
      stage: 'schema',
      entityType: error.entityType,
      entityId: error.entityId,
      field: error.field,
      message: error.message,
    ));
  }

  // The remaining stages consume typed content models. A manifest too broken
  // to reconstruct stops here with the schema errors that explain why.
  StoryPack pack;
  try {
    pack = StoryPack.fromJson(manifestJson);
  } on Object catch (e) {
    if (errors.isEmpty) {
      errors.add(PackBuildError(
        stage: 'schema',
        entityType: 'pack',
        entityId: (manifestJson['id'] as String?) ?? '',
        field: kManifestFileName,
        message: 'manifest could not be read as a story pack: $e',
      ));
    }
    return _failure(errors);
  }

  final availableAssetRefs = scanAvailableAssetRefs(contentDir);

  // -- Stage: decodability. -----------------------------------------------
  for (final story in pack.stories) {
    if (!levelsById.containsKey(story.levelId)) {
      // The schema stage has already reported the unknown levelId; linting
      // against a level that does not exist would only throw.
      continue;
    }
    for (final finding in lintStory(
      story,
      levels: levels,
      heartWordsByLevelId: heartWordsByLevelId,
    )) {
      errors.add(PackBuildError(
        stage: 'decodability',
        entityType: 'story',
        entityId: finding.storyId,
        field: switch (finding.kind) {
          DecodabilityFindingKind.outOfLevelWord => 'words',
          DecodabilityFindingKind.wordCountBounds => 'words',
          DecodabilityFindingKind.pageCountBounds => 'pages',
        },
        message: finding.message,
      ));
    }
  }
  for (final twister in pack.twisters) {
    // Unit 14: twisters are exempt from decodability. The call is kept so
    // the exemption lives in `lintTwister` (which returns no findings by
    // contract) rather than in an absent call site here.
    for (final finding in lintTwister(
      twister,
      levels: levels,
      heartWordsByLevelId: heartWordsByLevelId,
    )) {
      errors.add(PackBuildError(
        stage: 'decodability',
        entityType: 'twister',
        entityId: twister.id,
        field: 'words',
        message: finding.message,
      ));
    }
  }

  // -- Stage: asset presence. ---------------------------------------------
  // The word-token and vocab-card refs the ticket names explicitly go through
  // the dedicated checker; the remaining audio sites (sentence narration,
  // celebration, twister narration) are swept here so no shipped audio ref
  // escapes the check. Grapheme-sound example words are excluded: the
  // graphemeSound stage below reports their missing audio in its own,
  // per-field taxonomy.
  final presenceResult = checkAssetPresence(
    stories: pack.stories,
    vocabCards: pack.vocabCards,
    availableAssetRefs: availableAssetRefs,
  );
  for (final error in presenceResult.errors) {
    errors.add(PackBuildError(
      stage: 'assetPresence',
      entityType: error.entityType,
      entityId: error.entityId,
      field: error.field,
      message: error.message,
    ));
  }

  final audioRefSites = _collectAudioRefSites(pack);
  const presenceCheckedElsewhere = {'wordToken', 'vocabCard', 'graphemeSound'};
  for (final site in audioRefSites) {
    if (presenceCheckedElsewhere.contains(site.entityType)) continue;
    if (availableAssetRefs.contains(site.ref)) continue;
    errors.add(PackBuildError(
      stage: 'assetPresence',
      entityType: site.entityType,
      entityId: site.entityId,
      field: site.field,
      message: 'no asset found for ${site.field} "${site.ref}" on '
          '${site.entityType} "${site.entityId}"',
    ));
  }

  // -- Stage: loudness (Unit 13). -----------------------------------------
  // Measured once per distinct file, not once per reference: a shared word
  // pronunciation is one asset with one verdict. Refs with no file behind
  // them are skipped — assetPresence has already named them.
  final measuredRefs = <String>{};
  for (final site in audioRefSites) {
    if (!measuredRefs.add(site.ref)) continue;
    if (!availableAssetRefs.contains(site.ref)) continue;

    final file = File(_resolveRef(contentDir, site.ref));
    try {
      final result = checkAssetLoudness(
        await file.readAsBytes(),
        assetRef: site.ref,
        targetLufs: loudnessTargetLufs,
        toleranceLu: loudnessToleranceLu,
      );
      if (result.passes) continue;
      errors.add(PackBuildError(
        stage: 'loudness',
        entityType: 'asset',
        entityId: site.ref,
        field: site.field,
        message: 'audio asset "${site.ref}" measures '
            '${result.measuredLufs.toStringAsFixed(2)} LUFS integrated; '
            'required ${loudnessTargetLufs.toStringAsFixed(1)} LUFS '
            '±${loudnessToleranceLu.toStringAsFixed(1)} LU',
      ));
    } on ArgumentError catch (e) {
      errors.add(PackBuildError(
        stage: 'loudness',
        entityType: 'asset',
        entityId: site.ref,
        field: site.field,
        message: 'audio asset "${site.ref}" could not be measured: ${e.message}',
      ));
    }
  }

  // -- Stage: Rive declared-inputs sidecars (A-16). -----------------------
  final sidecarJsonByRiveRef = <String, Map<String, dynamic>>{};
  final malformedSidecars = <String, String>{};
  for (final riveRef in _collectRiveRefs(pack)) {
    final sidecarFile = File(_resolveRef(contentDir, riveSidecarRefFor(riveRef)));
    if (!sidecarFile.existsSync()) continue;
    try {
      final decoded = jsonDecode(await sidecarFile.readAsString());
      if (decoded is Map<String, dynamic>) {
        sidecarJsonByRiveRef[riveRef] = decoded;
      } else {
        malformedSidecars[riveRef] = 'its root is not a JSON object';
      }
    } on FormatException catch (e) {
      malformedSidecars[riveRef] = 'it is not valid JSON (${e.message})';
    }
  }
  final riveResult = validateAllRiveInputs(
    stories: pack.stories,
    collectibles: pack.collectibles,
    sidecarJsonByRiveRef: sidecarJsonByRiveRef,
  );
  for (final error in riveResult.errors) {
    final malformedReason = malformedSidecars[error.riveRef];
    errors.add(PackBuildError(
      stage: 'riveInputs',
      entityType: 'rive',
      entityId: error.riveRef,
      field: 'inputs',
      message: malformedReason == null
          ? error.message
          : 'declared-inputs sidecar "${riveSidecarRefFor(error.riveRef)}" for '
              '"${error.riveRef}" was ignored because $malformedReason (A-16)',
    ));
  }

  // -- Stage: GraphemeSound inventory (Unit 15). --------------------------
  final graphemeResult = validateGraphemeSoundInventory(
    pack.graphemeSounds,
    levelsById: levelsById,
    availableAssetRefs: availableAssetRefs,
  );
  for (final error in graphemeResult.errors) {
    errors.add(PackBuildError(
      stage: 'graphemeSound',
      entityType: error.entityType,
      entityId: error.entityId,
      field: error.field,
      message: error.message,
    ));
  }

  // -- Warn-only: A-9 starter composition. --------------------------------
  final compositionWarnings = starterCompositionLevelIds == null
      ? const <StarterPackCompositionWarning>[]
      : validateStarterPackComposition(
          stories: pack.stories,
          startingLevelIds: starterCompositionLevelIds,
        );

  if (errors.isNotEmpty) {
    return PackBuildResult(
      success: false,
      errors: List.unmodifiable(errors),
      pack: null,
      compositionWarnings: compositionWarnings,
    );
  }

  // -- Emit: the bundle's asset list, then its A-15 checksum. -------------
  final assetRefs = <String>{
    for (final site in audioRefSites) site.ref,
    ..._collectRiveRefs(pack),
  }.toList()
    ..sort();

  StoryPack rebuild(String checksum) => StoryPack(
        id: pack.id,
        version: pack.version,
        minAppVersion: pack.minAppVersion,
        stories: pack.stories,
        twisters: pack.twisters,
        vocabCards: pack.vocabCards,
        collectibles: pack.collectibles,
        graphemeSounds: pack.graphemeSounds,
        assetRefs: assetRefs,
        checksum: checksum,
      );

  final checksum = computeManifestChecksum(rebuild('').toJson());

  return PackBuildResult(
    success: true,
    errors: const [],
    pack: rebuild(checksum),
    compositionWarnings: compositionWarnings,
  );
}

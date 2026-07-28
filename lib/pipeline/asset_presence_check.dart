/// Asset-presence check (PRD §8 Unit 13 acceptance: "audio assets exist for
/// every WordToken and VocabCard in every launch story"; ticket
/// pack-build-cli accept entry 5).
///
/// Deliberately *source-agnostic*: this file never opens, decodes or sniffs an
/// asset — presence alone satisfies a ref, so an owner-supplied recording, a
/// placeholder, or (post-v1) a TTS render all pass identically. Format
/// judgement belongs to `loudness_check.dart`, which runs after this and only
/// on refs this check found.
///
/// The only I/O here is [scanAvailableAssetRefs]'s directory walk; the
/// checking itself is a pure function over a ref set, so it is exercisable
/// without a filesystem.
library;

import 'dart:io';

import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:path/path.dart' as p;

/// Recursively scans [contentDir] and returns every file found, expressed as
/// a '/'-separated path relative to [contentDir] — matching how refs are
/// authored in a manifest (`'audio/words/cat.wav'`).
///
/// Every file is reported, not just audio: the pack build resolves Rive
/// sidecars and the manifest itself out of the same content directory, and a
/// presence check that pre-filtered by extension would quietly disagree with
/// what is actually on disk. Returns an empty set for an empty or missing
/// directory.
Set<String> scanAvailableAssetRefs(String contentDir) {
  final dir = Directory(contentDir);
  if (!dir.existsSync()) return <String>{};

  final refs = <String>{};
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    refs.add(p.split(p.relative(entity.path, from: contentDir)).join('/'));
  }
  return refs;
}

/// One missing asset: `field`/`entityType` locate the ref in the content
/// model, `entityId` names the owning entity (a `WordToken` has no id, so its
/// `text` stands in), and `ref` is the ref that had no file behind it.
class AssetPresenceError {
  const AssetPresenceError({
    required this.field,
    required this.entityType,
    required this.entityId,
    required this.ref,
    required this.message,
  });

  /// `'pronunciationAudioRef'` or `'definitionAudioRef'`.
  final String field;

  /// `'wordToken'` or `'vocabCard'`.
  final String entityType;

  /// `WordToken.text` or `VocabCard.id`.
  final String entityId;

  /// The manifest ref with no file behind it.
  final String ref;

  final String message;

  @override
  String toString() => 'AssetPresenceError(field: $field, entityType: $entityType, '
      'entityId: $entityId, ref: $ref, message: $message)';
}

/// The outcome of [checkAssetPresence]: `isValid` is true iff [errors] is
/// empty. Every missing ref is aggregated rather than failing fast, matching
/// this codebase's `PackManifestValidationResult` convention.
class AssetPresenceResult {
  const AssetPresenceResult({required this.isValid, required this.errors});

  final bool isValid;
  final List<AssetPresenceError> errors;
}

/// Checks that every `WordToken.pronunciationAudioRef` (across every sentence
/// of every page of every story in [stories]) and every
/// `VocabCard.definitionAudioRef` in [vocabCards] is present in
/// [availableAssetRefs].
///
/// Membership is an exact string match: no path normalization is applied
/// beyond whatever the caller already put in the set (in the pack build, the
/// '/'-separated relative paths [scanAvailableAssetRefs] produces).
///
/// Each *occurrence* reports independently — the same ref missing from two
/// words yields two errors, because the authoring fix is per-word.
AssetPresenceResult checkAssetPresence({
  required List<Story> stories,
  required List<VocabCard> vocabCards,
  required Set<String> availableAssetRefs,
}) {
  final errors = <AssetPresenceError>[];

  for (final story in stories) {
    for (final page in story.pages) {
      for (final sentence in page.sentences) {
        for (final word in sentence.words) {
          if (availableAssetRefs.contains(word.pronunciationAudioRef)) continue;
          errors.add(AssetPresenceError(
            field: 'pronunciationAudioRef',
            entityType: 'wordToken',
            entityId: word.text,
            ref: word.pronunciationAudioRef,
            message: 'no asset found for pronunciationAudioRef '
                '"${word.pronunciationAudioRef}" (word "${word.text}" in story '
                '"${story.id}")',
          ));
        }
      }
    }
  }

  for (final card in vocabCards) {
    if (availableAssetRefs.contains(card.definitionAudioRef)) continue;
    errors.add(AssetPresenceError(
      field: 'definitionAudioRef',
      entityType: 'vocabCard',
      entityId: card.id,
      ref: card.definitionAudioRef,
      message: 'no asset found for definitionAudioRef '
          '"${card.definitionAudioRef}" (vocab card "${card.id}")',
    ));
  }

  return AssetPresenceResult(isValid: errors.isEmpty, errors: List.unmodifiable(errors));
}

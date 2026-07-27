// Pins the API of lib/pipeline/asset_presence_check.dart (PRD §8 Unit 13
// acceptance: "audio assets exist for every WordToken and VocabCard in every
// launch story"; ticket pack-build-cli accept entry 5: "audio assets must
// exist for every WordToken pronunciationAudioRef and every VocabCard
// definitionAudioRef in every story (source-agnostic -- any audio file
// satisfies the ref); missing asset fails build naming the ref"). This suite
// is authored before the implementation exists, so it is EXPECTED to fail to
// compile until asset_presence_check.dart is written with exactly the shapes
// exercised below.
//
// Pinned API surface this suite requires:
//
//   /// Recursively scans `contentDir` and returns the set of every file
//   /// found, expressed as '/'-separated paths relative to `contentDir`
//   /// (matching how refs are authored in a manifest, e.g.
//   /// 'audio/words/cat.wav'). Source-agnostic: file content/format is never
//   /// inspected here, only presence.
//   Set<String> scanAvailableAssetRefs(String contentDir);
//
//   class AssetPresenceError {
//     final String field;      // 'pronunciationAudioRef' | 'definitionAudioRef'
//     final String entityType; // 'wordToken' | 'vocabCard'
//     final String entityId;   // WordToken.text (WordToken has no id field) | VocabCard.id
//     final String ref;
//     final String message;
//   }
//   class AssetPresenceResult {
//     final bool isValid;
//     final List<AssetPresenceError> errors;
//   }
//
//   /// Checks that every WordToken.pronunciationAudioRef (across every
//   /// sentence of every page of every story) and every
//   /// VocabCard.definitionAudioRef is present in `availableAssetRefs`.
//   /// Aggregates every missing ref rather than failing fast.
//   AssetPresenceResult checkAssetPresence({
//     required List<Story> stories,
//     required List<VocabCard> vocabCards,
//     required Set<String> availableAssetRefs,
//   });
//
// Contract this suite locks in (builder-mechanical):
//  - Membership is exact-string match between a ref and `availableAssetRefs`
//    -- no path normalization beyond what scanAvailableAssetRefs itself
//    produces.
//  - Scope is exactly WordToken.pronunciationAudioRef and
//    VocabCard.definitionAudioRef (per the ticket's accept-5 wording) --
//    narrationAudioRef/celebrationAudioRef presence is out of this file's
//    scope (covered elsewhere by the pack builder's own wiring, if at all).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/pipeline/asset_presence_check.dart';
import 'package:path/path.dart' as p;

WordToken _word(String text, String ref) => WordToken(
      text: text,
      graphemePhonemeMap: [(graphemes: text, phonemeId: kEnglishPhonemeIds.first)],
      pronunciationAudioRef: ref,
    );

VocabCard _vocabCard(String id, String word, String ref) => VocabCard(
      id: id,
      word: word,
      definitionText: 'A definition of $word.',
      definitionAudioRef: ref,
    );

Story _storyWithWords(String id, List<WordToken> words) => Story(
      id: id,
      levelId: 'level.1',
      title: 'Story $id',
      pages: [
        Page(sentences: [Sentence(words: words)]),
      ],
      riveAnimationRef: 'rive/$id.riv',
      celebrationAudioRef: 'audio/celebration/$id.wav',
      collectibleRef: 'collectible.$id',
      skillsExercised: const [],
      packId: 'pack.fixture',
      contentVersion: '1',
    );

/// A minimal, valid PCM16 mono WAV -- content is irrelevant to presence
/// checks (source-agnostic: "any audio file satisfies the ref"), so this is
/// deliberately tiny (silence) rather than a full sine fixture.
Uint8List _placeholderWavBytes() {
  const dataLength = 4; // 2 sample frames of silence
  final builder = BytesBuilder();
  void s(String v) => builder.add(v.codeUnits);
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
  u32(44100);
  u32(44100 * 2);
  u16(2);
  u16(16);
  s('data');
  u32(dataLength);
  builder.add(Uint8List(dataLength));
  return builder.toBytes();
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('asset_presence_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('scanAvailableAssetRefs (positive, ticket note: generated placeholder WAVs)', () {
    test('finds every generated WAV file, expressed as a path relative to contentDir', () async {
      final catFile = File(p.join(tempDir.path, 'audio', 'words', 'cat.wav'));
      await catFile.parent.create(recursive: true);
      await catFile.writeAsBytes(_placeholderWavBytes());

      final defFile = File(p.join(tempDir.path, 'audio', 'defs', 'cat.wav'));
      await defFile.parent.create(recursive: true);
      await defFile.writeAsBytes(_placeholderWavBytes());

      final refs = scanAvailableAssetRefs(tempDir.path);

      expect(refs, containsAll(<String>{'audio/words/cat.wav', 'audio/defs/cat.wav'}));
    });

    test('returns an empty set for an empty directory', () async {
      final refs = scanAvailableAssetRefs(tempDir.path);
      expect(refs, isEmpty);
    });
  });

  group('checkAssetPresence (positive, accept 5)', () {
    test('all WordToken and VocabCard audio refs present in availableAssetRefs pass', () {
      final story = _storyWithWords('s1', [_word('cat', 'audio/words/cat.wav')]);
      final card = _vocabCard('vocab.cat', 'cat', 'audio/defs/cat.wav');

      final result = checkAssetPresence(
        stories: [story],
        vocabCards: [card],
        availableAssetRefs: {'audio/words/cat.wav', 'audio/defs/cat.wav'},
      );

      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test(
      'source-agnostic: presence is satisfied by a real generated placeholder WAV regardless of its origin',
      () async {
        final ref = 'audio/words/dog.wav';
        final file = File(p.join(tempDir.path, ref));
        await file.parent.create(recursive: true);
        await file.writeAsBytes(_placeholderWavBytes());
        final availableAssetRefs = scanAvailableAssetRefs(tempDir.path);

        final story = _storyWithWords('s1', [_word('dog', ref)]);
        final result = checkAssetPresence(stories: [story], vocabCards: const [], availableAssetRefs: availableAssetRefs);

        expect(result.isValid, isTrue);
      },
    );
  });

  group('checkAssetPresence (negative, accept 5: missing WordToken audio)', () {
    test('a missing WordToken.pronunciationAudioRef fails, naming the ref', () {
      final story = _storyWithWords('s1', [_word('cat', 'audio/words/cat.wav')]);

      final result = checkAssetPresence(stories: [story], vocabCards: const [], availableAssetRefs: const {});

      expect(result.isValid, isFalse);
      final error = result.errors.firstWhere(
        (e) => e.field == 'pronunciationAudioRef' && e.entityType == 'wordToken',
        orElse: () => throw StateError('expected a pronunciationAudioRef error'),
      );
      expect(error.ref, 'audio/words/cat.wav');
      expect(error.entityId, 'cat');
      expect(error.message, isNotEmpty);
    });
  });

  group('checkAssetPresence (negative, accept 5: missing VocabCard audio)', () {
    test('a missing VocabCard.definitionAudioRef fails, naming the ref and card id', () {
      final card = _vocabCard('vocab.cat', 'cat', 'audio/defs/cat.wav');

      final result = checkAssetPresence(stories: const [], vocabCards: [card], availableAssetRefs: const {});

      expect(result.isValid, isFalse);
      final error = result.errors.firstWhere(
        (e) => e.field == 'definitionAudioRef' && e.entityType == 'vocabCard',
        orElse: () => throw StateError('expected a definitionAudioRef error'),
      );
      expect(error.ref, 'audio/defs/cat.wav');
      expect(error.entityId, 'vocab.cat');
    });
  });

  group('checkAssetPresence (edge: aggregates, does not fail fast, accept 5)', () {
    test('a missing WordToken ref and a missing VocabCard ref both appear in one result', () {
      final story = _storyWithWords('s1', [_word('cat', 'audio/words/cat.wav')]);
      final card = _vocabCard('vocab.dog', 'dog', 'audio/defs/dog.wav');

      final result = checkAssetPresence(stories: [story], vocabCards: [card], availableAssetRefs: const {});

      expect(result.errors.length, greaterThanOrEqualTo(2));
      expect(result.errors.any((e) => e.ref == 'audio/words/cat.wav'), isTrue);
      expect(result.errors.any((e) => e.ref == 'audio/defs/dog.wav'), isTrue);
    });

    test('a story with multiple words missing refs across multiple sentences reports each independently', () {
      final story = Story(
        id: 's1',
        levelId: 'level.1',
        title: 'Story s1',
        pages: [
          Page(sentences: [
            Sentence(words: [_word('cat', 'audio/words/cat.wav')]),
            Sentence(words: [_word('sat', 'audio/words/sat.wav')]),
          ]),
        ],
        riveAnimationRef: 'rive/s1.riv',
        celebrationAudioRef: 'audio/celebration/s1.wav',
        collectibleRef: 'collectible.s1',
        skillsExercised: const [],
        packId: 'pack.fixture',
        contentVersion: '1',
      );

      final result = checkAssetPresence(stories: [story], vocabCards: const [], availableAssetRefs: const {});

      expect(result.errors.where((e) => e.field == 'pronunciationAudioRef'), hasLength(2));
    });
  });
}

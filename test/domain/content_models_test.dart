// Pins the API of lib/domain/models/content_models.dart (PRD §5 "Content
// models", ticket domain-models accept entry 1 + the GraphemeSound/Phoneme/
// word-count-bound entries). This suite is authored before the
// implementation exists, so it is EXPECTED to fail to compile until
// content_models.dart is written with exactly the shapes exercised below.
//
// Pinned API surface this suite requires (transcribed from §5 + ticket, with
// builder-mechanical naming choices called out):
//   enum LevelFormat { sentence, multiSentence, paragraph }
//   class PhonicsSkill { id, name, sequenceOrder, introducesGraphemes: List<String> }
//   class Level { id, ordinal, newSkills: List<PhonicsSkill>, format: LevelFormat,
//                 vocabEnabled: bool, narrationEnabled: bool }
//     - Level's constructor takes narrationEnabled as optional; when omitted
//       it defaults to `format == LevelFormat.sentence` (A-11 default rule).
//   class Story { id, levelId, title, pages: List<Page>, riveAnimationRef,
//                 celebrationAudioRef, collectibleRef,
//                 skillsExercised: List<PhonicsSkill>, packId, contentVersion }
//   class Page { sentences: List<Sentence> }
//   class Sentence { words: List<WordToken>, narrationAudioRef: String? }
//   class WordToken { text, graphemePhonemeMap: List<({String graphemes, String phonemeId})>,
//                      pronunciationAudioRef, vocabCardId: String? }
//   class VocabCard { id, word, definitionText, definitionAudioRef, illustrationRef: String? }
//   class Phoneme { id, humanAudioRef } -- throws ArgumentError if id is not
//     a member of `kEnglishPhonemeIds` (the pinned-count-of-44 constant this
//     file defines; exact spelling of ids is builder-mechanical per ticket
//     notes, so tests only assert against the constant, never a hardcoded id).
//   class Collectible { id, storyId, riveRef, sceneSlot }
//   class TongueTwister { id, levelId, words: List<WordToken>, targetPhonemeId,
//                          narrationAudioRef, packId }
//   class GraphemeSound { id, grapheme, phonemeIds: List<String>,
//                          introducedAtLevelId,
//                          exampleWords: List<({String wordText, String pronunciationAudioRef, String minLevelId})> }
//   const List<String> kEnglishPhonemeIds; // exactly 44 unique, non-empty ids
//   const int kSentenceLevelMinWords = 3;
//   const int kSentenceLevelMaxWords = 8;
//   const int kParagraphLevelMinWords = 40;
//   const int kParagraphLevelMaxWords = 90;
//   const int kParagraphLevelMinPages = 1;
//   const int kParagraphLevelMaxPages = 3;
//
// All model classes are value types: two instances built from equal
// constructor arguments must be `==` and share a hashCode, and List-typed
// fields must be defensively copied (mutating the list passed to the
// constructor must not leak into the constructed object) -- this is how
// "immutable Dart types" (ticket wording) is pinned at runtime.
//
// StoryPack and pack-manifest JSON (de)serialization/validation are NOT
// tested here -- they live in lib/domain/models/pack_manifest.dart and are
// pinned by pack_manifest_test.dart, per the ticket's file split.

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';

PhonicsSkill _skill({
  String id = 'skill.short_a',
  String name = 'short a',
  int sequenceOrder = 1,
  List<String> introducesGraphemes = const ['a'],
}) =>
    PhonicsSkill(
      id: id,
      name: name,
      sequenceOrder: sequenceOrder,
      introducesGraphemes: introducesGraphemes,
    );

WordToken _wordToken({
  String text = 'cat',
  List<({String graphemes, String phonemeId})> graphemePhonemeMap =
      const [(graphemes: 'c', phonemeId: 'K'), (graphemes: 'a', phonemeId: 'AE'), (graphemes: 't', phonemeId: 'T')],
  String pronunciationAudioRef = 'audio/words/cat.wav',
  String? vocabCardId,
}) =>
    WordToken(
      text: text,
      graphemePhonemeMap: graphemePhonemeMap,
      pronunciationAudioRef: pronunciationAudioRef,
      vocabCardId: vocabCardId,
    );

void main() {
  group('PhonicsSkill (positive)', () {
    test('constructs with exactly the pinned fields and exposes them verbatim', () {
      final skill = _skill(
        id: 'skill.digraph_sh',
        name: 'digraph sh',
        sequenceOrder: 7,
        introducesGraphemes: ['sh'],
      );
      expect(skill.id, 'skill.digraph_sh');
      expect(skill.name, 'digraph sh');
      expect(skill.sequenceOrder, 7);
      expect(skill.introducesGraphemes, ['sh']);
    });

    test('two skills built from equal args are value-equal (== and hashCode)', () {
      final a = _skill(id: 's1', introducesGraphemes: ['a', 'e']);
      final b = _skill(id: 's1', introducesGraphemes: ['a', 'e']);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });
  });

  group('PhonicsSkill (edge: immutability)', () {
    test('introducesGraphemes is defensively copied: mutating the source list post-construction does not leak', () {
      final source = <String>['a', 't'];
      final skill = _skill(introducesGraphemes: source);
      source.add('mutated-after-construction');
      expect(skill.introducesGraphemes, ['a', 't']);
    });
  });

  group('Level (positive)', () {
    test('constructs with all three pinned formats', () {
      for (final format in LevelFormat.values) {
        final level = Level(
          id: 'level.$format',
          ordinal: 1,
          newSkills: [_skill()],
          format: format,
          vocabEnabled: false,
        );
        expect(level.format, format);
      }
    });

    test('LevelFormat has exactly the three pinned values', () {
      expect(
        LevelFormat.values.map((f) => f.name).toSet(),
        {'sentence', 'multiSentence', 'paragraph'},
      );
    });

    test('narrationEnabled default rule: sentence-format levels default to true when unspecified (A-11)', () {
      final level = Level(
        id: 'level.1',
        ordinal: 1,
        newSkills: const [],
        format: LevelFormat.sentence,
        vocabEnabled: false,
      );
      expect(level.narrationEnabled, isTrue);
    });

    test('narrationEnabled default rule: higher-format levels default to false when unspecified', () {
      for (final format in [LevelFormat.multiSentence, LevelFormat.paragraph]) {
        final level = Level(
          id: 'level.$format',
          ordinal: 5,
          newSkills: const [],
          format: format,
          vocabEnabled: true,
        );
        expect(level.narrationEnabled, isFalse, reason: '$format should default narrationEnabled=false');
      }
    });

    test('narrationEnabled opt-in is honored for a higher-format level (Unit 5 reads this flag)', () {
      final level = Level(
        id: 'level.multi.optin',
        ordinal: 6,
        newSkills: const [],
        format: LevelFormat.multiSentence,
        vocabEnabled: true,
        narrationEnabled: true,
      );
      expect(level.narrationEnabled, isTrue);
    });
  });

  group('Level (edge: immutability + value equality)', () {
    test('newSkills is defensively copied', () {
      final skills = [_skill(id: 's1')];
      final level = Level(
        id: 'level.1',
        ordinal: 1,
        newSkills: skills,
        format: LevelFormat.sentence,
        vocabEnabled: false,
      );
      skills.add(_skill(id: 's2'));
      expect(level.newSkills.map((s) => s.id), ['s1']);
    });

    test('two levels built from equal args (including resolved narrationEnabled) are value-equal', () {
      final a = Level(id: 'l1', ordinal: 1, newSkills: const [], format: LevelFormat.sentence, vocabEnabled: false);
      final b = Level(id: 'l1', ordinal: 1, newSkills: const [], format: LevelFormat.sentence, vocabEnabled: false);
      expect(a, equals(b));
    });
  });

  group('Story (positive)', () {
    test('constructs with exactly the pinned fields', () {
      final story = Story(
        id: 'story.1',
        levelId: 'level.1',
        title: 'The Cat Sat',
        pages: [
          Page(sentences: [Sentence(words: [_wordToken()], narrationAudioRef: 'audio/narration/story1.wav')]),
        ],
        riveAnimationRef: 'rive/story1.riv',
        celebrationAudioRef: 'audio/celebration/story1.wav',
        collectibleRef: 'collectible.cat',
        skillsExercised: [_skill()],
        packId: 'pack.starter',
        contentVersion: '1',
      );
      expect(story.id, 'story.1');
      expect(story.levelId, 'level.1');
      expect(story.title, 'The Cat Sat');
      expect(story.pages, hasLength(1));
      expect(story.riveAnimationRef, 'rive/story1.riv');
      expect(story.celebrationAudioRef, 'audio/celebration/story1.wav');
      expect(story.collectibleRef, 'collectible.cat');
      expect(story.skillsExercised, hasLength(1));
      expect(story.packId, 'pack.starter');
      expect(story.contentVersion, '1');
    });
  });

  group('Story (edge: immutability)', () {
    test('pages is defensively copied', () {
      final pages = [Page(sentences: const [])];
      final story = Story(
        id: 's1',
        levelId: 'l1',
        title: 't',
        pages: pages,
        riveAnimationRef: 'r',
        celebrationAudioRef: 'c',
        collectibleRef: 'col',
        skillsExercised: const [],
        packId: 'p',
        contentVersion: '1',
      );
      pages.add(Page(sentences: const []));
      expect(story.pages, hasLength(1));
    });
  });

  group('Page and Sentence (positive)', () {
    test('Page holds an ordered list of Sentence', () {
      final page = Page(sentences: [
        Sentence(words: [_wordToken(text: 'The')]),
        Sentence(words: [_wordToken(text: 'cat')]),
      ]);
      expect(page.sentences, hasLength(2));
      expect(page.sentences[0].words.single.text, 'The');
    });

    test('Sentence.narrationAudioRef is optional and nullable', () {
      final withNarration = Sentence(words: [_wordToken()], narrationAudioRef: 'audio/a.wav');
      final withoutNarration = Sentence(words: [_wordToken()]);
      expect(withNarration.narrationAudioRef, 'audio/a.wav');
      expect(withoutNarration.narrationAudioRef, isNull);
    });
  });

  group('WordToken (positive)', () {
    test('constructs with the pinned fields including the ordered graphemePhonemeMap', () {
      final token = _wordToken(
        text: 'cat',
        graphemePhonemeMap: const [
          (graphemes: 'c', phonemeId: 'K'),
          (graphemes: 'a', phonemeId: 'AE'),
          (graphemes: 't', phonemeId: 'T'),
        ],
        vocabCardId: 'vocab.cat',
      );
      expect(token.text, 'cat');
      expect(token.graphemePhonemeMap.map((e) => e.graphemes), ['c', 'a', 't']);
      expect(token.graphemePhonemeMap.map((e) => e.phonemeId), ['K', 'AE', 'T']);
      expect(token.pronunciationAudioRef, 'audio/words/cat.wav');
      expect(token.vocabCardId, 'vocab.cat');
    });

    test('vocabCardId is nullable, meaning the word does not render blue', () {
      final token = _wordToken(vocabCardId: null);
      expect(token.vocabCardId, isNull);
    });

    test('digraphs map as a single grapheme-phoneme entry, not split letter-by-letter (pinned design)', () {
      // "ship": sh-i-p, three graphemePhonemeMap entries, not four.
      final token = _wordToken(
        text: 'ship',
        graphemePhonemeMap: const [
          (graphemes: 'sh', phonemeId: 'SH'),
          (graphemes: 'i', phonemeId: 'IH'),
          (graphemes: 'p', phonemeId: 'P'),
        ],
      );
      expect(token.graphemePhonemeMap, hasLength(3));
      expect(token.graphemePhonemeMap.first.graphemes, 'sh');
    });
  });

  group('WordToken (edge: order preservation + immutability)', () {
    test('graphemePhonemeMap preserves insertion order exactly (drives sound-out highlighting order)', () {
      final token = _wordToken(
        text: 'cake',
        graphemePhonemeMap: const [
          (graphemes: 'c', phonemeId: 'K'),
          (graphemes: 'a', phonemeId: 'EY'),
          (graphemes: 'k', phonemeId: 'K'),
          (graphemes: 'e', phonemeId: ''), // silent e
        ],
      );
      expect(token.graphemePhonemeMap.map((e) => e.graphemes).toList(), ['c', 'a', 'k', 'e']);
    });

    test('graphemePhonemeMap list is defensively copied', () {
      final map = [(graphemes: 'a', phonemeId: 'AE')];
      final token = WordToken(
        text: 'a',
        graphemePhonemeMap: map,
        pronunciationAudioRef: 'r',
      );
      map.add((graphemes: 'x', phonemeId: 'X'));
      expect(token.graphemePhonemeMap, hasLength(1));
    });
  });

  group('VocabCard (positive + edge)', () {
    test('constructs with pinned fields, illustrationRef optional', () {
      final withIllustration = VocabCard(
        id: 'vocab.cat',
        word: 'cat',
        definitionText: 'A small furry pet that says meow.',
        definitionAudioRef: 'audio/defs/cat.wav',
        illustrationRef: 'art/cat.png',
      );
      final withoutIllustration = VocabCard(
        id: 'vocab.dog',
        word: 'dog',
        definitionText: 'A furry pet that barks.',
        definitionAudioRef: 'audio/defs/dog.wav',
      );
      expect(withIllustration.illustrationRef, 'art/cat.png');
      expect(withoutIllustration.illustrationRef, isNull);
    });
  });

  group('Phoneme (positive)', () {
    test('kEnglishPhonemeIds has exactly 44 unique, non-empty ids (the 44 English phonemes)', () {
      expect(kEnglishPhonemeIds, hasLength(44));
      expect(kEnglishPhonemeIds.toSet(), hasLength(44));
      for (final id in kEnglishPhonemeIds) {
        expect(id, isNotEmpty);
      }
    });

    test('constructs successfully with any id drawn from kEnglishPhonemeIds', () {
      for (final id in kEnglishPhonemeIds) {
        final phoneme = Phoneme(id: id, humanAudioRef: 'audio/phonemes/$id.wav');
        expect(phoneme.id, id);
        expect(phoneme.humanAudioRef, 'audio/phonemes/$id.wav');
      }
    });
  });

  group('Phoneme (negative)', () {
    test('rejects an id that is not one of the pinned 44 phonemes', () {
      expect(
        () => Phoneme(id: 'NOT_A_REAL_PHONEME_ID_ZZZ', humanAudioRef: 'audio/x.wav'),
        throwsArgumentError,
      );
    });

    test('rejects an empty-string id', () {
      expect(
        () => Phoneme(id: '', humanAudioRef: 'audio/x.wav'),
        throwsArgumentError,
      );
    });
  });

  group('Collectible (positive)', () {
    test('constructs with pinned fields', () {
      final collectible = Collectible(
        id: 'collectible.cat',
        storyId: 'story.1',
        riveRef: 'rive/collectibles/cat.riv',
        sceneSlot: 'shelf.3',
      );
      expect(collectible.id, 'collectible.cat');
      expect(collectible.storyId, 'story.1');
      expect(collectible.riveRef, 'rive/collectibles/cat.riv');
      expect(collectible.sceneSlot, 'shelf.3');
    });
  });

  group('TongueTwister (positive)', () {
    test('constructs with pinned fields including targetPhonemeId', () {
      final twister = TongueTwister(
        id: 'twister.1',
        levelId: 'level.3',
        words: [_wordToken(text: 'she'), _wordToken(text: 'sells')],
        targetPhonemeId: kEnglishPhonemeIds.first,
        narrationAudioRef: 'audio/twisters/1.wav',
        packId: 'pack.starter',
      );
      expect(twister.words, hasLength(2));
      expect(twister.targetPhonemeId, kEnglishPhonemeIds.first);
      expect(twister.narrationAudioRef, 'audio/twisters/1.wav');
      expect(twister.packId, 'pack.starter');
    });
  });

  group('GraphemeSound (positive)', () {
    test('constructs with pinned fields, phonemeIds ordered, exampleWords as tuples gated by minLevelId', () {
      final sound = GraphemeSound(
        id: 'grapheme.oi',
        grapheme: 'oi',
        phonemeIds: const ['OY'],
        introducedAtLevelId: 'level.9',
        exampleWords: const [
          (wordText: 'coin', pronunciationAudioRef: 'audio/words/coin.wav', minLevelId: 'level.9'),
          (wordText: 'boil', pronunciationAudioRef: 'audio/words/boil.wav', minLevelId: 'level.10'),
        ],
      );
      expect(sound.id, 'grapheme.oi');
      expect(sound.grapheme, 'oi');
      expect(sound.phonemeIds, ['OY']);
      expect(sound.introducedAtLevelId, 'level.9');
      expect(sound.exampleWords, hasLength(2));
      expect(sound.exampleWords[0].wordText, 'coin');
      expect(sound.exampleWords[1].minLevelId, 'level.10');
    });

    test('phonemeIds preserves order for multi-phoneme graphemes', () {
      final sound = GraphemeSound(
        id: 'grapheme.x',
        grapheme: 'x',
        phonemeIds: const ['K', 'S'],
        introducedAtLevelId: 'level.1',
        exampleWords: const [],
      );
      expect(sound.phonemeIds, ['K', 'S']);
    });
  });

  group('GraphemeSound (edge: immutability + empty inventory)', () {
    test('exampleWords is defensively copied', () {
      final words = [(wordText: 'coin', pronunciationAudioRef: 'a', minLevelId: 'l1')];
      final sound = GraphemeSound(
        id: 'g1',
        grapheme: 'oi',
        phonemeIds: const ['OY'],
        introducedAtLevelId: 'l1',
        exampleWords: words,
      );
      words.add((wordText: 'boil', pronunciationAudioRef: 'b', minLevelId: 'l1'));
      expect(sound.exampleWords, hasLength(1));
    });

    test('exampleWords may be empty (a grapheme with no authored example words yet)', () {
      final sound = GraphemeSound(
        id: 'g2',
        grapheme: 'sh',
        phonemeIds: const ['SH'],
        introducedAtLevelId: 'l1',
        exampleWords: const [],
      );
      expect(sound.exampleWords, isEmpty);
    });
  });

  group('Audio refs are source-agnostic opaque strings (asserted by API shape)', () {
    test('every audio-ref field across content models is a plain String, not a wrapper type', () {
      final token = _wordToken();
      final sentence = Sentence(words: [token], narrationAudioRef: 'audio/n.wav');
      final vocab = VocabCard(id: 'v', word: 'w', definitionText: 'd', definitionAudioRef: 'audio/d.wav');
      final phoneme = Phoneme(id: kEnglishPhonemeIds.first, humanAudioRef: 'audio/p.wav');
      final twister = TongueTwister(
        id: 't',
        levelId: 'l',
        words: [token],
        targetPhonemeId: kEnglishPhonemeIds.first,
        narrationAudioRef: 'audio/t.wav',
        packId: 'pack',
      );

      expect(token.pronunciationAudioRef, isA<String>());
      expect(sentence.narrationAudioRef, isA<String>());
      expect(vocab.definitionAudioRef, isA<String>());
      expect(phoneme.humanAudioRef, isA<String>());
      expect(twister.narrationAudioRef, isA<String>());
      // No recorded-vs-TTS distinction exists: the same field accepts either
      // origin's ref with no discriminator, tag, or subtype required.
      final ttsStyleRef = TongueTwister(
        id: 't2',
        levelId: 'l',
        words: [token],
        targetPhonemeId: kEnglishPhonemeIds.first,
        narrationAudioRef: 'tts://future-engine/clip-id',
        packId: 'pack',
      );
      expect(ttsStyleRef.narrationAudioRef, 'tts://future-engine/clip-id');
    });
  });

  group('A-8 word-count bound constants (positive: pinned defaults)', () {
    test('sentence-level bounds are 3-8 words', () {
      expect(kSentenceLevelMinWords, 3);
      expect(kSentenceLevelMaxWords, 8);
    });

    test('paragraph-level bounds are 40-90 words across 1-3 pages', () {
      expect(kParagraphLevelMinWords, 40);
      expect(kParagraphLevelMaxWords, 90);
      expect(kParagraphLevelMinPages, 1);
      expect(kParagraphLevelMaxPages, 3);
    });
  });

  group('A-8 word-count bound constants (edge: ordering sanity)', () {
    test('min bounds are strictly less than max bounds', () {
      expect(kSentenceLevelMinWords, lessThan(kSentenceLevelMaxWords));
      expect(kParagraphLevelMinWords, lessThan(kParagraphLevelMaxWords));
      expect(kParagraphLevelMinPages, lessThanOrEqualTo(kParagraphLevelMaxPages));
    });
  });
}

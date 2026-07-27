/// Content domain models (PRD §5 "Content models (authored, immutable once
/// published)").
///
/// These types describe content authored by the pipeline (Unit 3) and
/// shipped inside versioned story packs (see `pack_manifest.dart`). They are
/// pure, immutable Dart value types: no Flutter imports, no persistence
/// annotations. Two instances built from equal constructor arguments are
/// `==` and share a `hashCode`; every `List`-typed field is defensively
/// copied at construction time so external mutation of the source list can
/// never leak into a constructed instance.
///
/// `PhonicsSkill.introducesGraphemes` is the one shared schema that both the
/// phonics-engine's scope-&-sequence loader and the decodability linter
/// consume; neither of those units may define its own copy of this shape
/// (PRD §5, validator fix / PRD amendment referenced by the domain-models
/// ticket).
library;

/// Compares two lists for deep (element-by-element) equality.
bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Combines the hash codes of a list's elements, order-sensitive.
int _hashList(List<Object?> items) => Object.hashAll(items);

/// The fixed set of 44 English phonemes shipped with the app binary
/// (PRD §5 Phoneme: "one of the 44 English phonemes"). Exact id spelling is
/// builder-mechanical (ARPAbet-style, content-facing strings) per the
/// domain-models ticket notes; callers must treat ids as opaque tokens.
const List<String> kEnglishPhonemeIds = [
  // 24 consonant phonemes.
  'B', 'D', 'F', 'G', 'HH', 'JH', 'K', 'L', 'M', 'N', 'NG', 'P',
  'R', 'S', 'SH', 'T', 'TH', 'DH', 'V', 'W', 'Y', 'Z', 'ZH', 'CH',
  // 20 vowel phonemes (monophthongs, diphthongs, and r-controlled vowels).
  'AA', 'AE', 'AH', 'AO', 'AW', 'AY', 'EH', 'ER', 'EY', 'IH',
  'IY', 'OW', 'OY', 'UH', 'UW', 'AX', 'AIR', 'EAR', 'URE', 'ARE',
];

/// A-8: sentence-format levels are authored at 3-8 words per story.
const int kSentenceLevelMinWords = 3;
const int kSentenceLevelMaxWords = 8;

/// A-8: paragraph-format levels are authored at 40-90 words, across 1-3
/// pages.
const int kParagraphLevelMinWords = 40;
const int kParagraphLevelMaxWords = 90;
const int kParagraphLevelMinPages = 1;
const int kParagraphLevelMaxPages = 3;

/// A story's rendering format, driving both word-count bounds (A-8) and the
/// narration/vocab defaults below. Format progresses
/// `sentence` -> `multiSentence` -> `paragraph` as the reader advances.
enum LevelFormat { sentence, multiSentence, paragraph }

/// One skill in the phonics scope & sequence (Unit 2).
///
/// `introducesGraphemes` is the set of graphemes this skill teaches; the
/// decodability linter's cumulative grapheme set at level N is the union of
/// `introducesGraphemes` over every skill of a level with ordinal <= N.
class PhonicsSkill {
  PhonicsSkill({
    required this.id,
    required this.name,
    required this.sequenceOrder,
    required List<String> introducesGraphemes,
  }) : introducesGraphemes = List.unmodifiable(introducesGraphemes);

  final String id;
  final String name;
  final int sequenceOrder;

  /// The graphemes this skill introduces (e.g. `['sh']` for the "digraph
  /// sh" skill). Defensively copied and unmodifiable.
  final List<String> introducesGraphemes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PhonicsSkill &&
          other.id == id &&
          other.name == name &&
          other.sequenceOrder == sequenceOrder &&
          _listEquals(other.introducesGraphemes, introducesGraphemes));

  @override
  int get hashCode =>
      Object.hash(id, name, sequenceOrder, _hashList(introducesGraphemes));
}

/// One rung of the reading ladder.
///
/// `narrationEnabled` defaults to `true` when `format == LevelFormat.sentence`
/// and to `false` for higher formats (A-11), unless explicitly overridden at
/// construction time -- higher-format levels may opt in.
class Level {
  Level({
    required this.id,
    required this.ordinal,
    required List<PhonicsSkill> newSkills,
    required this.format,
    required this.vocabEnabled,
    bool? narrationEnabled,
  })  : newSkills = List.unmodifiable(newSkills),
        narrationEnabled = narrationEnabled ?? (format == LevelFormat.sentence);

  final String id;
  final int ordinal;
  final List<PhonicsSkill> newSkills;
  final LevelFormat format;
  final bool vocabEnabled;

  /// True at all sentence-format levels by default; opt-in for higher
  /// formats. Pack validation requires `narrationAudioRef` on every
  /// sentence-format story regardless of this flag (A-11); above
  /// sentence-format this flag is purely a Unit 5 UI signal.
  final bool narrationEnabled;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Level &&
          other.id == id &&
          other.ordinal == ordinal &&
          _listEquals(other.newSkills, newSkills) &&
          other.format == format &&
          other.vocabEnabled == vocabEnabled &&
          other.narrationEnabled == narrationEnabled);

  @override
  int get hashCode => Object.hash(
        id,
        ordinal,
        _hashList(newSkills),
        format,
        vocabEnabled,
        narrationEnabled,
      );
}

/// An authored story.
class Story {
  Story({
    required this.id,
    required this.levelId,
    required this.title,
    required List<Page> pages,
    required this.riveAnimationRef,
    required this.celebrationAudioRef,
    required this.collectibleRef,
    required List<PhonicsSkill> skillsExercised,
    required this.packId,
    required this.contentVersion,
  })  : pages = List.unmodifiable(pages),
        skillsExercised = List.unmodifiable(skillsExercised);

  final String id;
  final String levelId;
  final String title;
  final List<Page> pages;
  final String riveAnimationRef;
  final String celebrationAudioRef;
  final String collectibleRef;
  final List<PhonicsSkill> skillsExercised;
  final String packId;
  final String contentVersion;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Story &&
          other.id == id &&
          other.levelId == levelId &&
          other.title == title &&
          _listEquals(other.pages, pages) &&
          other.riveAnimationRef == riveAnimationRef &&
          other.celebrationAudioRef == celebrationAudioRef &&
          other.collectibleRef == collectibleRef &&
          _listEquals(other.skillsExercised, skillsExercised) &&
          other.packId == packId &&
          other.contentVersion == contentVersion);

  @override
  int get hashCode => Object.hash(
        id,
        levelId,
        title,
        _hashList(pages),
        riveAnimationRef,
        celebrationAudioRef,
        collectibleRef,
        _hashList(skillsExercised),
        Object.hash(packId, contentVersion),
      );
}

/// One page of a story: an ordered list of sentences. Sentence-format
/// stories have exactly one page with one sentence (enforced by
/// `validatePackManifest`, not by this constructor -- see
/// `pack_manifest.dart`).
class Page {
  Page({required List<Sentence> sentences})
      : sentences = List.unmodifiable(sentences);

  final List<Sentence> sentences;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Page && _listEquals(other.sentences, sentences));

  @override
  int get hashCode => _hashList(sentences);
}

/// One sentence of story text.
///
/// `narrationAudioRef` is the recorded human read-aloud for this sentence;
/// required at sentence-format levels (A-11), supplied by the product owner.
class Sentence {
  Sentence({required List<WordToken> words, this.narrationAudioRef})
      : words = List.unmodifiable(words);

  final List<WordToken> words;
  final String? narrationAudioRef;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Sentence &&
          _listEquals(other.words, words) &&
          other.narrationAudioRef == narrationAudioRef);

  @override
  int get hashCode => Object.hash(_hashList(words), narrationAudioRef);
}

/// One word within a sentence (or tongue twister).
///
/// `graphemePhonemeMap` is an ordered list of `(graphemes, phonemeId)` pairs
/// that drives sound-out highlighting; digraphs are a single entry (`'sh'`
/// maps as one unit, not letter-by-letter). `vocabCardId` presence means the
/// word renders blue when the owning `Level.vocabEnabled` is true.
class WordToken {
  WordToken({
    required this.text,
    required List<({String graphemes, String phonemeId})> graphemePhonemeMap,
    required this.pronunciationAudioRef,
    this.vocabCardId,
  }) : graphemePhonemeMap = List.unmodifiable(graphemePhonemeMap);

  final String text;
  final List<({String graphemes, String phonemeId})> graphemePhonemeMap;
  final String pronunciationAudioRef;
  final String? vocabCardId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WordToken &&
          other.text == text &&
          _listEquals(other.graphemePhonemeMap, graphemePhonemeMap) &&
          other.pronunciationAudioRef == pronunciationAudioRef &&
          other.vocabCardId == vocabCardId);

  @override
  int get hashCode => Object.hash(
        text,
        _hashList(graphemePhonemeMap),
        pronunciationAudioRef,
        vocabCardId,
      );
}

/// A kid-friendly vocabulary definition card.
class VocabCard {
  VocabCard({
    required this.id,
    required this.word,
    required this.definitionText,
    required this.definitionAudioRef,
    this.illustrationRef,
  });

  final String id;
  final String word;
  final String definitionText;
  final String definitionAudioRef;
  final String? illustrationRef;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VocabCard &&
          other.id == id &&
          other.word == word &&
          other.definitionText == definitionText &&
          other.definitionAudioRef == definitionAudioRef &&
          other.illustrationRef == illustrationRef);

  @override
  int get hashCode => Object.hash(
        id,
        word,
        definitionText,
        definitionAudioRef,
        illustrationRef,
      );
}

/// One of the 44 English phonemes, with its recorded human-voiced audio.
/// Fixed set shipped in the app binary (PRD §5).
class Phoneme {
  Phoneme({required this.id, required this.humanAudioRef}) {
    if (!kEnglishPhonemeIds.contains(id)) {
      throw ArgumentError.value(
        id,
        'id',
        'must be one of kEnglishPhonemeIds (the pinned 44 English phonemes)',
      );
    }
  }

  final String id;
  final String humanAudioRef;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Phoneme && other.id == id && other.humanAudioRef == humanAudioRef);

  @override
  int get hashCode => Object.hash(id, humanAudioRef);
}

/// A collectible earned by completing a story; placed in the collection
/// scene at `sceneSlot`.
class Collectible {
  Collectible({
    required this.id,
    required this.storyId,
    required this.riveRef,
    required this.sceneSlot,
  });

  final String id;
  final String storyId;
  final String riveRef;
  final String sceneSlot;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Collectible &&
          other.id == id &&
          other.storyId == storyId &&
          other.riveRef == riveRef &&
          other.sceneSlot == sceneSlot);

  @override
  int get hashCode => Object.hash(id, storyId, riveRef, sceneSlot);
}

/// A tongue twister that drills a single target phoneme (Unit 14). Exempt
/// from decodability linting -- modeled-first content may use above-level
/// words.
class TongueTwister {
  TongueTwister({
    required this.id,
    required this.levelId,
    required List<WordToken> words,
    required this.targetPhonemeId,
    required this.narrationAudioRef,
    required this.packId,
  }) : words = List.unmodifiable(words);

  final String id;
  final String levelId;
  final List<WordToken> words;
  final String targetPhonemeId;
  final String narrationAudioRef;
  final String packId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is TongueTwister &&
          other.id == id &&
          other.levelId == levelId &&
          _listEquals(other.words, words) &&
          other.targetPhonemeId == targetPhonemeId &&
          other.narrationAudioRef == narrationAudioRef &&
          other.packId == packId);

  @override
  int get hashCode => Object.hash(
        id,
        levelId,
        _hashList(words),
        targetPhonemeId,
        narrationAudioRef,
        packId,
      );
}

/// A phonics sound card in the Sound Garden (Unit 15).
///
/// `phonemeIds` is ordered and plays via the recorded phoneme set.
/// `introducedAtLevelId` drives the awake/muted state in the Sound Garden.
/// `exampleWords` are `(wordText, pronunciationAudioRef, minLevelId)`
/// tuples; a word appears on the card only when the profile's current level
/// is at or above `minLevelId`. The full inventory ships in binary starter
/// content; example words extend via packs.
class GraphemeSound {
  GraphemeSound({
    required this.id,
    required this.grapheme,
    required List<String> phonemeIds,
    required this.introducedAtLevelId,
    required List<({String wordText, String pronunciationAudioRef, String minLevelId})> exampleWords,
  })  : phonemeIds = List.unmodifiable(phonemeIds),
        exampleWords = List.unmodifiable(exampleWords);

  final String id;
  final String grapheme;
  final List<String> phonemeIds;
  final String introducedAtLevelId;
  final List<({String wordText, String pronunciationAudioRef, String minLevelId})> exampleWords;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GraphemeSound &&
          other.id == id &&
          other.grapheme == grapheme &&
          _listEquals(other.phonemeIds, phonemeIds) &&
          other.introducedAtLevelId == introducedAtLevelId &&
          _listEquals(other.exampleWords, exampleWords));

  @override
  int get hashCode => Object.hash(
        id,
        grapheme,
        _hashList(phonemeIds),
        introducedAtLevelId,
        _hashList(exampleWords),
      );
}

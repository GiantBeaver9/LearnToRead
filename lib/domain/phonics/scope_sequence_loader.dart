/// Phonics scope & sequence loader (PRD §8 Unit 2 pinned design: "a single
/// ordered scope & sequence of PhonicsSkills, science-of-reading aligned,
/// stored as data (not code)"; ticket phonics-engine accept entry "Scope &
/// sequence loads from data files (JSON) ... changing story order requires
/// no code change").
///
/// [loadPhonicsContent] is the one place this unit parses JSON. It is
/// intentionally dumb about the *content* of the scope & sequence (which
/// skills at which level, heart-word lists) -- that table is authored
/// content owned by the content pipeline (Unit 3 / OQ-5) and is supplied
/// entirely by the JSON text passed in. This file only pins the *shape* of
/// that JSON and the loader's parsing contract; see
/// `test/domain/phonics/scope_sequence_loader_test.dart` for the exact
/// pinned schema and error contract this implementation transcribes.
///
/// Pure Dart, no I/O: callers (fixtures in tests today; the content-pack
/// loader in a later unit) read the JSON text themselves and pass it in.
library;

import 'dart:convert';

import '../models/content_models.dart';

/// A lightweight reference to an authored [content_models.Story]: just the
/// `id` and the `levelId` it was authored under. The phonics engine only
/// ever needs to reason about story identity, ordering, and level
/// membership -- never the full authored `Story` (pages, audio refs, etc,
/// which belong to the content-pack loader) -- so this is deliberately a
/// narrower type than `Story`.
///
/// Value-equal by `(id, levelId)`, like the domain-models content types.
class StoryRef {
  const StoryRef({required this.id, required this.levelId});

  final String id;
  final String levelId;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StoryRef && other.id == id && other.levelId == levelId);

  @override
  int get hashCode => Object.hash(id, levelId);
}

/// The full result of loading one scope-&-sequence JSON document: the
/// ordered [Level]s (sorted ascending by `ordinal`, regardless of the raw
/// JSON array order), the per-level heart-word lists, and [stories] in
/// *exact* JSON authored order.
///
/// [stories]' order is load-bearing: it IS the "global authored order" the
/// rest of the phonics engine (`phonics_engine.dart`) trusts for the
/// rolling-window unlock rule (PRD: "the next 3 uncompleted stories in
/// global authored order (which is level-ordered)"). It is never re-derived
/// or re-sorted from level ordinals -- the JSON "stories" array order is
/// authoritative.
class PhonicsContent {
  const PhonicsContent({
    required this.levels,
    required this.heartWordsByLevelId,
    required this.stories,
  });

  /// Ascending by `ordinal`.
  final List<Level> levels;

  /// Every level id maps to its heart-word list (empty list if the level's
  /// JSON had no `"heartWords"` key).
  final Map<String, List<String>> heartWordsByLevelId;

  /// Global authored order -- exactly the order of the JSON `"stories"`
  /// array.
  final List<StoryRef> stories;
}

LevelFormat _parseFormat(String raw, String levelId) {
  switch (raw) {
    case 'sentence':
      return LevelFormat.sentence;
    case 'multiSentence':
      return LevelFormat.multiSentence;
    case 'paragraph':
      return LevelFormat.paragraph;
    default:
      throw FormatException(
        'Level "$levelId" has an unrecognized "format" value: "$raw"',
      );
  }
}

PhonicsSkill _parseSkill(dynamic raw, String levelId) {
  if (raw is! Map<String, dynamic>) {
    throw FormatException(
      'A skill entry in level "$levelId" is not a JSON object',
    );
  }
  final id = raw['id'];
  final name = raw['name'];
  final sequenceOrder = raw['sequenceOrder'];
  final introducesGraphemes = raw['introducesGraphemes'];
  if (id is! String) {
    throw FormatException('A skill in level "$levelId" is missing "id"');
  }
  if (name is! String) {
    throw FormatException('Skill "$id" (level "$levelId") is missing "name"');
  }
  if (sequenceOrder is! int) {
    throw FormatException(
      'Skill "$id" (level "$levelId") is missing "sequenceOrder"',
    );
  }
  if (introducesGraphemes is! List) {
    throw FormatException(
      'Skill "$id" (level "$levelId") is missing "introducesGraphemes"',
    );
  }
  return PhonicsSkill(
    id: id,
    name: name,
    sequenceOrder: sequenceOrder,
    introducesGraphemes: introducesGraphemes.cast<String>(),
  );
}

Level _parseLevel(dynamic raw, Map<String, List<String>> heartWordsByLevelId) {
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('A "levels" entry is not a JSON object');
  }
  final id = raw['id'];
  if (id is! String) {
    throw const FormatException('A level is missing "id"');
  }
  final ordinal = raw['ordinal'];
  if (ordinal is! int) {
    throw FormatException('Level "$id" is missing "ordinal"');
  }
  final formatRaw = raw['format'];
  if (formatRaw is! String) {
    throw FormatException('Level "$id" is missing "format"');
  }
  final vocabEnabled = raw['vocabEnabled'];
  if (vocabEnabled is! bool) {
    throw FormatException('Level "$id" is missing "vocabEnabled"');
  }
  final skillsRaw = raw['skills'];
  if (skillsRaw is! List) {
    throw FormatException('Level "$id" is missing "skills"');
  }

  final heartWordsRaw = raw['heartWords'];
  final heartWords =
      heartWordsRaw == null ? const <String>[] : (heartWordsRaw as List).cast<String>();
  heartWordsByLevelId[id] = heartWords;

  return Level(
    id: id,
    ordinal: ordinal,
    newSkills: skillsRaw.map((s) => _parseSkill(s, id)).toList(),
    format: _parseFormat(formatRaw, id),
    vocabEnabled: vocabEnabled,
  );
}

StoryRef _parseStory(dynamic raw, Set<String> knownLevelIds) {
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('A "stories" entry is not a JSON object');
  }
  final id = raw['id'];
  if (id is! String) {
    throw const FormatException('A story is missing "id"');
  }
  final levelId = raw['levelId'];
  if (levelId is! String) {
    throw FormatException('Story "$id" is missing "levelId"');
  }
  if (!knownLevelIds.contains(levelId)) {
    throw FormatException(
      'Story "$id" references unknown levelId "$levelId"',
    );
  }
  return StoryRef(id: id, levelId: levelId);
}

/// Parses [jsonText] into a [PhonicsContent].
///
/// Root JSON object: `{ "levels": [...], "stories": [...] }`.
///
/// Level object: `{ "id": String, "ordinal": int, "format": "sentence" |
/// "multiSentence" | "paragraph", "vocabEnabled": bool, "heartWords":
/// [String] (optional, defaults to []), "skills": [SkillObject] }`.
///
/// SkillObject: `{ "id": String, "name": String, "sequenceOrder": int,
/// "introducesGraphemes": [String] }`.
///
/// Story object: `{ "id": String, "levelId": String }` -- `"levelId"` must
/// match some level's `"id"`.
///
/// Throws [FormatException] for: input that isn't valid JSON at all; a
/// missing `"levels"` or `"stories"` root key; a level/skill/story object
/// missing a required field; an unrecognized `"format"` string; or a story
/// whose `"levelId"` matches no level.
PhonicsContent loadPhonicsContent(String jsonText) {
  final decoded = jsonDecode(jsonText);
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Root JSON value must be an object');
  }

  final levelsRaw = decoded['levels'];
  if (levelsRaw is! List) {
    throw const FormatException('Root object is missing a "levels" array');
  }
  final storiesRaw = decoded['stories'];
  if (storiesRaw is! List) {
    throw const FormatException('Root object is missing a "stories" array');
  }

  final heartWordsByLevelId = <String, List<String>>{};
  final levels = levelsRaw.map((l) => _parseLevel(l, heartWordsByLevelId)).toList()
    ..sort((a, b) => a.ordinal.compareTo(b.ordinal));

  final knownLevelIds = levels.map((l) => l.id).toSet();
  final stories = storiesRaw.map((s) => _parseStory(s, knownLevelIds)).toList();

  return PhonicsContent(
    levels: levels,
    heartWordsByLevelId: heartWordsByLevelId,
    stories: stories,
  );
}

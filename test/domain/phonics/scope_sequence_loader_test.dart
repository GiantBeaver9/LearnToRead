// Pins the API of lib/domain/phonics/scope_sequence_loader.dart (PRD §8
// Unit 2 pinned design: "a single ordered scope & sequence of PhonicsSkills
// ... stored as data (not code)"; ticket phonics-engine accept entry
// "Scope & sequence loads from data files (JSON) ... changing story order
// requires no code change"). This suite is authored before the
// implementation exists, so it is EXPECTED to fail to compile until
// scope_sequence_loader.dart is written with exactly the shapes exercised
// below.
//
// Pinned API surface this suite requires:
//   class StoryRef {
//     const StoryRef({required String id, required String levelId});
//     String id; String levelId;
//     // value-equal (==/hashCode) by (id, levelId), like the
//     // domain-models content types.
//   }
//   class PhonicsContent {
//     const PhonicsContent({
//       required List<Level> levels,
//       required Map<String, List<String>> heartWordsByLevelId,
//       required List<StoryRef> stories,
//     });
//     List<Level> levels;                          // getter
//     Map<String, List<String>> heartWordsByLevelId; // getter
//     List<StoryRef> stories;                        // getter
//   }
//   PhonicsContent loadPhonicsContent(String jsonText)
//
// loadPhonicsContent's pinned parsing contract (this is the contract this
// file locks in -- it is a builder-mechanical design choice this test suite
// makes, since the ticket explicitly leaves the *real* scope & sequence
// table to Unit 3/OQ-5 and only pins structure):
//   Root JSON object: { "levels": [...], "stories": [...] }.
//   Level object: { "id": String, "ordinal": int,
//                    "format": "sentence" | "multiSentence" | "paragraph",
//                    "vocabEnabled": bool,
//                    "heartWords": [String] (optional, defaults to []),
//                    "skills": [SkillObject] }.
//   SkillObject: { "id": String, "name": String, "sequenceOrder": int,
//                   "introducesGraphemes": [String] }.
//   Story object (top-level "stories" array entries):
//     { "id": String, "levelId": String } -- "levelId" must match some
//     level's "id".
//   `PhonicsContent.levels` is sorted ascending by `ordinal`, regardless of
//   the order levels appear in the JSON array (defensive).
//   `PhonicsContent.stories` preserves the *exact* order of the JSON
//   "stories" array -- that array order IS the global authored order the
//   rest of the engine trusts (PRD: "the next 3 uncompleted stories in
//   global authored order (which is level-ordered)"); the loader does not
//   re-derive or re-sort it from level ordinals.
//   `heartWordsByLevelId` maps every level's id to its "heartWords" list
//   (or [] if the key is absent).
//   Throws FormatException for: a missing "levels" or "stories" root key; a
//   level/skill/story object missing a required field; an unrecognized
//   "format" string; or a story whose "levelId" does not match any level's
//   "id"; or input that isn't valid JSON at all.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/phonics/scope_sequence_loader.dart';

String _readFixture(String name) =>
    File('test/domain/phonics/fixtures/$name').readAsStringSync();

void main() {
  group('loadPhonicsContent (positive: fixture_sequence.json)', () {
    late PhonicsContent content;

    setUpAll(() {
      content = loadPhonicsContent(_readFixture('fixture_sequence.json'));
    });

    test('parses all 4 levels ascending by ordinal', () {
      expect(content.levels, hasLength(4));
      expect(content.levels.map((l) => l.id).toList(),
          ['level-1', 'level-2', 'level-3', 'level-4']);
      expect(content.levels.map((l) => l.ordinal).toList(), [1, 2, 3, 4]);
    });

    test('parses each level\'s pinned format and vocabEnabled', () {
      expect(
        content.levels.map((l) => l.format).toList(),
        [
          LevelFormat.sentence,
          LevelFormat.sentence,
          LevelFormat.multiSentence,
          LevelFormat.paragraph,
        ],
      );
      expect(
        content.levels.map((l) => l.vocabEnabled).toList(),
        [false, false, false, true],
      );
    });

    test('parses per-level skills with sequenceOrder and introducesGraphemes', () {
      final level1 = content.levels.firstWhere((l) => l.id == 'level-1');
      expect(level1.newSkills, hasLength(1));
      expect(level1.newSkills.single.id, 'skill-cvc-short-a');
      expect(level1.newSkills.single.sequenceOrder, 1);
      expect(level1.newSkills.single.introducesGraphemes, ['a']);

      final level4 = content.levels.firstWhere((l) => l.id == 'level-4');
      expect(level4.newSkills.single.introducesGraphemes, ['a_e']);
    });

    test('parses per-level heart word lists', () {
      expect(content.heartWordsByLevelId['level-1'], ['the', 'a']);
      expect(content.heartWordsByLevelId['level-2'], ['said', 'was']);
      expect(content.heartWordsByLevelId['level-3'], ['they']);
      expect(content.heartWordsByLevelId['level-4'], ['friend']);
    });

    test('parses stories in exact global authored JSON order', () {
      expect(
        content.stories.map((s) => s.id).toList(),
        [
          'story-1-1', 'story-1-2',
          'story-2-1', 'story-2-2',
          'story-3-1', 'story-3-2',
          'story-4-1', 'story-4-2', 'story-4-3',
        ],
      );
    });

    test('each story carries the levelId it was authored under', () {
      expect(
        content.stories.firstWhere((s) => s.id == 'story-3-2').levelId,
        'level-3',
      );
      expect(
        content.stories.firstWhere((s) => s.id == 'story-4-1').levelId,
        'level-4',
      );
    });
  });

  group('loadPhonicsContent (positive: alternate_sequence.json loads independently)', () {
    test('parses a differently-shaped scope & sequence with no code change', () {
      final content = loadPhonicsContent(_readFixture('alternate_sequence.json'));
      expect(content.levels.map((l) => l.id).toList(),
          ['alt-level-1', 'alt-level-2', 'alt-level-3']);
      expect(content.stories, hasLength(7));
      expect(content.stories.map((s) => s.id).toList(), [
        'alt-story-1-1', 'alt-story-1-2', 'alt-story-1-3', 'alt-story-1-4',
        'alt-story-2-1', 'alt-story-2-2',
        'alt-story-3-1',
      ]);
    });
  });

  group('loadPhonicsContent (data-driven: fixture swap needs no code change)', () {
    test('the same loader function produces structurally different content for each fixture', () {
      final fixtureContent = loadPhonicsContent(_readFixture('fixture_sequence.json'));
      final alternateContent = loadPhonicsContent(_readFixture('alternate_sequence.json'));

      expect(fixtureContent.levels.length, isNot(alternateContent.levels.length));
      expect(fixtureContent.stories.length, isNot(alternateContent.stories.length));
      expect(
        fixtureContent.stories.map((s) => s.id).toSet(),
        isNot(alternateContent.stories.map((s) => s.id).toSet()),
      );
    });
  });

  group('loadPhonicsContent (negative: malformed input)', () {
    test('rejects input that is not valid JSON at all', () {
      expect(() => loadPhonicsContent('not json'), throwsA(isA<FormatException>()));
    });

    test('rejects a root object missing "levels"', () {
      const json = '{"stories": []}';
      expect(() => loadPhonicsContent(json), throwsA(isA<FormatException>()));
    });

    test('rejects a root object missing "stories"', () {
      const json = '{"levels": []}';
      expect(() => loadPhonicsContent(json), throwsA(isA<FormatException>()));
    });

    test('rejects a level object missing "ordinal"', () {
      const json = '''
      {
        "levels": [
          {"id": "level-1", "format": "sentence", "vocabEnabled": false, "skills": []}
        ],
        "stories": []
      }
      ''';
      expect(() => loadPhonicsContent(json), throwsA(isA<FormatException>()));
    });

    test('rejects a level with an unrecognized "format" string', () {
      const json = '''
      {
        "levels": [
          {"id": "level-1", "ordinal": 1, "format": "bogus-format", "vocabEnabled": false, "skills": []}
        ],
        "stories": []
      }
      ''';
      expect(() => loadPhonicsContent(json), throwsA(isA<FormatException>()));
    });

    test('rejects a story whose levelId matches no level', () {
      const json = '''
      {
        "levels": [
          {"id": "level-1", "ordinal": 1, "format": "sentence", "vocabEnabled": false, "skills": []}
        ],
        "stories": [
          {"id": "story-1", "levelId": "no-such-level"}
        ]
      }
      ''';
      expect(() => loadPhonicsContent(json), throwsA(isA<FormatException>()));
    });

    test('rejects a skill object missing "introducesGraphemes"', () {
      const json = '''
      {
        "levels": [
          {
            "id": "level-1", "ordinal": 1, "format": "sentence", "vocabEnabled": false,
            "skills": [{"id": "skill-1", "name": "Skill 1", "sequenceOrder": 1}]
          }
        ],
        "stories": []
      }
      ''';
      expect(() => loadPhonicsContent(json), throwsA(isA<FormatException>()));
    });
  });

  group('loadPhonicsContent (edge cases)', () {
    test('levels out of ordinal order in the raw JSON are still sorted ascending', () {
      const json = '''
      {
        "levels": [
          {"id": "level-3", "ordinal": 3, "format": "multiSentence", "vocabEnabled": false, "skills": []},
          {"id": "level-1", "ordinal": 1, "format": "sentence", "vocabEnabled": false, "skills": []},
          {"id": "level-2", "ordinal": 2, "format": "sentence", "vocabEnabled": false, "skills": []}
        ],
        "stories": []
      }
      ''';
      final content = loadPhonicsContent(json);
      expect(content.levels.map((l) => l.id).toList(), ['level-1', 'level-2', 'level-3']);
    });

    test('a level with no "heartWords" key defaults to an empty list', () {
      const json = '''
      {
        "levels": [
          {"id": "level-1", "ordinal": 1, "format": "sentence", "vocabEnabled": false, "skills": []}
        ],
        "stories": []
      }
      ''';
      final content = loadPhonicsContent(json);
      expect(content.heartWordsByLevelId['level-1'], isEmpty);
    });

    test('a level with an empty "skills" array parses with zero newSkills', () {
      const json = '''
      {
        "levels": [
          {"id": "level-1", "ordinal": 1, "format": "sentence", "vocabEnabled": false, "skills": []}
        ],
        "stories": []
      }
      ''';
      final content = loadPhonicsContent(json);
      expect(content.levels.single.newSkills, isEmpty);
    });

    test('a scope & sequence with zero stories parses to an empty story list, not an error', () {
      const json = '''
      {
        "levels": [
          {"id": "level-1", "ordinal": 1, "format": "sentence", "vocabEnabled": false, "skills": []}
        ],
        "stories": []
      }
      ''';
      final content = loadPhonicsContent(json);
      expect(content.stories, isEmpty);
    });
  });

  group('StoryRef (positive: value equality)', () {
    test('two StoryRefs built from equal (id, levelId) are value-equal', () {
      const a = StoryRef(id: 'story-1', levelId: 'level-1');
      const b = StoryRef(id: 'story-1', levelId: 'level-1');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('StoryRefs with different ids are not equal', () {
      const a = StoryRef(id: 'story-1', levelId: 'level-1');
      const b = StoryRef(id: 'story-2', levelId: 'level-1');
      expect(a, isNot(equals(b)));
    });
  });
}

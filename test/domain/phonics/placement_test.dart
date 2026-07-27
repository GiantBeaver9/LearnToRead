// Pins the API of lib/domain/phonics/placement.dart (PRD §8 Unit 2 pinned
// design: "Profile start level from age band: 5-6 -> level 1; 7-8 -> first
// multiSentence level; 9-10 -> first paragraph level. Parent can override
// in parent corner."; ticket phonics-engine accept entry "Age-band
// placement ... parent override supported as an input"). This suite is
// authored before the implementation exists, so it is EXPECTED to fail to
// compile until placement.dart is written with exactly the shape exercised
// below.
//
// Pinned API surface this suite requires:
//   String placeStartingLevel({
//     required AgeBand ageBand,
//     required PhonicsContent content,
//     String? parentOverrideLevelId,
//   })
//
// Pinned placement contract (this file locks it in):
//   - `content.levels` is assumed ascending-ordinal-sorted, as guaranteed by
//     `loadPhonicsContent` (scope_sequence_loader.dart).
//   - `parentOverrideLevelId`, when non-null, wins outright over ageBand: if
//     it matches some level's id in `content.levels`, that id is returned
//     verbatim; if it matches no level, throws ArgumentError.
//   - Else, by ageBand:
//       AgeBand.fiveToSix    -> the id of `content.levels.first` (lowest
//                                ordinal, "level 1").
//       AgeBand.sevenToEight -> the id of the first level (ascending
//                                ordinal order) with
//                                `format == LevelFormat.multiSentence`;
//                                throws StateError if no such level exists.
//       AgeBand.nineToTen    -> the id of the first level (ascending
//                                ordinal order) with
//                                `format == LevelFormat.paragraph`; throws
//                                StateError if no such level exists.
//   - Throws StateError if `content.levels` is empty, regardless of
//     ageBand/override.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/domain/phonics/placement.dart';
import 'package:learn_to_read/domain/phonics/scope_sequence_loader.dart';

String _readFixture(String name) =>
    File('test/domain/phonics/fixtures/$name').readAsStringSync();

void main() {
  late PhonicsContent content;

  setUpAll(() {
    content = loadPhonicsContent(_readFixture('fixture_sequence.json'));
  });

  group('placeStartingLevel (positive: age-band defaults)', () {
    test('5-6 places at level 1 (lowest ordinal)', () {
      expect(
        placeStartingLevel(ageBand: AgeBand.fiveToSix, content: content),
        'level-1',
      );
    });

    test('7-8 places at the first multiSentence level', () {
      expect(
        placeStartingLevel(ageBand: AgeBand.sevenToEight, content: content),
        'level-3',
      );
    });

    test('9-10 places at the first paragraph level', () {
      expect(
        placeStartingLevel(ageBand: AgeBand.nineToTen, content: content),
        'level-4',
      );
    });
  });

  group('placeStartingLevel (positive: parent override)', () {
    test('override wins over a 5-6 band, landing on a higher level', () {
      expect(
        placeStartingLevel(
          ageBand: AgeBand.fiveToSix,
          content: content,
          parentOverrideLevelId: 'level-4',
        ),
        'level-4',
      );
    });

    test('override wins over a 9-10 band, landing on a lower level', () {
      expect(
        placeStartingLevel(
          ageBand: AgeBand.nineToTen,
          content: content,
          parentOverrideLevelId: 'level-1',
        ),
        'level-1',
      );
    });

    test('override to the same level the band would have picked is a no-op', () {
      expect(
        placeStartingLevel(
          ageBand: AgeBand.sevenToEight,
          content: content,
          parentOverrideLevelId: 'level-3',
        ),
        'level-3',
      );
    });
  });

  group('placeStartingLevel (negative)', () {
    test('an override levelId absent from content.levels throws ArgumentError', () {
      expect(
        () => placeStartingLevel(
          ageBand: AgeBand.fiveToSix,
          content: content,
          parentOverrideLevelId: 'no-such-level',
        ),
        throwsArgumentError,
      );
    });

    test('an empty-string override throws ArgumentError', () {
      expect(
        () => placeStartingLevel(
          ageBand: AgeBand.fiveToSix,
          content: content,
          parentOverrideLevelId: '',
        ),
        throwsArgumentError,
      );
    });
  });

  group('placeStartingLevel (edge cases)', () {
    test('a single-level content places every band-eligible request at that level', () {
      const json = '''
      {
        "levels": [
          {"id": "only-level", "ordinal": 1, "format": "sentence", "vocabEnabled": false, "skills": []}
        ],
        "stories": []
      }
      ''';
      final singleLevelContent = loadPhonicsContent(json);
      expect(
        placeStartingLevel(ageBand: AgeBand.fiveToSix, content: singleLevelContent),
        'only-level',
      );
    });

    test('7-8 throws StateError when content has no multiSentence level', () {
      const json = '''
      {
        "levels": [
          {"id": "s1", "ordinal": 1, "format": "sentence", "vocabEnabled": false, "skills": []},
          {"id": "p1", "ordinal": 2, "format": "paragraph", "vocabEnabled": true, "skills": []}
        ],
        "stories": []
      }
      ''';
      final noMultiSentenceContent = loadPhonicsContent(json);
      expect(
        () => placeStartingLevel(ageBand: AgeBand.sevenToEight, content: noMultiSentenceContent),
        throwsStateError,
      );
    });

    test('9-10 throws StateError when content has no paragraph level', () {
      const json = '''
      {
        "levels": [
          {"id": "s1", "ordinal": 1, "format": "sentence", "vocabEnabled": false, "skills": []},
          {"id": "m1", "ordinal": 2, "format": "multiSentence", "vocabEnabled": false, "skills": []}
        ],
        "stories": []
      }
      ''';
      final noParagraphContent = loadPhonicsContent(json);
      expect(
        () => placeStartingLevel(ageBand: AgeBand.nineToTen, content: noParagraphContent),
        throwsStateError,
      );
    });

    test('an empty content.levels throws StateError regardless of band', () {
      const json = '{"levels": [], "stories": []}';
      final emptyContent = loadPhonicsContent(json);
      expect(
        () => placeStartingLevel(ageBand: AgeBand.fiveToSix, content: emptyContent),
        throwsStateError,
      );
    });

    test('placement follows swapped fixture data with no code change (alternate_sequence.json)', () {
      final alternateContent = loadPhonicsContent(_readFixture('alternate_sequence.json'));
      expect(
        placeStartingLevel(ageBand: AgeBand.fiveToSix, content: alternateContent),
        'alt-level-1',
      );
      expect(
        placeStartingLevel(ageBand: AgeBand.sevenToEight, content: alternateContent),
        'alt-level-2',
      );
      expect(
        placeStartingLevel(ageBand: AgeBand.nineToTen, content: alternateContent),
        'alt-level-3',
      );
    });
  });
}

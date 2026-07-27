// Pins the API of lib/pipeline/cumulative_grapheme_set.dart (PRD §5
// PhonicsSkill.introducesGraphemes: "the decodability linter's cumulative
// grapheme set at level N is the union over all skills of levels <= N --
// one shared type, one schema"; §8 Unit 3 pinned design: "rejects any story
// containing a word not decodable from the cumulative grapheme set at its
// level"; ticket decodability-linter accept entry 3). This suite is
// authored before the implementation exists, so it is EXPECTED to fail to
// compile until cumulative_grapheme_set.dart is written with exactly the
// shape exercised below.
//
// Pinned API surface this suite requires:
//   Set<String> cumulativeGraphemeSet({
//     required List<Level> levels,
//     required String levelId,
//   })
//
// Contract this suite locks in (builder-mechanical design choices made by
// this test suite, since the ticket leaves exact shapes to the builder and
// only pins behavior):
//  - Resolves `levelId` against `levels` by `Level.id`; the *ordinal* of
//    that resolved level (not its position in the `levels` list) is the
//    comparison bound N.
//  - Returns the union, as a `Set<String>`, of `skill.introducesGraphemes`
//    over every skill (`level.newSkills`) of every level in `levels` whose
//    `ordinal <= N` -- including the target level itself.
//  - Grapheme units are opaque strings: a digraph ("sh") or a silent-e
//    pattern ("a_e") is one element of the set, never decomposed into its
//    component letters.
//  - Result does not depend on the order `levels` are passed in (only on
//    each level's own `ordinal` field).
//  - Duplicate graphemes -- whether repeated across two skills of the same
//    level or reintroduced by a later level -- collapse to one set element.
//  - Throws `ArgumentError` when no level in `levels` has `id == levelId`
//    (including when `levels` is empty).
//
// Consumes only content_models.dart's `Level`/`PhonicsSkill` -- the one
// shared domain-models schema -- never a locally redefined shape (ticket
// notes: "consume the merged domain-models types from lib/domain/, do not
// define your own").

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/pipeline/cumulative_grapheme_set.dart';

PhonicsSkill _skill(
  String id,
  String name,
  int order,
  List<String> graphemes,
) => PhonicsSkill(
  id: id,
  name: name,
  sequenceOrder: order,
  introducesGraphemes: graphemes,
);

// A 4-level fixture scope & sequence, mirroring the decodability-linter
// ticket's example words ("ship" -> digraph sh, "cake" -> silent-e a_e).
final _level1 = Level(
  id: 'level-1',
  ordinal: 1,
  format: LevelFormat.sentence,
  vocabEnabled: false,
  newSkills: [
    _skill('skill.consonants-1', 'starter consonants', 1, [
      'c',
      't',
      'p',
      'n',
      's',
      'd',
    ]),
    _skill('skill.short-a', 'short a', 2, ['a']),
  ],
);
final _level2 = Level(
  id: 'level-2',
  ordinal: 2,
  format: LevelFormat.sentence,
  vocabEnabled: false,
  newSkills: [
    _skill('skill.digraph-sh', 'digraph sh', 3, ['sh']),
    _skill('skill.short-i', 'short i', 4, ['i']),
  ],
);
final _level3 = Level(
  id: 'level-3',
  ordinal: 3,
  format: LevelFormat.multiSentence,
  vocabEnabled: false,
  newSkills: [
    _skill('skill.silent-e', 'silent e (a_e)', 5, ['a_e']),
    _skill('skill.k', 'k', 6, ['k']),
  ],
);
final _level4 = Level(
  id: 'level-4',
  ordinal: 4,
  format: LevelFormat.paragraph,
  vocabEnabled: true,
  newSkills: const [], // introduces nothing new
);

final _allLevels = [_level1, _level2, _level3, _level4];

void main() {
  group('cumulativeGraphemeSet (positive: cumulative union)', () {
    test('level 1 is just its own skills\' graphemes', () {
      final set = cumulativeGraphemeSet(levels: _allLevels, levelId: 'level-1');
      expect(set, {'c', 't', 'p', 'n', 's', 'd', 'a'});
    });

    test(
      'level 2 unions level 1 with its own skills, including the digraph "sh" as one unit',
      () {
        final set = cumulativeGraphemeSet(
          levels: _allLevels,
          levelId: 'level-2',
        );
        expect(set, {'c', 't', 'p', 'n', 's', 'd', 'a', 'sh', 'i'});
        expect(set, contains('sh'));
        expect(
          set.contains('h'),
          isFalse,
          reason: 'digraph "sh" must not be decomposed into "s" and "h"',
        );
      },
    );

    test(
      'level 3 unions levels 1-2 with the silent-e pattern "a_e" as one unit, not split into "a" and "e"',
      () {
        final set = cumulativeGraphemeSet(
          levels: _allLevels,
          levelId: 'level-3',
        );
        expect(set, {'c', 't', 'p', 'n', 's', 'd', 'a', 'sh', 'i', 'a_e', 'k'});
        expect(
          set.contains('e'),
          isFalse,
          reason:
              'silent-e pattern "a_e" must not be decomposed into "a" and "e"',
        );
      },
    );

    test(
      'level 4 (no new skills) still carries every earlier level\'s graphemes forward',
      () {
        final set = cumulativeGraphemeSet(
          levels: _allLevels,
          levelId: 'level-4',
        );
        expect(
          set,
          cumulativeGraphemeSet(levels: _allLevels, levelId: 'level-3'),
        );
      },
    );

    test('result does not depend on the order `levels` is passed in', () {
      final forward = cumulativeGraphemeSet(
        levels: _allLevels,
        levelId: 'level-3',
      );
      final shuffled = cumulativeGraphemeSet(
        levels: [_level4, _level1, _level3, _level2],
        levelId: 'level-3',
      );
      final reversed = cumulativeGraphemeSet(
        levels: _allLevels.reversed.toList(),
        levelId: 'level-3',
      );
      expect(shuffled, forward);
      expect(reversed, forward);
    });
  });

  group('cumulativeGraphemeSet (negative)', () {
    test('throws ArgumentError when levelId matches no level', () {
      expect(
        () => cumulativeGraphemeSet(
          levels: _allLevels,
          levelId: 'level-does-not-exist',
        ),
        throwsArgumentError,
      );
    });

    test('throws ArgumentError when `levels` is empty', () {
      expect(
        () => cumulativeGraphemeSet(levels: const [], levelId: 'level-1'),
        throwsArgumentError,
      );
    });
  });

  group('cumulativeGraphemeSet (edge)', () {
    test(
      'duplicate graphemes -- within one level\'s skills and across levels -- collapse to one set element',
      () {
        final levelA = Level(
          id: 'a',
          ordinal: 1,
          format: LevelFormat.sentence,
          vocabEnabled: false,
          newSkills: [
            _skill('skA1', 'skill A1', 1, ['x', 'y']),
            _skill('skA2', 'skill A2', 2, [
              'y',
              'z',
            ]), // 'y' repeated within level a
          ],
        );
        final levelB = Level(
          id: 'b',
          ordinal: 2,
          format: LevelFormat.sentence,
          vocabEnabled: false,
          newSkills: [
            _skill('skB1', 'skill B1', 3, [
              'x',
              'w',
            ]), // 'x' repeated from level a
          ],
        );
        final set = cumulativeGraphemeSet(
          levels: [levelA, levelB],
          levelId: 'b',
        );
        expect(set, {'x', 'y', 'z', 'w'});
      },
    );

    test('a level with an empty skills list contributes nothing new', () {
      final levelEmpty = Level(
        id: 'empty',
        ordinal: 1,
        format: LevelFormat.sentence,
        vocabEnabled: false,
        newSkills: const [],
      );
      final set = cumulativeGraphemeSet(levels: [levelEmpty], levelId: 'empty');
      expect(set, isEmpty);
    });

    test(
      'a single-level `levels` list returns exactly that level\'s own graphemes, regardless of its ordinal value',
      () {
        final lonely = Level(
          id: 'lonely',
          ordinal: 42,
          format: LevelFormat.sentence,
          vocabEnabled: false,
          newSkills: [
            _skill('sk', 'sk', 1, ['q', 'z']),
          ],
        );
        final set = cumulativeGraphemeSet(levels: [lonely], levelId: 'lonely');
        expect(set, {'q', 'z'});
      },
    );
  });
}

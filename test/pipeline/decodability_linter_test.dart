// Pins the API of lib/pipeline/decodability_linter.dart (PRD §8 Unit 3
// pinned design: "the decodability linter ... rejects any story containing
// a word not decodable from the cumulative grapheme set at its level,
// unless whitelisted as a heart word for that level"; §6 "a story at level
// N may only use words decodable with skills introduced at levels <= N,
// plus that level's explicitly-tagged heart words"; §7 R5: "every word
// checked against the level's cumulative grapheme set"; §8 Unit 14: pack
// build "decodability linter skips twisters"; §5
// PhonicsSkill.introducesGraphemes, the one shared cumulative-set schema).
// This suite is authored before the implementation exists, so it is
// EXPECTED to fail to compile until decodability_linter.dart is written
// with exactly the shapes exercised below.
//
// Pinned API surface this suite requires:
//   enum DecodabilityFindingKind { outOfLevelWord, wordCountBounds, pageCountBounds }
//   class DecodabilityFinding {
//     DecodabilityFindingKind kind;
//     String storyId;
//     String levelId;
//     String? word;                     // set for outOfLevelWord findings, null otherwise
//     List<String> outOfLevelGraphemes; // set for outOfLevelWord findings, [] otherwise
//     String message;                   // human-readable, non-empty
//   }
//   List<DecodabilityFinding> lintStory(
//     Story story, {
//     required List<Level> levels,
//     required Map<String, List<String>> heartWordsByLevelId,
//   })
//   List<DecodabilityFinding> lintTwister(
//     TongueTwister twister, {
//     required List<Level> levels,
//     required Map<String, List<String>> heartWordsByLevelId,
//   })
//
// Contract this suite locks in (builder-mechanical design choices made by
// this test suite, since the ticket leaves exact shapes to the builder and
// only pins behavior):
//  - lintStory resolves `story.levelId` against `levels` by `Level.id`;
//    throws ArgumentError if no level in `levels` has that id.
//  - Cumulative grapheme set at the story's level = union of
//    `skill.introducesGraphemes` over every skill of every level in
//    `levels` whose ordinal <= the story level's ordinal.
//  - Cumulative heart-word set at the story's level = union of
//    `heartWordsByLevelId[level.id]` (defaulting to [] when a level has no
//    entry in the map) over every level whose ordinal <= the story level's
//    ordinal -- so a heart word tagged at level N is honored at level N and
//    above, not below (mirrors the grapheme cumulative-union rule).
//  - A word is decodable iff `word.text` is in the cumulative heart-word
//    set (which short-circuits the grapheme check entirely), OR every
//    grapheme in its `graphemePhonemeMap`'s `graphemes` entries is a member
//    of the cumulative grapheme set.
//  - Each undecodable word produces exactly one `outOfLevelWord` finding
//    naming `storyId`, `levelId`, `word` (== WordToken.text), and
//    `outOfLevelGraphemes` (the grapheme units from that word's
//    `graphemePhonemeMap` absent from the cumulative grapheme set).
//  - A-8 length bounds are additional, independent findings checked against
//    the resolved level's `format`:
//      * `LevelFormat.sentence`: total word count across all
//        pages/sentences must be in
//        [kSentenceLevelMinWords, kSentenceLevelMaxWords] inclusive, else
//        one `wordCountBounds` finding.
//      * `LevelFormat.paragraph`: total word count must be in
//        [kParagraphLevelMinWords, kParagraphLevelMaxWords] inclusive (else
//        one `wordCountBounds` finding), AND `story.pages.length` must be
//        in [kParagraphLevelMinPages, kParagraphLevelMaxPages] inclusive
//        (else one `pageCountBounds` finding) -- independently, both may
//        fire on the same story.
//      * `LevelFormat.multiSentence`: no length bound is defined in the
//        domain models (content_models.dart defines only sentence- and
//        paragraph-level bound constants), so no bounds finding is ever
//        produced for a multiSentence-format story.
//  - Findings are aggregated across the whole story (never fail-fast on the
//    first problem), matching this codebase's existing
//    PackManifestValidationResult convention.
//  - lintTwister always returns `const []`: twisters are wholly exempt from
//    both decodability and length-bounds linting (Unit 14 pinned,
//    "modeled-first content may use above-level words"), even a twister
//    whose `levelId` cannot be resolved against `levels` at all.

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/pipeline/decodability_linter.dart';

// ---------------------------------------------------------------------------
// Fixture scope & sequence (shared shape with cumulative_grapheme_set_test.dart,
// but kept file-local per this codebase's existing test-fixture convention).
// ---------------------------------------------------------------------------

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
  newSkills: const [],
);

final _allLevels = [_level1, _level2, _level3, _level4];

// ---------------------------------------------------------------------------
// Word fixtures.
// ---------------------------------------------------------------------------

WordToken _word(
  String text,
  List<({String graphemes, String phonemeId})> map,
) => WordToken(
  text: text,
  graphemePhonemeMap: map,
  pronunciationAudioRef: 'audio/words/$text.wav',
);

/// Builds a word decodable purely from level-1's single-letter graphemes
/// (c, t, p, n, s, d, a): every character of `text` must be one of those
/// letters. Used as inert filler for tests that are really about word-count
/// bounds, not decodability.
WordToken _lvl1Word(String text) => _word(
  text,
  text.split('').map((ch) => (graphemes: ch, phonemeId: 'X')).toList(),
);

final _wShip = _word('ship', const [
  (graphemes: 'sh', phonemeId: 'SH'),
  (graphemes: 'i', phonemeId: 'IH'),
  (graphemes: 'p', phonemeId: 'P'),
]);
final _wCake = _word('cake', const [
  (graphemes: 'c', phonemeId: 'K'),
  (graphemes: 'a_e', phonemeId: 'EY'),
  (graphemes: 'k', phonemeId: 'K'),
]);
final _wSaid = _word('said', const [
  (graphemes: 's', phonemeId: 'S'),
  (graphemes: 'ai', phonemeId: 'EH'),
  (graphemes: 'd', phonemeId: 'D'),
]);

// ---------------------------------------------------------------------------
// Story fixtures.
// ---------------------------------------------------------------------------

Story _singleSentenceStory({
  required String id,
  required String levelId,
  required List<WordToken> words,
}) => Story(
  id: id,
  levelId: levelId,
  title: 'Test story',
  pages: [
    Page(
      sentences: [
        Sentence(words: words, narrationAudioRef: 'audio/narration/$id.wav'),
      ],
    ),
  ],
  riveAnimationRef: 'rive/$id.riv',
  celebrationAudioRef: 'audio/celebration/$id.wav',
  collectibleRef: 'collectible.$id',
  skillsExercised: const [],
  packId: 'pack.test',
  contentVersion: '1',
);

Story _paragraphStory({
  required String id,
  required String levelId,
  required List<int> wordsPerPage,
}) => Story(
  id: id,
  levelId: levelId,
  title: 'Test paragraph story',
  pages: wordsPerPage
      .map(
        (n) => Page(
          sentences: [
            Sentence(words: List.generate(n, (_) => _lvl1Word('cat'))),
          ],
        ),
      )
      .toList(),
  riveAnimationRef: 'rive/$id.riv',
  celebrationAudioRef: 'audio/celebration/$id.wav',
  collectibleRef: 'collectible.$id',
  skillsExercised: const [],
  packId: 'pack.test',
  contentVersion: '1',
);

List<DecodabilityFinding> _wordFindings(List<DecodabilityFinding> findings) =>
    findings
        .where((f) => f.kind == DecodabilityFindingKind.outOfLevelWord)
        .toList();

void main() {
  group('lintStory (positive+negative: out-of-level word rejection, accept 1)', () {
    test(
      'rejects a story with an out-of-level word, naming the story id, word, and out-of-level graphemes',
      () {
        final story = _singleSentenceStory(
          id: 'story.ship-1',
          levelId: 'level-1',
          words: [_lvl1Word('cat'), _wShip, _lvl1Word('sat')],
        );

        final findings = lintStory(
          story,
          levels: _allLevels,
          heartWordsByLevelId: const {},
        );
        final wordFindings = _wordFindings(findings);

        expect(wordFindings, hasLength(1));
        final finding = wordFindings.single;
        expect(finding.kind, DecodabilityFindingKind.outOfLevelWord);
        expect(finding.storyId, 'story.ship-1');
        expect(finding.levelId, 'level-1');
        expect(finding.word, 'ship');
        expect(finding.outOfLevelGraphemes.toSet(), {'sh', 'i'});
        expect(finding.message, isNotEmpty);
      },
    );

    test(
      'a fully decodable story at level-1 produces zero out-of-level-word findings',
      () {
        final story = _singleSentenceStory(
          id: 'story.clean',
          levelId: 'level-1',
          words: [_lvl1Word('cat'), _lvl1Word('sat'), _lvl1Word('pan')],
        );

        final findings = lintStory(
          story,
          levels: _allLevels,
          heartWordsByLevelId: const {},
        );

        expect(_wordFindings(findings), isEmpty);
      },
    );
  });

  group(
    'lintStory (positive: accept 2 -- both ways the same story is later accepted)',
    () {
      test(
        '(a) the same story passes once "ship" is whitelisted as a heart word at level-1',
        () {
          final story = _singleSentenceStory(
            id: 'story.ship-1',
            levelId: 'level-1',
            words: [_lvl1Word('cat'), _wShip, _lvl1Word('sat')],
          );

          final findings = lintStory(
            story,
            levels: _allLevels,
            heartWordsByLevelId: const {
              'level-1': ['ship'],
            },
          );

          expect(_wordFindings(findings), isEmpty);
        },
      );

      test(
        '(b) the same story passes once level-2 (>= level-1) introduces the missing graphemes "sh"/"i"',
        () {
          final story = _singleSentenceStory(
            id: 'story.ship-1',
            levelId: 'level-2',
            words: [_lvl1Word('cat'), _wShip, _lvl1Word('sat')],
          );

          final findings = lintStory(
            story,
            levels: _allLevels,
            heartWordsByLevelId: const {},
          );

          expect(_wordFindings(findings), isEmpty);
        },
      );
    },
  );

  group(
    'lintStory (positive+negative: accept 3 -- digraph & silent-e decomposition)',
    () {
      test(
        '"cake" is rejected before level-3 (silent-e pattern "a_e" and "k" not yet introduced)',
        () {
          final story = _singleSentenceStory(
            id: 'story.cake-early',
            levelId: 'level-1',
            words: [_lvl1Word('cat'), _wCake, _lvl1Word('sat')],
          );

          final findings = lintStory(
            story,
            levels: _allLevels,
            heartWordsByLevelId: const {},
          );
          final wordFindings = _wordFindings(findings);

          expect(wordFindings, hasLength(1));
          expect(wordFindings.single.word, 'cake');
          expect(wordFindings.single.outOfLevelGraphemes.toSet(), {'a_e', 'k'});
        },
      );

      test(
        '"cake" is accepted at level-3, where "a_e" and "k" enter the cumulative set',
        () {
          final story = _singleSentenceStory(
            id: 'story.cake-late',
            levelId: 'level-3',
            words: [_wCake],
          );

          final findings = lintStory(
            story,
            levels: _allLevels,
            heartWordsByLevelId: const {},
          );

          expect(_wordFindings(findings), isEmpty);
        },
      );
    },
  );

  group(
    'lintStory (edge: accept 4 -- heart words are honored at their level and above, not below)',
    () {
      const heartWords = {
        'level-2': ['said'],
      };

      test('"said" is rejected below its tagged level (level-1 < level-2)', () {
        final story = _singleSentenceStory(
          id: 'story.said-below',
          levelId: 'level-1',
          words: [_lvl1Word('cat'), _wSaid, _lvl1Word('sat')],
        );

        final findings = lintStory(
          story,
          levels: _allLevels,
          heartWordsByLevelId: heartWords,
        );
        final wordFindings = _wordFindings(findings);

        expect(wordFindings, hasLength(1));
        expect(wordFindings.single.word, 'said');
        expect(wordFindings.single.outOfLevelGraphemes.toSet(), {'ai'});
      });

      test('"said" is accepted exactly at its tagged level (level-2)', () {
        final story = _singleSentenceStory(
          id: 'story.said-at',
          levelId: 'level-2',
          words: [_lvl1Word('cat'), _wSaid, _lvl1Word('sat')],
        );

        final findings = lintStory(
          story,
          levels: _allLevels,
          heartWordsByLevelId: heartWords,
        );

        expect(_wordFindings(findings), isEmpty);
      });

      test(
        '"said" is accepted above its tagged level (level-3 > level-2, cumulative)',
        () {
          final story = _singleSentenceStory(
            id: 'story.said-above',
            levelId: 'level-3',
            words: [_wSaid],
          );

          final findings = lintStory(
            story,
            levels: _allLevels,
            heartWordsByLevelId: heartWords,
          );

          expect(_wordFindings(findings), isEmpty);
        },
      );

      test(
        'a level with no entry at all in heartWordsByLevelId defaults to no heart words for that level',
        () {
          final story = _singleSentenceStory(
            id: 'story.said-no-entry',
            levelId: 'level-2',
            words: [_lvl1Word('cat'), _wSaid, _lvl1Word('sat')],
          );

          // heartWordsByLevelId has entries for other levels, but none for
          // 'level-2' -- must default to [] for 'level-2', not crash or
          // silently accept.
          final findings = lintStory(
            story,
            levels: _allLevels,
            heartWordsByLevelId: const {
              'level-1': ['someOtherWord'],
            },
          );

          expect(_wordFindings(findings), hasLength(1));
          expect(_wordFindings(findings).single.word, 'said');
        },
      );
    },
  );

  group('lintTwister (positive: accept 5 -- twisters are wholly exempt)', () {
    test('a twister with out-of-level words produces zero findings', () {
      final twister = TongueTwister(
        id: 'twister.1',
        levelId: 'level-1',
        words: [_wShip, _wCake, _wSaid],
        targetPhonemeId: kEnglishPhonemeIds.first,
        narrationAudioRef: 'audio/twisters/1.wav',
        packId: 'pack.test',
      );

      final findings = lintTwister(
        twister,
        levels: _allLevels,
        heartWordsByLevelId: const {},
      );

      expect(findings, isEmpty);
    });

    test(
      'a twister whose levelId cannot even be resolved still produces zero findings (no throw)',
      () {
        final twister = TongueTwister(
          id: 'twister.2',
          levelId: 'level-does-not-exist',
          words: [_wShip],
          targetPhonemeId: kEnglishPhonemeIds.first,
          narrationAudioRef: 'audio/twisters/2.wav',
          packId: 'pack.test',
        );

        final findings = lintTwister(
          twister,
          levels: _allLevels,
          heartWordsByLevelId: const {},
        );

        expect(findings, isEmpty);
      },
    );

    test('a twister with zero words produces zero findings', () {
      final twister = TongueTwister(
        id: 'twister.3',
        levelId: 'level-1',
        words: const [],
        targetPhonemeId: kEnglishPhonemeIds.first,
        narrationAudioRef: 'audio/twisters/3.wav',
        packId: 'pack.test',
      );

      final findings = lintTwister(
        twister,
        levels: _allLevels,
        heartWordsByLevelId: const {},
      );

      expect(findings, isEmpty);
    });
  });

  group(
    'lintStory (positive+negative: accept 6 -- A-8 sentence-level word-count bounds)',
    () {
      List<DecodabilityFinding> boundsFindings(
        List<DecodabilityFinding> findings,
      ) => findings
          .where((f) => f.kind == DecodabilityFindingKind.wordCountBounds)
          .toList();

      test(
        'exactly kSentenceLevelMinWords (3) decodable words passes with zero findings',
        () {
          final story = _singleSentenceStory(
            id: 'story.sentence-min',
            levelId: 'level-1',
            words: [_lvl1Word('cat'), _lvl1Word('sat'), _lvl1Word('pan')],
          );
          expect(
            story.pages.single.sentences.single.words,
            hasLength(kSentenceLevelMinWords),
          );

          final findings = lintStory(
            story,
            levels: _allLevels,
            heartWordsByLevelId: const {},
          );

          expect(findings, isEmpty);
        },
      );

      test(
        'exactly kSentenceLevelMaxWords (8) decodable words passes with zero findings',
        () {
          final words = [
            _lvl1Word('cat'),
            _lvl1Word('sat'),
            _lvl1Word('pan'),
            _lvl1Word('tan'),
            _lvl1Word('nap'),
            _lvl1Word('tap'),
            _lvl1Word('can'),
            _lvl1Word('ant'),
          ];
          final story = _singleSentenceStory(
            id: 'story.sentence-max',
            levelId: 'level-1',
            words: words,
          );
          expect(words, hasLength(kSentenceLevelMaxWords));

          final findings = lintStory(
            story,
            levels: _allLevels,
            heartWordsByLevelId: const {},
          );

          expect(findings, isEmpty);
        },
      );

      test(
        'fewer than kSentenceLevelMinWords words produces a wordCountBounds finding',
        () {
          final story = _singleSentenceStory(
            id: 'story.sentence-too-few',
            levelId: 'level-1',
            words: [_lvl1Word('cat'), _lvl1Word('sat')],
          );

          final findings = lintStory(
            story,
            levels: _allLevels,
            heartWordsByLevelId: const {},
          );
          final bounds = boundsFindings(findings);

          expect(bounds, hasLength(1));
          expect(bounds.single.storyId, 'story.sentence-too-few');
          expect(bounds.single.levelId, 'level-1');
        },
      );

      test(
        'more than kSentenceLevelMaxWords words produces a wordCountBounds finding',
        () {
          final words = [
            _lvl1Word('cat'),
            _lvl1Word('sat'),
            _lvl1Word('pan'),
            _lvl1Word('tan'),
            _lvl1Word('nap'),
            _lvl1Word('tap'),
            _lvl1Word('can'),
            _lvl1Word('ant'),
            _lvl1Word('tad'),
          ];
          final story = _singleSentenceStory(
            id: 'story.sentence-too-many',
            levelId: 'level-1',
            words: words,
          );
          expect(words.length, greaterThan(kSentenceLevelMaxWords));

          final findings = lintStory(
            story,
            levels: _allLevels,
            heartWordsByLevelId: const {},
          );

          expect(boundsFindings(findings), hasLength(1));
        },
      );
    },
  );

  group(
    'lintStory (positive+negative: accept 6 -- A-8 paragraph-level word/page-count bounds)',
    () {
      List<DecodabilityFinding> wordBounds(
        List<DecodabilityFinding> findings,
      ) => findings
          .where((f) => f.kind == DecodabilityFindingKind.wordCountBounds)
          .toList();
      List<DecodabilityFinding> pageBounds(
        List<DecodabilityFinding> findings,
      ) => findings
          .where((f) => f.kind == DecodabilityFindingKind.pageCountBounds)
          .toList();

      test(
        'exactly kParagraphLevelMinWords (40) across 1 page passes with zero findings',
        () {
          final story = _paragraphStory(
            id: 'story.paragraph-min',
            levelId: 'level-4',
            wordsPerPage: [kParagraphLevelMinWords],
          );

          final findings = lintStory(
            story,
            levels: _allLevels,
            heartWordsByLevelId: const {},
          );

          expect(findings, isEmpty);
        },
      );

      test(
        'exactly kParagraphLevelMaxWords (90) across kParagraphLevelMaxPages (3) pages passes with zero findings',
        () {
          final perPage = kParagraphLevelMaxWords ~/ kParagraphLevelMaxPages;
          final remainder =
              kParagraphLevelMaxWords -
              (perPage * (kParagraphLevelMaxPages - 1));
          final wordsPerPage = [
            ...List.filled(kParagraphLevelMaxPages - 1, perPage),
            remainder,
          ];
          final story = _paragraphStory(
            id: 'story.paragraph-max',
            levelId: 'level-4',
            wordsPerPage: wordsPerPage,
          );
          expect(wordsPerPage.reduce((a, b) => a + b), kParagraphLevelMaxWords);
          expect(wordsPerPage, hasLength(kParagraphLevelMaxPages));

          final findings = lintStory(
            story,
            levels: _allLevels,
            heartWordsByLevelId: const {},
          );

          expect(findings, isEmpty);
        },
      );

      test(
        'fewer than kParagraphLevelMinWords words produces a wordCountBounds finding but not a pageCountBounds one',
        () {
          final story = _paragraphStory(
            id: 'story.paragraph-too-few-words',
            levelId: 'level-4',
            wordsPerPage: [kParagraphLevelMinWords - 1],
          );

          final findings = lintStory(
            story,
            levels: _allLevels,
            heartWordsByLevelId: const {},
          );

          expect(wordBounds(findings), hasLength(1));
          expect(pageBounds(findings), isEmpty);
        },
      );

      test(
        'more than kParagraphLevelMaxWords words produces a wordCountBounds finding but not a pageCountBounds one',
        () {
          final story = _paragraphStory(
            id: 'story.paragraph-too-many-words',
            levelId: 'level-4',
            wordsPerPage: [kParagraphLevelMaxWords + 1, 30, 30],
          );

          final findings = lintStory(
            story,
            levels: _allLevels,
            heartWordsByLevelId: const {},
          );

          expect(wordBounds(findings), hasLength(1));
          expect(pageBounds(findings), isEmpty);
        },
      );

      test(
        'more than kParagraphLevelMaxPages pages produces a pageCountBounds finding but not a wordCountBounds one',
        () {
          final story = _paragraphStory(
            id: 'story.paragraph-too-many-pages',
            levelId: 'level-4',
            wordsPerPage: List.filled(
              kParagraphLevelMaxPages + 1,
              11,
            ), // 11 * 4 = 44, within the word-count band
          );
          final totalWords = 11 * (kParagraphLevelMaxPages + 1);
          expect(
            totalWords,
            inInclusiveRange(kParagraphLevelMinWords, kParagraphLevelMaxWords),
          );

          final findings = lintStory(
            story,
            levels: _allLevels,
            heartWordsByLevelId: const {},
          );

          expect(pageBounds(findings), hasLength(1));
          expect(wordBounds(findings), isEmpty);
        },
      );
    },
  );

  group(
    'lintStory (edge: A-8 bounds do not apply to multiSentence-format levels)',
    () {
      test(
        'a single-word story at a multiSentence-format level produces no bounds findings at all',
        () {
          final story = _singleSentenceStory(
            id: 'story.multi-1word',
            levelId: 'level-3',
            words: [_wCake],
          );

          final findings = lintStory(
            story,
            levels: _allLevels,
            heartWordsByLevelId: const {},
          );

          expect(
            findings.where(
              (f) =>
                  f.kind == DecodabilityFindingKind.wordCountBounds ||
                  f.kind == DecodabilityFindingKind.pageCountBounds,
            ),
            isEmpty,
          );
        },
      );
    },
  );

  group('lintStory (edge: empty story)', () {
    test(
      'a paragraph-level story with zero pages produces both a wordCountBounds and a pageCountBounds finding',
      () {
        final story = Story(
          id: 'story.empty',
          levelId: 'level-4',
          title: 'Empty',
          pages: const [],
          riveAnimationRef: 'rive/empty.riv',
          celebrationAudioRef: 'audio/celebration/empty.wav',
          collectibleRef: 'collectible.empty',
          skillsExercised: const [],
          packId: 'pack.test',
          contentVersion: '1',
        );

        final findings = lintStory(
          story,
          levels: _allLevels,
          heartWordsByLevelId: const {},
        );

        expect(
          findings.where(
            (f) => f.kind == DecodabilityFindingKind.wordCountBounds,
          ),
          hasLength(1),
        );
        expect(
          findings.where(
            (f) => f.kind == DecodabilityFindingKind.pageCountBounds,
          ),
          hasLength(1),
        );
        expect(
          findings.where(
            (f) => f.kind == DecodabilityFindingKind.outOfLevelWord,
          ),
          isEmpty,
        );
      },
    );
  });

  group('lintStory (edge: unresolvable level)', () {
    test(
      'throws ArgumentError when story.levelId matches no level in `levels`',
      () {
        final story = _singleSentenceStory(
          id: 'story.orphan',
          levelId: 'level-does-not-exist',
          words: [_lvl1Word('cat'), _lvl1Word('sat'), _lvl1Word('pan')],
        );

        expect(
          () => lintStory(
            story,
            levels: _allLevels,
            heartWordsByLevelId: const {},
          ),
          throwsArgumentError,
        );
      },
    );
  });

  group('lintStory (edge: aggregation -- findings do not fail fast)', () {
    test(
      'a story with both an out-of-level word and a word-count violation reports both findings',
      () {
        final story = _singleSentenceStory(
          id: 'story.both-problems',
          levelId: 'level-1',
          words: [
            _wShip,
          ], // 1 word: below kSentenceLevelMinWords, and out-of-level at level-1
        );

        final findings = lintStory(
          story,
          levels: _allLevels,
          heartWordsByLevelId: const {},
        );

        expect(
          findings.any((f) => f.kind == DecodabilityFindingKind.outOfLevelWord),
          isTrue,
        );
        expect(
          findings.any(
            (f) => f.kind == DecodabilityFindingKind.wordCountBounds,
          ),
          isTrue,
        );
      },
    );
  });
}

# Decodability linter (Unit: decodability-linter)

Build-time-only pure-function lint that guards the "words a story uses match
what phonics has actually taught by that level" constraint. Pure Dart, no I/O,
no Flutter imports — usable from both the pack-build CLI (a later unit) and
from tests.

Source: `lib/pipeline/cumulative_grapheme_set.dart`,
`lib/pipeline/decodability_linter.dart`.
PRD refs: §5 `PhonicsSkill.introducesGraphemes`, §6 content decodability
constraint, §7 R5, §8 Unit 3 (linter), §8 Unit 14 (twister exemption), §9 A-8.

## `cumulativeGraphemeSet`

```dart
Set<String> cumulativeGraphemeSet({
  required List<Level> levels,
  required String levelId,
})
```

Resolves `levelId` against `levels` by `Level.id`, then returns the union of
`skill.introducesGraphemes` over every skill (`level.newSkills`) of every
level in `levels` whose `ordinal` is ≤ the resolved level's own `ordinal`
(including that level). The comparison bound is the resolved level's
*ordinal* field, not its position in the `levels` list, so the result does
not depend on list order. Grapheme units are opaque strings: a digraph
(`'sh'`) or a silent-e pattern (`'a_e'`) is one set element, never split into
component letters. Duplicate graphemes — whether repeated within one level's
skills or reintroduced by a later level — collapse to one element.

Throws `ArgumentError` when no level in `levels` has `id == levelId`
(including when `levels` is empty).

Consumes only `content_models.dart`'s `Level`/`PhonicsSkill` — the one shared
domain-models schema — never a locally redefined shape.

## `lintStory` / `lintTwister`

```dart
enum DecodabilityFindingKind { outOfLevelWord, wordCountBounds, pageCountBounds }

class DecodabilityFinding {
  DecodabilityFindingKind kind;
  String storyId;
  String levelId;
  String? word;                     // set for outOfLevelWord, null otherwise
  List<String> outOfLevelGraphemes; // set for outOfLevelWord, [] otherwise
  String message;                   // human-readable, non-empty
}

List<DecodabilityFinding> lintStory(
  Story story, {
  required List<Level> levels,
  required Map<String, List<String>> heartWordsByLevelId,
})

List<DecodabilityFinding> lintTwister(
  TongueTwister twister, {
  required List<Level> levels,
  required Map<String, List<String>> heartWordsByLevelId,
})
```

### `lintStory`

1. Resolves `story.levelId` against `levels` by `Level.id`; throws
   `ArgumentError` if unresolvable.
2. Computes the cumulative grapheme set at the story's level via
   `cumulativeGraphemeSet`.
3. Computes the cumulative heart-word set at the story's level: the union of
   `heartWordsByLevelId[level.id]` (defaulting to `[]` for a level absent
   from the map) over every level with `ordinal <=` the story level's
   ordinal — mirroring the grapheme cumulative-union rule, so a heart word
   tagged at level N is honored at level N and above, never below.
4. For every word in every sentence of every page: the word is decodable
   iff `word.text` is in the cumulative heart-word set (short-circuits the
   grapheme check entirely), OR every `graphemes` entry in its
   `graphemePhonemeMap` is a member of the cumulative grapheme set.
   Each undecodable word produces exactly one `outOfLevelWord` finding
   naming `storyId`, `levelId`, `word` (== `WordToken.text`), and
   `outOfLevelGraphemes` (the out-of-set grapheme units from that word's
   `graphemePhonemeMap`, in map order).
5. A-8 length bounds, checked against the resolved level's `format`,
   independent of the per-word check above:
   - `LevelFormat.sentence`: total word count across all pages/sentences
     must be in `[kSentenceLevelMinWords, kSentenceLevelMaxWords]`
     inclusive, else one `wordCountBounds` finding.
   - `LevelFormat.paragraph`: total word count must be in
     `[kParagraphLevelMinWords, kParagraphLevelMaxWords]` inclusive (else one
     `wordCountBounds` finding), **and** `story.pages.length` must be in
     `[kParagraphLevelMinPages, kParagraphLevelMaxPages]` inclusive (else one
     `pageCountBounds` finding) — these two checks are independent; both may
     fire on the same story.
   - `LevelFormat.multiSentence`: no length bound is defined in the domain
     models (`content_models.dart` defines only sentence- and
     paragraph-level bound constants), so no bounds finding is ever produced
     for a multiSentence-format story.
6. Findings are aggregated across the whole story — never fail-fast on the
   first problem — matching this codebase's existing
   `PackManifestValidationResult` convention.

### `lintTwister`

Always returns `const []`. TongueTwisters are wholly exempt from both
decodability and length-bounds linting (Unit 14 pinned: "modeled-first
content may use above-level words") — even when `twister.levelId` cannot be
resolved against `levels` at all, and even for a twister with zero words.

## Deviations / unpinned decisions

None requiring a stop. The ticket left exact API shapes to the builder;
every shape actually used here (the `DecodabilityFinding` field set, the
cumulative heart-word union rule, the independence of the two paragraph-level
bounds checks, the `multiSentence`-format exemption from any bounds check)
is exactly what the frozen test suites in
`test/pipeline/cumulative_grapheme_set_test.dart` and
`test/pipeline/decodability_linter_test.dart` pin, transcribed verbatim.

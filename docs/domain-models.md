# Domain models (Unit: domain-models)

Foundation types for LearnToRead: content models, device-local user models,
the story-pack manifest schema + validator, and the single tuning file.
Pure Dart, immutable value types, no Flutter imports, no Drift annotations —
this unit is headless-testable and almost every other unit depends on it.

Source: `lib/domain/models/content_models.dart`, `lib/domain/models/user_models.dart`,
`lib/domain/models/pack_manifest.dart`, `lib/domain/tuning.dart`.
PRD refs: §5, §8 Unit 3 (pack format), §8 Unit 4 (thresholds), §8 Unit 6
(tuning file), §8 Unit 15 (GraphemeSound), §9 A-8/A-11/A-12/A-13.

## Model map

### Content models (authored, immutable once published)

All content types live in `content_models.dart`. They are value types: two
instances built from equal constructor arguments are `==` with matching
`hashCode`s, and every `List`-typed field is defensively copied at
construction (`List.unmodifiable`), so mutating a source list after
construction can never leak into the built object.

| Type | Fields | Notes |
|---|---|---|
| `PhonicsSkill` | `id, name, sequenceOrder, introducesGraphemes: [String]` | The graphemes a skill teaches. The decodability linter's cumulative grapheme set at level N is the union of `introducesGraphemes` over every skill of level ≤ N. This is the *one* shared schema — phonics-engine's loader and the decodability linter both consume this type; neither defines its own. |
| `Level` | `id, ordinal, newSkills: [PhonicsSkill], format: LevelFormat, vocabEnabled, narrationEnabled` | `format` moves `sentence → multiSentence → paragraph`. `narrationEnabled` defaults to `true` when `format == sentence`, else `false`, unless explicitly passed (higher levels may opt in — a Unit 5 UI signal only). |
| `Story` | `id, levelId, title, pages: [Page], riveAnimationRef, celebrationAudioRef, collectibleRef, skillsExercised: [PhonicsSkill], packId, contentVersion` | |
| `Page` | `sentences: [Sentence]` | Sentence-format stories have exactly one page with one sentence — enforced by `validatePackManifest`, not by the constructor (the constructor can't represent an "invalid" story, so the invariant is checked on manifest JSON, see below). |
| `Sentence` | `words: [WordToken], narrationAudioRef: String?` | `narrationAudioRef` is the recorded human read-aloud; required (non-null) on every sentence at a sentence-format level (A-11). |
| `WordToken` | `text, graphemePhonemeMap: [(graphemes, phonemeId)], pronunciationAudioRef, vocabCardId: String?` | `graphemePhonemeMap` is ordered and drives sound-out highlighting; digraphs are one entry (`'sh'` is a single `(graphemes: 'sh', ...)`, never split `s`/`h`). `vocabCardId` presence means the word renders blue when the owning `Level.vocabEnabled` is true. |
| `VocabCard` | `id, word, definitionText, definitionAudioRef, illustrationRef: String?` | |
| `Phoneme` | `id, humanAudioRef` | `id` must be one of `kEnglishPhonemeIds`; constructor throws `ArgumentError` otherwise (including empty string). |
| `Collectible` | `id, storyId, riveRef, sceneSlot` | |
| `TongueTwister` | `id, levelId, words: [WordToken], targetPhonemeId, narrationAudioRef, packId` | Exempt from decodability linting. |
| `GraphemeSound` | `id, grapheme, phonemeIds: [String], introducedAtLevelId, exampleWords: [(wordText, pronunciationAudioRef, minLevelId)]` | `phonemeIds` ordered (multi-phoneme graphemes like `'x'` → `['K', 'S']`). An example word only appears once the profile's current level ≥ `minLevelId`. Inventory ships in binary starter content; example words extend via packs. |

Constants also defined in `content_models.dart`:
- `kEnglishPhonemeIds` — the pinned 44 English phonemes (24 consonants + 20
  vowels/diphthongs/r-controlled vowels), ARPAbet-style ids. Exact spelling
  is builder-mechanical per the ticket; callers must treat ids as opaque.
- `kSentenceLevelMinWords = 3`, `kSentenceLevelMaxWords = 8` (A-8).
- `kParagraphLevelMinWords = 40`, `kParagraphLevelMaxWords = 90`,
  `kParagraphLevelMinPages = 1`, `kParagraphLevelMaxPages = 3` (A-8).

Audio refs (`riveAnimationRef` aside) are always plain, source-agnostic
`String`s across every content model — no wrapper type or
recorded-vs-TTS discriminator. A ref like `'tts://future-engine/clip-id'`
is exactly as valid as a recorded-audio path; TTS may substitute post-v1
with no model change.

### Device-local user models

All types live in `user_models.dart`. Local-first only — no server holds
user data. No JSON (de)serialization is defined here; persistence is owned
by the local-storage/Drift ticket.

| Type | Fields | Notes |
|---|---|---|
| `AgeBand` (enum) | `fiveToSix, sevenToEight, nineToTen` | Each has a `label` (`'5-6'`, `'7-8'`, `'9-10'`). |
| `Profile` | `localId, displayName, ageBand, currentLevelId, micConsent: bool, cloudAsrConsent: bool, createdAt: DateTime` | Max `kMaxProfilesPerDevice = 4` per device — constant lives here, enforcement is local-storage/UI. |
| `StoryStatus` (enum) | `locked, available, completed` | |
| `StoryProgress` | `profileId, storyId, status, completedAt: DateTime?, timesRead: int` | |
| `HelpLevel` (enum) | `none, soundOut, modeled` | |
| `WordHelpRecord` | `profileId, wordText, encounterCount: int, helpCount: int, lastHelpLevel: HelpLevel` | Powers the §4.3 learning signal and the Unit 10 parent pilot view. |
| `TwisterProgress` | `profileId, twisterId, timesCompleted: int` | |
| `CollectionState` | `profileId, earnedCollectibles: [String]` | List of earned `Collectible.id`s. |

### Story pack manifest

`pack_manifest.dart` defines `StoryPack` and the manifest validator.

**`StoryPack`** — `id, version, minAppVersion, stories: [Story],
twisters: [TongueTwister], vocabCards: [VocabCard],
collectibles: [Collectible], graphemeSounds: [GraphemeSound],
assetRefs: [String], checksum`, plus `toJson()`/`StoryPack.fromJson(...)`.

`PhonicsSkill.introducesGraphemes` still travels inside a manifest — it's
nested under each `Story.skillsExercised` — but `PhonicsSkill` and `Level`
as top-level scope-&-sequence data do **not** travel in the manifest at
all: they're loaded separately by the phonics-engine unit (Unit 2: "stored
as data not code") and supplied to the validator as out-of-band
`levelsById` context. `Phoneme` likewise never travels in a manifest — it's
a fixed 44-entry set shipped in the app binary.

`StoryPack.fromJson` **trusts** its input; it is only meant to run on the
output of `toJson()` (or that JSON round-tripped through
`jsonEncode`/`jsonDecode`). Anything that might be a corrupted or
hand-edited manifest must go through `validatePackManifest` first.

**`validatePackManifest(Map<String, dynamic> manifestJson, {required Map<String, Level> levelsById})`**
→ `PackManifestValidationResult { isValid: bool, errors: [PackManifestValidationError] }`.

It operates on raw JSON, not on a constructed `StoryPack`. This is
deliberate: `Story.riveAnimationRef`, `TongueTwister.targetPhonemeId`, etc.
are non-nullable, so an in-memory `Story` that is "missing" a required
field cannot be constructed at all — the "manifest missing a required
field" scenario can only be simulated at the raw-JSON layer (as if a pack's
`manifest.json` were hand-edited or corrupted before being trusted).
`validatePackManifest` is therefore the gate a pack must clear *before*
`StoryPack.fromJson` is ever called on it in the real pipeline (pack-build-cli
composes this validator with its own asset/loudness/decodability checks).

Every `PackManifestValidationError` has `field`, `entityType` (one of
`'pack' | 'story' | 'twister' | 'vocabCard' | 'collectible' | 'graphemeSound' | 'level'`),
`entityId`, and `message`. Validation **aggregates** every independent
failure it finds rather than failing fast on the first one.

#### Validation rules

1. **Required top-level pack fields**: `id, version, minAppVersion, stories,
   twisters, vocabCards, collectibles, graphemeSounds, assetRefs, checksum`
   must all be present (non-null) — else `entityType: 'pack'`.
2. **Required per-entity fields**:
   - Story: `id, levelId, title, pages, riveAnimationRef, celebrationAudioRef,
     collectibleRef, skillsExercised, packId, contentVersion`.
   - TongueTwister: `id, levelId, words, targetPhonemeId, narrationAudioRef, packId`.
   - VocabCard: `id, word, definitionText, definitionAudioRef` (`illustrationRef`
     is optional).
   - Collectible: `id, storyId, riveRef, sceneSlot`.
   - GraphemeSound: `id, grapheme, phonemeIds, introducedAtLevelId, exampleWords`.
3. **Story → Level reference**: a story's `levelId` must resolve inside
   `levelsById`, else `field: 'levelId', entityType: 'story'`.
4. **narrationEnabled default rule (Level-level)**: every sentence-format
   `Level` present in `levelsById` must have `narrationEnabled == true`
   (PRD: "true at all sentence-format levels"). A sentence-format level with
   `narrationEnabled == false` fails with `field: 'narrationEnabled',
   entityType: 'level'`.
5. **Sentence-format story invariant**: for a story whose resolved level has
   `format == LevelFormat.sentence`, the story must have exactly one page
   (`field: 'pages'` otherwise) with exactly one sentence
   (`field: 'sentences'` otherwise). `multiSentence`/`paragraph` stories are
   exempt.
6. **A-11 narration requirement**: for a story whose resolved level has
   `format == LevelFormat.sentence`, every sentence across every page must
   carry a non-null `narrationAudioRef` (`field: 'narrationAudioRef',
   entityType: 'story'`). This is scoped strictly to *sentence-format*
   stories — a `multiSentence`/`paragraph` level opting `narrationEnabled`
   in is a Unit 5 UI signal only and does **not** trigger this hard
   pack-build requirement (PRD A-11: "pack build requires
   `narrationAudioRef` for every sentence-format story").

An empty manifest (no stories/twisters/cards/collectibles/sounds) is valid
as long as the required top-level fields are present.

## Tuning file (`lib/domain/tuning.dart`)

The single tuning file (PRD §8 Unit 6 pinned design: *"Timings T1/T2,
struggle sensitivity, and phonetic-closeness thresholds (Unit 4) are
constants in one tuning file; pilot adjustments touch only that file."*).
Every constant is a genuine `const` (not `final`) so a pilot tuning pass
never needs to touch code outside this file.

| Constant | Value | Source | Meaning |
|---|---|---|---|
| `kStruggleT1` | `Duration(seconds: 4)` | Unit 6 (T1) | Sustained-silence threshold that (with `kStruggleConsecutiveNonMatchingBursts`) drives `struggleDetected` (A-12). Also the wait before Tier 1 of the stuck-word scaffold engages. |
| `kTier2WaitT2` | `Duration(seconds: 4)` | Unit 6 (T2) | Wait time after Tier 1 sound-out before Tier 2 ("model it") engages. |
| `kWordModeShortWordMaxPhonemes` | `4` | Unit 4 / A-8 closeness policy | A word of ≤ this many phonemes is "short" for closeness-matching (inclusive boundary: exactly 4 phonemes is short, 5 is long). |
| `kWordModeMaxSubstitutedPhonemesShortWord` | `1` | Unit 4 | Max substituted phonemes tolerated for a short word to count as a near-miss accept (e.g. "gat"→"cat"). |
| `kWordModeMaxSubstitutedPhonemesLongWord` | `2` | Unit 4 | Same, for longer words. |
| `kStruggleConsecutiveNonMatchingBursts` | `2` | A-12(a) | Consecutive finalized non-matching speech-hypothesis bursts that trigger `struggleDetected`. A-12(b) (sustained silence ≥ T1) reuses `kStruggleT1` directly — no separate constant. |
| `kSoundModeMatchThreshold` | `0.60` | A-13 | Sound-mode (tongue twister / Sound Garden echo) acceptance: fraction of the target phoneme sequence that must match. |
| `kSoundModePerPhonemeMaxDistance` | `1` | A-13 | Max per-phoneme edit distance tolerated within a sound-mode match. |
| `kSoundModeTargetPhonemeWeight` | `2` | A-13 | Weight applied to matches of the twister/card's target phoneme when scoring a sound-mode echo attempt. |

## Deviations / unpinned decisions

None. Every field, enum, constant name, and default value was transcribed
from the ticket's `pinned_design` / PRD §5, §8 Units 3/4/6/15, and §9
A-8/A-11/A-12/A-13, and where the ticket left a design point implicit (the
`validatePackManifest` entity-type strings, the A-11/sentence-invariant
scoping to level format rather than the `narrationEnabled` flag value, the
exact spelling of `kEnglishPhonemeIds`), the frozen test suite in
`test/domain/*.dart` pinned the exact resolution and this implementation
follows it verbatim.

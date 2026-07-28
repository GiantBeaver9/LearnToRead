// Demo starter-pack content generator (post-build-loop owner tooling).
//
// Usage:
//   dart run tool/demo_content.dart [--out=content/demo]
//
// Authors the demo starter pack IN CODE against the real model classes
// (type-checked, so a schema drift breaks this script at compile time, not
// the app at runtime), then materializes a pack-build content directory:
//
//   content/demo/manifest.json          -- StoryPack.toJson()
//   content/demo/levels.json            -- pack_build.dart --levels input
//   content/demo/heart_words.json       -- pack_build.dart --heart-words input
//   content/demo/scope_sequence.json    -- the app's scope-&-sequence document
//                                          (loadPhonicsContent shape)
//   content/demo/<asset dirs>           -- placeholder assets for every ref
//
// Placeholder audio is a short faded sine tone per clip, amplitude-scaled
// until lib/pipeline/loudness_check.dart itself measures it at -16 LUFS --
// the same code the pack builder rejects with, so placeholders always pass.
// EXISTING FILES ARE NEVER OVERWRITTEN: drop real recordings in place (same
// names -- see docs/audio/recording-checklist.md) and re-run; only still-
// missing refs get placeholders.
//
// Placeholder .riv files are NOT real Rive animations (the app's default
// StoryStage is the fake; real art is OQ-4 owner content) -- they exist so
// asset-presence and A-16 sidecar validation pass.
//
// After running this, build the installable pack with:
//   dart run tool/pack_build.dart content/demo build/starter_pack/manifest.json \
//     --levels=content/demo/levels.json --heart-words=content/demo/heart_words.json

// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/pack_manifest.dart';
import 'package:learn_to_read/pipeline/loudness_check.dart';
import 'package:learn_to_read/pipeline/rive_input_validator.dart';

// ---------------------------------------------------------------------------
// Content authoring helpers
// ---------------------------------------------------------------------------

/// Builds a [WordToken]; pronunciation clips are shared per lowercased word
/// text under `words/`, so "The" and "the" are one recording.
WordToken w(String text, List<(String, String)> map, {String? vocab}) =>
    WordToken(
      text: text,
      graphemePhonemeMap: [
        for (final (g, p) in map) (graphemes: g, phonemeId: p),
      ],
      pronunciationAudioRef: 'words/${text.toLowerCase()}.wav',
      vocabCardId: vocab,
    );

Sentence s(List<WordToken> words, {String? narration}) =>
    Sentence(words: words, narrationAudioRef: narration);

// ---------------------------------------------------------------------------
// The demo scope & sequence (3 levels)
// ---------------------------------------------------------------------------

final PhonicsSkill _skillSatpin = PhonicsSkill(
  id: 'skill.demo.satpin',
  name: 's a t p i n c',
  sequenceOrder: 1,
  introducesGraphemes: const ['s', 'a', 't', 'p', 'i', 'n', 'c'],
);

final PhonicsSkill _skillSet2 = PhonicsSkill(
  id: 'skill.demo.set2',
  name: 'm d g o e h r u b f l',
  sequenceOrder: 2,
  introducesGraphemes: const ['m', 'd', 'g', 'o', 'e', 'h', 'r', 'u', 'b', 'f', 'l'],
);

final PhonicsSkill _skillDigraphs = PhonicsSkill(
  id: 'skill.demo.digraphs',
  name: 'sh ck ll ss',
  sequenceOrder: 3,
  introducesGraphemes: const ['sh', 'ck', 'll', 'ss'],
);

final PhonicsSkill _skillSet3 = PhonicsSkill(
  id: 'skill.demo.set3',
  name: 'w y z j v k',
  sequenceOrder: 4,
  introducesGraphemes: const ['w', 'y', 'z', 'j', 'v', 'k'],
);

final PhonicsSkill _skillVowelTeams = PhonicsSkill(
  id: 'skill.demo.vowel-teams',
  name: 'ee ea ay ai oa ar or th ng zz',
  sequenceOrder: 5,
  introducesGraphemes: const ['ee', 'ea', 'ay', 'ai', 'oa', 'ar', 'or', 'th', 'ng', 'zz', 're'],
);

final List<Level> _levels = [
  Level(
    id: 'level.demo.1',
    ordinal: 1,
    format: LevelFormat.sentence,
    vocabEnabled: false,
    newSkills: [_skillSatpin],
  ),
  Level(
    id: 'level.demo.2',
    ordinal: 2,
    format: LevelFormat.multiSentence,
    vocabEnabled: false,
    narrationEnabled: true,
    newSkills: [_skillSet2, _skillDigraphs],
  ),
  Level(
    id: 'level.demo.3',
    ordinal: 3,
    format: LevelFormat.paragraph,
    vocabEnabled: true,
    newSkills: [_skillSet3, _skillVowelTeams],
  ),
];

final Map<String, List<String>> _heartWords = {
  'level.demo.1': ['the', 'The'],
  'level.demo.2': [],
  'level.demo.3': ['to', 'To', 'of', 'Of'],
};

// ---------------------------------------------------------------------------
// Stories
// ---------------------------------------------------------------------------

// Shared decompositions for words reused across stories.
WordToken _the([String text = 'the']) => w(text, [('th', 'DH'), ('e', 'AX')]);
WordToken _a([String text = 'a']) => w(text, [('a', 'AX')]);
WordToken _in() => w('in', [('i', 'IH'), ('n', 'N')]);
WordToken _is() => w('is', [('i', 'IH'), ('s', 'Z')]);
WordToken _red() => w('red', [('r', 'R'), ('e', 'EH'), ('d', 'D')]);
WordToken _bug([String text = 'bug']) =>
    w(text, [('b', 'B'), ('u', 'AH'), ('g', 'G')]);

final Story _storyCat = Story(
  id: 'story.demo.cat',
  levelId: 'level.demo.1',
  title: 'The Cat in the Tin',
  pages: [
    Page(
      sentences: [
        s(
          [
            _the('The'),
            w('cat', [('c', 'K'), ('a', 'AE'), ('t', 'T')]),
            w('sat', [('s', 'S'), ('a', 'AE'), ('t', 'T')]),
            _in(),
            _a(),
            w('tin', [('t', 'T'), ('i', 'IH'), ('n', 'N')]),
          ],
          narration: 'narration/cat_p1_s1.wav',
        ),
      ],
    ),
  ],
  riveAnimationRef: 'rive/story_cat.riv',
  celebrationAudioRef: 'celebrations/cheer_01.wav',
  collectibleRef: 'collectible.demo.cat',
  skillsExercised: [_skillSatpin],
  packId: 'pack.starter',
  contentVersion: '1',
);

final Story _storyShip = Story(
  id: 'story.demo.ship',
  levelId: 'level.demo.2',
  title: 'The Red Ship',
  pages: [
    Page(
      sentences: [
        s(
          [
            _the('The'),
            w('ship', [('sh', 'SH'), ('i', 'IH'), ('p', 'P')]),
            _is(),
            _red(),
          ],
          narration: 'narration/ship_p1_s1.wav',
        ),
        s(
          [
            w('It', [('i', 'IH'), ('t', 'T')]),
            w('can', [('c', 'K'), ('a', 'AE'), ('n', 'N')]),
            w('go', [('g', 'G'), ('o', 'OW')]),
            w('fast', [('f', 'F'), ('a', 'AE'), ('s', 'S'), ('t', 'T')]),
          ],
          narration: 'narration/ship_p1_s2.wav',
        ),
      ],
    ),
  ],
  riveAnimationRef: 'rive/story_ship.riv',
  celebrationAudioRef: 'celebrations/cheer_02.wav',
  collectibleRef: 'collectible.demo.ship',
  skillsExercised: [_skillSet2, _skillDigraphs],
  packId: 'pack.starter',
  contentVersion: '1',
);

final Story _storyGarden = Story(
  id: 'story.demo.garden',
  levelId: 'level.demo.3',
  title: "Ben's Bug Garden",
  pages: [
    Page(
      sentences: [
        s([
          w('Ben', [('b', 'B'), ('e', 'EH'), ('n', 'N')]),
          w('has', [('h', 'HH'), ('a', 'AE'), ('s', 'Z')]),
          _a(),
          w(
            'garden',
            [('g', 'G'), ('ar', 'ARE'), ('d', 'D'), ('e', 'AX'), ('n', 'N')],
            vocab: 'vocab.demo.garden',
          ),
        ]),
        s([
          w('He', [('h', 'HH'), ('e', 'IY')]),
          w('digs', [('d', 'D'), ('i', 'IH'), ('g', 'G'), ('s', 'Z')]),
          _in(),
          _the(),
          w('mud', [('m', 'M'), ('u', 'AH'), ('d', 'D')]),
        ]),
        s([
          _the('The'),
          w('sun', [('s', 'S'), ('u', 'AH'), ('n', 'N')]),
          _is(),
          w('up', [('u', 'AH'), ('p', 'P')]),
          w('and', [('a', 'AE'), ('n', 'N'), ('d', 'D')]),
          _the(),
          w('day', [('d', 'D'), ('ay', 'EY')]),
          _is(),
          w('hot', [('h', 'HH'), ('o', 'AA'), ('t', 'T')]),
        ]),
        s([
          _a('A'),
          w('big', [('b', 'B'), ('i', 'IH'), ('g', 'G')]),
          _bug(),
          w('sits', [('s', 'S'), ('i', 'IH'), ('t', 'T'), ('s', 'S')]),
          w('on', [('o', 'AA'), ('n', 'N')]),
          _a(),
          w('leaf', [('l', 'L'), ('ea', 'IY'), ('f', 'F')]),
        ]),
      ],
    ),
    Page(
      sentences: [
        s([
          _the('The'),
          _bug(),
          w('hums', [('h', 'HH'), ('u', 'AH'), ('m', 'M'), ('s', 'Z')]),
          w('and', [('a', 'AE'), ('n', 'N'), ('d', 'D')]),
          w('flits', [('f', 'F'), ('l', 'L'), ('i', 'IH'), ('t', 'T'), ('s', 'S')]),
          w('to', [('t', 'T'), ('o', 'UW')]),
          _a(),
          _red(),
          w('bud', [('b', 'B'), ('u', 'AH'), ('d', 'D')]),
        ]),
        s([
          w('Ben', [('b', 'B'), ('e', 'EH'), ('n', 'N')]),
          w('grins', [('g', 'G'), ('r', 'R'), ('i', 'IH'), ('n', 'N'), ('s', 'Z')]),
        ]),
        s([
          w('His', [('h', 'HH'), ('i', 'IH'), ('s', 'Z')]),
          w(
            'garden',
            [('g', 'G'), ('ar', 'ARE'), ('d', 'D'), ('e', 'AX'), ('n', 'N')],
            vocab: 'vocab.demo.garden',
          ),
          _is(),
          w('full', [('f', 'F'), ('u', 'UH'), ('ll', 'L')]),
          w('of', [('o', 'AH'), ('f', 'V')]),
          w(
            'buzzing',
            [('b', 'B'), ('u', 'AH'), ('zz', 'Z'), ('i', 'IH'), ('ng', 'NG')],
            vocab: 'vocab.demo.buzzing',
          ),
          w('bugs', [('b', 'B'), ('u', 'AH'), ('g', 'G'), ('s', 'Z')]),
        ]),
      ],
    ),
  ],
  riveAnimationRef: 'rive/story_garden.riv',
  celebrationAudioRef: 'celebrations/cheer_03.wav',
  collectibleRef: 'collectible.demo.garden',
  skillsExercised: [_skillSet3, _skillVowelTeams],
  packId: 'pack.starter',
  contentVersion: '1',
);

// ---------------------------------------------------------------------------
// Twisters (decodability-exempt; sound mode listens for SOUNDS)
// ---------------------------------------------------------------------------

final TongueTwister _twisterShells = TongueTwister(
  id: 'twister.demo.shells',
  levelId: 'level.demo.2',
  words: [
    w('She', [('sh', 'SH'), ('e', 'IY')]),
    w('sells', [('s', 'S'), ('e', 'EH'), ('ll', 'L'), ('s', 'Z')]),
    w('sea', [('s', 'S'), ('ea', 'IY')]),
    w('shells', [('sh', 'SH'), ('e', 'EH'), ('ll', 'L'), ('s', 'Z')]),
    w('by', [('b', 'B'), ('y', 'AY')]),
    _the(),
    w('sea', [('s', 'S'), ('ea', 'IY')]),
    w('shore', [('sh', 'SH'), ('o', 'AO'), ('re', 'R')]),
  ],
  targetPhonemeId: 'SH',
  narrationAudioRef: 'narration/twister_shells.wav',
  packId: 'pack.starter',
);

final TongueTwister _twisterSoup = TongueTwister(
  id: 'twister.demo.soup',
  levelId: 'level.demo.1',
  words: [
    w('Sad', [('s', 'S'), ('a', 'AE'), ('d', 'D')]),
    w('Sam', [('s', 'S'), ('a', 'AE'), ('m', 'M')]),
    w('sips', [('s', 'S'), ('i', 'IH'), ('p', 'P'), ('s', 'S')]),
    w('sea', [('s', 'S'), ('ea', 'IY')]),
    w('soup', [('s', 'S'), ('ou', 'UW'), ('p', 'P')]),
  ],
  targetPhonemeId: 'S',
  narrationAudioRef: 'narration/twister_soup.wav',
  packId: 'pack.starter',
);

// ---------------------------------------------------------------------------
// Vocab, collectibles, Sound Garden
// ---------------------------------------------------------------------------

final List<VocabCard> _vocabCards = [
  VocabCard(
    id: 'vocab.demo.garden',
    word: 'garden',
    definitionText:
        'A garden is a place outside where plants and flowers grow.',
    definitionAudioRef: 'vocab/garden_definition.wav',
  ),
  VocabCard(
    id: 'vocab.demo.buzzing',
    word: 'buzzing',
    definitionText:
        'Buzzing is the soft humming sound a bug makes with its wings.',
    definitionAudioRef: 'vocab/buzzing_definition.wav',
  ),
];

final List<Collectible> _collectibles = [
  Collectible(
    id: 'collectible.demo.cat',
    storyId: 'story.demo.cat',
    riveRef: 'rive/collect_cat.riv',
    sceneSlot: '0:0',
  ),
  Collectible(
    id: 'collectible.demo.ship',
    storyId: 'story.demo.ship',
    riveRef: 'rive/collect_ship.riv',
    sceneSlot: '0:1',
  ),
  Collectible(
    id: 'collectible.demo.garden',
    storyId: 'story.demo.garden',
    riveRef: 'rive/collect_garden.riv',
    sceneSlot: '1:0',
  ),
];

final List<GraphemeSound> _graphemeSounds = [
  GraphemeSound(
    id: 'gs.demo.sh',
    grapheme: 'sh',
    phonemeIds: const ['SH'],
    introducedAtLevelId: 'level.demo.2',
    exampleWords: const [
      (wordText: 'ship', pronunciationAudioRef: 'words/ship.wav', minLevelId: 'level.demo.2'),
      (wordText: 'shells', pronunciationAudioRef: 'words/shells.wav', minLevelId: 'level.demo.2'),
    ],
  ),
  GraphemeSound(
    id: 'gs.demo.ee',
    grapheme: 'ee',
    phonemeIds: const ['IY'],
    introducedAtLevelId: 'level.demo.3',
    exampleWords: const [
      (wordText: 'see', pronunciationAudioRef: 'words/see.wav', minLevelId: 'level.demo.3'),
      (wordText: 'tree', pronunciationAudioRef: 'words/tree.wav', minLevelId: 'level.demo.3'),
    ],
  ),
  GraphemeSound(
    id: 'gs.demo.th',
    grapheme: 'th',
    phonemeIds: const ['TH', 'DH'],
    introducedAtLevelId: 'level.demo.3',
    exampleWords: const [
      (wordText: 'thin', pronunciationAudioRef: 'words/thin.wav', minLevelId: 'level.demo.3'),
      (wordText: 'the', pronunciationAudioRef: 'words/the.wav', minLevelId: 'level.demo.3'),
    ],
  ),
  GraphemeSound(
    id: 'gs.demo.ar',
    grapheme: 'ar',
    phonemeIds: const ['ARE'],
    introducedAtLevelId: 'level.demo.3',
    exampleWords: const [
      (wordText: 'garden', pronunciationAudioRef: 'words/garden.wav', minLevelId: 'level.demo.3'),
      (wordText: 'car', pronunciationAudioRef: 'words/car.wav', minLevelId: 'level.demo.3'),
    ],
  ),
  GraphemeSound(
    id: 'gs.demo.ay',
    grapheme: 'ay',
    phonemeIds: const ['EY'],
    introducedAtLevelId: 'level.demo.3',
    exampleWords: const [
      (wordText: 'day', pronunciationAudioRef: 'words/day.wav', minLevelId: 'level.demo.3'),
      (wordText: 'play', pronunciationAudioRef: 'words/play.wav', minLevelId: 'level.demo.3'),
    ],
  ),
];

// ---------------------------------------------------------------------------
// Pack assembly
// ---------------------------------------------------------------------------

/// Every audio/animation ref in the pack plus the app-bundled 44 phoneme
/// clips and celebration/prompt sets that live in the same content dir.
List<String> _collectAssetRefs(StoryPack pack) {
  final refs = <String>{};

  void addWord(WordToken token) => refs.add(token.pronunciationAudioRef);

  for (final story in pack.stories) {
    refs.add(story.riveAnimationRef);
    refs.add(riveSidecarRefFor(story.riveAnimationRef));
    refs.add(story.celebrationAudioRef);
    for (final page in story.pages) {
      for (final sentence in page.sentences) {
        final narration = sentence.narrationAudioRef;
        if (narration != null) refs.add(narration);
        sentence.words.forEach(addWord);
      }
    }
  }
  for (final twister in pack.twisters) {
    refs.add(twister.narrationAudioRef);
    twister.words.forEach(addWord);
  }
  for (final card in pack.vocabCards) {
    refs.add(card.definitionAudioRef);
  }
  for (final collectible in pack.collectibles) {
    refs.add(collectible.riveRef);
    refs.add(riveSidecarRefFor(collectible.riveRef));
  }
  for (final sound in pack.graphemeSounds) {
    for (final example in sound.exampleWords) {
      refs.add(example.pronunciationAudioRef);
    }
  }
  for (final phonemeId in kEnglishPhonemeIds) {
    refs.add('phonemes/$phonemeId.wav');
  }
  for (var i = 1; i <= 10; i++) {
    refs.add('celebrations/cheer_${i.toString().padLeft(2, '0')}.wav');
  }
  refs.add('prompts/your_turn.wav');
  // The warm near-miss line (Unit 6) and the pre-reader nav voice prompts
  // (kNavVoicePromptRefs in lib/app/router.dart — fixed refs, so the files
  // must exist at exactly these pack-relative paths).
  refs.add('prompts/near_miss.wav');
  refs.addAll(const [
    'audio/nav/map.wav',
    'audio/nav/collection.wav',
    'audio/nav/garden.wav',
    'audio/nav/parent-corner.wav',
    'audio/nav/flashcards.wav',
  ]);
  return refs.toList()..sort();
}

StoryPack _buildDemoPack() {
  final withoutRefs = StoryPack(
    id: 'pack.starter',
    version: '0.1.0',
    minAppVersion: '0.1.0',
    stories: [_storyCat, _storyShip, _storyGarden],
    twisters: [_twisterSoup, _twisterShells],
    vocabCards: _vocabCards,
    collectibles: _collectibles,
    graphemeSounds: _graphemeSounds,
    assetRefs: const [],
    checksum: '',
  );
  return StoryPack(
    id: withoutRefs.id,
    version: withoutRefs.version,
    minAppVersion: withoutRefs.minAppVersion,
    stories: withoutRefs.stories,
    twisters: withoutRefs.twisters,
    vocabCards: withoutRefs.vocabCards,
    collectibles: withoutRefs.collectibles,
    graphemeSounds: withoutRefs.graphemeSounds,
    assetRefs: _collectAssetRefs(withoutRefs),
    checksum: '',
  );
}

// ---------------------------------------------------------------------------
// Placeholder asset generation
// ---------------------------------------------------------------------------

const int _sampleRate = 44100;

/// Category -> (frequency Hz, duration seconds) so placeholder clips are
/// audibly distinguishable in the running app.
(double, double) _toneFor(String ref) {
  if (ref.startsWith('phonemes/')) return (660, 0.35);
  if (ref.startsWith('words/')) return (440, 0.5);
  if (ref.startsWith('narration/')) return (330, 1.2);
  if (ref.startsWith('celebrations/')) return (550, 0.8);
  if (ref.startsWith('prompts/')) return (500, 0.6);
  if (ref.startsWith('audio/nav/')) return (520, 0.7);
  if (ref.startsWith('vocab/')) return (392, 1.0);
  return (480, 0.5);
}

Uint8List _sineWav(double frequency, double seconds, double amplitude) {
  final frameCount = (seconds * _sampleRate).round();
  final fade = (0.005 * _sampleRate).round();
  final samples = Int16List(frameCount);
  for (var i = 0; i < frameCount; i++) {
    var v = amplitude * math.sin(2 * math.pi * frequency * i / _sampleRate);
    if (i < fade) v *= i / fade;
    if (i >= frameCount - fade) v *= (frameCount - 1 - i) / fade;
    samples[i] = (v.clamp(-1.0, 1.0) * 32767).round();
  }
  final data = samples.buffer.asUint8List();
  final header = ByteData(44);
  void ascii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      header.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  ascii(0, 'RIFF');
  header.setUint32(4, 36 + data.length, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little); // PCM
  header.setUint16(22, 1, Endian.little); // mono
  header.setUint32(24, _sampleRate, Endian.little);
  header.setUint32(28, _sampleRate * 2, Endian.little);
  header.setUint16(32, 2, Endian.little);
  header.setUint16(34, 16, Endian.little);
  ascii(36, 'data');
  header.setUint32(40, data.length, Endian.little);
  return Uint8List.fromList([...header.buffer.asUint8List(), ...data]);
}

/// Generates a -16 LUFS tone as measured by the pipeline's own BS.1770
/// implementation: synthesize, measure, correct by the dB difference, and
/// verify the corrected clip actually passes.
Uint8List _placeholderWav(String ref) {
  final (frequency, seconds) = _toneFor(ref);
  var amplitude = 0.24;
  var bytes = _sineWav(frequency, seconds, amplitude);
  for (var attempt = 0; attempt < 4; attempt++) {
    final result = checkAssetLoudness(bytes, assetRef: ref, targetLufs: -16.0, toleranceLu: 0.25);
    if (result.passes) return bytes;
    amplitude *= math.pow(10, (-16.0 - result.measuredLufs) / 20).toDouble();
    bytes = _sineWav(frequency, seconds, amplitude.clamp(0.001, 0.98));
  }
  final last = checkAssetLoudness(bytes, assetRef: ref, targetLufs: -16.0, toleranceLu: 1.0);
  if (!last.passes) {
    throw StateError('could not normalize placeholder $ref: $last');
  }
  return bytes;
}

// ---------------------------------------------------------------------------
// Output documents
// ---------------------------------------------------------------------------

Map<String, dynamic> _cliLevelJson(Level level) => {
      'id': level.id,
      'ordinal': level.ordinal,
      'format': level.format.name,
      'vocabEnabled': level.vocabEnabled,
      'narrationEnabled': level.narrationEnabled,
      'newSkills': [
        for (final skill in level.newSkills)
          {
            'id': skill.id,
            'name': skill.name,
            'sequenceOrder': skill.sequenceOrder,
            'introducesGraphemes': skill.introducesGraphemes,
          },
      ],
    };

/// The app-side scope-&-sequence document (`loadPhonicsContent` shape):
/// same levels, but with `skills` + inline `heartWords`, plus the authored
/// global story order.
Map<String, dynamic> _scopeSequenceJson(StoryPack pack) => {
      'levels': [
        for (final level in _levels)
          {
            'id': level.id,
            'ordinal': level.ordinal,
            'format': level.format.name,
            'vocabEnabled': level.vocabEnabled,
            'skills': [
              for (final skill in level.newSkills)
                {
                  'id': skill.id,
                  'name': skill.name,
                  'sequenceOrder': skill.sequenceOrder,
                  'introducesGraphemes': skill.introducesGraphemes,
                },
            ],
            'heartWords': _heartWords[level.id] ?? const [],
          },
      ],
      'stories': [
        for (final story in pack.stories)
          {'id': story.id, 'levelId': story.levelId},
      ],
    };

// ---------------------------------------------------------------------------
// main
// ---------------------------------------------------------------------------

Future<void> main(List<String> args) async {
  final outArg = args
      .where((a) => a.startsWith('--out='))
      .map((a) => a.substring('--out='.length))
      .firstOrNull;
  final outDir = Directory(outArg ?? 'content/demo')..createSync(recursive: true);

  final pack = _buildDemoPack();

  File('${outDir.path}/manifest.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(pack.toJson()));
  File('${outDir.path}/levels.json').writeAsStringSync(
    const JsonEncoder.withIndent('  ').convert([for (final l in _levels) _cliLevelJson(l)]),
  );
  File('${outDir.path}/heart_words.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_heartWords));
  File('${outDir.path}/scope_sequence.json')
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_scopeSequenceJson(pack)));

  var generatedAudio = 0;
  var generatedOther = 0;
  var kept = 0;
  for (final ref in pack.assetRefs) {
    final file = File('${outDir.path}/${ref.split('/').join(Platform.pathSeparator)}');
    if (file.existsSync()) {
      kept++;
      continue;
    }
    file.parent.createSync(recursive: true);
    if (ref.endsWith('.wav')) {
      file.writeAsBytesSync(_placeholderWav(ref));
      generatedAudio++;
    } else if (ref.endsWith('.riv')) {
      file.writeAsBytesSync(utf8.encode('RIVE-PLACEHOLDER (owner art, OQ-4)'));
      generatedOther++;
    } else if (ref.endsWith('.riv.inputs.json')) {
      file.writeAsStringSync(jsonEncode({'inputs': kRequiredRiveStateMachineInputs}));
      generatedOther++;
    }
  }

  print('demo content written to ${outDir.path}');
  print('  ${pack.stories.length} stories, ${pack.twisters.length} twisters, '
      '${pack.vocabCards.length} vocab cards, ${pack.graphemeSounds.length} grapheme sounds');
  print('  ${pack.assetRefs.length} asset refs: $generatedAudio placeholder WAVs generated, '
      '$generatedOther other placeholders generated, $kept existing files kept');
  print('next: dart run tool/pack_build.dart ${outDir.path} '
      'build/starter_pack/manifest.json --levels=${outDir.path}/levels.json '
      '--heart-words=${outDir.path}/heart_words.json '
      '--starter-levels=level.demo.1,level.demo.2,level.demo.3');
}

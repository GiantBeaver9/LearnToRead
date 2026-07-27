// Pins the API of lib/features/help/help_recorder.dart (PRD §5
// WordHelpRecord; §4.3 learning signal; §8 Unit 6; ticket
// stuck-word-scaffold accept entries 6 and 10 -- the "every word
// resolution records an encounter, helped or not" validator fix). This
// suite is authored before the implementation exists, so it is EXPECTED to
// fail to compile until help_recorder.dart is written with exactly the
// shapes exercised below.
//
// Pinned API surface this suite requires:
//   abstract class HelpRecorderApi {
//     Future<void> recordResolution({required WordToken word, required HelpLevel tier});
//   }
//   class HelpRecorder implements HelpRecorderApi {
//     HelpRecorder({required WordHelpDao wordHelpDao, required String profileId});
//   }
//
// Contract this suite locks in (builder-mechanical design choice: the
// ticket pins the *effect* on WordHelpRecord rows, not this exact class
// split; `HelpRecorderApi` exists so stuck_word_controller_test.dart and
// near_miss_prompt_test.dart can substitute a DB-free test double and stay
// decoupled from Drift/async-IO -- this file is the one place `HelpRecorder`
// itself is exercised against a real in-memory database, mirroring
// word_help_dao_test.dart's own setup):
//  - `recordResolution(tier: HelpLevel.none)` calls only
//    `WordHelpDao.recordEncounter` -- the word was read with no help, but
//    the encounter still counts (the §4.3 denominator fix): encounterCount
//    increments, helpCount and lastHelpLevel are untouched.
//  - `recordResolution(tier: HelpLevel.soundOut | HelpLevel.modeled)` calls
//    `WordHelpDao.recordEncounter` AND THEN `WordHelpDao.recordHelp(tier:
//    tier)` -- every helped resolution is *also* an encounter (ticket
//    accept entry 6: "every helped word recorded ... AND every word
//    resolution records an encounter").
//  - `HelpRecorder` never invents its own DB writes beyond delegating to
//    `WordHelpDao`'s already-pinned `recordEncounter`/`recordHelp`
//    semantics (word_help_dao_test.dart pins those independently); this
//    suite checks the delegation is wired correctly, not the DAO's own
//    row-accumulation rules a second time.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/features/help/help_recorder.dart';

WordToken _wordCat() => WordToken(
  text: 'cat',
  graphemePhonemeMap: const [
    (graphemes: 'c', phonemeId: 'K'),
    (graphemes: 'a', phonemeId: 'AE'),
    (graphemes: 't', phonemeId: 'T'),
  ],
  pronunciationAudioRef: 'audio/words/cat.wav',
);

WordToken _wordDog() => WordToken(
  text: 'dog',
  graphemePhonemeMap: const [
    (graphemes: 'd', phonemeId: 'D'),
    (graphemes: 'o', phonemeId: 'AO'),
    (graphemes: 'g', phonemeId: 'G'),
  ],
  pronunciationAudioRef: 'audio/words/dog.wav',
);

void main() {
  late AppDatabase db;
  late HelpRecorder recorder;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    recorder = HelpRecorder(wordHelpDao: db.wordHelpDao, profileId: 'profile.1');
  });

  tearDown(() async {
    await db.close();
  });

  group('POSITIVE: unaided (tier none) resolution is an encounter only', () {
    test('first unaided resolution creates a row: encounterCount=1, helpCount=0, lastHelpLevel=none', () async {
      await recorder.recordResolution(word: _wordCat(), tier: HelpLevel.none);

      final record = await db.wordHelpDao.getRecord(profileId: 'profile.1', wordText: 'cat');
      expect(record, isNotNull);
      expect(record!.encounterCount, 1);
      expect(record.helpCount, 0);
      expect(record.lastHelpLevel, HelpLevel.none);
    });

    test('repeated unaided resolutions increment encounterCount without adding help', () async {
      await recorder.recordResolution(word: _wordCat(), tier: HelpLevel.none);
      await recorder.recordResolution(word: _wordCat(), tier: HelpLevel.none);
      await recorder.recordResolution(word: _wordCat(), tier: HelpLevel.none);

      final record = await db.wordHelpDao.getRecord(profileId: 'profile.1', wordText: 'cat');
      expect(record!.encounterCount, 3);
      expect(record.helpCount, 0);
      expect(record.lastHelpLevel, HelpLevel.none);
    });
  });

  group('POSITIVE: helped resolutions record both an encounter and the tier reached', () {
    test('recordResolution(tier: soundOut) increments both encounterCount and helpCount', () async {
      await recorder.recordResolution(word: _wordCat(), tier: HelpLevel.soundOut);

      final record = await db.wordHelpDao.getRecord(profileId: 'profile.1', wordText: 'cat');
      expect(record, isNotNull);
      expect(record!.encounterCount, 1, reason: 'a helped word is still an encounter');
      expect(record.helpCount, 1);
      expect(record.lastHelpLevel, HelpLevel.soundOut);
    });

    test('recordResolution(tier: modeled) increments both encounterCount and helpCount', () async {
      await recorder.recordResolution(word: _wordCat(), tier: HelpLevel.modeled);

      final record = await db.wordHelpDao.getRecord(profileId: 'profile.1', wordText: 'cat');
      expect(record!.encounterCount, 1);
      expect(record.helpCount, 1);
      expect(record.lastHelpLevel, HelpLevel.modeled);
    });

    test('escalating from soundOut to modeled across encounters updates lastHelpLevel and both counts', () async {
      await recorder.recordResolution(word: _wordCat(), tier: HelpLevel.soundOut);
      await recorder.recordResolution(word: _wordCat(), tier: HelpLevel.modeled);

      final record = await db.wordHelpDao.getRecord(profileId: 'profile.1', wordText: 'cat');
      expect(record!.encounterCount, 2);
      expect(record.helpCount, 2);
      expect(record.lastHelpLevel, HelpLevel.modeled);
    });

    test('a later unaided resolution does not regress lastHelpLevel but still counts as an encounter', () async {
      await recorder.recordResolution(word: _wordCat(), tier: HelpLevel.modeled);
      await recorder.recordResolution(word: _wordCat(), tier: HelpLevel.none);

      final record = await db.wordHelpDao.getRecord(profileId: 'profile.1', wordText: 'cat');
      expect(record!.encounterCount, 2);
      expect(record.helpCount, 1);
      expect(record.lastHelpLevel, HelpLevel.modeled);
    });
  });

  group('POSITIVE: §4.3 help-rate trajectory readable through HelpRecorder alone', () {
    test('help rate declines across encounters as help is needed less', () async {
      await recorder.recordResolution(word: _wordCat(), tier: HelpLevel.soundOut);
      await recorder.recordResolution(word: _wordCat(), tier: HelpLevel.soundOut);
      final afterTwoHelped = await db.wordHelpDao.getRecord(profileId: 'profile.1', wordText: 'cat');
      final rateAfterTwo = afterTwoHelped!.helpCount / afterTwoHelped.encounterCount;
      expect(rateAfterTwo, 1.0);

      await recorder.recordResolution(word: _wordCat(), tier: HelpLevel.none);
      await recorder.recordResolution(word: _wordCat(), tier: HelpLevel.none);
      await recorder.recordResolution(word: _wordCat(), tier: HelpLevel.none);
      final afterFive = await db.wordHelpDao.getRecord(profileId: 'profile.1', wordText: 'cat');
      expect(afterFive!.encounterCount, 5);
      expect(afterFive.helpCount, 2);
      final rateAfterFive = afterFive.helpCount / afterFive.encounterCount;
      expect(rateAfterFive, 0.4);
      expect(rateAfterFive, lessThan(rateAfterTwo));
    });
  });

  group('EDGE: multi-word / multi-profile isolation and type surface', () {
    test('HelpRecorder implements HelpRecorderApi', () {
      expect(recorder, isA<HelpRecorderApi>());
    });

    test('different words for the same profile produce independent rows', () async {
      await recorder.recordResolution(word: _wordCat(), tier: HelpLevel.soundOut);
      await recorder.recordResolution(word: _wordDog(), tier: HelpLevel.none);

      final all = await db.wordHelpDao.allForProfile('profile.1');
      expect(all.map((r) => r.wordText).toSet(), {'cat', 'dog'});
      final cat = all.firstWhere((r) => r.wordText == 'cat');
      final dog = all.firstWhere((r) => r.wordText == 'dog');
      expect(cat.helpCount, 1);
      expect(dog.helpCount, 0);
    });

    test('the same word for different profiles produces independent rows', () async {
      final otherRecorder = HelpRecorder(wordHelpDao: db.wordHelpDao, profileId: 'profile.2');

      await recorder.recordResolution(word: _wordCat(), tier: HelpLevel.soundOut);
      await otherRecorder.recordResolution(word: _wordCat(), tier: HelpLevel.none);

      final profile1 = await db.wordHelpDao.getRecord(profileId: 'profile.1', wordText: 'cat');
      final profile2 = await db.wordHelpDao.getRecord(profileId: 'profile.2', wordText: 'cat');
      expect(profile1!.helpCount, 1);
      expect(profile2!.helpCount, 0);
    });
  });
}

// Pins the API of lib/data/db/daos/word_help_dao.dart (PRD §5
// WordHelpRecord; §4.3 learning signal; §8 Unit 6 tiered help; ticket
// local-storage accept entry 3).
//
// Pinned API surface:
//   class WordHelpDao {
//     Future<void> recordEncounter({
//       required String profileId,
//       required String wordText,
//     }); // called for EVERY word read (helped or unaided); creates the row
//         // on first sight (encounterCount=1, helpCount=0, lastHelpLevel=
//         // HelpLevel.none) or increments encounterCount on an existing row
//     Future<void> recordHelp({
//       required String profileId,
//       required String wordText,
//       required HelpLevel tier,
//     }); // called in addition to recordEncounter when a word needed help;
//         // increments helpCount and sets lastHelpLevel to the tier
//         // reached; never touches encounterCount
//     Future<WordHelpRecord?> getRecord({
//       required String profileId,
//       required String wordText,
//     });
//     Future<List<WordHelpRecord>> allForProfile(String profileId);
//     Future<int> rowCountForProfile(String profileId);
//   }
//
// Round trips go through the domain WordHelpRecord type, never a
// Drift-generated row class.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/domain/models/user_models.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('WordHelpDao recordEncounter (positive)', () {
    test(
      'first encounter creates a row with encounterCount=1, helpCount=0, lastHelpLevel=none',
      () async {
        await db.wordHelpDao.recordEncounter(
          profileId: 'profile.1',
          wordText: 'cat',
        );

        final record = await db.wordHelpDao.getRecord(
          profileId: 'profile.1',
          wordText: 'cat',
        );
        expect(record, isNotNull);
        expect(record!.encounterCount, 1);
        expect(record.helpCount, 0);
        expect(record.lastHelpLevel, HelpLevel.none);
      },
    );

    test(
      'repeated encounters of an unaided word increment encounterCount without adding help',
      () async {
        await db.wordHelpDao.recordEncounter(
          profileId: 'profile.1',
          wordText: 'cat',
        );
        await db.wordHelpDao.recordEncounter(
          profileId: 'profile.1',
          wordText: 'cat',
        );
        await db.wordHelpDao.recordEncounter(
          profileId: 'profile.1',
          wordText: 'cat',
        );

        final record = await db.wordHelpDao.getRecord(
          profileId: 'profile.1',
          wordText: 'cat',
        );
        expect(record!.encounterCount, 3);
        expect(record.helpCount, 0);
        expect(record.lastHelpLevel, HelpLevel.none);
      },
    );

    test('encounters do not duplicate rows per word', () async {
      await db.wordHelpDao.recordEncounter(
        profileId: 'profile.1',
        wordText: 'cat',
      );
      await db.wordHelpDao.recordEncounter(
        profileId: 'profile.1',
        wordText: 'cat',
      );
      await db.wordHelpDao.recordEncounter(
        profileId: 'profile.1',
        wordText: 'dog',
      );

      expect(await db.wordHelpDao.rowCountForProfile('profile.1'), 2);
    });
  });

  group('WordHelpDao recordHelp tier transitions (positive)', () {
    test(
      'recordHelp increments helpCount and sets lastHelpLevel to the tier reached',
      () async {
        await db.wordHelpDao.recordEncounter(
          profileId: 'profile.1',
          wordText: 'cat',
        );
        await db.wordHelpDao.recordHelp(
          profileId: 'profile.1',
          wordText: 'cat',
          tier: HelpLevel.soundOut,
        );

        final record = await db.wordHelpDao.getRecord(
          profileId: 'profile.1',
          wordText: 'cat',
        );
        expect(record!.helpCount, 1);
        expect(record.lastHelpLevel, HelpLevel.soundOut);
        expect(
          record.encounterCount,
          1,
          reason: 'recordHelp must not touch encounterCount',
        );
      },
    );

    test(
      'escalating from soundOut to modeled updates lastHelpLevel and increments helpCount again',
      () async {
        await db.wordHelpDao.recordEncounter(
          profileId: 'profile.1',
          wordText: 'cat',
        );
        await db.wordHelpDao.recordHelp(
          profileId: 'profile.1',
          wordText: 'cat',
          tier: HelpLevel.soundOut,
        );
        await db.wordHelpDao.recordHelp(
          profileId: 'profile.1',
          wordText: 'cat',
          tier: HelpLevel.modeled,
        );

        final record = await db.wordHelpDao.getRecord(
          profileId: 'profile.1',
          wordText: 'cat',
        );
        expect(record!.helpCount, 2);
        expect(record.lastHelpLevel, HelpLevel.modeled);
      },
    );

    test(
      'a later encounter with no help does not regress lastHelpLevel',
      () async {
        await db.wordHelpDao.recordEncounter(
          profileId: 'profile.1',
          wordText: 'cat',
        );
        await db.wordHelpDao.recordHelp(
          profileId: 'profile.1',
          wordText: 'cat',
          tier: HelpLevel.modeled,
        );
        await db.wordHelpDao.recordEncounter(
          profileId: 'profile.1',
          wordText: 'cat',
        );

        final record = await db.wordHelpDao.getRecord(
          profileId: 'profile.1',
          wordText: 'cat',
        );
        expect(record!.encounterCount, 2);
        expect(record.helpCount, 1);
        expect(record.lastHelpLevel, HelpLevel.modeled);
      },
    );
  });

  group(
    'WordHelpDao help-rate trajectory over encounters (positive, §4.3 fixture history)',
    () {
      test(
        'help rate (helpCount/encounterCount) declines as later encounters need no help',
        () async {
          const profileId = 'profile.1';
          const word = 'cat';

          // Encounter 1: needed help.
          await db.wordHelpDao.recordEncounter(
            profileId: profileId,
            wordText: word,
          );
          await db.wordHelpDao.recordHelp(
            profileId: profileId,
            wordText: word,
            tier: HelpLevel.soundOut,
          );
          final afterEncounter1 = await db.wordHelpDao.getRecord(
            profileId: profileId,
            wordText: word,
          );
          expect(afterEncounter1!.encounterCount, 1);
          expect(afterEncounter1.helpCount, 1);
          final rateAfter1 =
              afterEncounter1.helpCount / afterEncounter1.encounterCount;
          expect(rateAfter1, 1.0);

          // Encounter 2: needed help again.
          await db.wordHelpDao.recordEncounter(
            profileId: profileId,
            wordText: word,
          );
          await db.wordHelpDao.recordHelp(
            profileId: profileId,
            wordText: word,
            tier: HelpLevel.soundOut,
          );
          final afterEncounter2 = await db.wordHelpDao.getRecord(
            profileId: profileId,
            wordText: word,
          );
          final rateAfter2 =
              afterEncounter2!.helpCount / afterEncounter2.encounterCount;
          expect(rateAfter2, 1.0);

          // Encounters 3, 4, 5: the child reads it unaided -- the learning
          // signal (does needing help decline?).
          await db.wordHelpDao.recordEncounter(
            profileId: profileId,
            wordText: word,
          );
          await db.wordHelpDao.recordEncounter(
            profileId: profileId,
            wordText: word,
          );
          await db.wordHelpDao.recordEncounter(
            profileId: profileId,
            wordText: word,
          );
          final afterEncounter5 = await db.wordHelpDao.getRecord(
            profileId: profileId,
            wordText: word,
          );
          expect(afterEncounter5!.encounterCount, 5);
          expect(afterEncounter5.helpCount, 2);
          final rateAfter5 =
              afterEncounter5.helpCount / afterEncounter5.encounterCount;
          expect(rateAfter5, 0.4);

          expect(
            rateAfter5,
            lessThan(rateAfter1),
            reason:
                'help-rate trajectory should decline as the word is learned',
          );
          expect(rateAfter5, lessThan(rateAfter2));
        },
      );
    },
  );

  group('WordHelpDao getRecord / allForProfile / rowCountForProfile (edge)', () {
    test('getRecord returns null for a word never encountered', () async {
      expect(
        await db.wordHelpDao.getRecord(
          profileId: 'profile.1',
          wordText: 'never',
        ),
        isNull,
      );
    });

    test(
      'rowCountForProfile is 0 for a profile with no word history',
      () async {
        expect(await db.wordHelpDao.rowCountForProfile('profile.nobody'), 0);
      },
    );

    test(
      'recordHelp with no prior recordEncounter still stores a valid, non-throwing record',
      () async {
        await db.wordHelpDao.recordHelp(
          profileId: 'profile.1',
          wordText: 'surprise',
          tier: HelpLevel.modeled,
        );

        final record = await db.wordHelpDao.getRecord(
          profileId: 'profile.1',
          wordText: 'surprise',
        );
        expect(record, isNotNull);
        expect(record!.helpCount, 1);
        expect(record.lastHelpLevel, HelpLevel.modeled);
      },
    );

    test(
      'allForProfile lists every distinct word for the profile, and none for another profile',
      () async {
        await db.wordHelpDao.recordEncounter(
          profileId: 'profile.1',
          wordText: 'cat',
        );
        await db.wordHelpDao.recordEncounter(
          profileId: 'profile.1',
          wordText: 'dog',
        );
        await db.wordHelpDao.recordEncounter(
          profileId: 'profile.2',
          wordText: 'cat',
        );

        final profile1Words = await db.wordHelpDao.allForProfile('profile.1');
        expect(profile1Words.map((r) => r.wordText).toSet(), {'cat', 'dog'});

        final profile2Words = await db.wordHelpDao.allForProfile('profile.2');
        expect(profile2Words.map((r) => r.wordText).toSet(), {'cat'});
      },
    );
  });
}

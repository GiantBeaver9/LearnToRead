// Pins the deletion half of lib/features/parent/profile_editor.dart's API
// (PRD §8 Unit 10 pinned design: "Deleting a profile shows a plain
// confirmation and erases all its local data irreversibly -- progress,
// help records, twister progress, collection; deleted profile leaves zero
// rows"; ticket accept entry 7: "Deleting a profile shows a plain
// confirmation and erases all its local data irreversibly -- progress,
// help records, twister progress, collection; deleted profile leaves zero
// rows (test over local-storage erasure)."). Orchestrator instruction for
// this suite specifically: "delete flow requires confirmation, cascades to
// zero rows (assert across all tables), and cannot be triggered by a
// single tap."
//
// This suite drives the delete affordance through the real UI (not
// straight DAO calls -- that cascading-erasure contract is already pinned
// at the storage layer by test/data/db/erasure_test.dart) and additionally
// verifies the UI-level guarantees the storage suite cannot: a lone tap on
// the delete icon must not erase anything, and only confirming the dialog
// commits the (irreversible) deletion.
//
// lib/features/parent/profile_editor.dart does not exist yet -- this suite
// is EXPECTED to fail to compile until it is written with exactly the
// shape pinned below (a subset of profile_crud_test.dart's pinned surface,
// restated here for this file's self-containedness); that failure IS the
// red state.
//
// Pinned API surface (delete-relevant subset):
//
//   class ProfileEditor extends StatefulWidget {
//     const ProfileEditor({
//       Key? key,
//       required ProfilesDao profilesDao,
//       required PhonicsContent phonicsContent,
//       String Function()? idGenerator,
//     });
//   }
//
//   Keys (pinned, test-load-bearing):
//     Key('profile-row-<localId>')
//     Key('delete-profile-<localId>')     -- IconButton; a single tap opens
//                                            a confirmation dialog and does
//                                            NOT itself delete anything
//     Key('delete-confirm-dialog')        -- the confirmation dialog/sheet
//                                            shown after tapping
//                                            delete-profile-<id>; carries a
//                                            plain-language warning (no
//                                            specific copy pinned)
//     Key('confirm-delete-<localId>')     -- inside the dialog; commits the
//                                            deletion via
//                                            profilesDao.deleteProfile
//                                            (the DAO's own cascading
//                                            erasure across every table --
//                                            StoryProgress, WordHelpRecord,
//                                            TwisterProgress,
//                                            CollectionState -- is already
//                                            pinned by
//                                            test/data/db/erasure_test.dart;
//                                            this suite exercises it
//                                            end-to-end through the UI)
//     Key('cancel-delete-<localId>')      -- inside the dialog; dismisses
//                                            it without deleting anything

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/domain/phonics/scope_sequence_loader.dart';
import 'package:learn_to_read/features/parent/profile_editor.dart';

Profile _profile(String id, {String name = 'Kid'}) => Profile(
  localId: id,
  displayName: name,
  ageBand: AgeBand.sevenToEight,
  currentLevelId: 'level.1',
  micConsent: false,
  cloudAsrConsent: false,
  createdAt: DateTime(2026, 1, 1),
);

/// Minimal single-level fixture -- the delete flow does not exercise
/// placement, so ProfileEditor only needs *some* valid PhonicsContent to
/// construct.
PhonicsContent _minimalContent() => loadPhonicsContent('''
{
  "levels": [
    {"id": "level.1", "ordinal": 1, "format": "sentence", "vocabEnabled": false, "skills": []}
  ],
  "stories": []
}
''');

/// Populates every table this unit owns for [profileId], mirroring the
/// fixture shape in test/data/db/erasure_test.dart so this UI-level suite
/// exercises the same cascading-erasure surface end-to-end.
Future<void> _populateAllTablesFor(AppDatabase db, String profileId) async {
  await db.profilesDao.insertProfile(_profile(profileId, name: profileId));

  await db.storyProgressDao.upsertProgress(
    StoryProgress(
      profileId: profileId,
      storyId: 'story.1',
      status: StoryStatus.available,
      timesRead: 0,
    ),
  );
  await db.storyProgressDao.recordCompletion(
    profileId: profileId,
    storyId: 'story.2',
  );

  await db.wordHelpDao.recordEncounter(profileId: profileId, wordText: 'cat');
  await db.wordHelpDao.recordHelp(
    profileId: profileId,
    wordText: 'cat',
    tier: HelpLevel.soundOut,
  );

  await db.twisterProgressDao.recordCompletion(
    profileId: profileId,
    twisterId: 'twister.1',
  );

  await db.collectionDao.grantCollectible(
    profileId: profileId,
    collectibleId: 'collectible.cat',
  );
}

Future<void> _expectZeroRowsEverywhere(AppDatabase db, String profileId) async {
  expect(await db.profilesDao.getProfile(profileId), isNull, reason: 'Profiles');
  expect(
    await db.storyProgressDao.rowCountForProfile(profileId),
    0,
    reason: 'StoryProgress',
  );
  expect(
    await db.wordHelpDao.rowCountForProfile(profileId),
    0,
    reason: 'WordHelpRecord',
  );
  expect(
    await db.twisterProgressDao.rowCountForProfile(profileId),
    0,
    reason: 'TwisterProgress',
  );
  expect(
    await db.collectionDao.rowCountForProfile(profileId),
    0,
    reason: 'CollectionState',
  );
}

Widget _editorApp(AppDatabase db) {
  return MaterialApp(
    home: Scaffold(
      body: ProfileEditor(
        profilesDao: db.profilesDao,
        phonicsContent: _minimalContent(),
      ),
    ),
  );
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('Delete flow (negative: a single tap never deletes)', () {
    testWidgets(
      'tapping the delete icon alone opens the confirmation dialog and '
      'does NOT remove the profile or any of its data',
      (tester) async {
        await _populateAllTablesFor(db, 'profile.doomed');

        await tester.pumpWidget(_editorApp(db));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('delete-profile-profile.doomed')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('delete-confirm-dialog')),
          findsOneWidget,
          reason: 'a single tap must open a confirmation, not delete',
        );

        expect(await db.profilesDao.getProfile('profile.doomed'), isNotNull);
        expect(
          await db.storyProgressDao.rowCountForProfile('profile.doomed'),
          greaterThan(0),
        );
        expect(
          await db.wordHelpDao.rowCountForProfile('profile.doomed'),
          greaterThan(0),
        );
        expect(
          await db.twisterProgressDao.rowCountForProfile('profile.doomed'),
          greaterThan(0),
        );
        expect(
          await db.collectionDao.rowCountForProfile('profile.doomed'),
          greaterThan(0),
        );
      },
    );

    testWidgets(
      'tapping the delete icon repeatedly (without ever confirming) still '
      'never deletes -- repeated single taps are not a bypass',
      (tester) async {
        await _populateAllTablesFor(db, 'profile.doomed');

        await tester.pumpWidget(_editorApp(db));
        await tester.pumpAndSettle();

        for (var i = 0; i < 3; i++) {
          await tester.tap(find.byKey(const Key('delete-profile-profile.doomed')));
          await tester.pumpAndSettle();
        }

        expect(await db.profilesDao.getProfile('profile.doomed'), isNotNull);
      },
    );
  });

  group('Delete flow (negative: cancel leaves everything intact)', () {
    testWidgets(
      'tapping cancel in the confirmation dialog leaves the profile and '
      'all its data untouched',
      (tester) async {
        await _populateAllTablesFor(db, 'profile.doomed');

        await tester.pumpWidget(_editorApp(db));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('delete-profile-profile.doomed')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('cancel-delete-profile.doomed')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('delete-confirm-dialog')),
          findsNothing,
          reason: 'cancel must dismiss the dialog',
        );
        expect(await db.profilesDao.getProfile('profile.doomed'), isNotNull);
        expect(
          await db.storyProgressDao.rowCountForProfile('profile.doomed'),
          greaterThan(0),
        );
      },
    );
  });

  group(
    'Delete flow (positive: confirming cascades to zero rows across every '
    'table)',
    () {
      testWidgets(
        'confirming the dialog deletes the profile and leaves zero rows in '
        'every table this unit owns',
        (tester) async {
          await _populateAllTablesFor(db, 'profile.doomed');

          await tester.pumpWidget(_editorApp(db));
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(const Key('delete-profile-profile.doomed')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('confirm-delete-profile.doomed')));
          await tester.pumpAndSettle();

          await _expectZeroRowsEverywhere(db, 'profile.doomed');
        },
      );

      testWidgets(
        'the deleted profile disappears from the rendered list after '
        'confirming',
        (tester) async {
          await _populateAllTablesFor(db, 'profile.doomed');

          await tester.pumpWidget(_editorApp(db));
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(const Key('delete-profile-profile.doomed')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('confirm-delete-profile.doomed')));
          await tester.pumpAndSettle();

          expect(
            find.byKey(const Key('profile-row-profile.doomed')),
            findsNothing,
          );
        },
      );

      testWidgets(
        'deleting one profile does not touch a second profile\'s data in '
        'any table (scoped erasure, not a full wipe)',
        (tester) async {
          await _populateAllTablesFor(db, 'profile.doomed');
          await _populateAllTablesFor(db, 'profile.survivor');

          await tester.pumpWidget(_editorApp(db));
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(const Key('delete-profile-profile.doomed')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const Key('confirm-delete-profile.doomed')));
          await tester.pumpAndSettle();

          await _expectZeroRowsEverywhere(db, 'profile.doomed');

          expect(await db.profilesDao.getProfile('profile.survivor'), isNotNull);
          expect(
            await db.storyProgressDao.rowCountForProfile('profile.survivor'),
            2,
          );
          expect(
            await db.wordHelpDao.rowCountForProfile('profile.survivor'),
            1,
          );
          expect(
            await db.twisterProgressDao.rowCountForProfile('profile.survivor'),
            1,
          );
          expect(
            await db.collectionDao.rowCountForProfile('profile.survivor'),
            1,
          );
          expect(
            find.byKey(const Key('profile-row-profile.survivor')),
            findsOneWidget,
            reason: 'the surviving profile must still render',
          );
        },
      );
    },
  );

  group('Delete flow (edge: empty profile deletes cleanly)', () {
    testWidgets(
      'a profile with no progress/help/twister/collection data still '
      'requires confirmation and deletes cleanly to zero rows',
      (tester) async {
        await db.profilesDao.insertProfile(_profile('profile.empty'));

        await tester.pumpWidget(_editorApp(db));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('delete-profile-profile.empty')));
        await tester.pumpAndSettle();
        expect(await db.profilesDao.getProfile('profile.empty'), isNotNull);

        await tester.tap(find.byKey(const Key('confirm-delete-profile.empty')));
        await tester.pumpAndSettle();

        await _expectZeroRowsEverywhere(db, 'profile.empty');
      },
    );
  });
}

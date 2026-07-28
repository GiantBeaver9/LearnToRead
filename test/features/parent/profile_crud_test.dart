// Pins the API of lib/features/parent/profile_editor.dart (PRD §8 Unit 10
// pinned design: "Create/edit/delete profiles: name, age band (sets
// starting level per Unit 2), optional level override."; ticket accept
// entry 3: "Profile CRUD: create/edit/delete with name, age band (sets
// starting level per Unit 2 placement: 5-6 -> level 1; 7-8 -> first
// multiSentence; 9-10 -> first paragraph), optional level override; 5th
// create blocked (tests over local-storage).").
//
// This file covers CREATE (age-band placement, all three bands + parent
// override) and EDIT (name/band) plus the 5th-profile cap error surfacing
// in the UI. Deletion (confirmation + cascading erasure + single-tap
// safety) is pinned separately in erasure_test.dart -- both files exercise
// the same ProfileEditor, split by concern per the ticket's test_files.
//
// lib/features/parent/profile_editor.dart does not exist yet -- this suite
// is EXPECTED to fail to compile until it is written with exactly the
// shape pinned below; that failure IS the red state.
//
// Pinned API surface:
//
//   class ProfileEditor extends StatefulWidget {
//     const ProfileEditor({
//       Key? key,
//       required ProfilesDao profilesDao,
//       required PhonicsContent phonicsContent, // consumed via
//                                                // placeStartingLevel
//                                                // (domain/phonics/
//                                                // placement.dart) to
//                                                // compute currentLevelId
//                                                // on create
//       String Function()? idGenerator,         // defaults to some unique
//                                                // generator; tests inject
//                                                // a deterministic one
//     });
//   }
//
//   Keys (pinned, test-load-bearing):
//     -- Create form (always visible) --
//     Key('create-name-field')                        TextField
//     Key('create-age-band-option-fiveToSix')          tappable, default
//                                                       selected
//     Key('create-age-band-option-sevenToEight')       tappable
//     Key('create-age-band-option-nineToTen')          tappable
//     Key('create-level-override-field')               TextField, optional
//                                                       (empty => no
//                                                       override; a level
//                                                       id string => passed
//                                                       verbatim as
//                                                       placeStartingLevel's
//                                                       parentOverrideLevelId)
//     Key('add-profile-button')                        submits the create
//                                                       form: calls
//                                                       placeStartingLevel
//                                                       then
//                                                       profilesDao.
//                                                       insertProfile
//     Key('profile-cap-error')                          Text, appears only
//                                                       after insertProfile
//                                                       throws
//                                                       MaxProfilesExceededException
//                                                       (device already has
//                                                       4 profiles)
//
//     -- Profile list (one row per stored profile) --
//     Key('profile-row-<localId>')
//     Key('profile-name-text-<localId>')                Text(displayName)
//     Key('profile-band-text-<localId>')                Text(ageBand.label)
//     Key('profile-level-text-<localId>')               Text(currentLevelId)
//     Key('edit-profile-<localId>')                     IconButton, toggles
//                                                       inline edit mode
//                                                       for that row
//     Key('delete-profile-<localId>')                   IconButton (see
//                                                       erasure_test.dart)
//
//     -- Inline edit mode for a row (appears after edit-profile-<id>) --
//     Key('edit-name-field-<localId>')                  TextField,
//                                                       pre-filled with the
//                                                       row's current
//                                                       displayName
//     Key('edit-age-band-option-<localId>-fiveToSix')   tappable, one of
//     Key('edit-age-band-option-<localId>-sevenToEight') three, pre-
//     Key('edit-age-band-option-<localId>-nineToTen')   selected to the
//                                                       row's current
//                                                       ageBand
//     Key('save-edit-<localId>')                        commits: calls
//                                                       profilesDao.
//                                                       updateProfile with
//                                                       the edited name/
//                                                       band, preserving
//                                                       currentLevelId,
//                                                       micConsent,
//                                                       cloudAsrConsent,
//                                                       localId, and
//                                                       createdAt exactly
//                                                       as they were (edit
//                                                       does not
//                                                       re-place the level)
//     Key('cancel-edit-<localId>')                      discards the
//                                                       in-progress edit
//                                                       without any DAO
//                                                       call

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/data/db/daos/profiles_dao.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/domain/phonics/scope_sequence_loader.dart';
import 'package:learn_to_read/features/parent/profile_editor.dart';

PhonicsContent _loadFixtureContent() => loadPhonicsContent(
  File('test/domain/phonics/fixtures/fixture_sequence.json').readAsStringSync(),
);
// Fixture level shape (see the fixture file itself): level-1 (sentence),
// level-2 (sentence), level-3 (multiSentence), level-4 (paragraph). So:
//   5-6   -> level-1 (lowest ordinal)
//   7-8   -> level-3 (first multiSentence)
//   9-10  -> level-4 (first paragraph)

String Function() _counterIdGenerator({String prefix = 'profile'}) {
  var n = 0;
  return () => '$prefix.${n++}';
}

Profile _existingProfile(
  String id, {
  String name = 'Existing',
  AgeBand ageBand = AgeBand.fiveToSix,
  String currentLevelId = 'level-1',
}) => Profile(
  localId: id,
  displayName: name,
  ageBand: ageBand,
  currentLevelId: currentLevelId,
  micConsent: false,
  cloudAsrConsent: false,
  createdAt: DateTime(2026, 1, 1),
);

Widget _editorApp({
  required ProfilesDao profilesDao,
  required PhonicsContent phonicsContent,
  String Function()? idGenerator,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ProfileEditor(
        profilesDao: profilesDao,
        phonicsContent: phonicsContent,
        idGenerator: idGenerator,
      ),
    ),
  );
}

Future<void> _fillCreateForm(
  WidgetTester tester, {
  required String name,
  required String ageBandKeySuffix,
  String? overrideLevelId,
}) async {
  await tester.enterText(find.byKey(const Key('create-name-field')), name);
  await tester.tap(
    find.byKey(Key('create-age-band-option-$ageBandKeySuffix')),
  );
  await tester.pump();
  if (overrideLevelId != null) {
    await tester.enterText(
      find.byKey(const Key('create-level-override-field')),
      overrideLevelId,
    );
  }
}

void main() {
  late AppDatabase db;
  late PhonicsContent content;

  setUpAll(() {
    content = _loadFixtureContent();
  });

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  group('ProfileEditor create flow (positive: age-band placement)', () {
    testWidgets('5-6 band places the new profile at level-1', (tester) async {
      await tester.pumpWidget(
        _editorApp(
          profilesDao: db.profilesDao,
          phonicsContent: content,
          idGenerator: _counterIdGenerator(),
        ),
      );

      await _fillCreateForm(
        tester,
        name: 'Ada',
        ageBandKeySuffix: 'fiveToSix',
      );
      await tester.tap(find.byKey(const Key('add-profile-button')));
      await tester.pumpAndSettle();

      final all = await db.profilesDao.allProfiles();
      expect(all, hasLength(1));
      expect(all.single.displayName, 'Ada');
      expect(all.single.ageBand, AgeBand.fiveToSix);
      expect(all.single.currentLevelId, 'level-1');
    });

    testWidgets(
      '7-8 band places the new profile at the first multiSentence level',
      (tester) async {
        await tester.pumpWidget(
          _editorApp(
            profilesDao: db.profilesDao,
            phonicsContent: content,
            idGenerator: _counterIdGenerator(),
          ),
        );

        await _fillCreateForm(
          tester,
          name: 'Ben',
          ageBandKeySuffix: 'sevenToEight',
        );
        await tester.tap(find.byKey(const Key('add-profile-button')));
        await tester.pumpAndSettle();

        final all = await db.profilesDao.allProfiles();
        expect(all.single.ageBand, AgeBand.sevenToEight);
        expect(all.single.currentLevelId, 'level-3');
      },
    );

    testWidgets(
      '9-10 band places the new profile at the first paragraph level',
      (tester) async {
        await tester.pumpWidget(
          _editorApp(
            profilesDao: db.profilesDao,
            phonicsContent: content,
            idGenerator: _counterIdGenerator(),
          ),
        );

        await _fillCreateForm(
          tester,
          name: 'Cy',
          ageBandKeySuffix: 'nineToTen',
        );
        await tester.tap(find.byKey(const Key('add-profile-button')));
        await tester.pumpAndSettle();

        final all = await db.profilesDao.allProfiles();
        expect(all.single.ageBand, AgeBand.nineToTen);
        expect(all.single.currentLevelId, 'level-4');
      },
    );

    testWidgets(
      'a parent level override wins outright over the age-band default',
      (tester) async {
        await tester.pumpWidget(
          _editorApp(
            profilesDao: db.profilesDao,
            phonicsContent: content,
            idGenerator: _counterIdGenerator(),
          ),
        );

        // 5-6 would normally place at level-1; override to level-2.
        await _fillCreateForm(
          tester,
          name: 'Dee',
          ageBandKeySuffix: 'fiveToSix',
          overrideLevelId: 'level-2',
        );
        await tester.tap(find.byKey(const Key('add-profile-button')));
        await tester.pumpAndSettle();

        final all = await db.profilesDao.allProfiles();
        expect(all.single.ageBand, AgeBand.fiveToSix);
        expect(
          all.single.currentLevelId,
          'level-2',
          reason: 'override must win over the age-band default',
        );
      },
    );

    testWidgets(
      'the new profile appears in the rendered list after creation',
      (tester) async {
        await tester.pumpWidget(
          _editorApp(
            profilesDao: db.profilesDao,
            phonicsContent: content,
            idGenerator: _counterIdGenerator(),
          ),
        );

        await _fillCreateForm(
          tester,
          name: 'Ada',
          ageBandKeySuffix: 'fiveToSix',
        );
        await tester.tap(find.byKey(const Key('add-profile-button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('profile-row-profile.0')), findsOneWidget);
        expect(
          find.descendant(
            of: find.byKey(const Key('profile-row-profile.0')),
            matching: find.text('Ada'),
          ),
          findsOneWidget,
        );
      },
    );
  });

  group('ProfileEditor create flow (negative: 5th profile blocked)', () {
    testWidgets(
      'attempting to create a 5th profile surfaces the cap error and does '
      'not add a row',
      (tester) async {
        for (final id in ['p1', 'p2', 'p3', 'p4']) {
          await db.profilesDao.insertProfile(_existingProfile(id, name: id));
        }

        await tester.pumpWidget(
          _editorApp(
            profilesDao: db.profilesDao,
            phonicsContent: content,
            idGenerator: _counterIdGenerator(prefix: 'newp'),
          ),
        );
        await tester.pumpAndSettle();

        await _fillCreateForm(
          tester,
          name: 'FifthKid',
          ageBandKeySuffix: 'fiveToSix',
        );
        await tester.tap(find.byKey(const Key('add-profile-button')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('profile-cap-error')),
          findsOneWidget,
          reason: 'the 5th create attempt must surface a cap error in the UI',
        );

        final all = await db.profilesDao.allProfiles();
        expect(
          all,
          hasLength(4),
          reason: 'the failed 5th create must not add a row',
        );
        expect(
          all.map((p) => p.displayName),
          isNot(contains('FifthKid')),
        );
      },
    );

    testWidgets(
      'freeing a slot by deleting one of the 4 profiles allows a new '
      'create to succeed again',
      (tester) async {
        for (final id in ['p1', 'p2', 'p3', 'p4']) {
          await db.profilesDao.insertProfile(_existingProfile(id, name: id));
        }
        await db.profilesDao.deleteProfile('p1');

        await tester.pumpWidget(
          _editorApp(
            profilesDao: db.profilesDao,
            phonicsContent: content,
            idGenerator: _counterIdGenerator(prefix: 'newp'),
          ),
        );
        await tester.pumpAndSettle();

        await _fillCreateForm(
          tester,
          name: 'RoomAgain',
          ageBandKeySuffix: 'fiveToSix',
        );
        await tester.tap(find.byKey(const Key('add-profile-button')));
        await tester.pumpAndSettle();

        final all = await db.profilesDao.allProfiles();
        expect(all, hasLength(4));
        expect(all.map((p) => p.displayName), contains('RoomAgain'));
      },
    );
  });

  group('ProfileEditor edit flow (positive: name/band update)', () {
    testWidgets(
      'editing a profile updates name and age band, leaving level/consent/'
      'identity fields untouched',
      (tester) async {
        final original = _existingProfile(
          'p1',
          name: 'Ada',
          ageBand: AgeBand.fiveToSix,
          currentLevelId: 'level-1',
        );
        await db.profilesDao.insertProfile(original);

        await tester.pumpWidget(
          _editorApp(profilesDao: db.profilesDao, phonicsContent: content),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('edit-profile-p1')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('edit-name-field-p1')),
          'Adaeze',
        );
        await tester.tap(
          find.byKey(const Key('edit-age-band-option-p1-sevenToEight')),
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('save-edit-p1')));
        await tester.pumpAndSettle();

        final updated = await db.profilesDao.getProfile('p1');
        expect(updated!.displayName, 'Adaeze');
        expect(updated.ageBand, AgeBand.sevenToEight);
        expect(
          updated.currentLevelId,
          'level-1',
          reason: 'editing name/band alone must not re-place the level',
        );
        expect(updated.localId, 'p1');
        expect(updated.createdAt, original.createdAt);
        expect(updated.micConsent, original.micConsent);
        expect(updated.cloudAsrConsent, original.cloudAsrConsent);
      },
    );

    testWidgets(
      'the edited name/band renders in the list after saving',
      (tester) async {
        await db.profilesDao.insertProfile(_existingProfile('p1', name: 'Ada'));

        await tester.pumpWidget(
          _editorApp(profilesDao: db.profilesDao, phonicsContent: content),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('edit-profile-p1')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('edit-name-field-p1')),
          'Adaeze',
        );
        await tester.tap(find.byKey(const Key('save-edit-p1')));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(const Key('profile-row-p1')),
            matching: find.text('Adaeze'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const Key('profile-row-p1')),
            matching: find.text('Ada'),
          ),
          findsNothing,
        );
      },
    );
  });

  group('ProfileEditor edit flow (edge: cancel discards changes)', () {
    testWidgets(
      'cancelling an in-progress edit makes no DAO call and leaves the '
      'stored profile unchanged',
      (tester) async {
        final original = _existingProfile('p1', name: 'Ada');
        await db.profilesDao.insertProfile(original);

        await tester.pumpWidget(
          _editorApp(profilesDao: db.profilesDao, phonicsContent: content),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('edit-profile-p1')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('edit-name-field-p1')),
          'Should Not Persist',
        );
        await tester.tap(find.byKey(const Key('cancel-edit-p1')));
        await tester.pumpAndSettle();

        final stored = await db.profilesDao.getProfile('p1');
        expect(stored, equals(original));
      },
    );
  });
}

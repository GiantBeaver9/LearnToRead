// Pins the API of lib/features/parent/consent_controller.dart (PRD §8
// Unit 10 pinned design: "Per-child microphone toggle (default off until
// enabled). A cloud processing toggle appears only if a cloud engine is in
// use ... Consent state changes take effect immediately (Unit 4 reads them
// per session start and on change)."; PRD §6: "no ... mic toggles in the
// parent corner" baseline; ticket accept entry 6: "Consent matrix tests
// (transcribed): mic off -> reading uses tap-only mode and the mic is
// never requested; mic on -> recognition enabled; OS-level mic permission
// denial handled gracefully -> tap mode (permission service faked);
// consent changes take effect immediately (tracker hook re-read per
// session start and on change)." and entry 5: "Per-child microphone toggle
// defaults OFF until enabled; a cloud-processing toggle appears ONLY if a
// cloud engine is in use ... test both engine configurations."
//
// lib/features/parent/consent_controller.dart does not exist yet -- this
// suite is EXPECTED to fail to compile until it is written with exactly
// the shape pinned below; that failure IS the red state.
//
// Pinned API surface (this ticket has no dependency on the listening
// pipeline unit, so the mic-permission plumbing needed to exercise the
// consent matrix is defined and owned entirely inside this one file):
//
//   enum MicPermissionStatus { granted, denied, notDetermined }
//
//   abstract class MicPermissionService {
//     Future<MicPermissionStatus> requestPermission();
//   }
//
//   /// Test/POC fake: records whether it was ever asked, returns a fixed
//   /// canned [result].
//   class FakeMicPermissionService implements MicPermissionService {
//     FakeMicPermissionService(MicPermissionStatus result);
//     bool get wasRequested;
//     @override
//     Future<MicPermissionStatus> requestPermission();
//   }
//
//   enum ReadingMode { tapOnly, deviceRecognition, cloudRecognition }
//
//   /// Pure combinator: no OS/permission call, given a resolved
//   /// [MicPermissionStatus].
//   ReadingMode resolveReadingMode({
//     required bool micConsent,
//     required MicPermissionStatus permissionStatus,
//     required bool cloudEngineInUse,
//     bool cloudAsrConsent = false,
//   });
//
//   /// The full flow a reading-screen entry (or session start) runs: only
//   /// calls [permissionService.requestPermission] when [micConsent] is
//   /// true -- pinning "mic is never requested" when consent is off.
//   Future<ReadingMode> resolveReadingModeWithPermissionCheck({
//     required bool micConsent,
//     required MicPermissionService permissionService,
//     required bool cloudEngineInUse,
//     bool cloudAsrConsent = false,
//   });
//
//   class ConsentController extends StatefulWidget {
//     const ConsentController({
//       Key? key,
//       required Profile profile,
//       required ProfilesDao profilesDao,
//       required bool cloudEngineInUse,
//       void Function(Profile updated)? onConsentChanged, // the "tracker
//                                                          // hook re-read
//                                                          // ... on change"
//                                                          // seam
//     });
//   }
//
//   Keys (pinned, test-load-bearing):
//     Key('mic-consent-toggle-<localId>')    -- a Switch/Checkbox-like
//                                                toggle; `value` mirrors
//                                                Profile.micConsent
//     Key('cloud-consent-toggle-<localId>')  -- rendered ONLY when
//                                                cloudEngineInUse is true;
//                                                absent (findsNothing)
//                                                otherwise

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/features/parent/consent_controller.dart';

Profile _profile(
  String id, {
  bool micConsent = false,
  bool cloudAsrConsent = false,
}) => Profile(
  localId: id,
  displayName: 'Kid $id',
  ageBand: AgeBand.fiveToSix,
  currentLevelId: 'level.1',
  micConsent: micConsent,
  cloudAsrConsent: cloudAsrConsent,
  createdAt: DateTime(2026, 1, 1),
);

Widget _consentApp({
  required Profile profile,
  required ProfilesDao profilesDao,
  required bool cloudEngineInUse,
  void Function(Profile updated)? onConsentChanged,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ConsentController(
        profile: profile,
        profilesDao: profilesDao,
        cloudEngineInUse: cloudEngineInUse,
        onConsentChanged: onConsentChanged,
      ),
    ),
  );
}

void main() {
  group('resolveReadingMode (positive: pure decision matrix)', () {
    test('mic off -> tapOnly, regardless of everything else', () {
      expect(
        resolveReadingMode(
          micConsent: false,
          permissionStatus: MicPermissionStatus.granted,
          cloudEngineInUse: true,
          cloudAsrConsent: true,
        ),
        ReadingMode.tapOnly,
      );
    });

    test(
      'mic on + permission granted + on-device engine -> deviceRecognition',
      () {
        expect(
          resolveReadingMode(
            micConsent: true,
            permissionStatus: MicPermissionStatus.granted,
            cloudEngineInUse: false,
          ),
          ReadingMode.deviceRecognition,
        );
      },
    );

    test(
      'mic on + permission granted + cloud engine in use + cloud consent '
      '-> cloudRecognition',
      () {
        expect(
          resolveReadingMode(
            micConsent: true,
            permissionStatus: MicPermissionStatus.granted,
            cloudEngineInUse: true,
            cloudAsrConsent: true,
          ),
          ReadingMode.cloudRecognition,
        );
      },
    );
  });

  group('resolveReadingMode (negative: denial and withheld consent)', () {
    test(
      'mic on + OS permission denied -> tapOnly (graceful fallback, no '
      'crash/exception)',
      () {
        expect(
          resolveReadingMode(
            micConsent: true,
            permissionStatus: MicPermissionStatus.denied,
            cloudEngineInUse: false,
          ),
          ReadingMode.tapOnly,
        );
      },
    );

    test(
      'cloud engine in use but cloud consent withheld -> falls back to '
      'deviceRecognition, never cloudRecognition',
      () {
        expect(
          resolveReadingMode(
            micConsent: true,
            permissionStatus: MicPermissionStatus.granted,
            cloudEngineInUse: true,
            cloudAsrConsent: false,
          ),
          ReadingMode.deviceRecognition,
        );
      },
    );
  });

  group('resolveReadingMode (edge: not-yet-determined permission)', () {
    test(
      'mic on + permission notDetermined -> tapOnly (never optimistically '
      'grants recognition)',
      () {
        expect(
          resolveReadingMode(
            micConsent: true,
            permissionStatus: MicPermissionStatus.notDetermined,
            cloudEngineInUse: false,
          ),
          ReadingMode.tapOnly,
        );
      },
    );
  });

  group(
    'resolveReadingModeWithPermissionCheck (positive + negative: the mic '
    'is never requested when consent is off)',
    () {
      test(
        'mic consent off -> permission service is never asked, result is '
        'tapOnly',
        () async {
          final service = FakeMicPermissionService(MicPermissionStatus.granted);

          final mode = await resolveReadingModeWithPermissionCheck(
            micConsent: false,
            permissionService: service,
            cloudEngineInUse: false,
          );

          expect(mode, ReadingMode.tapOnly);
          expect(
            service.wasRequested,
            isFalse,
            reason: 'mic must never be requested when consent is off',
          );
        },
      );

      test(
        'mic consent on -> permission service IS asked, and a granted '
        'result yields deviceRecognition',
        () async {
          final service = FakeMicPermissionService(MicPermissionStatus.granted);

          final mode = await resolveReadingModeWithPermissionCheck(
            micConsent: true,
            permissionService: service,
            cloudEngineInUse: false,
          );

          expect(mode, ReadingMode.deviceRecognition);
          expect(service.wasRequested, isTrue);
        },
      );

      test(
        'mic consent on but OS denies -> gracefully falls to tapOnly',
        () async {
          final service = FakeMicPermissionService(MicPermissionStatus.denied);

          final mode = await resolveReadingModeWithPermissionCheck(
            micConsent: true,
            permissionService: service,
            cloudEngineInUse: false,
          );

          expect(mode, ReadingMode.tapOnly);
          expect(service.wasRequested, isTrue);
        },
      );
    },
  );

  group('ConsentController widget (positive: default-off + persistence)', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    testWidgets('mic toggle defaults OFF for a freshly created profile', (
      tester,
    ) async {
      final profile = _profile('p1', micConsent: false);
      await db.profilesDao.insertProfile(profile);

      await tester.pumpWidget(
        _consentApp(
          profile: profile,
          profilesDao: db.profilesDao,
          cloudEngineInUse: false,
        ),
      );

      final toggle = tester.widget<Switch>(
        find.byKey(const Key('mic-consent-toggle-p1')),
      );
      expect(toggle.value, isFalse);
    });

    testWidgets(
      'toggling mic on persists to the database immediately, with no '
      'separate save step',
      (tester) async {
        final profile = _profile('p1', micConsent: false);
        await db.profilesDao.insertProfile(profile);

        await tester.pumpWidget(
          _consentApp(
            profile: profile,
            profilesDao: db.profilesDao,
            cloudEngineInUse: false,
          ),
        );

        await tester.tap(find.byKey(const Key('mic-consent-toggle-p1')));
        await tester.pump();

        final stored = await db.profilesDao.getProfile('p1');
        expect(
          stored!.micConsent,
          isTrue,
          reason: 'consent changes take effect immediately (PRD §8 Unit 10)',
        );
      },
    );

    testWidgets(
      'toggling mic off after it was on persists the reversal immediately',
      (tester) async {
        final profile = _profile('p1', micConsent: true);
        await db.profilesDao.insertProfile(profile);

        await tester.pumpWidget(
          _consentApp(
            profile: profile,
            profilesDao: db.profilesDao,
            cloudEngineInUse: false,
          ),
        );

        await tester.tap(find.byKey(const Key('mic-consent-toggle-p1')));
        await tester.pump();

        final stored = await db.profilesDao.getProfile('p1');
        expect(stored!.micConsent, isFalse);
      },
    );

    testWidgets(
      'onConsentChanged fires with the freshly-persisted profile on every '
      'toggle -- the tracker-hook-re-read-on-change seam',
      (tester) async {
        final profile = _profile('p1', micConsent: false);
        await db.profilesDao.insertProfile(profile);
        final changes = <Profile>[];

        await tester.pumpWidget(
          _consentApp(
            profile: profile,
            profilesDao: db.profilesDao,
            cloudEngineInUse: false,
            onConsentChanged: changes.add,
          ),
        );

        await tester.tap(find.byKey(const Key('mic-consent-toggle-p1')));
        await tester.pump();

        expect(changes, hasLength(1));
        expect(changes.single.micConsent, isTrue);
      },
    );

    testWidgets(
      'a consent change made in one instance is visible to a freshly '
      'constructed instance reading the same profile -- simulating a new '
      'session start reading the latest consent, not a stale value',
      (tester) async {
        final profile = _profile('p1', micConsent: false);
        await db.profilesDao.insertProfile(profile);

        await tester.pumpWidget(
          _consentApp(
            profile: profile,
            profilesDao: db.profilesDao,
            cloudEngineInUse: false,
          ),
        );
        await tester.tap(find.byKey(const Key('mic-consent-toggle-p1')));
        await tester.pump();

        // Simulate a brand-new session: fetch the profile fresh from the
        // DB (as session start does) and mount a fresh ConsentController.
        final freshProfile = await db.profilesDao.getProfile('p1');
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(
          _consentApp(
            profile: freshProfile!,
            profilesDao: db.profilesDao,
            cloudEngineInUse: false,
          ),
        );

        final toggle = tester.widget<Switch>(
          find.byKey(const Key('mic-consent-toggle-p1')),
        );
        expect(toggle.value, isTrue);
      },
    );
  });

  group(
    'ConsentController widget (positive + negative: cloud toggle gated on '
    'engine configuration -- both configurations tested)',
    () {
      late AppDatabase db;

      setUp(() {
        db = AppDatabase(NativeDatabase.memory());
      });

      tearDown(() async {
        await db.close();
      });

      testWidgets(
        'cloudEngineInUse=true renders the cloud-processing toggle',
        (tester) async {
          final profile = _profile('p1');
          await db.profilesDao.insertProfile(profile);

          await tester.pumpWidget(
            _consentApp(
              profile: profile,
              profilesDao: db.profilesDao,
              cloudEngineInUse: true,
            ),
          );

          expect(
            find.byKey(const Key('cloud-consent-toggle-p1')),
            findsOneWidget,
          );
        },
      );

      testWidgets(
        'cloudEngineInUse=false (POC default, on-device per A-10) hides '
        'the cloud toggle entirely -- typically mic only',
        (tester) async {
          final profile = _profile('p1');
          await db.profilesDao.insertProfile(profile);

          await tester.pumpWidget(
            _consentApp(
              profile: profile,
              profilesDao: db.profilesDao,
              cloudEngineInUse: false,
            ),
          );

          expect(
            find.byKey(const Key('cloud-consent-toggle-p1')),
            findsNothing,
          );
          expect(
            find.byKey(const Key('mic-consent-toggle-p1')),
            findsOneWidget,
            reason: 'the mic toggle is always present regardless of engine',
          );
        },
      );

      testWidgets(
        'toggling cloud consent (when the toggle is present) persists '
        'cloudAsrConsent immediately',
        (tester) async {
          final profile = _profile('p1', micConsent: true);
          await db.profilesDao.insertProfile(profile);

          await tester.pumpWidget(
            _consentApp(
              profile: profile,
              profilesDao: db.profilesDao,
              cloudEngineInUse: true,
            ),
          );

          await tester.tap(find.byKey(const Key('cloud-consent-toggle-p1')));
          await tester.pump();

          final stored = await db.profilesDao.getProfile('p1');
          expect(stored!.cloudAsrConsent, isTrue);
        },
      );
    },
  );
}

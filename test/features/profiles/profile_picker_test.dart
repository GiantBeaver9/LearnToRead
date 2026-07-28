// Pins the API of lib/features/profiles/profile_picker_screen.dart and
// lib/features/profiles/profile_avatar.dart (PRD §8 Unit 10 pinned design:
// "Up to 4 local profiles; child-facing profile picker at launch
// (icon/avatar based, no reading required)"; ticket profiles-parent-corner
// accept entry 1: "Child-facing profile picker at launch: icon/avatar
// based, no reading required to navigate (icons + voice prompt hooks); up
// to 4 profiles shown; selecting one enters that child's home (map) and
// triggers session_start semantics via the injected hook (widget tests).").
//
// Neither file exists yet -- this suite is EXPECTED to fail to compile
// until they are written with exactly the shape pinned below; that failure
// IS the red state.
//
// Pinned API surface:
//
//   class ProfilePickerScreen extends StatelessWidget {
//     const ProfilePickerScreen({
//       Key? key,
//       required List<Profile> profiles,          // rendered in list order;
//                                                  // never more than
//                                                  // kMaxProfilesPerDevice
//                                                  // in real use (enforced
//                                                  // upstream by
//                                                  // ProfilesDao)
//       required void Function(Profile profile, int profileOrdinal)
//           onProfileSelected,                    // the injected hook:
//                                                  // profileOrdinal is the
//                                                  // 1-based position of
//                                                  // the tapped profile
//                                                  // within `profiles`,
//                                                  // exactly what
//                                                  // SessionTracker.
//                                                  // startSession's
//                                                  // profileOrdinal input
//                                                  // (PRD §5 "profile
//                                                  // ordinal (1-4)") needs
//       void Function(Profile profile)? onVoicePrompt, // optional: fires
//                                                  // when a tile is tapped,
//                                                  // BEFORE onProfileSelected
//                                                  // -- the "voice prompt
//                                                  // hook" seam the (later,
//                                                  // owner-recorded) audio
//                                                  // system hangs a ref off
//                                                  // of; PRD notes: "Voice
//                                                  // -prompt audio refs for
//                                                  // navigation are
//                                                  // owner-recorded content
//                                                  // -- placeholder refs."
//     });
//   }
//
//   Keys (pinned, test-load-bearing):
//     Key('profile-picker-tile-<localId>')  -- one per profile, tappable
//     Key('profile-avatar-<localId>')       -- the ProfileAvatar within
//                                              each tile; must contain a
//                                              descendant Icon (icon-first,
//                                              no-reading-required
//                                              identification)
//
//   class ProfileAvatar extends StatelessWidget {
//     const ProfileAvatar({Key? key, required Profile profile});
//   }
//   -- renders some Icon deterministically from the profile. The exact icon
//   mapping is a builder decision (not PRD-pinned); only "renders an Icon
//   descendant" is asserted here.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/features/profiles/profile_avatar.dart';
import 'package:learn_to_read/features/profiles/profile_picker_screen.dart';

Profile _profile(String id, {String name = 'Kid'}) => Profile(
  localId: id,
  displayName: name,
  ageBand: AgeBand.fiveToSix,
  currentLevelId: 'level.1',
  micConsent: false,
  cloudAsrConsent: false,
  createdAt: DateTime(2026, 1, 1),
);

Widget _pickerApp({
  required List<Profile> profiles,
  required void Function(Profile profile, int profileOrdinal)
  onProfileSelected,
  void Function(Profile profile)? onVoicePrompt,
}) {
  return MaterialApp(
    home: Scaffold(
      body: ProfilePickerScreen(
        profiles: profiles,
        onProfileSelected: onProfileSelected,
        onVoicePrompt: onVoicePrompt,
      ),
    ),
  );
}

void main() {
  group('ProfilePickerScreen rendering (positive)', () {
    testWidgets(
      'renders one tappable, icon-first tile per profile (up to 4)',
      (tester) async {
        final profiles = [
          _profile('p1', name: 'Ada'),
          _profile('p2', name: 'Ben'),
          _profile('p3', name: 'Cy'),
          _profile('p4', name: 'Dee'),
        ];

        await tester.pumpWidget(
          _pickerApp(profiles: profiles, onProfileSelected: (_, __) {}),
        );

        for (final p in profiles) {
          final tile = find.byKey(Key('profile-picker-tile-${p.localId}'));
          expect(
            tile,
            findsOneWidget,
            reason: 'every profile in the list must render a tile',
          );

          final avatar = find.byKey(Key('profile-avatar-${p.localId}'));
          expect(avatar, findsOneWidget);

          final iconWithinAvatar = find.descendant(
            of: avatar,
            matching: find.byType(Icon),
          );
          expect(
            iconWithinAvatar,
            findsWidgets,
            reason:
                'icon-first identification: each avatar must render an '
                'Icon so a non-reading child can identify their profile',
          );
        }
      },
    );

    testWidgets('renders correctly with a single profile', (tester) async {
      final profiles = [_profile('solo', name: 'Solo')];

      await tester.pumpWidget(
        _pickerApp(profiles: profiles, onProfileSelected: (_, __) {}),
      );

      expect(find.byKey(const Key('profile-picker-tile-solo')), findsOneWidget);
    });
  });

  group('ProfilePickerScreen selection callback (positive)', () {
    testWidgets(
      'tapping a tile fires onProfileSelected exactly once, with that '
      'profile and its 1-based ordinal position',
      (tester) async {
        final profiles = [
          _profile('p1', name: 'Ada'),
          _profile('p2', name: 'Ben'),
          _profile('p3', name: 'Cy'),
        ];
        final calls = <(Profile, int)>[];

        await tester.pumpWidget(
          _pickerApp(
            profiles: profiles,
            onProfileSelected: (profile, ordinal) =>
                calls.add((profile, ordinal)),
          ),
        );

        await tester.tap(find.byKey(const Key('profile-picker-tile-p2')));
        await tester.pump();

        expect(
          calls,
          hasLength(1),
          reason: 'exactly one selection fires per tap',
        );
        expect(calls.single.$1, profiles[1]);
        expect(
          calls.single.$2,
          2,
          reason: 'p2 is at index 1, so its ordinal is 1-based position 2',
        );
      },
    );

    testWidgets(
      'selecting the first profile fires ordinal 1, and the last of 4 '
      'fires ordinal 4',
      (tester) async {
        final profiles = [
          _profile('p1'),
          _profile('p2'),
          _profile('p3'),
          _profile('p4'),
        ];
        final ordinals = <int>[];

        await tester.pumpWidget(
          _pickerApp(
            profiles: profiles,
            onProfileSelected: (_, ordinal) => ordinals.add(ordinal),
          ),
        );

        await tester.tap(find.byKey(const Key('profile-picker-tile-p1')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('profile-picker-tile-p4')));
        await tester.pump();

        expect(ordinals, [1, 4]);
      },
    );

    testWidgets(
      'the optional voice-prompt hook fires on tap, before selection',
      (tester) async {
        final profiles = [_profile('p1', name: 'Ada')];
        final events = <String>[];

        await tester.pumpWidget(
          _pickerApp(
            profiles: profiles,
            onProfileSelected: (profile, _) =>
                events.add('selected:${profile.localId}'),
            onVoicePrompt: (profile) =>
                events.add('voicePrompt:${profile.localId}'),
          ),
        );

        await tester.tap(find.byKey(const Key('profile-picker-tile-p1')));
        await tester.pump();

        expect(events, ['voicePrompt:p1', 'selected:p1']);
      },
    );
  });

  group('ProfilePickerScreen selection callback (negative)', () {
    testWidgets(
      'tapping profile A never invokes the callback with profile B\'s '
      'identity',
      (tester) async {
        final profileA = _profile('A', name: 'Ada');
        final profileB = _profile('B', name: 'Ben');
        Profile? selected;

        await tester.pumpWidget(
          _pickerApp(
            profiles: [profileA, profileB],
            onProfileSelected: (profile, _) => selected = profile,
          ),
        );

        await tester.tap(find.byKey(const Key('profile-picker-tile-A')));
        await tester.pump();

        expect(selected, profileA);
        expect(selected, isNot(profileB));
      },
    );

    testWidgets(
      'without a voice-prompt hook supplied, tapping still selects '
      'normally (the hook is optional, not required)',
      (tester) async {
        final profiles = [_profile('p1')];
        var selectedCount = 0;

        await tester.pumpWidget(
          _pickerApp(
            profiles: profiles,
            onProfileSelected: (_, __) => selectedCount++,
          ),
        );

        await tester.tap(find.byKey(const Key('profile-picker-tile-p1')));
        await tester.pump();

        expect(selectedCount, 1);
      },
    );
  });

  group('ProfilePickerScreen (edge)', () {
    testWidgets(
      'all four tiles at the device cap render as distinct, independently '
      'tappable widgets',
      (tester) async {
        final profiles = [
          _profile('p1'),
          _profile('p2'),
          _profile('p3'),
          _profile('p4'),
        ];
        final selectedIds = <String>[];

        await tester.pumpWidget(
          _pickerApp(
            profiles: profiles,
            onProfileSelected: (profile, _) => selectedIds.add(profile.localId),
          ),
        );

        for (final p in profiles) {
          await tester.tap(find.byKey(Key('profile-picker-tile-${p.localId}')));
          await tester.pump();
        }

        expect(selectedIds, ['p1', 'p2', 'p3', 'p4']);
      },
    );
  });
}

// Test suite for the awake/muted derivation in
// lib/features/sound_garden/sound_card_controller.dart, plus the tap-gating
// contrast in lib/features/sound_garden/sound_card.dart (PRD §8 Unit 15
// "Visibility (ratified)"; ticket sound-garden accept entry 2).
//
// Neither lib/features/sound_garden/sound_card_controller.dart nor
// lib/features/sound_garden/sound_card.dart exist yet: every import below
// fails to resolve, which is the expected red state.
//
// See sound_garden_screen_test.dart for the canonical pinned API. This file
// restates only the two relevant slices:
//
//   enum CardWakeState { awake, muted }
//   CardWakeState wakeStateFor({
//     required GraphemeSound card,
//     required Profile profile,
//     required List<Level> levels,
//   });
//   -- awake iff card.introducedAtLevelId's ordinal <=
//      profile.currentLevelId's ordinal (INCLUSIVE boundary); ordinals
//      resolved via `levels.firstWhere((l) => l.id == ...)`.
//
//   enum CardEchoState { hidden, listening, matched }
//   class SoundCardWidget extends StatelessWidget {
//     const SoundCardWidget({
//       super.key,
//       required GraphemeSound card,
//       required CardWakeState wakeState,
//       CardEchoState echoState = CardEchoState.hidden,
//       required VoidCallback onTap,
//     });
//   }
//   -- onTap is wired UNCONDITIONALLY, regardless of wakeState (pinned
//      contrast vs MapNode's `onTap: isTappable ? onTap : null` asleep-node
//      gating -- see map_states_test.dart). A muted card is still fully
//      tappable and, by the same tap path, echoable.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/features/sound_garden/sound_card.dart';
import 'package:learn_to_read/features/sound_garden/sound_card_controller.dart';

List<Level> _levels() => [
      for (var i = 1; i <= 5; i++)
        Level(
          id: 'level.$i',
          ordinal: i,
          newSkills: const [],
          format: LevelFormat.sentence,
          vocabEnabled: false,
        ),
    ];

GraphemeSound _card(String introducedAtLevelId) => GraphemeSound(
      id: 'gs.sh',
      grapheme: 'sh',
      phonemeIds: const ['SH'],
      introducedAtLevelId: introducedAtLevelId,
      exampleWords: const [],
    );

Profile _profile(String currentLevelId) => Profile(
      localId: 'profile.amara',
      displayName: 'Amara',
      ageBand: AgeBand.fiveToSix,
      currentLevelId: currentLevelId,
      micConsent: true,
      cloudAsrConsent: false,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  group('wakeStateFor — pure derivation over fixture profiles at '
      'different levels (accept 2)', () {
    test('POSITIVE: introducedAtLevelId strictly below the profile level '
        '-> awake', () {
      expect(
        wakeStateFor(card: _card('level.1'), profile: _profile('level.3'), levels: _levels()),
        CardWakeState.awake,
      );
    });

    test('EDGE: introducedAtLevelId EXACTLY EQUAL to the profile level -> '
        'awake (inclusive boundary, PRD "introducedAtLevelId <= profile '
        'currentLevelId")', () {
      expect(
        wakeStateFor(card: _card('level.3'), profile: _profile('level.3'), levels: _levels()),
        CardWakeState.awake,
      );
    });

    test('NEGATIVE: introducedAtLevelId strictly above the profile level '
        '-> muted (present, not filtered out -- callers still render it)',
        () {
      expect(
        wakeStateFor(card: _card('level.4'), profile: _profile('level.3'), levels: _levels()),
        CardWakeState.muted,
      );
    });

    test('POSITIVE: a fixture profile at the lowest level (level.1) sees '
        'the level.1 card awake and every higher-level card muted', () {
      final profile = _profile('level.1');
      final levels = _levels();
      expect(wakeStateFor(card: _card('level.1'), profile: profile, levels: levels),
          CardWakeState.awake);
      expect(wakeStateFor(card: _card('level.2'), profile: profile, levels: levels),
          CardWakeState.muted);
      expect(wakeStateFor(card: _card('level.5'), profile: profile, levels: levels),
          CardWakeState.muted);
    });

    test('POSITIVE: a fixture profile at the highest level (level.5) sees '
        'every card awake, including the level.5 boundary card', () {
      final profile = _profile('level.5');
      final levels = _levels();
      for (var i = 1; i <= 5; i++) {
        expect(
          wakeStateFor(card: _card('level.$i'), profile: profile, levels: levels),
          CardWakeState.awake,
          reason: 'level.$i should be awake for a level.5 profile',
        );
      }
    });

    test('EDGE: an unresolvable card level id throws ArgumentError rather '
        'than silently defaulting a wake state', () {
      expect(
        () => wakeStateFor(
          card: _card('level.unknown'),
          profile: _profile('level.3'),
          levels: _levels(),
        ),
        throwsArgumentError,
      );
    });
  });

  group('SoundCardWidget — muted cards remain fully tappable and echoable '
      '(accept 2)', () {
    testWidgets('POSITIVE: a MUTED card still invokes onTap when tapped '
        '(same tap path as an awake card -- no special-casing)', (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SoundCardWidget(
            card: _card('level.9'),
            wakeState: CardWakeState.muted,
            onTap: () => tapped = true,
          ),
        ),
      ));

      await tester.tap(find.byKey(const ValueKey('sound-card-gs.sh')));
      await tester.pump();

      expect(tapped, isTrue,
          reason: 'PRD §8 Unit 15: muted cards are still fully tappable and '
              'echoable -- tapping must never be swallowed');
    });

    testWidgets('POSITIVE: an AWAKE card invokes onTap identically', (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SoundCardWidget(
            card: _card('level.1'),
            wakeState: CardWakeState.awake,
            onTap: () => tapped = true,
          ),
        ),
      ));

      await tester.tap(find.byKey(const ValueKey('sound-card-gs.sh')));
      await tester.pump();

      expect(tapped, isTrue);
    });

    testWidgets('POSITIVE: a muted card exposes the same '
        'sound-card-echo-prompt-<id> marker as an awake card once '
        'echoState is listening -- muted never suppresses the echo prompt',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SoundCardWidget(
            card: _card('level.9'),
            wakeState: CardWakeState.muted,
            echoState: CardEchoState.listening,
            onTap: () {},
          ),
        ),
      ));
      await tester.pump();

      expect(find.byKey(const ValueKey('sound-card-echo-prompt-gs.sh')), findsOneWidget);
    });

    testWidgets('NEGATIVE: a muted card is visually distinguishable via the '
        'sound-card-muted-<id> marker (present), while an awake card never '
        'carries it (absent)', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SoundCardWidget(
            card: _card('level.9'),
            wakeState: CardWakeState.muted,
            onTap: () {},
          ),
        ),
      ));
      await tester.pump();
      expect(find.byKey(const ValueKey('sound-card-muted-gs.sh')), findsOneWidget);

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SoundCardWidget(
            card: _card('level.1'),
            wakeState: CardWakeState.awake,
            onTap: () {},
          ),
        ),
      ));
      await tester.pump();
      expect(find.byKey(const ValueKey('sound-card-muted-gs.sh')), findsNothing);
    });
  });
}

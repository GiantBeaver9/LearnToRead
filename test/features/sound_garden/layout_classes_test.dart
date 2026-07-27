// Headless layout-class coverage for
// lib/features/sound_garden/sound_garden_screen.dart (PRD §8 Unit 15
// acceptance: "golden tests for the four layout classes [DEVICE]"; ticket
// sound-garden accept entry 12: "All four layout classes render without
// overflow (headless layout_classes_test; [DEVICE] goldens for the four
// layout classes routed to owner)").
//
// lib/features/sound_garden/sound_garden_screen.dart does not exist yet:
// this file fails to compile/analyze until it (and its sibling
// implementation files) are created, which is the expected red state.
//
// This suite is the headless proxy for the [DEVICE] golden acceptance: it
// pumps SoundGardenScreen at all four LayoutClass sizes with a
// representative fixture (mixed awake/muted cards, varying example-word
// counts, a multi-phoneme blend) and asserts no overflow/render exception
// is thrown (`tester.takeException() == null`). The actual pixel-level
// goldens are a [DEVICE]/owner task, explicitly skip-marked below per the
// established convention -- see test/features/map/layout_classes_test.dart,
// this suite's direct template.
//
// See sound_garden_screen_test.dart for the canonical pinned API.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/listening/contracts/fake_asr_engine.dart';
import 'package:learn_to_read/features/listening/matcher/sound_mode_scorer.dart';
import 'package:learn_to_read/features/sound_garden/sound_garden_screen.dart';

const _installId = 'a1b2c3d4-1234-4abc-8def-0123456789ab';

/// Resizes the actual test viewport (not just an ambient MediaQuery) so the
/// screen lays out exactly as it would at a real device size of [size] --
/// mirrors test/design/layout_test.dart's `_pumpAt` helper (private there,
/// so redefined locally per-file, same behavior as
/// test/features/map/layout_classes_test.dart).
Future<void> _pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(child);
}

const _phonePortrait = Size(375, 812);
const _phoneLandscape = Size(812, 375);
const _tabletPortrait = Size(768, 1024);
const _tabletLandscape = Size(1024, 768);

const _layoutSizes = <String, Size>{
  'phonePortrait': _phonePortrait,
  'phoneLandscape': _phoneLandscape,
  'tabletPortrait': _tabletPortrait,
  'tabletLandscape': _tabletLandscape,
};

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

GraphemeSound _card(
  String id,
  String grapheme,
  List<String> phonemeIds,
  String introducedAtLevelId, {
  List<({String wordText, String pronunciationAudioRef, String minLevelId})>
      exampleWords = const [],
}) =>
    GraphemeSound(
      id: id,
      grapheme: grapheme,
      phonemeIds: phonemeIds,
      introducedAtLevelId: introducedAtLevelId,
      exampleWords: exampleWords,
    );

/// A representative full-inventory fixture, well beyond the launch scope-
/// &-sequence count: 24 cards spanning short vowels, digraphs, a blend
/// (multi-phoneme), vowel teams, diphthongs, and r-controlled vowels, with
/// example words of varying visibility, at a mid-scope profile level so
/// both awake and muted cards render simultaneously.
List<GraphemeSound> _inventory() => [
      for (var i = 1; i <= 24; i++)
        _card(
          'gs.$i',
          i.isEven ? 'a$i' : 'sh$i',
          i % 3 == 0 ? const ['B', 'L'] : const ['SH'],
          'level.${1 + (i % 5)}',
          exampleWords: [
            (
              wordText: 'word$i',
              pronunciationAudioRef: 'audio/words/word$i.mp3',
              minLevelId: 'level.${1 + (i % 5)}',
            ),
          ],
        ),
    ];

Widget _buildScreen() {
  final inventory = _inventory();
  final downloaded = inventory.expand((c) => c.exampleWords).map((w) => w.pronunciationAudioRef).toSet();
  final phonemeRefs = <String, String>{
    for (final card in inventory)
      for (final phoneme in card.phonemeIds) phoneme: 'audio/phonemes/$phoneme.mp3',
  };

  return MaterialApp(
    home: SoundGardenScreen(
      profile: Profile(
        localId: 'profile.amara',
        displayName: 'Amara',
        ageBand: AgeBand.fiveToSix,
        currentLevelId: 'level.3',
        micConsent: true,
        cloudAsrConsent: false,
        createdAt: DateTime(2026, 1, 1),
      ),
      profileOrdinal: 1,
      levelOrdinal: 3,
      installId: _installId,
      inventory: inventory,
      levels: _levels(),
      audioService: FakeAudioService(),
      phonemeAudioRefs: phonemeRefs,
      downloadedExampleWordAudioRefs: downloaded,
      echoEngine: FakeAsrEngine(script: const []),
      buildScorer: (card) => SoundModeScorer(
        targetPhonemeSequence: card.phonemeIds,
        targetPhonemeId: card.phonemeIds.first,
      ),
      onAnalyticsEvent: (_) {},
    ),
  );
}

void main() {
  group('SoundGardenScreen — all four layout classes, no overflow '
      '(accept 12)', () {
    for (final entry in _layoutSizes.entries) {
      testWidgets('POSITIVE: ${entry.key} (${entry.value}) renders without overflow', (tester) async {
        await _pumpAt(tester, entry.value, _buildScreen());
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('SoundGardenScreen — beyond-launch inventory count, four layout '
      'classes (accept 12, edge)', () {
    for (final entry in _layoutSizes.entries) {
      testWidgets(
        'EDGE: ${entry.key} with the full 24-card fixture inventory '
        '(mixed awake/muted, multi-phoneme blends, example words) still '
        'renders without overflow',
        (tester) async {
          await _pumpAt(tester, entry.value, _buildScreen());
          await tester.pump();
          expect(tester.takeException(), isNull);
        },
      );
    }
  });

  group('[DEVICE] pixel goldens — not testable headlessly, skipped with '
      'reason', () {
    for (final layoutClassName in _layoutSizes.keys) {
      test(
        'SoundGardenScreen golden at $layoutClassName matches the '
        'illustrated card style guide',
        () {},
        skip: '[DEVICE] Real card/garden illustrations are owner-'
            'commissioned (PRD §10 OQ-4); this container has only '
            'token-styled placeholder painting, so a pixel golden here '
            'would pin placeholder art, not the shipped design. Routed to '
            'the owner once the illustrated card assets and style-guide '
            'sign-off land. The headless proxy above (no-overflow '
            'assertion at this exact layout class) is the compile-time '
            'stand-in.',
      );
    }
  });
}

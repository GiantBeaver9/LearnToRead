/// Headless layout-class coverage for `ReadingScreen`
/// (lib/features/reading/reading_screen.dart; PRD §8 Unit 5 accept
/// "Golden tests for all four layout classes at sentence and paragraph
/// levels"; ticket reading-screen accept entry 12).
///
/// Mirrors test/features/map/layout_classes_test.dart's established pattern
/// exactly: pump the screen at each of the four `LayoutClass` sizes
/// (lib/design/layout.dart, merged) and assert no overflow, then route the
/// actual pixel-level goldens to the owner as `[DEVICE]`-skipped stubs. This
/// file imports lib/features/reading/reading_screen.dart, which does not
/// exist yet: it fails to compile/analyze until it is created (and until
/// word_text_view.dart / narration_controller.dart / page_turn.dart /
/// listening_indicator.dart / reading_controller.dart exist, which
/// reading_screen.dart composes) -- the expected red state.
///
/// Pinned contract this suite locks in:
///  - `ReadingScreen` arranges its text/stage regions through
///    `ReadingLayout` (lib/design/layout.dart, merged, already tested for
///    its own Row/Column behavior in test/design/layout_test.dart) -- this
///    suite only re-verifies that `ReadingScreen` actually uses it and that
///    real reading content (sentence- and paragraph-length) never overflows
///    at any of the four classes.
///  - The stage region is driven by the `StoryStage` abstraction
///    (lib/design/rive_stage.dart) -- `FakeStoryStage` in every test here --
///    and shows the idle scene throughout ordinary reading (PRD §8 Unit 8):
///    `ReadingScreen` never calls `stage.trigger(...)` itself, so
///    `FakeStoryStage.triggeredInputs` stays empty and `activeState` stays
///    `StoryStageInput.idle` across every interaction this suite drives.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/design/fake_rive_stage.dart';
import 'package:learn_to_read/design/layout.dart';
import 'package:learn_to_read/design/rive_stage.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/features/analytics/analytics_client.dart';
import 'package:learn_to_read/features/analytics/event_queue.dart';
import 'package:learn_to_read/features/analytics/transport.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/listening/contracts/tracker_events.dart';
import 'package:learn_to_read/features/reading/reading_controller.dart';
import 'package:learn_to_read/features/reading/reading_screen.dart';

/// Resizes the actual test viewport (not just an ambient MediaQuery) so the
/// screen lays out exactly as it would at a real device size of [size] --
/// mirrors test/design/layout_test.dart's `_pumpAt` helper (private there,
/// so redefined locally per-file, same behavior, per this repo's
/// established convention).
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

WordToken _word(String text) => WordToken(
      text: text,
      graphemePhonemeMap: [(graphemes: text, phonemeId: 'AH')],
      pronunciationAudioRef: 'audio/words/$text.mp3',
    );

class _FakeTrackerHandle implements ReadingTrackerHandle {
  final StreamController<TrackerEvent> _controller =
      StreamController<TrackerEvent>.broadcast();
  bool _listening = false;

  @override
  Stream<TrackerEvent> get eventsStream => _controller.stream;

  @override
  bool get isListening => _listening;

  @override
  void pause() => _listening = false;

  @override
  void resume() => _listening = true;

  @override
  void stop() => _listening = false;

  @override
  void tapCurrentWord() {}
}

AnalyticsClient _noOpAnalyticsClient() => AnalyticsClient(
      enabled: false,
      queue: EventQueue(
        transport: const NullAnalyticsTransport(),
        clock: () => DateTime.utc(2026, 1, 1),
        storageDirectory: Directory.systemTemp,
      ),
    );

/// A realistically long sentence-format story: eight words, one page, one
/// sentence -- exercises the sentence text-size tokens
/// (`DesignTokens.sentenceTextSize*`).
Story _sentenceStory() => Story(
      id: 'story.sentence',
      levelId: 'level.1',
      title: 'A Sentence Story',
      pages: [
        Page(sentences: [
          Sentence(words: [
            _word('the'),
            _word('little'),
            _word('brown'),
            _word('dog'),
            _word('ran'),
            _word('past'),
            _word('the'),
            _word('gate'),
          ]),
        ]),
      ],
      riveAnimationRef: 'rive/story.riv',
      celebrationAudioRef: 'audio/celebration.mp3',
      collectibleRef: 'collectible.1',
      skillsExercised: const [],
      packId: 'pack.test',
      contentVersion: '1',
    );

/// A realistically long paragraph-format story: three pages, several
/// sentences of several words each per page -- exercises the paragraph
/// text-size tokens and the page-turn machinery at real content volume.
Story _paragraphStory() {
  List<WordToken> sentence(List<String> words) => words.map(_word).toList();
  Page page(List<List<String>> sentences) =>
      Page(sentences: [for (final s in sentences) Sentence(words: sentence(s))]);

  return Story(
    id: 'story.paragraph',
    levelId: 'level.6',
    title: 'A Paragraph Story',
    pages: [
      page([
        ['once', 'upon', 'a', 'time', 'there', 'was', 'a', 'small', 'fox'],
        ['the', 'fox', 'lived', 'in', 'a', 'den', 'near', 'a', 'tall', 'oak', 'tree'],
        ['every', 'morning', 'the', 'fox', 'looked', 'for', 'breakfast'],
      ]),
      page([
        ['one', 'day', 'the', 'fox', 'found', 'a', 'basket', 'of', 'berries'],
        ['the', 'fox', 'shared', 'the', 'berries', 'with', 'a', 'friend'],
      ]),
      page([
        ['they', 'ate', 'together', 'under', 'the', 'tall', 'oak', 'tree'],
        ['the', 'fox', 'was', 'happy', 'and', 'full'],
      ]),
    ],
    riveAnimationRef: 'rive/story.riv',
    celebrationAudioRef: 'audio/celebration.mp3',
    collectibleRef: 'collectible.1',
    skillsExercised: const [],
    packId: 'pack.test',
    contentVersion: '1',
  );
}

Level _sentenceLevel() => Level(
      id: 'level.1',
      ordinal: 1,
      newSkills: const [],
      format: LevelFormat.sentence,
      vocabEnabled: true,
      narrationEnabled: false, // avoid narration-audio dependencies in this suite
    );

Level _paragraphLevel() => Level(
      id: 'level.6',
      ordinal: 6,
      newSkills: const [],
      format: LevelFormat.paragraph,
      vocabEnabled: false,
    );

Widget _buildScreen({
  required Story story,
  required Level level,
  required FakeStoryStage stage,
}) {
  return MaterialApp(
    home: ReadingScreen(
      story: story,
      level: level,
      tracker: _FakeTrackerHandle(),
      audioService: FakeAudioService(),
      analytics: _noOpAnalyticsClient(),
      installId: 'a1b2c3d4-1234-4abc-8def-0123456789ab',
      profileOrdinal: 1,
      levelOrdinal: level.ordinal,
      stage: stage,
      vocabCardOpener: (_) async {},
    ),
  );
}

void main() {
  group('ReadingScreen — sentence-format story, all four layout classes '
      '(POSITIVE)', () {
    for (final entry in _layoutSizes.entries) {
      testWidgets('${entry.key} (${entry.value}) renders without overflow, '
          'uses ReadingLayout, and shows the idle stage', (tester) async {
        final stage = FakeStoryStage();
        await _pumpAt(
          tester,
          entry.value,
          _buildScreen(story: _sentenceStory(), level: _sentenceLevel(), stage: stage),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byType(ReadingLayout), findsOneWidget);
        expect(stage.activeState, StoryStageInput.idle);
        expect(stage.triggeredInputs, isEmpty);
      });
    }
  });

  group('ReadingScreen — paragraph-format multi-page story, all four '
      'layout classes (POSITIVE)', () {
    for (final entry in _layoutSizes.entries) {
      testWidgets('${entry.key} (${entry.value}) renders without overflow', (tester) async {
        final stage = FakeStoryStage();
        await _pumpAt(
          tester,
          entry.value,
          _buildScreen(story: _paragraphStory(), level: _paragraphLevel(), stage: stage),
        );
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byType(ReadingLayout), findsOneWidget);
        expect(stage.activeState, StoryStageInput.idle);
      });
    }
  });

  group('ReadingScreen — resizing mid-read (EDGE)', () {
    testWidgets('rotating from portrait to landscape mid-story keeps '
        'reading content intact with no overflow', (tester) async {
      final stage = FakeStoryStage();
      final screen =
          _buildScreen(story: _sentenceStory(), level: _sentenceLevel(), stage: stage);

      await _pumpAt(tester, _phonePortrait, screen);
      await tester.pump();
      expect(tester.takeException(), isNull);

      await _pumpAt(tester, _phoneLandscape, screen);
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('the'), findsWidgets);
    });
  });

  group('[DEVICE] pixel goldens — not testable headlessly, skipped with '
      'reason', () {
    for (final layoutClassName in _layoutSizes.keys) {
      test(
        'ReadingScreen golden at $layoutClassName (sentence level) matches '
        'the illustrated storybook style guide',
        () {},
        skip: '[DEVICE] Real illustrated stage art and the licensed '
            'early-reader typeface are owner-commissioned/owner-supplied '
            '(PRD §10 OQ-8, OQ-4); DesignTokens.tokensAreOwnerSignedOff is '
            'still false. This container has only token-styled placeholder '
            'rendering, so a pixel golden here would pin placeholder art, '
            'not the shipped design. Routed to the owner once tokens are '
            'signed off. The headless proxy above (no-overflow assertion at '
            'this exact layout class, with real sentence-length content) is '
            'the compile-time stand-in.',
      );
    }

    for (final layoutClassName in _layoutSizes.keys) {
      test(
        'ReadingScreen golden at $layoutClassName (paragraph level, '
        'multi-page) matches the illustrated storybook style guide',
        () {},
        skip: '[DEVICE] Same rationale as the sentence-level goldens above, '
            'exercised at paragraph-level content volume and the page-turn '
            'transition instead.',
      );
    }
  });
}

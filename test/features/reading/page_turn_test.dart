/// Tests for page pacing and the page-turn transition (PRD §8 Unit 5: "One
/// sentence (early levels) up to one paragraph (later levels) per page;
/// multi-page stories page with a full-bleed page-turn transition"; ticket
/// reading-screen accept entry 5).
///
/// Exercises `PageTurn` (lib/features/reading/page_turn.dart) directly as a
/// widget, plus the end-to-end wiring through `ReadingScreen` +
/// `ReadingController` (lib/features/reading/reading_screen.dart,
/// reading_controller.dart) so a `pageCompleted` signal from
/// `WordStateMachine` (merged, reused) actually turns the page. None of the
/// three lib files exist yet -- this suite fails to compile/analyze until
/// they do (the expected red state).
///
/// Pinned contract this suite locks in:
///  - `PageTurn({required pageIndex, required pageBuilder})` renders
///    `pageBuilder(context, pageIndex)`, keyed `ValueKey('page-$pageIndex')`,
///    filling its parent's full available size (full-bleed: no
///    margin/gutter shrinks it below the parent's constraints).
///  - Changing `pageIndex` transitions to the new page's content; the old
///    page's keyed content is gone once the transition settles
///    (`pumpAndSettle`).
///  - `ReadingScreen`: a `WordStateResult.pageCompleted` (multi-page story,
///    a non-final page's last word resolves) turns the page -- the widget
///    tree shows the new page's first word as current and the old page's
///    words are no longer reachable via `WordTextView`'s per-word keys, all
///    without throwing.
///  - The last page's last word does NOT page-turn (`pageCompleted` is
///    mutually exclusive with `storyCompleted` per WordStateMachine) --
///    covered here structurally (no second page exists to turn to);
///    reading_screen_test.dart owns the completion-beat/celebration timing.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/design/fake_rive_stage.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/features/analytics/analytics_client.dart';
import 'package:learn_to_read/features/analytics/event_queue.dart';
import 'package:learn_to_read/features/analytics/transport.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/listening/contracts/tracker_events.dart';
import 'package:learn_to_read/features/reading/page_turn.dart';
import 'package:learn_to_read/features/reading/reading_controller.dart';
import 'package:learn_to_read/features/reading/reading_screen.dart';

// ---------------------------------------------------------------------------
// PageTurn — direct widget tests.
// ---------------------------------------------------------------------------

Widget _pageTurnHarness({required int pageIndex, required Size size}) {
  return MaterialApp(
    home: Center(
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: PageTurn(
          pageIndex: pageIndex,
          pageBuilder: (context, i) => Container(
            key: ValueKey('page-$i'),
            color: DesignTokens.readingBackground,
            child: Text('page $i', key: ValueKey('page-text-$i')),
          ),
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// End-to-end fixtures: ReadingScreen turns pages at WordStateMachine page
// boundaries.
// ---------------------------------------------------------------------------

WordToken _word(String text) => WordToken(
      text: text,
      graphemePhonemeMap: [(graphemes: text, phonemeId: 'AH')],
      pronunciationAudioRef: 'audio/words/$text.mp3',
    );

Level _paragraphLevel() => Level(
      id: 'level.5',
      ordinal: 5,
      newSkills: const [],
      format: LevelFormat.paragraph, // narrationEnabled defaults false
      vocabEnabled: false,
    );

/// A three-page story, one sentence (two words) per page.
Story _multiPageStory() => Story(
      id: 'story.multipage',
      levelId: 'level.5',
      title: 'Multi-page Story',
      pages: [
        Page(sentences: [Sentence(words: [_word('one'), _word('two')])]),
        Page(sentences: [Sentence(words: [_word('three'), _word('four')])]),
        Page(sentences: [Sentence(words: [_word('five'), _word('six')])]),
      ],
      riveAnimationRef: 'rive/story.riv',
      celebrationAudioRef: 'audio/celebration.mp3',
      collectibleRef: 'collectible.1',
      skillsExercised: const [],
      packId: 'pack.test',
      contentVersion: '1',
    );

class _FakeTrackerHandle implements ReadingTrackerHandle {
  final StreamController<TrackerEvent> _controller =
      StreamController<TrackerEvent>.broadcast();
  bool _listening = false;
  bool stopped = false;
  final List<String> calls = [];

  @override
  Stream<TrackerEvent> get eventsStream => _controller.stream;

  @override
  bool get isListening => _listening;

  @override
  void pause() {
    calls.add('pause');
    _listening = false;
  }

  @override
  void resume() {
    if (stopped) return;
    calls.add('resume');
    _listening = true;
  }

  @override
  void stop() {
    calls.add('stop');
    _listening = false;
    stopped = true;
  }

  @override
  void tapCurrentWord() => calls.add('tap');

  void emit(TrackerEvent event) => _controller.add(event);
}

AnalyticsClient _noOpAnalyticsClient() => AnalyticsClient(
      enabled: false,
      queue: EventQueue(
        transport: const NullAnalyticsTransport(),
        clock: () => DateTime.utc(2026, 1, 1),
        storageDirectory: Directory.systemTemp,
      ),
    );

Widget _buildScreen({
  required Story story,
  required Level level,
  required _FakeTrackerHandle tracker,
  VoidCallback? onStoryComplete,
}) {
  return MaterialApp(
    home: ReadingScreen(
      story: story,
      level: level,
      tracker: tracker,
      audioService: FakeAudioService(),
      analytics: _noOpAnalyticsClient(),
      installId: 'a1b2c3d4-1234-4abc-8def-0123456789ab',
      profileOrdinal: 1,
      levelOrdinal: 1,
      stage: FakeStoryStage(),
      vocabCardOpener: (_) async {},
      onStoryComplete: onStoryComplete,
    ),
  );
}

void _resolveWord(_FakeTrackerHandle tracker, int index) =>
    tracker.emit(WordAccepted(index: index));

void main() {
  group('PageTurn widget — POSITIVE', () {
    testWidgets('renders pageBuilder for the given pageIndex, keyed and '
        'full-bleed (fills the parent)', (tester) async {
      await tester.pumpWidget(_pageTurnHarness(pageIndex: 0, size: const Size(300, 400)));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('page-0')), findsOneWidget);
      final renderBox = tester.renderObject<RenderBox>(find.byKey(const ValueKey('page-0')));
      expect(renderBox.size.width, 300);
      expect(renderBox.size.height, 400);
    });

    testWidgets('changing pageIndex turns the page: the new page settles in '
        'and the old page is gone', (tester) async {
      final key = GlobalKey();
      Widget build(int pageIndex) => MaterialApp(
            key: key,
            home: Center(
              child: SizedBox(
                width: 300,
                height: 400,
                child: PageTurn(
                  pageIndex: pageIndex,
                  pageBuilder: (context, i) =>
                      Container(key: ValueKey('page-$i'), child: Text('page $i')),
                ),
              ),
            ),
          );

      await tester.pumpWidget(build(0));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('page-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('page-1')), findsNothing);

      await tester.pumpWidget(build(1));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('page-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('page-0')), findsNothing);
    });
  });

  group('PageTurn widget — EDGE', () {
    testWidgets('re-pumping the same pageIndex is a no-op: no exception, '
        'same page still showing', (tester) async {
      await tester.pumpWidget(_pageTurnHarness(pageIndex: 0, size: const Size(300, 400)));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_pageTurnHarness(pageIndex: 0, size: const Size(300, 400)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('page-0')), findsOneWidget);
    });
  });

  group('ReadingScreen — page-turn at WordStateMachine page boundaries '
      '(POSITIVE)', () {
    testWidgets('resolving the last word of page 0 turns to page 1: word 0 '
        'of the new page is current, page 0 words are gone', (tester) async {
      final tracker = _FakeTrackerHandle();
      await tester.pumpWidget(_buildScreen(
        story: _multiPageStory(),
        level: _paragraphLevel(),
        tracker: tracker,
      ));
      await tester.pump();
      expect(tracker.isListening, isTrue);

      _resolveWord(tracker, 0);
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);
      _resolveWord(tracker, 1);
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('one'), findsNothing);
      expect(find.text('two'), findsNothing);
      expect(find.text('three'), findsOneWidget);
      expect(find.byKey(const ValueKey('word-current-marker-0')), findsOneWidget);
    });

    testWidgets('turning the page never stops listening or completes the '
        'story', (tester) async {
      final tracker = _FakeTrackerHandle();
      final complete = <int>[];
      await tester.pumpWidget(_buildScreen(
        story: _multiPageStory(),
        level: _paragraphLevel(),
        tracker: tracker,
        onStoryComplete: () => complete.add(1),
      ));
      await tester.pump();

      _resolveWord(tracker, 0);
      await tester.pump(DesignTokens.greenSweepDuration);
      _resolveWord(tracker, 1);
      await tester.pumpAndSettle();

      expect(tracker.calls, isNot(contains('stop')));
      expect(tracker.isListening, isTrue);
      expect(complete, isEmpty);
    });
  });

  group('ReadingScreen — page pacing (EDGE)', () {
    testWidgets('a single-sentence (sentence-format) story never turns a '
        'page: the whole read stays on page 0', (tester) async {
      final tracker = _FakeTrackerHandle();
      final story = Story(
        id: 'story.single',
        levelId: 'level.1',
        title: 'Single Sentence',
        pages: [
          Page(sentences: [Sentence(words: [_word('go'), _word('now')])]),
        ],
        riveAnimationRef: 'rive/story.riv',
        celebrationAudioRef: 'audio/celebration.mp3',
        collectibleRef: 'collectible.1',
        skillsExercised: const [],
        packId: 'pack.test',
        contentVersion: '1',
      );
      final level = Level(
        id: 'level.1',
        ordinal: 1,
        newSkills: const [],
        format: LevelFormat.multiSentence,
        vocabEnabled: false,
      );

      await tester.pumpWidget(_buildScreen(story: story, level: level, tracker: tracker));
      await tester.pump();

      _resolveWord(tracker, 0);
      await tester.pump(DesignTokens.greenSweepDuration);
      expect(find.text('now'), findsOneWidget);
      expect(find.byKey(const ValueKey('word-current-marker-1')), findsOneWidget);
    });
  });
}

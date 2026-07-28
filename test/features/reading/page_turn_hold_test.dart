/// Tests for the ratified page-turn hold (PRD §8 Unit 5 "Page turn = book
/// page-curl", docs/design/mockup-spec.md §8, owner-confirmed 2026-07-28:
/// "the machine holds at page completion; the child's turn gesture IS the
/// reward beat").
///
/// Pinned contract:
///  - `WordStateMachine`: resolving the last word of a NON-final page enters
///    the `isPageComplete` hold -- words stay done/green, `currentPageIndex`
///    unchanged, further events inert. `turnPage()` exits the hold and
///    advances exactly once; it is a no-op any other time (double-turn
///    safe). Final-page completion is UNCHANGED (storyCompleted, no hold).
///  - `ReadingScreen`: while holding, the reading card carries the
///    `PageCurlCorner` dog-ear; the child's corner gesture turns the page
///    and fires `onPageTurned` exactly once. No dog-ear on single-page
///    stories or on the final page, ever.
///  - Listening: the tracker is neither stopped nor paused at page
///    completion or across the turn; `ReadingSession` moves its per-page
///    tracker at TURN time (`advancePage`), not at resolution time.
///  - The listening waveform (`WaveBars`) animates live -- and every pump in
///    this suite is bounded (no `pumpAndSettle` while listening).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/app/providers.dart' show ReadingSession;
import 'package:learn_to_read/design/fake_rive_stage.dart';
import 'package:learn_to_read/design/motion.dart';
import 'package:learn_to_read/design/page_curl.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart' show HelpLevel;
import 'package:learn_to_read/features/analytics/analytics_client.dart';
import 'package:learn_to_read/features/analytics/event_queue.dart';
import 'package:learn_to_read/features/analytics/transport.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/help/help_recorder.dart';
import 'package:learn_to_read/features/listening/contracts/fake_asr_engine.dart';
import 'package:learn_to_read/features/listening/contracts/tracker_events.dart';
import 'package:learn_to_read/features/reading/listening_indicator.dart';
import 'package:learn_to_read/features/reading/reading_controller.dart';
import 'package:learn_to_read/features/reading/reading_screen.dart';
import 'package:learn_to_read/features/reading/word_state.dart';
import 'package:learn_to_read/features/reading/word_state_machine.dart';

// ---------------------------------------------------------------------------
// Fixtures (same shapes as page_turn_test.dart).
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

Story _storyOf(String id, List<List<String>> pages) => Story(
      id: id,
      levelId: 'level.5',
      title: 'Story $id',
      pages: [
        for (final page in pages)
          Page(sentences: [
            Sentence(words: [for (final w in page) _word(w)]),
          ]),
      ],
      riveAnimationRef: 'rive/story.riv',
      celebrationAudioRef: 'audio/celebration.mp3',
      collectibleRef: 'collectible.1',
      skillsExercised: const [],
      packId: 'pack.test',
      contentVersion: '1',
    );

Story _twoPageStory() => _storyOf('story.two', [
      ['one', 'two'],
      ['three', 'four'],
    ]);

Story _singlePageStory() => _storyOf('story.single', [
      ['go', 'now'],
    ]);

WordStateMachine _machine(List<List<String>> pages) => WordStateMachine(
      pages: [
        for (final page in pages) [for (final w in page) _word(w)],
      ],
      level: _paragraphLevel(),
    );

class _FakeTrackerHandle implements ReadingTrackerHandle {
  final StreamController<TrackerEvent> _controller =
      StreamController<TrackerEvent>.broadcast();
  bool _listening = false;
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
    calls.add('resume');
    _listening = true;
  }

  @override
  void stop() {
    calls.add('stop');
    _listening = false;
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

class _NoOpHelpRecorder implements HelpRecorderApi {
  @override
  Future<void> recordResolution({
    required WordToken word,
    required HelpLevel tier,
  }) async {}
}

Widget _buildScreen({
  required Story story,
  required _FakeTrackerHandle tracker,
  VoidCallback? onStoryComplete,
  VoidCallback? onPageTurned,
}) {
  return MaterialApp(
    home: ReadingScreen(
      story: story,
      level: _paragraphLevel(),
      tracker: tracker,
      audioService: FakeAudioService(),
      analytics: _noOpAnalyticsClient(),
      installId: 'a1b2c3d4-1234-4abc-8def-0123456789ab',
      profileOrdinal: 1,
      levelOrdinal: 1,
      stage: FakeStoryStage(),
      vocabCardOpener: (_) async {},
      onStoryComplete: onStoryComplete,
      onPageTurned: onPageTurned,
    ),
  );
}

/// The dog-ear: the curl overlay an enabled [PageCurlCorner] paints.
Finder _dogEar() => find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint && widget.painter is PageCurlOverlayPainter,
    );

/// Taps the dog-ear's bottom-right hit region and pumps the turn with
/// BOUNDED stepped pumps (the live WaveBars waveform never settles, so
/// `pumpAndSettle` would hang).
Future<void> _turnByGesture(WidgetTester tester) async {
  final corner =
      tester.getBottomRight(find.byType(PageCurlCorner)) - const Offset(8, 8);
  await tester.tapAt(corner);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400)); // curl completes
  await tester.pump(const Duration(milliseconds: 400)); // PageTurn switch
  await tester.pump(const Duration(milliseconds: 400)); // settle the sweep
}

void main() {
  // =========================================================================
  group('WordStateMachine: the page-turn hold', () {
    test('POSITIVE: resolving the last word of a NON-final page holds -- no '
        'auto-advance, words stay done, further events inert', () {
      final machine = _machine([
        ['see', 'spot'],
        ['run', 'fast'],
      ]);

      machine.apply(const WordAccepted(index: 0));
      final boundary = machine.apply(const WordAccepted(index: 1));

      expect(boundary.pageCompleted, isTrue);
      expect(boundary.storyCompleted, isFalse);
      expect(boundary.snapshot.isPageComplete, isTrue);
      expect(boundary.snapshot.currentPageIndex, 0,
          reason: 'the machine STOPS at page completion (owner ruling)');
      expect(boundary.snapshot.currentIndex, -1);
      expect(
        boundary.snapshot.pages[0]
            .every((w) => w.lifecycle == WordLifecycle.done),
        isTrue,
      );
      expect(
        boundary.snapshot.pages[1]
            .every((w) => w.lifecycle == WordLifecycle.unread),
        isTrue,
        reason: 'the next page must not start until the child turns',
      );

      // Events during the hold are inert and never re-signal.
      final during = machine.apply(const WordAccepted(index: 0));
      expect(during.pageCompleted, isFalse);
      expect(during.storyCompleted, isFalse);
      expect(machine.snapshot.isPageComplete, isTrue);
      expect(machine.snapshot.currentPageIndex, 0);
    });

    test('POSITIVE: turnPage() advances exactly once; a double call cannot '
        'skip a page', () {
      final machine = _machine([
        ['a'],
        ['b'],
        ['c'],
      ]);
      machine.apply(const WordAccepted(index: 0)); // page 0 complete -> hold

      machine.turnPage();
      expect(machine.snapshot.currentPageIndex, 1);
      expect(machine.snapshot.isPageComplete, isFalse);
      expect(machine.snapshot.pages[1][0].lifecycle, WordLifecycle.current);

      machine.turnPage(); // no hold active: must be a no-op
      expect(machine.snapshot.currentPageIndex, 1);
      expect(machine.snapshot.pages[2][0].lifecycle, WordLifecycle.unread);
    });

    test('NEGATIVE: turnPage() mid-page is a no-op', () {
      final machine = _machine([
        ['see', 'spot'],
        ['run'],
      ]);
      machine.apply(const WordAccepted(index: 0)); // mid-page

      machine.turnPage();

      expect(machine.snapshot.currentPageIndex, 0);
      expect(machine.snapshot.currentIndex, 1);
      expect(machine.snapshot.pages[0][1].lifecycle, WordLifecycle.current);
    });

    test('POSITIVE: FINAL page completion is unchanged -- storyCompleted, no '
        'hold, and turnPage() after completion is a no-op', () {
      final machine = _machine([
        ['see'],
        ['run'],
      ]);
      machine.apply(const WordAccepted(index: 0));
      machine.turnPage();

      final done = machine.apply(const WordAccepted(index: 0));

      expect(done.storyCompleted, isTrue);
      expect(done.pageCompleted, isFalse);
      expect(done.snapshot.isPageComplete, isFalse);
      expect(done.snapshot.isStoryComplete, isTrue);
      expect(done.snapshot.currentIndex, -1);

      machine.turnPage();
      expect(machine.snapshot.currentPageIndex, 1);
      expect(machine.snapshot.isStoryComplete, isTrue);
    });

    test('EDGE: a single-page story never holds', () {
      final machine = _machine([
        ['go', 'now'],
      ]);
      machine.apply(const WordAccepted(index: 0));
      final done = machine.apply(const WordAccepted(index: 1));

      expect(done.storyCompleted, isTrue);
      expect(done.pageCompleted, isFalse);
      expect(done.snapshot.isPageComplete, isFalse);
    });
  });

  // =========================================================================
  group('ReadingController: turnPage + onPageTurned seam', () {
    test('POSITIVE: onPageTurned fires exactly once per turn, at turn time, '
        'and double-turn is safe', () async {
      final tracker = _FakeTrackerHandle();
      final turns = <int>[];
      final controller = ReadingController(
        story: _twoPageStory(),
        level: _paragraphLevel(),
        tracker: tracker,
        analytics: _noOpAnalyticsClient(),
        installId: 'a1b2c3d4-1234-4abc-8def-0123456789ab',
        profileOrdinal: 1,
        levelOrdinal: 1,
        onPageTurned: () => turns.add(1),
      );
      addTearDown(controller.dispose);
      controller.beginListening();

      controller.turnPage(); // nothing held yet: no-op, no callback
      expect(turns, isEmpty);
      expect(controller.snapshot.currentPageIndex, 0);

      tracker.emit(const WordAccepted(index: 0));
      tracker.emit(const WordAccepted(index: 1));
      await Future<void>.delayed(Duration.zero);

      // Held at resolution time: the session has NOT been told to advance.
      expect(controller.snapshot.isPageComplete, isTrue);
      expect(controller.snapshot.currentPageIndex, 0);
      expect(turns, isEmpty,
          reason: 'the tracker moves pages at TURN time, not resolution time');
      expect(tracker.calls, isNot(contains('stop')));

      controller.turnPage();
      expect(turns, hasLength(1));
      expect(controller.snapshot.currentPageIndex, 1);
      expect(controller.snapshot.isPageComplete, isFalse);

      controller.turnPage(); // double-turn: no second advance, no callback
      expect(turns, hasLength(1));
      expect(controller.snapshot.currentPageIndex, 1);
    });
  });

  // =========================================================================
  group('ReadingScreen: dog-ear + gesture', () {
    testWidgets('POSITIVE: completing a non-final page shows the dog-ear and '
        'holds; no dog-ear before completion', (tester) async {
      final tracker = _FakeTrackerHandle();
      await tester.pumpWidget(
        _buildScreen(story: _twoPageStory(), tracker: tracker),
      );
      await tester.pump();

      // Mid-page: no curl anywhere.
      expect(find.byType(PageCurlCorner), findsNothing);
      expect(_dogEar(), findsNothing);

      tracker.emit(const WordAccepted(index: 0));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);
      tracker.emit(const WordAccepted(index: 1));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);

      // Held: page 0 words still on screen, dog-ear present, page 1 absent.
      expect(find.text('one'), findsOneWidget);
      expect(find.text('two'), findsOneWidget);
      expect(find.text('three'), findsNothing);
      expect(find.byType(PageCurlCorner), findsOneWidget);
      expect(_dogEar(), findsOneWidget);
    });

    testWidgets('POSITIVE: the corner gesture turns the page exactly once -- '
        'a second tap cannot skip ahead', (tester) async {
      final tracker = _FakeTrackerHandle();
      final turns = <int>[];
      await tester.pumpWidget(_buildScreen(
        story: _storyOf('story.three', [
          ['one', 'two'],
          ['three', 'four'],
          ['five', 'six'],
        ]),
        tracker: tracker,
        onPageTurned: () => turns.add(1),
      ));
      await tester.pump();

      tracker.emit(const WordAccepted(index: 0));
      await tester.pump();
      tracker.emit(const WordAccepted(index: 1));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);
      final corner = tester.getBottomRight(find.byType(PageCurlCorner)) -
          const Offset(8, 8);

      await _turnByGesture(tester);
      // A stray extra tap on the same corner after the turn completed.
      await tester.tapAt(corner);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(turns, hasLength(1));
      expect(find.text('three'), findsOneWidget);
      expect(find.text('five'), findsNothing,
          reason: 'page 2 must not be reachable by a double gesture');
      expect(find.byKey(const ValueKey('word-current-marker-0')),
          findsOneWidget);
      // New page mid-read: the curl is gone until this page completes too.
      expect(find.byType(PageCurlCorner), findsNothing);
    });

    testWidgets('POSITIVE: listening is uninterrupted across the hold and the '
        'turn, and onPageTurned fires exactly once', (tester) async {
      final tracker = _FakeTrackerHandle();
      final turns = <int>[];
      await tester.pumpWidget(_buildScreen(
        story: _twoPageStory(),
        tracker: tracker,
        onPageTurned: () => turns.add(1),
      ));
      await tester.pump();

      tracker.emit(const WordAccepted(index: 0));
      await tester.pump();
      tracker.emit(const WordAccepted(index: 1));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);

      expect(tracker.isListening, isTrue);
      expect(tracker.calls, isNot(contains('stop')));
      expect(tracker.calls, isNot(contains('pause')));
      expect(turns, isEmpty);

      await _turnByGesture(tester);

      expect(turns, hasLength(1));
      expect(tracker.isListening, isTrue);
      expect(tracker.calls, isNot(contains('stop')));
      expect(tracker.calls, isNot(contains('pause')));
      expect(
        find.byKey(const ValueKey('listening-indicator-active')),
        findsOneWidget,
      );
    });

    testWidgets('POSITIVE: the FINAL page completes with no dog-ear and the '
        'celebration handoff is unchanged', (tester) async {
      final tracker = _FakeTrackerHandle();
      final complete = <int>[];
      await tester.pumpWidget(_buildScreen(
        story: _twoPageStory(),
        tracker: tracker,
        onStoryComplete: () => complete.add(1),
      ));
      await tester.pump();

      tracker.emit(const WordAccepted(index: 0));
      await tester.pump();
      tracker.emit(const WordAccepted(index: 1));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);
      await _turnByGesture(tester);

      // Final page: resolve both words.
      tracker.emit(const WordAccepted(index: 0));
      await tester.pump();
      tracker.emit(const WordAccepted(index: 1));
      await tester.pump();

      // No hold, no curl -- listening stops on the resolving event and the
      // celebration beat runs as before.
      expect(find.byType(PageCurlCorner), findsNothing);
      expect(tracker.calls, contains('stop'));
      expect(complete, isEmpty, reason: 'handoff waits for the ~400 ms beat');
      await tester.pump(kCelebrationBeat);
      await tester.pump();
      expect(complete, hasLength(1));
    });

    testWidgets('EDGE: a single-page story never shows a dog-ear, before or '
        'after completion', (tester) async {
      final tracker = _FakeTrackerHandle();
      await tester.pumpWidget(
        _buildScreen(story: _singlePageStory(), tracker: tracker),
      );
      await tester.pump();
      expect(find.byType(PageCurlCorner), findsNothing);

      tracker.emit(const WordAccepted(index: 0));
      await tester.pump();
      tracker.emit(const WordAccepted(index: 1));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);

      expect(find.byType(PageCurlCorner), findsNothing);
      expect(_dogEar(), findsNothing);
    });
  });

  // =========================================================================
  group('ReadingSession: the tracker moves at turn time', () {
    test('POSITIVE: page completion does not rebuild the tracker; '
        'advancePage() does, and the next page reads from index 0', () async {
      final session = ReadingSession(
        pages: [
          [_word('one'), _word('two')],
          [_word('three'), _word('four')],
        ],
        engine: FakeAsrEngine(script: const []),
        micConsent: false, // tap-only: the manual path drives the matcher
        audioService: FakeAudioService(),
        phonemeAudioRefs: const {},
        helpRecorder: _NoOpHelpRecorder(),
        yourTurnPromptAudioRef: 'audio/your_turn.mp3',
        nearMissPromptAudioRef: 'audio/near_miss.mp3',
        onHelpGiven: (_, __) {},
      );
      addTearDown(session.dispose);

      final events = <TrackerEvent>[];
      session.eventsStream.listen(events.add);
      session.start();

      session.tapCurrentWord(); // 'one'
      session.tapCurrentWord(); // 'two' -> page 0 complete
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(2));
      expect((events[1] as WordAccepted).index, 1);

      // Held: the finished page's tracker is still the live one -- a tap is
      // a silent no-op (its matcher is complete) and nothing advanced.
      session.tapCurrentWord();
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(2),
          reason: 'no page-1 tracker may exist before the child turns');

      // The child's turn gesture reaches the session.
      session.advancePage();
      session.tapCurrentWord(); // 'three' -- page 1, index 0
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(3));
      expect((events[2] as WordAccepted).index, 0,
          reason: 'the new tracker is scoped to page 1, page-relative');

      // No further page: advancing past the end is a no-op.
      session.advancePage();
      session.advancePage();
      session.tapCurrentWord(); // 'four' -- still page 1
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(4));
      expect((events[3] as WordAccepted).index, 1);
    });
  });

  // =========================================================================
  group('Listening waveform', () {
    testWidgets('POSITIVE: WaveBars animates live (two bounded pumps render '
        'different bar scales)', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: ListeningIndicator(isListening: true)),
      ));
      await tester.pump();

      List<Matrix4> barTransforms() => [
            for (final t in tester.widgetList<Transform>(find.descendant(
              of: find.byType(WaveBars),
              matching: find.byType(Transform),
            )))
              t.transform,
          ];

      final before = barTransforms();
      expect(before, isNotEmpty);
      await tester.pump(const Duration(milliseconds: 250));
      final after = barTransforms();

      expect(after, hasLength(before.length));
      expect(
        List.generate(before.length, (i) => before[i] != after[i])
            .any((changed) => changed),
        isTrue,
        reason: 'the un-parked waveform must actually move between frames',
      );
    });
  });
}

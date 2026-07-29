/// Tests for the curl-closes-every-page ruling (PRD §8 Unit 5, "Amended
/// 2026-07-29 (owner-directed)"): the page-curl closes EVERY page, the
/// final/only one included -- single-sentence stories too, so the youngest
/// readers get the book habit.
///
/// Pinned contract (new under the ruling):
///  - `WordStateMachine`: resolving the last word of the FINAL page
///    (including a single-page story) enters the SAME `isPageComplete` hold
///    as any other page -- `apply()` inert, `currentPageIndex` unchanged --
///    instead of signalling `storyCompleted` immediately. `turnPage()` in
///    that state signals `storyCompleted` exactly once; a double turn is
///    safe. There is NO `storyCompleted` without a turn.
///  - Tracker/mic: listening still stops at final-word RESOLUTION time --
///    the hold is purely visual; nothing records while the dog-ear waits.
///  - `ReadingScreen`: the dog-ear appears on the final-page hold exactly
///    as on mid-story holds; the same curl gesture turns it; the existing
///    ~400 ms beat then runs unchanged into `onStoryComplete`.
///  - The final turn is a story-close, not a page advance: `onPageTurned`
///    (wired to `ReadingSession.advancePage`) does not fire for it.
///  - No timeout, no auto-advance: the hold waits for the child
///    indefinitely.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/design/fake_rive_stage.dart';
import 'package:learn_to_read/design/page_curl.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/features/analytics/analytics_client.dart';
import 'package:learn_to_read/features/analytics/event_queue.dart';
import 'package:learn_to_read/features/analytics/transport.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/listening/contracts/tracker_events.dart';
import 'package:learn_to_read/features/reading/reading_controller.dart';
import 'package:learn_to_read/features/reading/reading_screen.dart';
import 'package:learn_to_read/features/reading/word_state.dart';
import 'package:learn_to_read/features/reading/word_state_machine.dart';

// ---------------------------------------------------------------------------
// Fixtures (same shapes as page_turn_hold_test.dart).
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

Story _singlePageStory() => _storyOf('story.single', [
      ['go', 'now'],
    ]);

Story _twoPageStory() => _storyOf('story.two', [
      ['one', 'two'],
      ['three', 'four'],
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

/// Taps the dog-ear's hit region and pumps JUST past the curl's completion
/// (350 ms settle), stopping short of the ~400 ms celebration beat so the
/// beat's not-yet-fired state stays observable. Bounded pumps throughout.
Future<void> _turnByGesture(WidgetTester tester) async {
  final corner =
      tester.getBottomRight(find.byType(PageCurlCorner)) - const Offset(8, 8);
  await tester.tapAt(corner);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 360)); // curl completes
}

void main() {
  // =========================================================================
  group('WordStateMachine: the final page holds for the curl', () {
    test('POSITIVE: a single-page story holds at completion -- apply() inert '
        'during the hold, page/words unchanged, no storyCompleted', () {
      final machine = _machine([
        ['go', 'now'],
      ]);

      machine.apply(const WordAccepted(index: 0));
      final done = machine.apply(const WordAccepted(index: 1));

      expect(done.pageCompleted, isTrue);
      expect(done.storyCompleted, isFalse);
      expect(done.snapshot.isPageComplete, isTrue);
      expect(done.snapshot.isStoryComplete, isFalse);
      expect(done.snapshot.currentPageIndex, 0);
      expect(done.snapshot.currentIndex, -1);
      expect(
        done.snapshot.pages[0].every((w) => w.lifecycle == WordLifecycle.done),
        isTrue,
        reason: 'the words stay green while the dog-ear waits',
      );

      // Events during the final hold are inert and never re-signal.
      final during = machine.apply(const WordAccepted(index: 0));
      expect(during.pageCompleted, isFalse);
      expect(during.storyCompleted, isFalse);
      expect(machine.snapshot.isPageComplete, isTrue);
      expect(machine.snapshot.isStoryComplete, isFalse);
    });

    test('POSITIVE: turnPage() during the final hold signals storyCompleted '
        'exactly once; a double turn is safe', () {
      final machine = _machine([
        ['go'],
      ]);
      machine.apply(const WordAccepted(index: 0));

      final turned = machine.turnPage();
      expect(turned.storyCompleted, isTrue);
      expect(turned.pageCompleted, isFalse);
      expect(turned.snapshot.isStoryComplete, isTrue);
      expect(turned.snapshot.isPageComplete, isFalse);
      expect(turned.snapshot.currentPageIndex, 0,
          reason: 'a single-page story has no page to advance to');

      final again = machine.turnPage();
      expect(again.storyCompleted, isFalse,
          reason: 'storyCompleted fires exactly once');
      expect(machine.snapshot.isStoryComplete, isTrue);

      // And events after completion stay inert.
      final after = machine.apply(const WordAccepted(index: 0));
      expect(after.pageCompleted, isFalse);
      expect(after.storyCompleted, isFalse);
    });

    test('POSITIVE: a multi-page story final page enters the same hold shape '
        'as its mid-story pages, and only its turn completes the story', () {
      final machine = _machine([
        ['one', 'two'],
        ['three', 'four'],
      ]);

      machine.apply(const WordAccepted(index: 0));
      final midHold = machine.apply(const WordAccepted(index: 1));
      expect(midHold.pageCompleted, isTrue);
      expect(midHold.snapshot.isPageComplete, isTrue);
      expect(machine.turnPage().storyCompleted, isFalse,
          reason: 'a non-final turn advances, it does not complete');
      expect(machine.snapshot.currentPageIndex, 1);

      machine.apply(const WordAccepted(index: 0));
      final finalHold = machine.apply(const WordAccepted(index: 1));
      expect(finalHold.pageCompleted, isTrue,
          reason: 'the final page holds exactly like the mid-story one');
      expect(finalHold.storyCompleted, isFalse);
      expect(finalHold.snapshot.isPageComplete, isTrue);
      expect(finalHold.snapshot.currentPageIndex, 1);

      expect(machine.turnPage().storyCompleted, isTrue);
    });

    test('NEGATIVE: no storyCompleted without a turn -- the machine can sit '
        'in the final hold through any number of stray events', () {
      final machine = _machine([
        ['go', 'now'],
      ]);
      machine.apply(const WordAccepted(index: 0));
      machine.apply(const WordAccepted(index: 1));

      for (var i = 0; i < 20; i++) {
        final result = machine.apply(const Silence(duration: Duration(seconds: 4)));
        expect(result.storyCompleted, isFalse);
        expect(result.pageCompleted, isFalse);
      }
      expect(machine.snapshot.isStoryComplete, isFalse);
      expect(machine.snapshot.isPageComplete, isTrue);
    });
  });

  // =========================================================================
  group('ReadingController: resolution stops the mic, the turn starts the beat', () {
    testWidgets('POSITIVE: the tracker stops at final-word RESOLUTION '
        '(before any turn); the beat runs only after turnPage(), and the '
        'final turn does not fire onPageTurned', (tester) async {
      final tracker = _FakeTrackerHandle();
      final complete = <int>[];
      final turns = <int>[];
      final controller = ReadingController(
        story: _singlePageStory(),
        level: _paragraphLevel(),
        tracker: tracker,
        analytics: _noOpAnalyticsClient(),
        installId: 'a1b2c3d4-1234-4abc-8def-0123456789ab',
        profileOrdinal: 1,
        levelOrdinal: 1,
        onStoryComplete: () => complete.add(1),
        onPageTurned: () => turns.add(1),
      );
      controller.addListener(() {}); // keep the beat alive (screen stand-in)
      addTearDown(controller.dispose);
      controller.beginListening();

      tracker.emit(const WordAccepted(index: 0));
      tracker.emit(const WordAccepted(index: 1));
      await tester.pump(); // flush the broadcast-stream deliveries

      // Held at resolution: mic already stopped, nothing handed off.
      expect(controller.snapshot.isPageComplete, isTrue);
      expect(controller.snapshot.isStoryComplete, isFalse);
      expect(tracker.calls, contains('stop'),
          reason: 'nothing may record while the dog-ear waits');
      expect(complete, isEmpty);

      // No timeout, no auto-advance: the hold waits indefinitely.
      await tester.pump(const Duration(minutes: 5));
      expect(complete, isEmpty);

      controller.turnPage();
      expect(turns, isEmpty,
          reason: 'the final turn is a story-close, not a page advance');
      expect(controller.snapshot.isStoryComplete, isTrue);
      expect(complete, isEmpty, reason: 'the ~400 ms beat has not elapsed');

      await tester.pump(kCelebrationBeat);
      expect(complete, hasLength(1));

      // Double-turn after completion: no second beat, no second handoff.
      controller.turnPage();
      await tester.pump(kCelebrationBeat * 2);
      expect(complete, hasLength(1));
      expect(tracker.calls.where((c) => c == 'stop'), hasLength(1),
          reason: 'stop() fires once, at resolution');
    });

    testWidgets('POSITIVE: on a multi-page story only the FINAL page '
        'resolution stops the tracker; the mid-story turn still fires '
        'onPageTurned', (tester) async {
      final tracker = _FakeTrackerHandle();
      final complete = <int>[];
      final turns = <int>[];
      final controller = ReadingController(
        story: _twoPageStory(),
        level: _paragraphLevel(),
        tracker: tracker,
        analytics: _noOpAnalyticsClient(),
        installId: 'a1b2c3d4-1234-4abc-8def-0123456789ab',
        profileOrdinal: 1,
        levelOrdinal: 1,
        onStoryComplete: () => complete.add(1),
        onPageTurned: () => turns.add(1),
      );
      controller.addListener(() {});
      addTearDown(controller.dispose);
      controller.beginListening();

      tracker.emit(const WordAccepted(index: 0));
      tracker.emit(const WordAccepted(index: 1));
      await tester.pump();
      expect(tracker.calls, isNot(contains('stop')),
          reason: 'a non-final hold keeps listening open');

      controller.turnPage();
      expect(turns, hasLength(1));
      expect(tracker.calls, isNot(contains('stop')));

      tracker.emit(const WordAccepted(index: 0));
      tracker.emit(const WordAccepted(index: 1));
      await tester.pump();
      expect(tracker.calls, contains('stop'),
          reason: 'the final page stops the mic at resolution');
      expect(complete, isEmpty);

      controller.turnPage();
      expect(turns, hasLength(1),
          reason: 'the final turn adds no page advance');
      await tester.pump(kCelebrationBeat);
      expect(complete, hasLength(1));
    });
  });

  // =========================================================================
  group('ReadingScreen: the dog-ear closes the book', () {
    testWidgets('POSITIVE: a single-page story holds with the dog-ear at '
        'completion; the curl gesture completes it -- storyCompleted once, '
        'celebration handoff after the unchanged beat', (tester) async {
      final tracker = _FakeTrackerHandle();
      final complete = <int>[];
      final turns = <int>[];
      await tester.pumpWidget(_buildScreen(
        story: _singlePageStory(),
        tracker: tracker,
        onStoryComplete: () => complete.add(1),
        onPageTurned: () => turns.add(1),
      ));
      await tester.pump();
      expect(find.byType(PageCurlCorner), findsNothing);

      tracker.emit(const WordAccepted(index: 0));
      await tester.pump();
      tracker.emit(const WordAccepted(index: 1));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);

      // Held: words still on screen, dog-ear showing, mic stopped, no
      // handoff no matter how long the child looks at their green words.
      expect(find.byType(PageCurlCorner), findsOneWidget);
      expect(_dogEar(), findsOneWidget);
      expect(find.text('go'), findsOneWidget);
      expect(find.text('now'), findsOneWidget);
      expect(tracker.calls, contains('stop'));
      await tester.pump(const Duration(minutes: 1));
      expect(complete, isEmpty);

      await _turnByGesture(tester);

      // Turned: the hold released, the beat is running, nothing advanced.
      expect(find.byType(PageCurlCorner), findsNothing);
      expect(turns, isEmpty,
          reason: 'closing the book is not a page advance');
      expect(complete, isEmpty, reason: 'handoff waits for the ~400 ms beat');
      await tester.pump(kCelebrationBeat);
      await tester.pump();
      expect(complete, hasLength(1));

      // The words are still green on screen behind the beat -> celebration.
      expect(find.text('go'), findsOneWidget);
      expect(find.text('now'), findsOneWidget);
    });

    testWidgets('POSITIVE: a double gesture on the final corner cannot hand '
        'off twice', (tester) async {
      final tracker = _FakeTrackerHandle();
      final complete = <int>[];
      await tester.pumpWidget(_buildScreen(
        story: _singlePageStory(),
        tracker: tracker,
        onStoryComplete: () => complete.add(1),
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
      // A stray extra tap where the corner used to be, after the turn.
      await tester.tapAt(corner);
      await tester.pump();

      await tester.pump(kCelebrationBeat);
      await tester.pump();
      await tester.pump(kCelebrationBeat * 2);
      expect(complete, hasLength(1));
    });

    testWidgets('POSITIVE: the FINAL page of a multi-page story shows the '
        'same dog-ear as its mid-story pages, and its turn hands off',
        (tester) async {
      final tracker = _FakeTrackerHandle();
      final complete = <int>[];
      final turns = <int>[];
      await tester.pumpWidget(_buildScreen(
        story: _twoPageStory(),
        tracker: tracker,
        onStoryComplete: () => complete.add(1),
        onPageTurned: () => turns.add(1),
      ));
      await tester.pump();

      // Page 0 -> hold -> turn (the mid-story path, unchanged).
      tracker.emit(const WordAccepted(index: 0));
      await tester.pump();
      tracker.emit(const WordAccepted(index: 1));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);
      expect(find.byType(PageCurlCorner), findsOneWidget);
      await _turnByGesture(tester);
      await tester.pump(const Duration(milliseconds: 400)); // PageTurn switch
      await tester.pump(const Duration(milliseconds: 400)); // settle
      expect(turns, hasLength(1));
      expect(find.text('three'), findsOneWidget);

      // Final page -> the SAME hold + dog-ear -> the closing turn.
      tracker.emit(const WordAccepted(index: 0));
      await tester.pump();
      tracker.emit(const WordAccepted(index: 1));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);
      expect(find.byType(PageCurlCorner), findsOneWidget);
      expect(_dogEar(), findsOneWidget);
      expect(tracker.calls, contains('stop'));

      await _turnByGesture(tester);
      expect(turns, hasLength(1),
          reason: 'the final turn fires no onPageTurned');
      expect(complete, isEmpty);
      await tester.pump(kCelebrationBeat);
      await tester.pump();
      expect(complete, hasLength(1));
    });
  });
}

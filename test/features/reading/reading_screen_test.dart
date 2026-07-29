/// Widget/integration tests for `ReadingScreen` composition (PRD §8 Unit 5,
/// Unit 4 UI side, §5 analytics; ticket reading-screen accept entries 6, 7,
/// 8, 9, 10; plus the "no per-word sound" half of accept entry 2).
///
/// Exercises `ReadingScreen` (lib/features/reading/reading_screen.dart) end
/// to end against a local `ReadingTrackerHandle` double, `FakeAudioService`
/// (audio-playback, merged), `FakeStoryStage` (design, merged), and a real
/// `AnalyticsClient` wired to a temp-dir `EventQueue` + recording transport
/// (mirrors test/features/analytics/kill_switch_test.dart's established
/// pattern). None of lib/features/reading/{reading_screen,reading_controller,
/// word_text_view,narration_controller,listening_indicator}.dart exist yet:
/// this suite fails to compile/analyze until they do -- the expected red
/// state.
///
/// Pinned contract this suite locks in:
///  - Tap fallback: the current word is always tappable
///    (`ValueKey('word-tap-$i')` on the current index only, unless it is
///    also vocab-tappable -- see below); tapping it calls
///    `ReadingTrackerHandle.tapCurrentWord()`, whose resulting `WordAccepted`
///    (pushed by the tracker double, exactly as the real `ReadingTracker`
///    does) renders identically to a spoken acceptance.
///  - Vocab tap: a vocab-tappable word (`vocabCardId != null &&
///    Level.vocabEnabled`) is tappable via the SAME key regardless of
///    lifecycle (before/during/after being read) and takes priority over
///    the tap-fallback path when both would apply. Tapping it: pauses
///    listening (`tracker.pause()`), calls the injected `VocabCardOpener`
///    with the word's `vocabCardId`, and -- once the opener's future
///    completes (the card closed) -- resumes listening (`tracker.resume()`)
///    with the reading cursor (`currentPageIndex`/`currentIndex`) unchanged.
///  - Listening indicator (`ValueKey('listening-indicator-active')`):
///    present iff `ReadingController.isListening` is true -- true once
///    listening begins, false while paused for a vocab card, true again
///    after it resumes, false once the story completes and the tracker
///    stops.
///  - Story completion: the event that resolves the last word calls
///    `tracker.stop()` synchronously; the machine then HOLDS with the
///    page-curl dog-ear (AMENDED 2026-07-29: curl-closes-every-page ruling
///    (PRD §8 Unit 5)) and `onStoryComplete` fires only after the child's
///    turn plus `celebrationBeat` (~400 ms) -- never before the turn.
///  - Analytics (`AnalyticsEventName.storyStarted`/`wordRead`): emitted via
///    the real `AnalyticsClient`/`EventQueue` pipeline with the exact §5
///    payload shape; `word_read`'s `result` matches the word's resolution
///    (correct/near_miss/helped) and fires once per newly-resolved word,
///    including every silently back-filled word from a lookahead
///    acceptance.
///  - `onReadingExited` fires exactly once, when the screen is disposed
///    (removed from the tree) -- the hook the app shell wires to
///    `SessionTracker.onReadingScreenExited()` (analytics, merged).
///  - No per-word sound: `FakeAudioService.callLog` stays empty across
///    ordinary word acceptances at a `narrationEnabled: false` level.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/design/fake_rive_stage.dart';
// AMENDED 2026-07-29: curl-closes-every-page ruling (PRD §8 Unit 5): the
// completion-beat test now turns the held final page via the dog-ear.
import 'package:learn_to_read/design/page_curl.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/features/analytics/analytics_client.dart';
import 'package:learn_to_read/features/analytics/event_queue.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/analytics/events.dart';
import 'package:learn_to_read/features/analytics/session_tracker.dart';
import 'package:learn_to_read/features/analytics/transport.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/listening/contracts/tracker_events.dart';
import 'package:learn_to_read/features/reading/reading_controller.dart';
import 'package:learn_to_read/features/reading/reading_screen.dart';

// ---------------------------------------------------------------------------
// Fixtures.
// ---------------------------------------------------------------------------

WordToken _word(String text, {String? vocabCardId}) => WordToken(
      text: text,
      graphemePhonemeMap: [(graphemes: text, phonemeId: 'AH')],
      pronunciationAudioRef: 'audio/words/$text.mp3',
      vocabCardId: vocabCardId,
    );

Level _level({bool vocabEnabled = false}) => Level(
      id: 'level.1',
      ordinal: 1,
      newSkills: const [],
      format: LevelFormat.multiSentence, // narrationEnabled defaults false
      vocabEnabled: vocabEnabled,
    );

Story _story(List<WordToken> words, {String id = 'story.1'}) => Story(
      id: id,
      levelId: 'level.1',
      title: 'Test Story',
      pages: [
        Page(sentences: [Sentence(words: words)]),
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
  int currentIndexForTap = 0;

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
  void tapCurrentWord() {
    calls.add('tap');
    // Mirrors the real ReadingTracker: tapCurrentWord() pushes a
    // WordAccepted through the SAME event stream as a spoken acceptance.
    _controller.add(WordAccepted(index: currentIndexForTap));
  }

  void emit(TrackerEvent event) => _controller.add(event);
}

class _VocabOpenerRig {
  final List<String> openedIds = [];
  Completer<void>? _pending;

  Future<void> open(String vocabCardId) {
    openedIds.add(vocabCardId);
    final completer = Completer<void>();
    _pending = completer;
    return completer.future;
  }

  void closeCard() {
    _pending?.complete();
    _pending = null;
  }
}

/// Wires a real `AnalyticsClient` to a temp-dir `EventQueue` and a
/// recording `AnalyticsTransport`, mirroring
/// test/features/analytics/kill_switch_test.dart's established pattern.
class _AnalyticsRig {
  late Directory tempDir;
  late _RecordingTransport transport;
  late EventQueue queue;
  late AnalyticsClient client;

  void setUp() {
    tempDir = Directory.systemTemp.createTempSync('reading_screen_test_');
    transport = _RecordingTransport();
    queue = EventQueue(
      transport: transport,
      clock: () => DateTime.utc(2026, 1, 1),
      storageDirectory: tempDir,
    );
    client = AnalyticsClient(enabled: true, queue: queue);
  }

  void tearDown() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  }

  /// Real async gap: lets in-flight `enqueue()` file writes land before
  /// reading them back. Must be called inside `tester.runAsync`.
  Future<List<Map<String, Object?>>> pendingEventsAfterSettling() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    return queue.pendingEvents();
  }
}

class _RecordingTransport implements AnalyticsTransport {
  final List<List<Map<String, Object?>>> calls = [];

  @override
  Future<TransportResult> send(List<Map<String, Object?>> batch) async {
    calls.add(batch);
    return TransportResult.success;
  }
}

Widget _buildScreen({
  required Story story,
  required Level level,
  required _FakeTrackerHandle tracker,
  required AnalyticsClient analytics,
  FakeAudioService? audioService,
  FakeStoryStage? stage,
  Future<void> Function(String vocabCardId)? vocabCardOpener,
  VoidCallback? onStoryComplete,
  VoidCallback? onReadingExited,
}) {
  return MaterialApp(
    home: ReadingScreen(
      story: story,
      level: level,
      tracker: tracker,
      audioService: audioService ?? FakeAudioService(),
      analytics: analytics,
      installId: 'a1b2c3d4-1234-4abc-8def-0123456789ab',
      profileOrdinal: 1,
      levelOrdinal: 1,
      stage: stage ?? FakeStoryStage(),
      vocabCardOpener: vocabCardOpener ?? (_) async {},
      onStoryComplete: onStoryComplete,
      onReadingExited: onReadingExited,
    ),
  );
}

bool _isListeningIndicatorActive(WidgetTester tester) =>
    tester.any(find.byKey(const ValueKey('listening-indicator-active')));

void main() {
  group('Analytics — story_started and word_read (POSITIVE)', () {
    late _AnalyticsRig rig;

    setUp(() => rig = _AnalyticsRig()..setUp());
    tearDown(() => rig.tearDown());

    testWidgets('story_started fires on open, carrying this storyId', (tester) async {
      final tracker = _FakeTrackerHandle();
      final words = [_word('the'), _word('cat')];
      await tester.pumpWidget(_buildScreen(
        story: _story(words, id: 'story.open-test'),
        level: _level(),
        tracker: tracker,
        analytics: rig.client,
      ));
      await tester.pump();

      late List<Map<String, Object?>> events;
      await tester.runAsync(() async {
        events = await rig.pendingEventsAfterSettling();
      });

      final started = events.where((e) => e['event'] == 'story_started').toList();
      expect(started, hasLength(1));
      expect(started.single['storyId'], 'story.open-test');
    });

    testWidgets('word_read(correct) fires for a plain WordAccepted', (tester) async {
      final tracker = _FakeTrackerHandle();
      final words = [_word('the'), _word('cat')];
      await tester.pumpWidget(_buildScreen(
        story: _story(words),
        level: _level(),
        tracker: tracker,
        analytics: rig.client,
      ));
      await tester.pump();

      tracker.emit(const WordAccepted(index: 0));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);

      late List<Map<String, Object?>> events;
      await tester.runAsync(() async {
        events = await rig.pendingEventsAfterSettling();
      });

      final wordReads = events.where((e) => e['event'] == 'word_read').toList();
      expect(wordReads, hasLength(1));
      expect(wordReads.single['result'], WordReadResult.correct.wireValue);
      expect(wordReads.single['wordHash'], hashWord('the'));
    });

    testWidgets('word_read(near_miss) fires for a WordAcceptedNearMiss', (tester) async {
      final tracker = _FakeTrackerHandle();
      final words = [_word('the'), _word('cat')];
      await tester.pumpWidget(_buildScreen(
        story: _story(words),
        level: _level(),
        tracker: tracker,
        analytics: rig.client,
      ));
      await tester.pump();

      tracker.emit(const WordAcceptedNearMiss(index: 0));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);

      late List<Map<String, Object?>> events;
      await tester.runAsync(() async {
        events = await rig.pendingEventsAfterSettling();
      });

      final wordReads = events.where((e) => e['event'] == 'word_read').toList();
      expect(wordReads, hasLength(1));
      expect(wordReads.single['result'], WordReadResult.nearMiss.wireValue);
    });

    testWidgets('word_read(helped) fires for a WordHelped', (tester) async {
      final tracker = _FakeTrackerHandle();
      final words = [_word('the'), _word('cat')];
      await tester.pumpWidget(_buildScreen(
        story: _story(words),
        level: _level(),
        tracker: tracker,
        analytics: rig.client,
      ));
      await tester.pump();

      tracker.emit(const WordHelped(index: 0, tier: HelpLevel.soundOut));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);

      late List<Map<String, Object?>> events;
      await tester.runAsync(() async {
        events = await rig.pendingEventsAfterSettling();
      });

      final wordReads = events.where((e) => e['event'] == 'word_read').toList();
      expect(wordReads, hasLength(1));
      expect(wordReads.single['result'], WordReadResult.helped.wireValue);
    });

    testWidgets('EDGE: a lookahead back-fill emits one word_read(correct) '
        'per silently-resolved word, plus the target word\'s own grade', (tester) async {
      final tracker = _FakeTrackerHandle();
      final words = [_word('a'), _word('big'), _word('cat')];
      await tester.pumpWidget(_buildScreen(
        story: _story(words),
        level: _level(),
        tracker: tracker,
        analytics: rig.client,
      ));
      await tester.pump();

      tracker.emit(const WordAcceptedNearMiss(index: 2));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);

      late List<Map<String, Object?>> events;
      await tester.runAsync(() async {
        events = await rig.pendingEventsAfterSettling();
      });

      final wordReads = events.where((e) => e['event'] == 'word_read').toList();
      expect(wordReads, hasLength(3));
      expect(wordReads[0]['wordHash'], hashWord('a'));
      expect(wordReads[0]['result'], WordReadResult.correct.wireValue);
      expect(wordReads[1]['wordHash'], hashWord('big'));
      expect(wordReads[1]['result'], WordReadResult.correct.wireValue);
      expect(wordReads[2]['wordHash'], hashWord('cat'));
      expect(wordReads[2]['result'], WordReadResult.nearMiss.wireValue);
    });

    testWidgets('NEGATIVE: an out-of-range event that resolves nothing '
        'emits no word_read', (tester) async {
      final tracker = _FakeTrackerHandle();
      final words = [_word('the'), _word('cat')];
      await tester.pumpWidget(_buildScreen(
        story: _story(words),
        level: _level(),
        tracker: tracker,
        analytics: rig.client,
      ));
      await tester.pump();

      tracker.emit(const WordAccepted(index: 99));
      await tester.pump();

      late List<Map<String, Object?>> events;
      await tester.runAsync(() async {
        events = await rig.pendingEventsAfterSettling();
      });

      expect(events.where((e) => e['event'] == 'word_read'), isEmpty);
    });
  });

  group('reading-exited hook (POSITIVE)', () {
    testWidgets('onReadingExited fires exactly once, when the screen is '
        'disposed', (tester) async {
      final tracker = _FakeTrackerHandle();
      final words = [_word('the'), _word('cat')];
      var exitedCalls = 0;
      final analytics = AnalyticsClient(
        enabled: false,
        queue: EventQueue(
          transport: const NullAnalyticsTransport(),
          clock: () => DateTime.utc(2026, 1, 1),
          storageDirectory: Directory.systemTemp,
        ),
      );

      await tester.pumpWidget(_buildScreen(
        story: _story(words),
        level: _level(),
        tracker: tracker,
        analytics: analytics,
        onReadingExited: () => exitedCalls++,
      ));
      await tester.pump();
      expect(exitedCalls, 0);

      // Replace the whole tree -- ReadingScreen (and its State) is disposed.
      await tester.pumpWidget(const SizedBox.shrink());
      expect(exitedCalls, 1);
    });

    testWidgets('POSITIVE: wired to a real SessionTracker, exiting mid-story '
        'registers as reading-exited (proves the hook integrates with the '
        'merged analytics session tracker, not just a bare callback)', (tester) async {
      final tracker = _FakeTrackerHandle();
      final words = [_word('the'), _word('cat')];
      final analytics = AnalyticsClient(
        enabled: false,
        queue: EventQueue(
          transport: const NullAnalyticsTransport(),
          clock: () => DateTime.utc(2026, 1, 1),
          storageDirectory: Directory.systemTemp,
        ),
      );
      final emitted = <String>[];
      final sessionTracker = SessionTracker(
        clock: () => DateTime.utc(2026, 1, 1),
        installId: 'a1b2c3d4-1234-4abc-8def-0123456789ab',
        onEvent: (event) => emitted.add(event.name.wireName),
      );
      sessionTracker.startSession(profileOrdinal: 1, levelOrdinal: 1);
      sessionTracker.onStoryStarted(storyId: 'story.1');

      await tester.pumpWidget(_buildScreen(
        story: _story(words, id: 'story.1'),
        level: _level(),
        tracker: tracker,
        analytics: analytics,
        onReadingExited: sessionTracker.onReadingScreenExited,
      ));
      await tester.pump();

      await tester.pumpWidget(const SizedBox.shrink());

      expect(emitted, contains('story_abandoned'));
    });
  });

  group('Tap fallback (POSITIVE / NEGATIVE)', () {
    testWidgets('tapping the current word calls tracker.tapCurrentWord(), '
        'and the resulting acceptance renders identically to a spoken one', (tester) async {
      final tracker = _FakeTrackerHandle()..currentIndexForTap = 0;
      final words = [_word('the'), _word('cat')];
      await tester.pumpWidget(_buildScreen(
        story: _story(words),
        level: _level(),
        tracker: tracker,
        analytics: _noOpAnalyticsClient(),
      ));
      await tester.pump();

      expect(find.byKey(const ValueKey('word-tap-0')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('word-tap-0')));
      await tester.pump();

      expect(tracker.calls, contains('tap'));
      await tester.pump(DesignTokens.greenSweepDuration);

      final text = tester.widget<Text>(find.byKey(const ValueKey('word-text-0')));
      expect(text.style?.color, DesignTokens.wordReadGreen);
    });

    testWidgets('NEGATIVE: a non-current, non-vocab word has no tap target '
        'at all', (tester) async {
      final tracker = _FakeTrackerHandle();
      final words = [_word('the'), _word('cat'), _word('sat')];
      await tester.pumpWidget(_buildScreen(
        story: _story(words),
        level: _level(),
        tracker: tracker,
        analytics: _noOpAnalyticsClient(),
      ));
      await tester.pump();

      expect(find.byKey(const ValueKey('word-tap-1')), findsNothing);
      expect(find.byKey(const ValueKey('word-tap-2')), findsNothing);
    });
  });

  group('Vocab tap: pause / open / restore cursor (integration, POSITIVE)', () {
    testWidgets('tapping a not-yet-current vocab word pauses listening, '
        'opens the card with its id, and restores the exact cursor on close', (tester) async {
      final tracker = _FakeTrackerHandle();
      final vocabRig = _VocabOpenerRig();
      final words = [
        _word('the'),
        _word('elephant', vocabCardId: 'vocab.elephant'),
        _word('walked'),
      ];
      await tester.pumpWidget(_buildScreen(
        story: _story(words),
        level: _level(vocabEnabled: true),
        tracker: tracker,
        analytics: _noOpAnalyticsClient(),
        vocabCardOpener: vocabRig.open,
      ));
      await tester.pump();
      expect(tracker.isListening, isTrue);
      expect(_isListeningIndicatorActive(tester), isTrue);
      // Orchestrator test-fix: reaching isListening==true necessarily logs
      // 'resume' in this fake, so the exact-log assertion below
      // (['pause','resume']) could never hold from a dirty log. Clear it,
      // exactly as narration_test.dart:399 does before its own exact-log
      // assertion.
      tracker.calls.clear();

      await tester.tap(find.byKey(const ValueKey('word-tap-1')));
      await tester.pump();

      expect(vocabRig.openedIds, ['vocab.elephant']);
      expect(tracker.calls, contains('pause'));
      expect(tracker.isListening, isFalse);
      expect(_isListeningIndicatorActive(tester), isFalse);

      // Cursor is still word 0, current, exactly as before the tap.
      expect(find.byKey(const ValueKey('word-current-marker-0')), findsOneWidget);

      vocabRig.closeCard();
      await tester.pump();
      await tester.pump();

      expect(tracker.calls, ['pause', 'resume']);
      expect(tracker.isListening, isTrue);
      expect(_isListeningIndicatorActive(tester), isTrue);
      expect(find.byKey(const ValueKey('word-current-marker-0')), findsOneWidget);
    });

    testWidgets('EDGE: tapping a vocab word AFTER it has already turned '
        'green still pauses/opens/restores, and does not re-resolve it', (tester) async {
      final tracker = _FakeTrackerHandle();
      final vocabRig = _VocabOpenerRig();
      final words = [_word('the', vocabCardId: 'vocab.the'), _word('cat')];
      await tester.pumpWidget(_buildScreen(
        story: _story(words),
        level: _level(vocabEnabled: true),
        tracker: tracker,
        analytics: _noOpAnalyticsClient(),
        vocabCardOpener: vocabRig.open,
      ));
      await tester.pump();

      tracker.emit(const WordAccepted(index: 0));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);
      expect(find.byKey(const ValueKey('word-current-marker-1')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('word-tap-0')));
      await tester.pump();
      expect(vocabRig.openedIds, ['vocab.the']);
      expect(tracker.isListening, isFalse);
      // Still current on word 1 -- opening the card for an already-read
      // word never re-resolves or moves the cursor.
      expect(find.byKey(const ValueKey('word-current-marker-1')), findsOneWidget);

      vocabRig.closeCard();
      await tester.pump();
      await tester.pump();
      expect(tracker.isListening, isTrue);
      expect(find.byKey(const ValueKey('word-current-marker-1')), findsOneWidget);
    });

    testWidgets('NEGATIVE: vocabEnabled == false renders no vocab tap '
        'target even when a word carries a vocabCardId', (tester) async {
      final tracker = _FakeTrackerHandle();
      final words = [_word('the'), _word('elephant', vocabCardId: 'vocab.elephant')];
      await tester.pumpWidget(_buildScreen(
        story: _story(words),
        level: _level(vocabEnabled: false),
        tracker: tracker,
        analytics: _noOpAnalyticsClient(),
      ));
      await tester.pump();

      expect(find.byKey(const ValueKey('word-tap-1')), findsNothing);
    });
  });

  group('Listening indicator (POSITIVE)', () {
    testWidgets('active once listening begins, inactive once the story '
        'completes', (tester) async {
      final tracker = _FakeTrackerHandle();
      final words = [_word('go')];
      await tester.pumpWidget(_buildScreen(
        story: _story(words),
        level: _level(),
        tracker: tracker,
        analytics: _noOpAnalyticsClient(),
      ));
      await tester.pump();
      expect(_isListeningIndicatorActive(tester), isTrue);

      tracker.emit(const WordAccepted(index: 0));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);

      expect(_isListeningIndicatorActive(tester), isFalse);
    });
  });

  group('Completion beat -> celebration handoff (fake-clock, POSITIVE)', () {
    // AMENDED 2026-07-29: curl-closes-every-page ruling (PRD §8 Unit 5):
    // the beat now starts at the child's TURN of the held final page, not
    // at the last word's resolution. tracker.stop() timing is unchanged
    // (synchronous on the resolving event).
    testWidgets('the last word resolving stops the tracker synchronously and '
        'holds; onStoryComplete fires only after the turn plus the ~400 ms '
        'beat, not before', (tester) async {
      final tracker = _FakeTrackerHandle();
      final words = [_word('go')];
      var completedCalls = 0;
      await tester.pumpWidget(_buildScreen(
        story: _story(words),
        level: _level(),
        tracker: tracker,
        analytics: _noOpAnalyticsClient(),
        onStoryComplete: () => completedCalls++,
      ));
      await tester.pump();

      tracker.emit(const WordAccepted(index: 0));
      await tester.pump();

      // stop() is synchronous, right on the resolving event.
      expect(tracker.calls, contains('stop'));
      expect(tracker.isListening, isFalse);
      expect(completedCalls, 0);

      // The hold waits for the child indefinitely: no beat without a turn.
      await tester.pump(const Duration(seconds: 5));
      expect(completedCalls, 0);
      expect(find.byType(PageCurlCorner), findsOneWidget);

      // The child closes the book (tap on the dog-ear's hit region).
      final corner = tester.getBottomRight(find.byType(PageCurlCorner)) -
          const Offset(8, 8);
      await tester.tapAt(corner);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 360)); // curl completes

      expect(completedCalls, 0);
      await tester.pump(const Duration(milliseconds: 399));
      expect(completedCalls, 0);

      await tester.pump(const Duration(milliseconds: 1));
      expect(completedCalls, 1);

      // Never fires twice.
      await tester.pump(const Duration(seconds: 1));
      expect(completedCalls, 1);
    });
  });

  group('No per-word sound (POSITIVE, accept entry 2)', () {
    testWidgets('FakeAudioService.callLog stays empty across ordinary word '
        'acceptances at a narrationEnabled: false level', (tester) async {
      final tracker = _FakeTrackerHandle();
      final audio = FakeAudioService();
      final words = [_word('the'), _word('cat'), _word('sat')];
      await tester.pumpWidget(_buildScreen(
        story: _story(words),
        level: _level(), // multiSentence -> narrationEnabled: false
        tracker: tracker,
        analytics: _noOpAnalyticsClient(),
        audioService: audio,
      ));
      await tester.pump();
      expect(audio.callLog, isEmpty);

      tracker.emit(const WordAccepted(index: 0));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);
      tracker.emit(const WordAcceptedNearMiss(index: 1));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);
      tracker.emit(const WordAccepted(index: 2));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);

      expect(audio.callLog, isEmpty);
    });
  });
}

AnalyticsClient _noOpAnalyticsClient() => AnalyticsClient(
      enabled: false,
      queue: EventQueue(
        transport: const NullAnalyticsTransport(),
        clock: () => DateTime.utc(2026, 1, 1),
        storageDirectory: Directory.systemTemp,
      ),
    );

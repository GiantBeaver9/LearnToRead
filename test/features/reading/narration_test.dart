/// Tests for listen-first narration (PRD §8 Unit 5 "Listen-first at early
/// levels", A-11 ratified; ticket reading-screen accept entry 3).
///
/// Exercises `NarrationController` (lib/features/reading/narration_controller.dart)
/// directly (a plain Dart controller, not a widget) against `FakeAudioService`
/// (audio-playback, merged), plus the listen-first *ordering* contract as
/// wired by `ReadingScreen`/`ReadingController` (lib/features/reading/
/// reading_screen.dart, reading_controller.dart): narration plays once,
/// completes, THEN (and only then) listening begins. None of the three lib
/// files exist yet -- this suite fails to compile/analyze until they do
/// (the expected red state).
///
/// Pinned contract this suite locks in:
///  - `NarrationController.playInitial(ref)` plays [ref] on
///    `AudioChannel.narration` and completes only once the clip finishes
///    (`FakeAudioService.completePlayback`).
///  - `NarrationController.replay(ref)` (the ear-icon button): pauses
///    listening (`ReadingTrackerHandle.pause`), plays [ref], and resumes
///    listening (`ReadingTrackerHandle.resume`) once playback ends -- even
///    if playback throws (a missing/corrupt clip must never strand the
///    child mid-pause).
///  - No per-word highlighting during narration in v1 (A-11): narration
///    playback never touches word state (asserted at the `ReadingScreen`
///    level -- the `WordTextView` word colors are unchanged across a
///    narration/replay cycle).
///  - `ReadingScreen`: at `Level.narrationEnabled` levels, opening a story
///    plays the sentence narration BEFORE the tracker's `eventsStream` is
///    subscribed (recognition not started until narration completes) --
///    verified by ordering `FakeAudioService.callLog`'s play entry against
///    when the `ReadingTrackerHandle` starts listening.
///  - At `narrationEnabled == false` levels (or no narration ref), listening
///    begins immediately with no narration playback at all.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/design/fake_rive_stage.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/features/analytics/analytics_client.dart';
import 'package:learn_to_read/features/analytics/event_queue.dart';
import 'package:learn_to_read/features/analytics/transport.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/listening/contracts/tracker_events.dart';
import 'package:learn_to_read/features/reading/narration_controller.dart';
import 'package:learn_to_read/features/reading/reading_controller.dart';
import 'package:learn_to_read/features/reading/reading_screen.dart';
import 'package:learn_to_read/features/reading/word_text_view.dart';

// ---------------------------------------------------------------------------
// Fixtures.
// ---------------------------------------------------------------------------

WordToken _word(String text) => WordToken(
      text: text,
      graphemePhonemeMap: [(graphemes: text, phonemeId: 'AH')],
      pronunciationAudioRef: 'audio/words/$text.mp3',
    );

Level _level({required bool narrationEnabled}) => Level(
      id: 'level.1',
      ordinal: 1,
      newSkills: const [],
      format: LevelFormat.sentence,
      vocabEnabled: false,
      narrationEnabled: narrationEnabled,
    );

Story _story({String? narrationAudioRef}) => Story(
      id: 'story.1',
      levelId: 'level.1',
      title: 'Test Story',
      pages: [
        Page(sentences: [
          Sentence(
            words: [_word('the'), _word('cat')],
            narrationAudioRef: narrationAudioRef,
          ),
        ]),
      ],
      riveAnimationRef: 'rive/story.riv',
      celebrationAudioRef: 'audio/celebration.mp3',
      collectibleRef: 'collectible.1',
      skillsExercised: const [],
      packId: 'pack.test',
      contentVersion: '1',
    );

/// Local `ReadingTrackerHandle` double, same shape as
/// word_states_render_test.dart's (redefined locally per this repo's
/// established per-file convention). `resume()`/`pause()` are the ordering
/// beacons this suite reads to prove listening starts after narration.
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
  required FakeAudioService audioService,
  VoidCallback? onStoryComplete,
}) {
  return MaterialApp(
    home: ReadingScreen(
      story: story,
      level: level,
      tracker: tracker,
      audioService: audioService,
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

void main() {
  group('NarrationController — unit', () {
    late FakeAudioService audio;
    late bool paused;
    late bool resumed;
    late NarrationController narration;

    setUp(() {
      audio = FakeAudioService();
      paused = false;
      resumed = false;
      narration = NarrationController(
        audioService: audio,
        pauseListening: () => paused = true,
        resumeListening: () => resumed = true,
      );
    });

    test('POSITIVE: playInitial plays on the narration channel and '
        'completes only once the clip finishes', () async {
      var completed = false;
      final future = narration.playInitial('audio/sentence.mp3').then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);

      expect(completed, isFalse);
      expect(audio.callLog, hasLength(1));
      final play = audio.callLog.single as PlayLogEntry;
      expect(play.ref, 'audio/sentence.mp3');
      expect(play.channel, AudioChannel.narration);

      audio.completePlayback(play.handle);
      await future;
      expect(completed, isTrue);
    });

    test('POSITIVE: playInitial does not pause/resume listening -- '
        'listening has not started yet at listen-first time', () async {
      final future = narration.playInitial('audio/sentence.mp3');
      await Future<void>.delayed(Duration.zero);
      final play = audio.callLog.single as PlayLogEntry;
      audio.completePlayback(play.handle);
      await future;

      expect(paused, isFalse);
      expect(resumed, isFalse);
    });

    test('POSITIVE: replay pauses listening, plays, then resumes listening '
        'once playback ends', () async {
      final order = <String>[];
      narration = NarrationController(
        audioService: audio,
        pauseListening: () => order.add('pause'),
        resumeListening: () => order.add('resume'),
      );

      final future = narration.replay('audio/sentence.mp3');
      await Future<void>.delayed(Duration.zero);
      expect(order, ['pause']);

      final play = audio.callLog.single as PlayLogEntry;
      expect(play.channel, AudioChannel.narration);
      audio.completePlayback(play.handle);
      await future;

      expect(order, ['pause', 'resume']);
    });

    test('EDGE: replay still resumes listening if the clip is missing '
        '(a content bug must never strand a paused child)', () async {
      audio = FakeAudioService(missingRefs: {'audio/missing.mp3'});
      final order = <String>[];
      narration = NarrationController(
        audioService: audio,
        pauseListening: () => order.add('pause'),
        resumeListening: () => order.add('resume'),
      );

      await narration.replay('audio/missing.mp3');
      expect(order, ['pause', 'resume']);
    });

    test('POSITIVE: isPlaying reflects in-flight playback', () async {
      expect(narration.isPlaying, isFalse);
      final future = narration.playInitial('audio/sentence.mp3');
      await Future<void>.delayed(Duration.zero);
      expect(narration.isPlaying, isTrue);

      final play = audio.callLog.single as PlayLogEntry;
      audio.completePlayback(play.handle);
      await future;
      expect(narration.isPlaying, isFalse);
    });
  });

  group('ReadingScreen — listen-first ordering (POSITIVE)', () {
    testWidgets('at a narrationEnabled level, narration plays before '
        'listening begins: a tracker event applied before narration '
        'completes has no effect on word state', (tester) async {
      final story = _story(narrationAudioRef: 'audio/sentence.mp3');
      final level = _level(narrationEnabled: true);
      final tracker = _FakeTrackerHandle();
      final audio = FakeAudioService();

      await tester.pumpWidget(_buildScreen(
        story: story,
        level: level,
        tracker: tracker,
        audioService: audio,
      ));
      await tester.pump();

      // Narration is playing; listening has not started.
      expect(audio.callLog, hasLength(1));
      final play = audio.callLog.single as PlayLogEntry;
      expect(play.channel, AudioChannel.narration);
      expect(tracker.calls, isEmpty);
      expect(tracker.isListening, isFalse);

      // Word 0's color is unchanged by narration itself: still the current
      // marker, no green anywhere (no karaoke).
      expect(find.byKey(const ValueKey('word-current-marker-0')), findsOneWidget);

      audio.completePlayback(play.handle);
      await tester.pump();
      await tester.pump();

      // Listening has now started.
      expect(tracker.calls, contains('resume'));
      expect(tracker.isListening, isTrue);
    });

    testWidgets('a tracker event emitted mid-narration is only applied '
        'after narration completes and listening begins', (tester) async {
      final story = _story(narrationAudioRef: 'audio/sentence.mp3');
      final level = _level(narrationEnabled: true);
      final tracker = _FakeTrackerHandle();
      final audio = FakeAudioService();

      await tester.pumpWidget(_buildScreen(
        story: story,
        level: level,
        tracker: tracker,
        audioService: audio,
      ));
      await tester.pump();

      // Emitted before subscription exists -- the broadcast stream drops it,
      // proving the controller had not subscribed (had not started
      // listening) during narration.
      tracker.emit(const WordAccepted(index: 0));
      await tester.pump();
      expect(find.byKey(const ValueKey('word-current-marker-0')), findsOneWidget);

      final play = audio.callLog.single as PlayLogEntry;
      audio.completePlayback(play.handle);
      await tester.pump();
      await tester.pump();
      expect(tracker.isListening, isTrue);

      tracker.emit(const WordAccepted(index: 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(const ValueKey('word-current-marker-0')), findsNothing);
    });
  });

  group('ReadingScreen — narrationEnabled == false (NEGATIVE)', () {
    testWidgets('listening begins immediately, with zero narration '
        'playback', (tester) async {
      final story = _story(narrationAudioRef: 'audio/sentence.mp3');
      final level = _level(narrationEnabled: false);
      final tracker = _FakeTrackerHandle();
      final audio = FakeAudioService();

      await tester.pumpWidget(_buildScreen(
        story: story,
        level: level,
        tracker: tracker,
        audioService: audio,
      ));
      await tester.pump();

      expect(audio.callLog, isEmpty);
      expect(tracker.calls, contains('resume'));
      expect(tracker.isListening, isTrue);
    });
  });

  group('ReadingScreen — EDGE: no narration ref even though the level '
      'permits narration', () {
    testWidgets('listening begins immediately when there is nothing to '
        'narrate', (tester) async {
      final story = _story(narrationAudioRef: null);
      final level = _level(narrationEnabled: true);
      final tracker = _FakeTrackerHandle();
      final audio = FakeAudioService();

      await tester.pumpWidget(_buildScreen(
        story: story,
        level: level,
        tracker: tracker,
        audioService: audio,
      ));
      await tester.pump();

      expect(audio.callLog, isEmpty);
      expect(tracker.isListening, isTrue);
    });
  });

  group('ReadingScreen — ear-icon replay (POSITIVE)', () {
    testWidgets('tapping the replay button pauses recognition while '
        'narration plays and resumes it after', (tester) async {
      final story = _story(narrationAudioRef: 'audio/sentence.mp3');
      final level = _level(narrationEnabled: true);
      final tracker = _FakeTrackerHandle();
      final audio = FakeAudioService();

      await tester.pumpWidget(_buildScreen(
        story: story,
        level: level,
        tracker: tracker,
        audioService: audio,
      ));
      await tester.pump();
      final firstPlay = audio.callLog.single as PlayLogEntry;
      audio.completePlayback(firstPlay.handle);
      await tester.pump();
      await tester.pump();
      expect(tracker.isListening, isTrue);
      tracker.calls.clear();

      expect(find.byKey(const ValueKey('narration-replay-button')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('narration-replay-button')));
      await tester.pump();

      expect(tracker.calls, ['pause']);
      expect(tracker.isListening, isFalse);

      final replayEntries = audio.callLog.whereType<PlayLogEntry>().toList();
      expect(replayEntries, hasLength(2));
      audio.completePlayback(replayEntries.last.handle);
      await tester.pump();
      await tester.pump();

      expect(tracker.calls, ['pause', 'resume']);
      expect(tracker.isListening, isTrue);
    });

    testWidgets('NEGATIVE: no replay button is rendered when the level has '
        'no narration', (tester) async {
      final story = _story(narrationAudioRef: null);
      final level = _level(narrationEnabled: false);
      final tracker = _FakeTrackerHandle();
      final audio = FakeAudioService();

      await tester.pumpWidget(_buildScreen(
        story: story,
        level: level,
        tracker: tracker,
        audioService: audio,
      ));
      await tester.pump();

      expect(find.byKey(const ValueKey('narration-replay-button')), findsNothing);
    });
  });
}

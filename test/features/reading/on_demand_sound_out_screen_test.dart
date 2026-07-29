// Widget tests for the on-demand sound-out wiring on the reading screen
// (owner direction 2026-07-29: "sounding out the phonics of everything").
//
// Exercises ReadingScreen end to end against the local
// ReadingTrackerHandle double + FakeAudioService + FakeStoryStage harness
// established by test/features/reading/reading_screen_test.dart. The
// pinned tap contract from the frozen suites is deliberately re-asserted
// alongside the new gestures, so this file proves ADDITIVITY:
//
//  - long-press on ANY word -- unread, current, green, vocab-purple --
//    runs that word's grapheme-by-grapheme sound-out: phoneme clips play
//    in graphemePhonemeMap order on the help channel while the SAME hint
//    panel / grapheme-chip treatment Tier-1 uses renders on that word,
//    the lit chip following the sounding clip;
//  - listening is paused for the duration of the pass and resumed after
//    (the NarrationController replay bracket, via the same seams);
//  - tap semantics are untouched: the current word's tap target still
//    routes to tracker.tapCurrentWord() while a pass runs on another word;
//  - a chip of a rendered sound-out panel is tappable and plays exactly
//    THAT cluster's phoneme, one clip, never the whole sequence, and
//    never the word-level tap path;
//  - a silent-letter chip is a gentle no-op.
//
// Stepped pumps only -- the listening indicator's waveform repeats
// forever, so pumpAndSettle would never return.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/design/fake_rive_stage.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/features/analytics/analytics_client.dart';
import 'package:learn_to_read/features/analytics/event_queue.dart';
import 'package:learn_to_read/features/analytics/transport.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/listening/contracts/help_state.dart';
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

WordToken _shipWord({String? vocabCardId}) => WordToken(
      text: 'ship',
      graphemePhonemeMap: const [
        (graphemes: 'sh', phonemeId: 'SH'),
        (graphemes: 'i', phonemeId: 'IH'),
        (graphemes: 'p', phonemeId: 'P'),
      ],
      pronunciationAudioRef: 'audio/words/ship.mp3',
      vocabCardId: vocabCardId,
    );

WordToken _cakeWord() => WordToken(
      text: 'cake',
      graphemePhonemeMap: const [
        (graphemes: 'c', phonemeId: 'K'),
        (graphemes: 'a', phonemeId: 'EY'),
        (graphemes: 'k', phonemeId: 'K'),
        (graphemes: 'e', phonemeId: ''), // silent e
      ],
      pronunciationAudioRef: 'audio/words/cake.mp3',
    );

const Map<String, AudioRef> _phonemeRefs = {
  'AH': 'audio/phonemes/AH.mp3',
  'SH': 'audio/phonemes/SH.mp3',
  'IH': 'audio/phonemes/IH.mp3',
  'P': 'audio/phonemes/P.mp3',
  'K': 'audio/phonemes/K.mp3',
  'EY': 'audio/phonemes/EY.mp3',
};

Level _level({bool vocabEnabled = false}) => Level(
      id: 'level.1',
      ordinal: 1,
      newSkills: const [],
      format: LevelFormat.multiSentence, // narrationEnabled defaults false
      vocabEnabled: vocabEnabled,
    );

Story _story(List<WordToken> words) => Story(
      id: 'story.1',
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
    _controller.add(WordAccepted(index: currentIndexForTap));
  }

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
  HelpState helpState = kNoHelp,
  Future<void> Function(String vocabCardId)? vocabCardOpener,
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
      vocabCardOpener: vocabCardOpener ?? (_) async {},
      helpState: helpState,
      phonemeAudioRefs: _phonemeRefs,
    ),
  );
}

List<PlayLogEntry> _plays(FakeAudioService audio) =>
    audio.callLog.whereType<PlayLogEntry>().toList();

/// Completes the most recent clip and pumps, advancing the pass one step.
Future<void> _completeLastClip(WidgetTester tester, FakeAudioService audio) async {
  audio.completePlayback(_plays(audio).last.handle);
  await tester.pump();
  await tester.pump();
}

/// Bounded drain: completes EVERY logged clip (a finished handle is a safe
/// no-op) until listening resumes, so a pass can never leave a clip
/// sounding past a test. Bounded so a defect fails instead of hanging.
Future<void> _drainUntilResumed(
  WidgetTester tester,
  FakeAudioService audio,
  _FakeTrackerHandle tracker,
) async {
  for (var i = 0; i < 10 && !tracker.isListening; i++) {
    for (final entry in _plays(audio)) {
      audio.completePlayback(entry.handle);
    }
    await tester.pump();
    await tester.pump();
  }
  expect(tracker.isListening, isTrue);
}

FontWeight? _chipWeight(WidgetTester tester, int wordIndex, int g) => tester
    .widget<Text>(find.byKey(ValueKey('grapheme-$wordIndex-$g')))
    .style
    ?.fontWeight;

void main() {
  group('long-press -> on-demand sound-out (POSITIVE)', () {
    testWidgets('long-pressing an UNREAD word plays its phoneme refs in '
        'order with the Tier-1 highlight treatment, pausing listening for '
        'the duration and resuming after', (tester) async {
      final tracker = _FakeTrackerHandle();
      final audio = FakeAudioService();
      final words = [_word('the'), _shipWord()];
      await tester.pumpWidget(_buildScreen(
        story: _story(words),
        level: _level(),
        tracker: tracker,
        audioService: audio,
      ));
      await tester.pump();
      expect(tracker.isListening, isTrue);
      tracker.calls.clear();

      // Word 1 is unread: no tap target exists there (pinned baseline),
      // but a long-press on its text starts the sound-out.
      expect(find.byKey(const ValueKey('word-tap-1')), findsNothing);
      await tester.longPress(find.byKey(const ValueKey('word-text-1')));
      await tester.pump();

      // Listening paused for the pass.
      expect(tracker.calls, contains('pause'));
      expect(tracker.isListening, isFalse);
      expect(
        tester.any(find.byKey(const ValueKey('listening-indicator-active'))),
        isFalse,
      );

      // The SAME hint-panel treatment Tier-1 uses, on word 1: one chip per
      // graphemePhonemeMap entry, digraph "sh" one unit, cluster 0 lit.
      expect(find.byKey(const ValueKey('sound-out-hint-panel-1')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('grapheme-1-0'))).data,
        'sh',
      );
      expect(_chipWeight(tester, 1, 0), FontWeight.bold);
      expect(_chipWeight(tester, 1, 1), FontWeight.normal);
      expect(_plays(audio).map((e) => e.ref).toList(), ['audio/phonemes/SH.mp3']);
      expect(_plays(audio).single.channel, AudioChannel.help);

      // Clip done -> next clip, highlight advances.
      await _completeLastClip(tester, audio);
      expect(_plays(audio).map((e) => e.ref).toList(),
          ['audio/phonemes/SH.mp3', 'audio/phonemes/IH.mp3']);
      expect(_chipWeight(tester, 1, 0), FontWeight.normal);
      expect(_chipWeight(tester, 1, 1), FontWeight.bold);

      await _completeLastClip(tester, audio);
      expect(_plays(audio).map((e) => e.ref).toList(), [
        'audio/phonemes/SH.mp3',
        'audio/phonemes/IH.mp3',
        'audio/phonemes/P.mp3',
      ]);
      expect(_chipWeight(tester, 1, 2), FontWeight.bold);

      // Last clip done -> panel clears, word renders plainly again, and
      // listening resumes.
      await _completeLastClip(tester, audio);
      expect(find.byKey(const ValueKey('sound-out-hint-panel-1')), findsNothing);
      expect(find.byKey(const ValueKey('word-text-1')), findsOneWidget);
      expect(tracker.calls, contains('resume'));
      expect(tracker.isListening, isTrue);
      expect(
        tester.any(find.byKey(const ValueKey('listening-indicator-active'))),
        isTrue,
      );
    });

    testWidgets('tap semantics stay pinned-identical while a pass runs: '
        'the current word\'s tap target still routes to '
        'tracker.tapCurrentWord() and renders the accepted green',
        (tester) async {
      final tracker = _FakeTrackerHandle()..currentIndexForTap = 0;
      final audio = FakeAudioService();
      final words = [_word('the'), _shipWord()];
      await tester.pumpWidget(_buildScreen(
        story: _story(words),
        level: _level(),
        tracker: tracker,
        audioService: audio,
      ));
      await tester.pump();

      // Start a pass on word 1 (unread) -- word 0 stays current.
      await tester.longPress(find.byKey(const ValueKey('word-text-1')));
      await tester.pump();
      expect(find.byKey(const ValueKey('sound-out-hint-panel-1')), findsOneWidget);

      // The pinned tap fallback, mid-pass, unchanged.
      expect(find.byKey(const ValueKey('word-tap-0')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('word-tap-0')));
      await tester.pump();
      expect(tracker.calls, contains('tap'));
      await tester.pump(DesignTokens.greenSweepDuration);
      final text = tester.widget<Text>(find.byKey(const ValueKey('word-text-0')));
      expect(text.style?.color, DesignTokens.wordReadGreen);

      // Drain the pass so no clip is left sounding.
      await _drainUntilResumed(tester, audio, tracker);
    });

    testWidgets('long-pressing a GREEN (done) word works', (tester) async {
      final tracker = _FakeTrackerHandle();
      final audio = FakeAudioService();
      final words = [_shipWord(), _word('the')];
      await tester.pumpWidget(_buildScreen(
        story: _story(words),
        level: _level(),
        tracker: tracker,
        audioService: audio,
      ));
      await tester.pump();

      tracker.emit(const WordAccepted(index: 0));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('word-text-0'))).style?.color,
        DesignTokens.wordReadGreen,
      );
      tracker.calls.clear();

      await tester.longPress(find.byKey(const ValueKey('word-text-0')));
      await tester.pump();

      expect(tracker.calls, contains('pause'));
      expect(find.byKey(const ValueKey('sound-out-hint-panel-0')), findsOneWidget);
      expect(_plays(audio).map((e) => e.ref).toList(), ['audio/phonemes/SH.mp3']);

      await _completeLastClip(tester, audio);
      await _completeLastClip(tester, audio);
      await _completeLastClip(tester, audio);
      expect(find.byKey(const ValueKey('sound-out-hint-panel-0')), findsNothing);
      expect(tracker.calls, contains('resume'));
      // Still green after the pass -- sounding out resolves nothing.
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('word-text-0'))).style?.color,
        DesignTokens.wordReadGreen,
      );
    });

    testWidgets('long-pressing a vocab-read PURPLE word works (via its '
        'always-present vocab tap target), and tapping it still opens the '
        'card', (tester) async {
      final tracker = _FakeTrackerHandle();
      final audio = FakeAudioService();
      final openedIds = <String>[];
      final words = [_shipWord(vocabCardId: 'vocab.ship'), _word('the')];
      await tester.pumpWidget(_buildScreen(
        story: _story(words),
        level: _level(vocabEnabled: true),
        tracker: tracker,
        audioService: audio,
        vocabCardOpener: (id) async => openedIds.add(id),
      ));
      await tester.pump();

      tracker.emit(const WordAccepted(index: 0));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('word-text-0'))).style?.color,
        DesignTokens.wordVocabReadPurple,
      );

      await tester.longPress(find.byKey(const ValueKey('word-tap-0')));
      await tester.pump();
      expect(find.byKey(const ValueKey('sound-out-hint-panel-0')), findsOneWidget);
      expect(_plays(audio).map((e) => e.ref).toList(), ['audio/phonemes/SH.mp3']);
      expect(openedIds, isEmpty, reason: 'a long-press is not a vocab tap');

      await _completeLastClip(tester, audio);
      await _completeLastClip(tester, audio);
      await _completeLastClip(tester, audio);
      expect(find.byKey(const ValueKey('sound-out-hint-panel-0')), findsNothing);

      // The pinned vocab tap path, untouched.
      await tester.tap(find.byKey(const ValueKey('word-tap-0')));
      await tester.pump();
      await tester.pump();
      expect(openedIds, ['vocab.ship']);
    });

    testWidgets('EDGE: a second long-press supersedes the first pass -- the '
        'panel moves to the new word and listening resumes exactly once at '
        'the end', (tester) async {
      final tracker = _FakeTrackerHandle();
      final audio = FakeAudioService();
      final words = [_word('the'), _shipWord(), _cakeWord()];
      await tester.pumpWidget(_buildScreen(
        story: _story(words),
        level: _level(),
        tracker: tracker,
        audioService: audio,
      ));
      await tester.pump();
      tracker.calls.clear();

      await tester.longPress(find.byKey(const ValueKey('word-text-1')));
      await tester.pump();
      expect(find.byKey(const ValueKey('sound-out-hint-panel-1')), findsOneWidget);

      await tester.longPress(find.byKey(const ValueKey('word-text-2')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('sound-out-hint-panel-1')), findsNothing);
      expect(find.byKey(const ValueKey('sound-out-hint-panel-2')), findsOneWidget);

      // Drain: cake has three sounding clusters (K, EY, K).
      await _completeLastClip(tester, audio);
      await _completeLastClip(tester, audio);
      await _completeLastClip(tester, audio);
      expect(find.byKey(const ValueKey('sound-out-hint-panel-2')), findsNothing);
      expect(tracker.calls.where((c) => c == 'pause').length, 1);
      expect(tracker.calls.where((c) => c == 'resume').length, 1);
      expect(tracker.isListening, isTrue);
    });
  });

  group('tappable grapheme chips (POSITIVE / NEGATIVE)', () {
    testWidgets('POSITIVE: tapping ONE chip of the Tier-1 "take it slowly" '
        'panel plays exactly that cluster\'s phoneme -- a single clip, no '
        'sequence, and never the word-level tap path', (tester) async {
      final tracker = _FakeTrackerHandle();
      final audio = FakeAudioService();
      final words = [_shipWord(), _word('the')];
      await tester.pumpWidget(_buildScreen(
        story: _story(words),
        level: _level(),
        tracker: tracker,
        audioService: audio,
        helpState: const HelpState(
          currentHelpTier: HelpLevel.soundOut,
          highlightedGraphemeIndex: 0,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400)); // panel fadeUp
      tracker.calls.clear();

      expect(find.byKey(const ValueKey('sound-out-hint-panel-0')), findsOneWidget);
      // The word-level tap target still exists for the current word.
      expect(find.byKey(const ValueKey('word-tap-0')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('grapheme-chip-tap-0-1')));
      await tester.pump();
      await tester.pump();

      expect(_plays(audio).map((e) => e.ref).toList(), ['audio/phonemes/IH.mp3']);
      expect(_plays(audio).single.channel, AudioChannel.help);
      expect(tracker.calls, isNot(contains('tap')),
          reason: 'a chip tap never advances the word');
      audio.completePlayback(_plays(audio).single.handle);
      await tester.pump();
      expect(_plays(audio), hasLength(1), reason: 'one clip, no sequence');
    });

    testWidgets('POSITIVE: chips of an on-demand panel are tappable too',
        (tester) async {
      final tracker = _FakeTrackerHandle();
      final audio = FakeAudioService();
      final words = [_word('the'), _shipWord()];
      await tester.pumpWidget(_buildScreen(
        story: _story(words),
        level: _level(),
        tracker: tracker,
        audioService: audio,
      ));
      await tester.pump();

      await tester.longPress(find.byKey(const ValueKey('word-text-1')));
      await tester.pump();
      expect(find.byKey(const ValueKey('grapheme-chip-tap-1-2')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('grapheme-chip-tap-1-2')));
      await tester.pump();
      await tester.pump();
      // SH (the pass's first clip) + P (the tapped chip).
      expect(_plays(audio).map((e) => e.ref).toList(),
          ['audio/phonemes/SH.mp3', 'audio/phonemes/P.mp3']);

      // Drain the pass cleanly.
      await _drainUntilResumed(tester, audio, tracker);
    });

    testWidgets('NEGATIVE: a silent-letter chip is a gentle no-op -- no '
        'audio, no word advance, no crash', (tester) async {
      final tracker = _FakeTrackerHandle();
      final audio = FakeAudioService();
      final words = [_cakeWord(), _word('the')];
      await tester.pumpWidget(_buildScreen(
        story: _story(words),
        level: _level(),
        tracker: tracker,
        audioService: audio,
        helpState: const HelpState(
          currentHelpTier: HelpLevel.soundOut,
          highlightedGraphemeIndex: 0,
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      tracker.calls.clear();

      await tester.tap(find.byKey(const ValueKey('grapheme-chip-tap-0-3')));
      await tester.pump();
      await tester.pump();

      expect(_plays(audio), isEmpty);
      expect(tracker.calls, isNot(contains('tap')));
      expect(tester.takeException(), isNull);
    });
  });
}

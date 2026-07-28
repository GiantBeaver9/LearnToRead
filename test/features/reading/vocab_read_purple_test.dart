/// NEW 2026-07-28: vocab-read purple ruling (PRD §8 Unit 1 "Vocabulary word
/// (read/helped): purple"; docs/design/mockup-spec.md §3).
///
/// A word WITH a vocabCardId (on a vocabEnabled level) that reaches the done
/// state renders `DesignTokens.wordVocabReadPurple`, not green; a helped
/// vocab word renders IDENTICALLY (the invisible-help rule is per word
/// kind); ordinary words keep `DesignTokens.wordReadGreen`; the resolve
/// sweep animates to purple over `DesignTokens.greenSweepDuration` exactly
/// as it does to green; and a done (purple) vocab word keeps its vocab tap
/// target.
///
/// Harness mirrors test/features/reading/word_states_render_test.dart
/// (ReadingController + WordTextView + a local ReadingTrackerHandle double,
/// redefined per file per this repo's convention).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/features/analytics/analytics_client.dart';
import 'package:learn_to_read/features/analytics/event_queue.dart';
import 'package:learn_to_read/features/analytics/transport.dart';
import 'package:learn_to_read/features/listening/contracts/help_state.dart';
import 'package:learn_to_read/features/listening/contracts/tracker_events.dart';
import 'package:learn_to_read/features/reading/reading_controller.dart';
import 'package:learn_to_read/features/reading/word_state.dart';
import 'package:learn_to_read/features/reading/word_text_view.dart';

// ---------------------------------------------------------------------------
// Fixtures (mirroring word_states_render_test.dart).
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
      format: LevelFormat.multiSentence,
      vocabEnabled: vocabEnabled,
    );

Story _storyOfWords(List<WordToken> words) => Story(
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

  @override
  Stream<TrackerEvent> get eventsStream => _controller.stream;

  @override
  bool get isListening => _listening;

  @override
  void pause() => _listening = false;

  @override
  void resume() {
    if (stopped) return;
    _listening = true;
  }

  @override
  void stop() {
    _listening = false;
    stopped = true;
  }

  @override
  void tapCurrentWord() {}

  void emit(TrackerEvent event) => _controller.add(event);
}

Widget _harness({
  required List<WordToken> words,
  required ReadingController controller,
  void Function(int index)? onVocabWordTap,
}) {
  return MaterialApp(
    home: Scaffold(
      body: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final snapshot = controller.snapshot;
          final pageWords = snapshot.isStoryComplete
              ? snapshot.pages[snapshot.pages.length - 1]
              : snapshot.currentPageWords;
          return WordTextView(
            words: words,
            wordStates: pageWords,
            helpState: const HelpState(
              currentHelpTier: HelpLevel.none,
              highlightedGraphemeIndex: -1,
            ),
            textSize: DesignTokens.sentenceTextSizePhone,
            onCurrentWordTap: (_) {},
            onVocabWordTap: onVocabWordTap ?? (_) {},
          );
        },
      ),
    ),
  );
}

Color? _colorOf(WidgetTester tester, int index) {
  final text = tester.widget<Text>(find.byKey(ValueKey('word-text-$index')));
  return text.style?.color;
}

AnalyticsClient _noOpAnalyticsClient() => AnalyticsClient(
      enabled: false,
      queue: EventQueue(
        transport: const NullAnalyticsTransport(),
        clock: () => DateTime.utc(2026, 1, 1),
        storageDirectory: Directory.systemTemp,
      ),
    );

void main() {
  late _FakeTrackerHandle tracker;
  late ReadingController controller;

  ReadingController buildController({
    required List<WordToken> words,
    Level? level,
  }) {
    tracker = _FakeTrackerHandle();
    return ReadingController(
      story: _storyOfWords(words),
      level: level ?? _level(),
      tracker: tracker,
      analytics: _noOpAnalyticsClient(),
      installId: 'a1b2c3d4-1234-4abc-8def-0123456789ab',
      profileOrdinal: 1,
      levelOrdinal: 1,
    )..beginListening();
  }

  group('POSITIVE: a read vocab word renders vocab-read purple', () {
    testWidgets('WordAccepted on a vocab word settles on wordVocabReadPurple, '
        'never green; the ordinary word beside it settles green', (tester) async {
      final words = [
        _word('the'),
        _word('elephant', vocabCardId: 'vocab.elephant'),
      ];
      controller = buildController(words: words, level: _level(vocabEnabled: true));
      await tester.pumpWidget(_harness(words: words, controller: controller));

      tracker.emit(const WordAccepted(index: 0));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);
      tracker.emit(const WordAccepted(index: 1));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);

      expect(_colorOf(tester, 0), DesignTokens.wordReadGreen,
          reason: 'ordinary words keep the read green');
      expect(_colorOf(tester, 1), DesignTokens.wordVocabReadPurple,
          reason: 'a read vocab word turns purple, not green');
      expect(_colorOf(tester, 1), isNot(DesignTokens.wordReadGreen));
      expect(_colorOf(tester, 1), isNot(DesignTokens.wordVocabBlue));
    });
  });

  group('POSITIVE: helped vocab word is pixel-identical to a read vocab word', () {
    testWidgets('WordHelped on a vocab word settles on the exact same purple '
        'as WordAccepted, and no helped-badge widget exists', (tester) async {
      final words = [
        _word('otter', vocabCardId: 'vocab.otter'),
        _word('newt', vocabCardId: 'vocab.newt'),
      ];
      controller = buildController(words: words, level: _level(vocabEnabled: true));
      await tester.pumpWidget(_harness(words: words, controller: controller));

      tracker.emit(const WordHelped(index: 0, tier: HelpLevel.soundOut));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);
      tracker.emit(const WordAccepted(index: 1));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);

      expect(_colorOf(tester, 0), _colorOf(tester, 1),
          reason: 'helped-vocab == read-vocab (invisible-help rule per word kind)');
      expect(_colorOf(tester, 0), DesignTokens.wordVocabReadPurple);
      expect(controller.snapshot.currentPageWords[0].resolution, WordResolution.helped);
      expect(controller.snapshot.currentPageWords[1].resolution, WordResolution.accepted);
      expect(find.byKey(const ValueKey('helped-badge-0')), findsNothing);
    });
  });

  group('POSITIVE: the resolve sweep animates to purple, not an instant recolor', () {
    testWidgets('immediately after WordAccepted a vocab word is not yet the '
        'exact purple; after the full sweep duration it is', (tester) async {
      final words = [
        _word('elephant', vocabCardId: 'vocab.elephant'),
        _word('runs'),
      ];
      controller = buildController(words: words, level: _level(vocabEnabled: true));
      await tester.pumpWidget(_harness(words: words, controller: controller));

      tracker.emit(const WordAccepted(index: 0));
      await tester.pump(); // apply event, start animation

      expect(_colorOf(tester, 0), isNot(DesignTokens.wordVocabReadPurple),
          reason: 'the sweep is animated, never an instant recolor');

      await tester.pump(DesignTokens.greenSweepDuration);
      expect(_colorOf(tester, 0), DesignTokens.wordVocabReadPurple);
    });
  });

  group('POSITIVE: the vocab tap affordance survives turning purple', () {
    testWidgets('a done (purple) vocab word still exposes its vocab tap '
        'target and taps still fire onVocabWordTap', (tester) async {
      final tapped = <int>[];
      final words = [
        _word('otter', vocabCardId: 'vocab.otter'),
        _word('sat'),
      ];
      controller = buildController(words: words, level: _level(vocabEnabled: true));
      await tester.pumpWidget(_harness(
        words: words,
        controller: controller,
        onVocabWordTap: tapped.add,
      ));

      tracker.emit(const WordAccepted(index: 0));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);
      expect(_colorOf(tester, 0), DesignTokens.wordVocabReadPurple);

      expect(find.byKey(const ValueKey('word-tap-0')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('word-tap-0')));
      await tester.pump();
      expect(tapped, [0]);
    });
  });

  group('NEGATIVE: purple never leaks to non-vocab paths', () {
    testWidgets('on a vocabEnabled level, a word WITHOUT a vocabCardId still '
        'settles green', (tester) async {
      final words = [_word('the'), _word('cat')];
      controller = buildController(words: words, level: _level(vocabEnabled: true));
      await tester.pumpWidget(_harness(words: words, controller: controller));

      tracker.emit(const WordAccepted(index: 0));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);

      expect(_colorOf(tester, 0), DesignTokens.wordReadGreen);
      expect(_colorOf(tester, 0), isNot(DesignTokens.wordVocabReadPurple));
    });

    testWidgets('vocabEnabled == false: a word with a vocabCardId behaves as '
        'ordinary — unread ink, then read green', (tester) async {
      final words = [
        _word('elephant', vocabCardId: 'vocab.elephant'),
        _word('runs'),
      ];
      controller = buildController(words: words, level: _level(vocabEnabled: false));
      await tester.pumpWidget(_harness(words: words, controller: controller));

      expect(_colorOf(tester, 1), DesignTokens.wordUnreadInk);

      tracker.emit(const WordAccepted(index: 0));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);

      expect(_colorOf(tester, 0), DesignTokens.wordReadGreen);
      expect(_colorOf(tester, 0), isNot(DesignTokens.wordVocabReadPurple));
    });
  });
}

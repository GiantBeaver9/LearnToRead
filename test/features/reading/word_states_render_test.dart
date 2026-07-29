/// Widget tests for word-state rendering (PRD §8 Unit 5, ticket
/// reading-screen accept entries 1, 2, 4).
///
/// Exercises `ReadingController` (lib/features/reading/reading_controller.dart)
/// wired to `WordTextView` (lib/features/reading/word_text_view.dart) through
/// a small harness, fed scripted `TrackerEvent`s via a local
/// `ReadingTrackerHandle` double. Neither lib file exists yet -- this suite
/// fails to compile/analyze until they do (the expected red state).
///
/// Pinned rendering contract this suite locks in (transcribed from PRD §8
/// Unit 1/5 + word_state.dart's `renderColor` doc):
///  - unread, non-vocab word: `DesignTokens.wordUnreadInk`.
///  - unread, vocab-tappable word: `DesignTokens.wordVocabBlue`.
///  - current word: `DesignTokens.wordCurrentInk` (== wordUnreadInk) plus a
///    dedicated underline/glow marker widget keyed
///    `ValueKey('word-current-marker-$i')`, present ONLY for the current
///    word.
///  - done word (any resolution -- accepted, near-miss, helped): animates
///    from its prior color to `DesignTokens.wordReadGreen` over
///    `DesignTokens.greenSweepDuration`, via `WordTextView`'s
///    `ValueKey('word-text-$i')` `Text` widget's `style.color`. Not an
///    instant recolor: immediately after the resolving event, the color is
///    NOT yet the exact green; after pumping the full sweep duration, it is
///    exactly `DesignTokens.wordReadGreen`.
///  - helped and accepted words are pixel-identical once done: same color,
///    no extra "helped" marker widget (`ValueKey('helped-badge-$i')` must
///    never exist) -- only `ReadingController.snapshot`'s `WordResolution`
///    (an invisible, non-rendered field) distinguishes them.
///  - lookahead back-fill (`WordAccepted(index: n)` while current index is
///    `< n`): every word from the old current index up to (not including)
///    `n` silently resolves `accepted`, then `n` resolves per the event.
///  - Tier-1 sound-out grapheme highlight: when `helpState.currentHelpTier
///    == HelpLevel.soundOut` and the current word's `highlightedGraphemeIndex
///    >= 0`, the current word renders as one `Text` span per
///    `WordToken.graphemePhonemeMap` entry, keyed
///    `ValueKey('grapheme-$wordIndex-$graphemeIndex')`; a digraph ("sh") is
///    one entry, hence one span, never split letter-by-letter.
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
// Fixtures.
// ---------------------------------------------------------------------------

WordToken _word(String text, {String? vocabCardId}) => WordToken(
      text: text,
      graphemePhonemeMap: [(graphemes: text, phonemeId: 'AH')],
      pronunciationAudioRef: 'audio/words/$text.mp3',
      vocabCardId: vocabCardId,
    );

WordToken _shipWord() => WordToken(
      text: 'ship',
      graphemePhonemeMap: const [
        (graphemes: 'sh', phonemeId: 'SH'),
        (graphemes: 'i', phonemeId: 'IH'),
        (graphemes: 'p', phonemeId: 'P'),
      ],
      pronunciationAudioRef: 'audio/words/ship.mp3',
    );

Level _level({bool vocabEnabled = false}) => Level(
      id: 'level.1',
      ordinal: 1,
      newSkills: const [],
      format: LevelFormat.multiSentence, // narrationEnabled defaults false
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

/// Local double for `ReadingTrackerHandle` (defined in reading_controller.dart):
/// gives the test explicit control over event-emission timing rather than
/// FakeReadingTracker's fire-and-forget script, so exact word-state render
/// sequences can be asserted frame-by-frame. See narration_test.dart /
/// reading_screen_test.dart for the same double, redefined locally per file
/// per this repo's established convention (see
/// test/features/map/layout_classes_test.dart's `_pumpAt`).
class _FakeTrackerHandle implements ReadingTrackerHandle {
  final StreamController<TrackerEvent> _controller =
      StreamController<TrackerEvent>.broadcast();
  bool _listening = false;
  bool stopped = false;
  final List<String> calls = [];
  void Function()? onTap;

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
    onTap?.call();
  }

  void emit(TrackerEvent event) => _controller.add(event);
}

class _Recorder {
  int calls = 0;
  void call() => calls++;
}

Widget _harness({
  required List<WordToken> words,
  required ReadingController controller,
  HelpState helpState = const HelpState(currentHelpTier: HelpLevel.none, highlightedGraphemeIndex: -1),
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
            helpState: helpState,
            textSize: DesignTokens.sentenceTextSizePhone,
            onCurrentWordTap: (_) => controller.tapCurrentWord(),
            onVocabWordTap: (_) {},
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

void main() {
  late _FakeTrackerHandle tracker;
  late ReadingController controller;

  ReadingController buildController({
    required List<WordToken> words,
    Level? level,
    VoidCallback? onStoryComplete,
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
      onStoryComplete: onStoryComplete,
    )..beginListening();
  }

  group('POSITIVE: initial render', () {
    testWidgets('word 0 is current, ink-colored, with the current marker; '
        'later words are unread ink with no marker', (tester) async {
      final words = [_word('the'), _word('cat'), _word('sat')];
      controller = buildController(words: words);
      await tester.pumpWidget(_harness(words: words, controller: controller));

      expect(_colorOf(tester, 0), DesignTokens.wordCurrentInk);
      expect(find.byKey(const ValueKey('word-current-marker-0')), findsOneWidget);

      expect(_colorOf(tester, 1), DesignTokens.wordUnreadInk);
      expect(find.byKey(const ValueKey('word-current-marker-1')), findsNothing);
      expect(_colorOf(tester, 2), DesignTokens.wordUnreadInk);
    });

    testWidgets('vocab-enabled level: an unread vocab word renders blue, '
        'not ink', (tester) async {
      final words = [_word('the'), _word('elephant', vocabCardId: 'vocab.elephant')];
      controller = buildController(words: words, level: _level(vocabEnabled: true));
      await tester.pumpWidget(_harness(words: words, controller: controller));

      expect(_colorOf(tester, 1), DesignTokens.wordVocabBlue);
    });
  });

  group('POSITIVE: acceptance and the green sweep', () {
    testWidgets('WordAccepted animates to green over greenSweepDuration, '
        'not an instant recolor, and advances the current marker', (tester) async {
      final words = [_word('the'), _word('cat')];
      controller = buildController(words: words);
      await tester.pumpWidget(_harness(words: words, controller: controller));

      tracker.emit(const WordAccepted(index: 0));
      await tester.pump(); // apply event, start animation

      expect(_colorOf(tester, 0), isNot(DesignTokens.wordReadGreen));

      await tester.pump(DesignTokens.greenSweepDuration);
      expect(_colorOf(tester, 0), DesignTokens.wordReadGreen);

      // Word 1 became current after word 0 resolved.
      expect(find.byKey(const ValueKey('word-current-marker-1')), findsOneWidget);
      expect(find.byKey(const ValueKey('word-current-marker-0')), findsNothing);
    });
  });

  group('POSITIVE: lookahead back-fill', () {
    testWidgets('WordAccepted(index: 2) while current is 0 silently resolves '
        '0 and 1 as accepted, then resolves 2 per the event', (tester) async {
      final words = [_word('a'), _word('big'), _word('cat')];
      controller = buildController(words: words);
      await tester.pumpWidget(_harness(words: words, controller: controller));

      tracker.emit(const WordAccepted(index: 2));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);

      expect(_colorOf(tester, 0), DesignTokens.wordReadGreen);
      expect(_colorOf(tester, 1), DesignTokens.wordReadGreen);
      expect(_colorOf(tester, 2), DesignTokens.wordReadGreen);
      expect(controller.snapshot.currentPageWords[0].resolution, WordResolution.accepted);
      expect(controller.snapshot.currentPageWords[1].resolution, WordResolution.accepted);
      expect(controller.snapshot.currentPageWords[2].resolution, WordResolution.accepted);
      // AMENDED 2026-07-29: curl-closes-every-page ruling (PRD §8 Unit 5):
      // the resolving event holds the finished page; the child's turn is
      // what completes the story.
      expect(controller.snapshot.isPageComplete, isTrue);
      expect(controller.snapshot.isStoryComplete, isFalse);
      controller.turnPage();
      expect(controller.snapshot.isStoryComplete, isTrue);
    });

    testWidgets('back-fill grade is carried by the targeted index: a '
        'near-miss lookahead marks only the target word near-miss', (tester) async {
      final words = [_word('a'), _word('big'), _word('cat'), _word('nap')];
      controller = buildController(words: words);
      await tester.pumpWidget(_harness(words: words, controller: controller));

      tracker.emit(const WordAcceptedNearMiss(index: 2));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);

      expect(controller.snapshot.currentPageWords[0].resolution, WordResolution.accepted);
      expect(controller.snapshot.currentPageWords[1].resolution, WordResolution.accepted);
      expect(controller.snapshot.currentPageWords[2].resolution, WordResolution.acceptedNearMiss);
      // All three render identically green regardless of grade.
      expect(_colorOf(tester, 0), DesignTokens.wordReadGreen);
      expect(_colorOf(tester, 1), DesignTokens.wordReadGreen);
      expect(_colorOf(tester, 2), DesignTokens.wordReadGreen);
    });
  });

  group('POSITIVE: helped renders identically to accepted', () {
    testWidgets('a helped word and an accepted word are pixel-identical '
        'once done, but their resolution differs and no helped-badge widget '
        'exists', (tester) async {
      final words = [_word('the'), _word('dog')];
      controller = buildController(words: words);
      await tester.pumpWidget(_harness(words: words, controller: controller));

      tracker.emit(const WordHelped(index: 0, tier: HelpLevel.soundOut));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);
      tracker.emit(const WordAccepted(index: 1));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);

      final helpedText = tester.widget<Text>(find.byKey(const ValueKey('word-text-0')));
      final acceptedText = tester.widget<Text>(find.byKey(const ValueKey('word-text-1')));
      expect(helpedText.style?.color, acceptedText.style?.color);
      expect(helpedText.style?.color, DesignTokens.wordReadGreen);

      expect(controller.snapshot.currentPageWords[0].resolution, WordResolution.helped);
      expect(controller.snapshot.currentPageWords[0].helpTier, HelpLevel.soundOut);
      expect(controller.snapshot.currentPageWords[1].resolution, WordResolution.accepted);

      expect(find.byKey(const ValueKey('helped-badge-0')), findsNothing);
      expect(find.byKey(const ValueKey('helped-badge-1')), findsNothing);
    });
  });

  group('NEGATIVE: events that do not resolve anything render nothing new', () {
    testWidgets('an out-of-range WordAccepted index is a no-op: nothing '
        'turns green, no crash', (tester) async {
      final words = [_word('the'), _word('cat')];
      controller = buildController(words: words);
      await tester.pumpWidget(_harness(words: words, controller: controller));

      tracker.emit(const WordAccepted(index: 99));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);

      expect(tester.takeException(), isNull);
      expect(_colorOf(tester, 0), DesignTokens.wordCurrentInk);
      expect(find.byKey(const ValueKey('word-current-marker-0')), findsOneWidget);
    });

    testWidgets('a StruggleDetected/Silence event never turns a word green '
        'or produces any error/negative marker widget', (tester) async {
      final words = [_word('the'), _word('cat')];
      controller = buildController(words: words);
      await tester.pumpWidget(_harness(words: words, controller: controller));

      tracker
        ..emit(const StruggleDetected(index: 0))
        ..emit(const Silence(duration: Duration(seconds: 4)));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(_colorOf(tester, 0), DesignTokens.wordCurrentInk);
      expect(find.byKey(const ValueKey('word-current-marker-0')), findsOneWidget);
    });
  });

  group('EDGE: last word of the story', () {
    // AMENDED 2026-07-29: curl-closes-every-page ruling (PRD §8 Unit 5):
    // resolving the last word now HOLDS (green, no current marker, story
    // not yet complete); the turn completes the story and starts the beat.
    testWidgets('resolving the last word turns it green and holds; the turn '
        'completes the story, and there is no current-word marker left '
        'anywhere', (tester) async {
      final words = [_word('go')];
      final beat = _Recorder();
      controller = buildController(words: words, onStoryComplete: beat.call);
      await tester.pumpWidget(_harness(words: words, controller: controller));

      tracker.emit(const WordAccepted(index: 0));
      await tester.pump();
      await tester.pump(DesignTokens.greenSweepDuration);

      expect(_colorOf(tester, 0), DesignTokens.wordReadGreen);
      expect(find.byKey(const ValueKey('word-current-marker-0')), findsNothing);
      expect(controller.snapshot.isPageComplete, isTrue);
      expect(controller.snapshot.isStoryComplete, isFalse);
      expect(beat.calls, 0, reason: 'no handoff without the child\'s turn');

      controller.turnPage();
      await tester.pump();
      expect(controller.snapshot.isStoryComplete, isTrue);
      expect(find.byKey(const ValueKey('word-current-marker-0')), findsNothing);
      // The celebration beat has not elapsed yet.
      expect(beat.calls, 0);
      await tester.pump(kCelebrationBeat);
      expect(beat.calls, 1);
    });
  });

  group('POSITIVE: Tier-1 sound-out grapheme highlight', () {
    testWidgets('digraph "sh" highlights as one span, never split s-h', (tester) async {
      final words = [_shipWord()];
      controller = buildController(words: words);
      await tester.pumpWidget(_harness(
        words: words,
        controller: controller,
        helpState: const HelpState(currentHelpTier: HelpLevel.soundOut, highlightedGraphemeIndex: 0),
      ));

      final shSpan = tester.widget<Text>(find.byKey(const ValueKey('grapheme-0-0')));
      expect(shSpan.data, 'sh');
      // Not split letter-by-letter: no separate "s" or "h" grapheme span.
      expect(find.text('s'), findsNothing);
      expect(find.text('h'), findsNothing);

      // The highlighted cluster is visually distinguished from the others.
      final iSpan = tester.widget<Text>(find.byKey(const ValueKey('grapheme-0-1')));
      expect(iSpan.data, 'i');
    });

    testWidgets('a negative highlightedGraphemeIndex renders the word plainly '
        '(no grapheme spans)', (tester) async {
      final words = [_shipWord()];
      controller = buildController(words: words);
      await tester.pumpWidget(_harness(
        words: words,
        controller: controller,
        helpState: const HelpState(currentHelpTier: HelpLevel.none, highlightedGraphemeIndex: -1),
      ));

      expect(find.byKey(const ValueKey('grapheme-0-0')), findsNothing);
      expect(find.byKey(const ValueKey('word-text-0')), findsOneWidget);
    });
  });
}

// ---------------------------------------------------------------------------
// A minimal AnalyticsClient that is disabled (a true no-op): these tests are
// about rendering, not analytics, so `enabled: false` guarantees zero I/O
// and zero throws while still giving ReadingController a real
// `AnalyticsClient` to call, matching lib/features/analytics/analytics_client.dart's
// documented kill-switch contract ("every method is a no-op" when disabled).
// `queue` is never touched when disabled, so a placeholder built from a
// NullAnalyticsTransport over a throwaway directory is safe here without any
// setUp/tearDown machinery.
AnalyticsClient _noOpAnalyticsClient() => AnalyticsClient(
      enabled: false,
      queue: EventQueue(
        transport: const NullAnalyticsTransport(),
        clock: () => DateTime.utc(2026, 1, 1),
        storageDirectory: Directory.systemTemp,
      ),
    );

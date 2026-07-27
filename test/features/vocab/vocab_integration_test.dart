/// Integration tests wiring the REAL vocab card (lib/features/vocab/
/// vocab_card.dart, vocab_card_opener.dart) into the REAL `ReadingScreen`
/// (lib/features/reading/reading_screen.dart, merged) end to end (PRD §8
/// Unit 7 accept "Widget test: tap blue word → card opens, audio autoplay
/// invoked, listening paused; close → listening resumed, cursor unchanged";
/// ticket vocab-cards accept entries 4 and 5).
///
/// test/features/reading/reading_screen_test.dart already pins the "pause /
/// call vocabCardOpener / resume, cursor unchanged" contract against a bare
/// `_VocabOpenerRig` double (a `Completer`-backed fake) -- that is the
/// reading-screen ticket's own frozen coverage and is NOT re-derived here.
/// This suite is the one place the REAL `vocab_card_opener.dart` seam is
/// exercised: does opening actually show `VocabCardPopover`, does it
/// actually autoplay the definition audio, does it actually log
/// `vocab_card_opened` with a schema-valid payload, and does closing it for
/// real actually resume listening at the identical cursor. Neither
/// lib/features/vocab/vocab_card.dart nor vocab_card_opener.dart exists
/// yet: this suite fails to compile/analyze until both do -- the expected
/// red state.
///
/// Pinned contract this suite locks in for `vocab_card_opener.dart` (a
/// builder decision this ticket owns -- see the ticket note "Implements the
/// VocabCardOpener interface that reading-screen injects (defined concrete
/// here)"):
///
///  - `VocabCardHost` is a `StatefulWidget` that wraps `child` (typically
///    `ReadingScreen`) in a `Stack`, overlaying `VocabCardPopover` when a
///    card is open. It is constructed with `cardsById` (vocabCardId ->
///    `VocabCard`), `pronunciationAudioRefsById` (vocabCardId -> the
///    originating `WordToken.pronunciationAudioRef` -- plumbed in
///    separately from `cardsById` because `VocabCard` itself carries no
///    pronunciation ref, only `definitionAudioRef`), `audioService`,
///    `analytics`, and the §5 analytics base fields (`installId`,
///    `profileOrdinal`, `levelOrdinal`, optional `storyId`).
///  - `VocabCardHostState.open(String vocabCardId)` is the function bound
///    (via a `GlobalKey<VocabCardHostState>`) to `ReadingScreen.vocabCardOpener`
///    (`Future<void> Function(String vocabCardId)`, lib/features/reading/
///    reading_screen.dart, frozen). It: looks up the card, records
///    `vocab_card_opened` (§5: `storyId` optional, no event-specific
///    fields), shows the popover, and returns a `Future` that completes
///    only when the popover closes (tap-outside or the close affordance) --
///    never when its audio finishes.
///  - An unknown `vocabCardId` (not in `cardsById`) is a content-integrity
///    no-op: the returned future completes immediately, nothing is shown,
///    nothing is logged -- it must never throw or hang, since a corrupt
///    pack must never strand a paused child.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart' hide Page;
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/design/fake_rive_stage.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/features/analytics/analytics_client.dart';
import 'package:learn_to_read/features/analytics/event_queue.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/analytics/events.dart';
import 'package:learn_to_read/features/analytics/transport.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/listening/contracts/tracker_events.dart';
import 'package:learn_to_read/features/reading/reading_controller.dart';
import 'package:learn_to_read/features/reading/reading_screen.dart';
import 'package:learn_to_read/features/vocab/vocab_card.dart';
import 'package:learn_to_read/features/vocab/vocab_card_opener.dart';

// ---------------------------------------------------------------------------
// Fixtures (mirrors test/features/reading/reading_screen_test.dart's
// established local-double convention).
// ---------------------------------------------------------------------------

WordToken _word(String text, {String? vocabCardId}) => WordToken(
      text: text,
      graphemePhonemeMap: [(graphemes: text, phonemeId: 'AH')],
      pronunciationAudioRef: 'audio/words/$text.mp3',
      vocabCardId: vocabCardId,
    );

Level _level({bool vocabEnabled = true}) => Level(
      id: 'level.1',
      ordinal: 1,
      newSkills: const [],
      format: LevelFormat.multiSentence, // narrationEnabled defaults false
      vocabEnabled: vocabEnabled,
    );

Story _story(List<WordToken> words, {String id = 'story.vocab-test'}) => Story(
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

VocabCard _elephantCard() => VocabCard(
      id: 'vocab.elephant',
      word: 'elephant',
      definitionText: 'A huge animal with a long trunk.',
      definitionAudioRef: 'audio/vocab/elephant_def.mp3',
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
}

/// Wires a real `AnalyticsClient` to a temp-dir `EventQueue` and a
/// recording `AnalyticsTransport`, mirroring
/// test/features/reading/reading_screen_test.dart's `_AnalyticsRig`.
class _AnalyticsRig {
  late Directory tempDir;
  late _RecordingTransport transport;
  late EventQueue queue;
  late AnalyticsClient client;

  void setUp() {
    tempDir = Directory.systemTemp.createTempSync('vocab_integration_test_');
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

bool _isListeningIndicatorActive(WidgetTester tester) =>
    tester.any(find.byKey(const ValueKey('listening-indicator-active')));

const _installId = 'a1b2c3d4-1234-4abc-8def-0123456789ab';
final _popoverKey = find.byKey(const ValueKey('vocab-card-popover'));
final _closeKey = find.byKey(const ValueKey('vocab-card-close-button'));
final _barrierKey = find.byKey(const ValueKey('vocab-card-barrier'));
final _replayKey = find.byKey(const ValueKey('vocab-card-replay-button'));
final _wordTapKey = find.byKey(const ValueKey('vocab-card-word-tap'));

/// Builds the widget tree the whole suite pumps: `VocabCardHost` (the REAL
/// opener seam) wrapping the REAL `ReadingScreen`, bound together through a
/// `GlobalKey<VocabCardHostState>` closure exactly the way the ticket note
/// says this ticket "defines concrete" -- reading-screen only ever sees
/// `ReadingScreen.vocabCardOpener`'s `Future<void> Function(String)` shape.
Widget _buildTree({
  required GlobalKey<VocabCardHostState> hostKey,
  required Story story,
  required Level level,
  required _FakeTrackerHandle tracker,
  required FakeAudioService audio,
  required AnalyticsClient analytics,
  Map<String, VocabCard> cardsById = const <String, VocabCard>{},
  Map<String, String> pronunciationAudioRefsById = const <String, String>{},
}) {
  return MaterialApp(
    home: VocabCardHost(
      key: hostKey,
      cardsById: cardsById,
      pronunciationAudioRefsById: pronunciationAudioRefsById,
      audioService: audio,
      analytics: analytics,
      installId: _installId,
      profileOrdinal: 1,
      levelOrdinal: 1,
      storyId: story.id,
      child: ReadingScreen(
        story: story,
        level: level,
        tracker: tracker,
        audioService: audio,
        analytics: analytics,
        installId: _installId,
        profileOrdinal: 1,
        levelOrdinal: 1,
        stage: FakeStoryStage(),
        vocabCardOpener: (id) => hostKey.currentState!.open(id),
      ),
    ),
  );
}

void main() {
  group('Vocab tap → real card opens, autoplays, pauses; close → resumes, '
      'cursor identical (POSITIVE, integration)', () {
    late _AnalyticsRig rig;
    late GlobalKey<VocabCardHostState> hostKey;
    late _FakeTrackerHandle tracker;
    late FakeAudioService audio;
    late Story story;

    setUp(() {
      rig = _AnalyticsRig()..setUp();
      hostKey = GlobalKey<VocabCardHostState>();
      tracker = _FakeTrackerHandle();
      audio = FakeAudioService();
      story = _story([_word('the'), _word('elephant', vocabCardId: 'vocab.elephant'), _word('walked')]);
    });

    tearDown(() => rig.tearDown());

    Future<void> pumpReady(WidgetTester tester) async {
      await tester.pumpWidget(_buildTree(
        hostKey: hostKey,
        story: story,
        level: _level(),
        tracker: tracker,
        audio: audio,
        analytics: rig.client,
        cardsById: {'vocab.elephant': _elephantCard()},
        pronunciationAudioRefsById: {'vocab.elephant': 'audio/words/elephant.mp3'},
      ));
      await tester.pump();
      expect(tracker.isListening, isTrue);
      // Orchestrator test-fix (see reading_screen_test.dart / narration_test.dart's
      // established fix): reaching isListening==true necessarily logs
      // 'resume' in this fake, so clear it before exact-log assertions.
      tracker.calls.clear();
    }

    testWidgets('tapping the blue word mid-listening opens the real card, '
        'autoplays its definition, and pauses listening', (tester) async {
      await pumpReady(tester);

      await tester.tap(find.byKey(const ValueKey('word-tap-1')));
      await tester.pump();

      expect(_popoverKey, findsOneWidget);
      expect(tracker.calls, contains('pause'));
      expect(tracker.calls.first, 'pause', reason: 'pause happens before the opener awaits');
      expect(tracker.isListening, isFalse);
      expect(_isListeningIndicatorActive(tester), isFalse);

      final plays = audio.callLog.whereType<PlayLogEntry>().toList();
      final definitionPlays = plays.where((e) => e.ref == 'audio/vocab/elephant_def.mp3');
      expect(definitionPlays, hasLength(1));
      expect(definitionPlays.single.channel, kVocabCardAudioChannel);

      // Cursor is still word 0, current, exactly as before the tap.
      expect(find.byKey(const ValueKey('word-current-marker-0')), findsOneWidget);
    });

    testWidgets('closing via the close affordance resumes listening at the '
        'identical cursor and removes the card', (tester) async {
      await pumpReady(tester);
      await tester.tap(find.byKey(const ValueKey('word-tap-1')));
      await tester.pump();

      await tester.tap(_closeKey);
      await tester.pump();
      await tester.pump();

      expect(_popoverKey, findsNothing);
      expect(tracker.calls, ['pause', 'resume']);
      expect(tracker.isListening, isTrue);
      expect(_isListeningIndicatorActive(tester), isTrue);
      expect(find.byKey(const ValueKey('word-current-marker-0')), findsOneWidget);
    });

    testWidgets('POSITIVE: closing via tap-outside (the barrier) resumes '
        'listening at the identical cursor exactly like the close '
        'affordance does', (tester) async {
      await pumpReady(tester);
      await tester.tap(find.byKey(const ValueKey('word-tap-1')));
      await tester.pump();

      // As in vocab_card_test.dart: the barrier spans the full screen and
      // the card sits centered on top of it, so tapping the barrier
      // finder's geometric center would actually hit the card. Tap a
      // corner instead.
      expect(_barrierKey, findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      await tester.pump();

      expect(_popoverKey, findsNothing);
      expect(tracker.calls, ['pause', 'resume']);
      expect(tracker.isListening, isTrue);
      expect(find.byKey(const ValueKey('word-current-marker-0')), findsOneWidget);
    });

    testWidgets('tapping the word inside the open card plays its '
        "pronunciation, distinct from the definition's own ref", (tester) async {
      await pumpReady(tester);
      await tester.tap(find.byKey(const ValueKey('word-tap-1')));
      await tester.pump();

      await tester.tap(_wordTapKey);
      await tester.pump();

      final plays = audio.callLog.whereType<PlayLogEntry>().toList();
      expect(plays.last.ref, 'audio/words/elephant.mp3');
      expect(plays.last.channel, kVocabCardAudioChannel);
    });

    testWidgets('the replay button repeats the definition audio', (tester) async {
      await pumpReady(tester);
      await tester.tap(find.byKey(const ValueKey('word-tap-1')));
      await tester.pump();

      await tester.tap(_replayKey);
      await tester.pump();

      final definitionPlays = audio.callLog
          .whereType<PlayLogEntry>()
          .where((e) => e.ref == 'audio/vocab/elephant_def.mp3');
      expect(definitionPlays, hasLength(2)); // autoplay + replay
    });

    testWidgets('vocab_card_opened is logged exactly once, with a '
        'schema-valid §5 payload carrying this storyId', (tester) async {
      await pumpReady(tester);
      await tester.tap(find.byKey(const ValueKey('word-tap-1')));
      await tester.pump();

      late List<Map<String, Object?>> events;
      await tester.runAsync(() async {
        events = await rig.pendingEventsAfterSettling();
      });

      final opened = events.where((e) => e['event'] == 'vocab_card_opened').toList();
      expect(opened, hasLength(1));
      expect(() => validateEventPayload(opened.single), returnsNormally);
      expect(opened.single['storyId'], story.id);
      expect(opened.single['installId'], _installId);
      expect(opened.single['profileOrdinal'], 1);
      expect(opened.single['levelOrdinal'], 1);
    });

    testWidgets('NEGATIVE: no vocab_card_opened is logged before any tap', (tester) async {
      await pumpReady(tester);

      late List<Map<String, Object?>> events;
      await tester.runAsync(() async {
        events = await rig.pendingEventsAfterSettling();
      });

      expect(events.where((e) => e['event'] == 'vocab_card_opened'), isEmpty);
    });

    testWidgets('EDGE: reopening the same card a second time logs '
        'vocab_card_opened twice, once per open (not once ever)', (tester) async {
      await pumpReady(tester);

      await tester.tap(find.byKey(const ValueKey('word-tap-1')));
      await tester.pump();
      await tester.tap(_closeKey);
      await tester.pump();
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('word-tap-1')));
      await tester.pump();

      late List<Map<String, Object?>> events;
      await tester.runAsync(() async {
        events = await rig.pendingEventsAfterSettling();
      });

      expect(events.where((e) => e['event'] == 'vocab_card_opened'), hasLength(2));
    });
  });

  group('VocabCardHostState.open — unknown id (EDGE)', () {
    testWidgets('an unresolvable vocabCardId completes immediately without '
        'showing a card or logging anything (content-integrity no-op, '
        'never throws or hangs)', (tester) async {
      final rig = _AnalyticsRig()..setUp();
      addTearDown(rig.tearDown);
      final hostKey = GlobalKey<VocabCardHostState>();
      final audio = FakeAudioService();

      await tester.pumpWidget(MaterialApp(
        home: VocabCardHost(
          key: hostKey,
          cardsById: const <String, VocabCard>{}, // empty: 'vocab.missing' unresolvable
          audioService: audio,
          analytics: rig.client,
          installId: _installId,
          profileOrdinal: 1,
          levelOrdinal: 1,
          child: const SizedBox.expand(),
        ),
      ));
      await tester.pump();

      final future = hostKey.currentState!.open('vocab.missing');
      await tester.pump();
      await expectLater(future, completes);

      expect(tester.takeException(), isNull);
      expect(_popoverKey, findsNothing);

      late List<Map<String, Object?>> events;
      await tester.runAsync(() async {
        events = await rig.pendingEventsAfterSettling();
      });
      expect(events.where((e) => e['event'] == 'vocab_card_opened'), isEmpty);
    });
  });
}

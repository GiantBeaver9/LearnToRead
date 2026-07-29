/// The reading screen state driver (PRD §8 Unit 5; ticket reading-screen).
///
/// [ReadingController] is the one place the Unit 4 tracker event stream is
/// turned into rendered reading state. It owns:
///
///  - the [WordStateMachine] (merged, reused verbatim) that projects tracker
///    events into per-word/per-page state,
///  - the microphone-session verbs the screen needs ([beginListening],
///    [pauseListening], [resumeListening], [tapCurrentWord]) expressed
///    against the narrow [ReadingTrackerHandle] seam,
///  - the §5 analytics this screen is the only unit in a position to emit
///    (`story_started` on open, `word_read` per newly resolved word), and
///  - the ~400 ms beat between the child turning the final page and the
///    celebration handoff ([kCelebrationBeat] / [onStoryComplete]; PRD §8
///    Unit 5, amended 2026-07-29: every page holds for the curl, so the
///    final turn -- not the last word's resolution -- starts the beat).
///
/// It contains no recognition logic whatsoever (PRD §8 Unit 5 pinned
/// design: the screen is driven solely by Unit 4 events) and no widgets:
/// it is a plain [ChangeNotifier] so both the screen and headless tests can
/// drive it.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:learn_to_read/domain/models/content_models.dart' show Level, Story, WordToken;
import 'package:learn_to_read/features/analytics/analytics_client.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/analytics/events.dart';
import 'package:learn_to_read/features/listening/contracts/tracker_events.dart';
import 'package:learn_to_read/features/reading/word_state.dart';
import 'package:learn_to_read/features/reading/word_state_machine.dart';

/// The pause between the child turning the story's final page and the
/// celebration sequence taking over (PRD §8 Unit 5: "listening stops and
/// control hands to the celebration sequence after a ~400 ms beat";
/// amended 2026-07-29: the curl closes every page, so the beat runs after
/// the final page's TURN -- the last word resolving holds, words green,
/// dog-ear showing, until the child closes the book).
///
/// The beat belongs to the reading screen, not to [WordStateMachine], which
/// only reports that the story finished.
const Duration kCelebrationBeat = Duration(milliseconds: 400);

/// The narrow slice of the Unit 4 listening tracker that the reading screen
/// is allowed to see.
///
/// Deliberately five verbs and one stream: everything the screen can do to
/// the microphone session is here, and nothing about engines, matching,
/// hypotheses, consent, or the tap engine leaks upward. `ReadingTracker`
/// (lib/features/listening/tracker/reading_tracker.dart, merged) already
/// exposes this exact shape, so the app shell adapts it with a one-line
/// `implements` wrapper; see docs/reading-screen.md for the wiring.
abstract class ReadingTrackerHandle {
  /// The single pinned tracker event stream (Unit 4) this screen renders.
  Stream<TrackerEvent> get eventsStream;

  /// Whether the microphone session is open right now; drives the design
  /// system listening indicator.
  bool get isListening;

  /// Suspends recognition (narration playing, vocabulary card open) without
  /// losing the reading cursor.
  void pause();

  /// Resumes recognition at the same word.
  void resume();

  /// Ends the session for good (story finished, or the screen is done).
  void stop();

  /// Accepts the current word by tap: the always-available fallback input,
  /// which the tracker pushes back through [eventsStream] exactly as if the
  /// word had been spoken.
  void tapCurrentWord();
}

/// Drives one story read: tracker events in, word state plus analytics plus
/// the celebration handoff out.
class ReadingController extends ChangeNotifier {
  /// Creates a controller for [story] at [level].
  ///
  /// [installId], [profileOrdinal] and [levelOrdinal] are the §5 analytics
  /// base fields, passed straight through to every event this controller
  /// emits. [onStoryComplete] fires [celebrationBeat] after the child TURNS
  /// the final page (PRD §8 Unit 5, amended 2026-07-29). [onPageTurned]
  /// fires each time [turnPage] advances a held non-final page. [clock] and
  /// [celebrationBeat] are injectable so timing is scriptable.
  ReadingController({
    required this.story,
    required this.level,
    required ReadingTrackerHandle tracker,
    required AnalyticsClient analytics,
    required this.installId,
    required this.profileOrdinal,
    required this.levelOrdinal,
    this.onStoryComplete,
    this.onPageTurned,
    Clock clock = systemClock,
    Duration celebrationBeat = kCelebrationBeat,
  })  : _tracker = tracker,
        _analytics = analytics,
        _clock = clock,
        _celebrationBeat = celebrationBeat,
        pages = _flattenPages(story) {
    _machine = WordStateMachine(pages: pages, level: level);
    _snapshot = _machine.snapshot;
    _trackStoryStarted();
  }

  /// The story being read.
  final Story story;

  /// The level it is being read at (drives vocab tappability and, in the
  /// screen, text sizing and listen-first narration).
  final Level level;

  /// Every page of [story] flattened to its word tokens, in reading order.
  /// Index `i` of `pages[p]` lines up with index `i` of
  /// `snapshot.pages[p]`.
  final List<List<WordToken>> pages;

  /// The random per-install UUID stamped on this screen analytics.
  final String installId;

  /// Which on-device profile is reading (ordinal 1-4).
  final int profileOrdinal;

  /// The profile current level ordinal.
  final int levelOrdinal;

  /// Fired once, [kCelebrationBeat] after the child turns the story's final
  /// page (PRD §8 Unit 5, amended 2026-07-29: the turn, not the last word's
  /// resolution, is what hands control to the celebration sequence), to
  /// hand over to the celebration sequence (Unit 8). The app shell wires
  /// it; this unit deliberately has no dependency on that one.
  final VoidCallback? onStoryComplete;

  /// Fired once per completed NON-final page turn, immediately after
  /// [turnPage] moves the machine onto the next page (PRD §8 Unit 5
  /// page-turn hold). The app shell wires it to the listening session's own
  /// page advance, so the tracker moves to the new page's words at TURN
  /// time, not at the moment the previous page's last word resolved. The
  /// final page's turn is a story-close, not a page advance: it does not
  /// fire this (there is no next page for the session to open, and the
  /// tracker already stopped at the last word's resolution).
  final VoidCallback? onPageTurned;

  final ReadingTrackerHandle _tracker;
  final AnalyticsClient _analytics;
  final Clock _clock;
  final Duration _celebrationBeat;

  late final WordStateMachine _machine;
  late WordStateSnapshot _snapshot;
  StreamSubscription<TrackerEvent>? _subscription;
  Timer? _beatTimer;
  bool _disposed = false;

  /// The current word/page state for the whole story.
  WordStateSnapshot get snapshot => _snapshot;

  /// The word tokens of the page being read.
  List<WordToken> get currentPageTokens => pages[_snapshot.currentPageIndex];

  /// Whether the microphone session is open, straight from the tracker.
  bool get isListening => _tracker.isListening;

  /// Whether this controller is already listening to the tracker stream.
  bool get hasBegun => _subscription != null;

  /// Subscribes to the tracker event stream and opens the microphone
  /// session.
  ///
  /// Called on open at levels without narration, and only once the
  /// listen-first narration has finished at levels with it (A-11): before
  /// this call nothing is subscribed, so nothing the tracker emits during
  /// narration can move the reading cursor.
  void beginListening() {
    if (_disposed || _subscription != null) return;
    _subscription = _tracker.eventsStream.listen(_onEvent);
    _tracker.resume();
    notifyListeners();
  }

  /// Suspends recognition (narration replaying, vocabulary card open).
  void pauseListening() {
    if (_disposed) return;
    _tracker.pause();
    notifyListeners();
  }

  /// Resumes recognition at the identical cursor it was paused at.
  void resumeListening() {
    if (_disposed) return;
    _tracker.resume();
    notifyListeners();
  }

  /// Routes a tap on the current word to the tracker tap path, which pushes
  /// an acceptance back through [ReadingTrackerHandle.eventsStream] exactly
  /// as a spoken word does.
  void tapCurrentWord() {
    if (_disposed) return;
    _tracker.tapCurrentWord();
  }

  /// Turns a held page (PRD §8 Unit 5 page-turn hold, mockup-spec §8;
  /// amended 2026-07-29: the curl closes every page): the screen's
  /// page-curl gesture lands here.
  ///
  /// Only meaningful while the machine reports
  /// [WordStateSnapshot.isPageComplete]; any other call -- including a
  /// double gesture for the same hold, or any call after the story
  /// completed -- is a no-op, so a page can never be skipped and completion
  /// can never re-fire. On a non-final turn the machine advances first,
  /// then [onPageTurned] fires (the session rebuilds its tracker for the
  /// new page), then listeners are notified. On the FINAL page's turn the
  /// machine signals story completion instead: the ~400 ms celebration beat
  /// starts here -- at turn time, not at the last word's resolution -- and
  /// [onPageTurned] is not called (there is no next page; the tracker
  /// already stopped at resolution).
  void turnPage() {
    if (_disposed) return;
    if (!_snapshot.isPageComplete) return;
    final result = _machine.turnPage();
    _snapshot = result.snapshot;
    if (result.storyCompleted) {
      _startCelebrationBeat();
    } else {
      onPageTurned?.call();
    }
    notifyListeners();
  }

  void _onEvent(TrackerEvent event) {
    if (_disposed) return;
    final fromPage = _snapshot.currentPageIndex;
    final fromIndex = _snapshot.currentIndex;
    final result = _machine.apply(event);
    _snapshot = result.snapshot;
    _trackWordReads(fromPage: fromPage, fromIndex: fromIndex, result: result);
    if (result.pageCompleted &&
        result.snapshot.currentPageIndex == pages.length - 1) {
      // Pinned ordering (unchanged by the 2026-07-29 curl-closes-every-page
      // ruling): listening stops on the very event that resolves the last
      // word -- there is nothing left to hear while the dog-ear waits. The
      // hold that follows is purely visual; the celebration beat runs only
      // once the child turns the page (see [turnPage]).
      _tracker.stop();
    }
    notifyListeners();
  }

  /// Holds the last word on screen, freshly green, for [kCelebrationBeat]
  /// and then hands over to [onStoryComplete] -- exactly once.
  void _startCelebrationBeat() {
    _beatTimer?.cancel();
    _beatTimer = Timer(_celebrationBeat, () {
      _beatTimer = null;
      if (_disposed) return;
      onStoryComplete?.call();
    });
  }

  void _cancelCelebrationBeat() {
    _beatTimer?.cancel();
    _beatTimer = null;
  }

  /// The beat is abandoned the moment nothing is watching this controller
  /// any more.
  ///
  /// The only listener a controller ever has is the screen rendering it, so
  /// an empty listener list means that screen is gone -- and a celebration
  /// must never be handed a screen that left. This also guarantees the beat
  /// cannot outlive the widget tree that started it, even when the owner
  /// forgets to [dispose] the controller.
  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) _cancelCelebrationBeat();
  }

  /// Emits one `word_read` per word this event newly resolved, in reading
  /// order.
  ///
  /// A lookahead back-fill resolves several words at once: each silently
  /// confirmed word is graded `correct` (it was never itself heard) and the
  /// word the event actually targeted carries its own grade, which is
  /// exactly what [WordState.resolution] already records.
  void _trackWordReads({
    required int fromPage,
    required int fromIndex,
    required WordStateResult result,
  }) {
    if (fromIndex < 0) return;
    final tokens = pages[fromPage];
    final states = result.snapshot.pages[fromPage];
    final movedOn = result.pageCompleted ||
        result.storyCompleted ||
        result.snapshot.currentPageIndex != fromPage;
    final until = movedOn ? tokens.length : result.snapshot.currentIndex;
    for (var i = fromIndex; i < until && i < tokens.length; i++) {
      final wordResult = _resultOf(states[i]);
      if (wordResult == null) continue;
      _track(
        AnalyticsEventName.wordRead,
        storyId: story.id,
        fields: <String, Object?>{
          'result': wordResult.wireValue,
          'wordHash': hashWord(tokens[i].text),
        },
      );
    }
  }

  WordReadResult? _resultOf(WordState state) {
    if (state.lifecycle != WordLifecycle.done) return null;
    switch (state.resolution) {
      case WordResolution.accepted:
        return WordReadResult.correct;
      case WordResolution.acceptedNearMiss:
        return WordReadResult.nearMiss;
      case WordResolution.helped:
        return WordReadResult.helped;
      case WordResolution.none:
        return null;
    }
  }

  void _trackStoryStarted() => _track(AnalyticsEventName.storyStarted, storyId: story.id);

  /// Records one §5 event.
  ///
  /// The call is deliberately handed to [Zone.root]: analytics is
  /// fire-and-forget background I/O, and running it in the root zone keeps
  /// its file writes independent of whatever zone the caller happens to be
  /// in (a widget test fake clock, a guarded app zone), so a queued write
  /// always drains on the real event loop rather than being stranded.
  void _track(
    AnalyticsEventName name, {
    String? storyId,
    Map<String, Object?> fields = const <String, Object?>{},
  }) {
    final event = AnalyticsEvent(
      name: name,
      timestamp: _clock(),
      installId: installId,
      profileOrdinal: profileOrdinal,
      levelOrdinal: levelOrdinal,
      storyId: storyId,
      fields: fields,
    );
    Zone.root.run(() => unawaited(_analytics.track(event)));
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    _subscription = null;
    _cancelCelebrationBeat();
    super.dispose();
  }

  /// Flattens `Story.pages -> Page.sentences -> words` into one token list
  /// per page, which is the shape [WordStateMachine] takes. A story with no
  /// pages normalizes to a single empty page so the snapshot is always
  /// indexable.
  static List<List<WordToken>> _flattenPages(Story story) {
    if (story.pages.isEmpty) return <List<WordToken>>[<WordToken>[]];
    return <List<WordToken>>[
      for (final page in story.pages)
        <WordToken>[
          for (final sentence in page.sentences) ...sentence.words,
        ],
    ];
  }
}

/// The Unit 5 word state machine (PRD §8 Unit 5, docs/tickets/
/// word-state-machine.json): pure Dart, headless -- takes the Unit 4
/// tracker event stream in, produces per-word [WordState]s out. Contains no
/// recognition logic, no timers, no audio; see docs/word-state-machine.md
/// for the full behavior spec.
library;

import 'package:learn_to_read/domain/models/content_models.dart' show Level, WordToken;
import 'package:learn_to_read/domain/models/user_models.dart' show HelpLevel;
import 'package:learn_to_read/features/listening/contracts/tracker_events.dart';
import 'package:learn_to_read/features/reading/word_state.dart';

/// A read-only view of every page's word states plus where the reader is
/// right now.
///
/// Riverpod-friendly: immutable, safe to hold as provider state and diff by
/// value. [pages] always includes every page (completed ones stay in the
/// list, done and unmutated) so the UI can render page-turn transitions
/// without losing prior pages.
class WordStateSnapshot {
  const WordStateSnapshot({
    required this.pages,
    required this.currentPageIndex,
    required this.currentIndex,
    required this.isStoryComplete,
  });

  /// Every page's words, in story order. Unmodifiable.
  final List<List<WordState>> pages;

  /// The page currently being read.
  final int currentPageIndex;

  /// The current word's index within `pages[currentPageIndex]`.
  ///
  /// `-1` once [isStoryComplete] is true (there is no longer a "current"
  /// word).
  final int currentIndex;

  /// True once the last word of the last page has resolved.
  final bool isStoryComplete;

  /// Shorthand for `pages[currentPageIndex]`.
  List<WordState> get currentPageWords => pages[currentPageIndex];
}

/// The result of applying one [TrackerEvent] to a [WordStateMachine].
class WordStateResult {
  const WordStateResult({
    required this.snapshot,
    required this.pageCompleted,
    required this.storyCompleted,
  });

  /// The machine's state immediately after the event was applied.
  final WordStateSnapshot snapshot;

  /// True iff this event just finished a page that is NOT the story's last
  /// page -- the screen should page-turn. Mutually exclusive with
  /// [storyCompleted].
  final bool pageCompleted;

  /// True iff this event just finished the LAST page of the story -- the
  /// screen should hand off to the celebration sequence (after its own
  /// ~400 ms beat; that timing is the reading-screen's, not this machine's).
  /// Fires exactly once: further events after completion report `false`
  /// (see [WordStateMachine.apply]).
  final bool storyCompleted;
}

/// Drives per-word [WordState]s for one story, page by page, from the Unit 4
/// tracker event stream.
///
/// `unread -> current -> (accepted | acceptedNearMiss | helped) -> done`.
/// Exactly one word is `current` within the active page at any time until
/// the whole story is done. This machine holds no opinion on WHETHER a word
/// was read correctly -- that judgment already happened upstream (Unit 4);
/// it only projects the resulting event stream into word/page/story state.
class WordStateMachine {
  /// Builds a machine over [pages] (already-flattened `Page.sentences ->
  /// words`, per page) at the given [level] (used only for
  /// `WordState.vocabTappable`: `WordToken.vocabCardId != null &&
  /// level.vocabEnabled`).
  ///
  /// The first word of the first page starts `current`; every other word
  /// starts `unread`.
  WordStateMachine({required List<List<WordToken>> pages, required Level level})
      : _pages = List.generate(
          pages.length,
          (p) => List.generate(
            pages[p].length,
            (i) => WordState(
              index: i,
              lifecycle: WordLifecycle.unread,
              vocabTappable: pages[p][i].vocabCardId != null && level.vocabEnabled,
            ),
          ),
        ) {
    if (_pages.isNotEmpty && _pages.first.isNotEmpty) {
      _pages[0][0] = _pages[0][0].copyWith(lifecycle: WordLifecycle.current);
    } else {
      // Degenerate empty story: nothing to read, nothing to complete.
      _isStoryComplete = true;
    }
  }

  final List<List<WordState>> _pages;
  int _currentPageIndex = 0;
  int _currentIndex = 0;
  bool _isStoryComplete = false;

  /// The machine's current state. Cheap to read repeatedly; each call
  /// returns a fresh, independently-unmodifiable snapshot over the live
  /// internal arrays.
  WordStateSnapshot get snapshot => WordStateSnapshot(
        pages: List.unmodifiable(_pages.map(List<WordState>.unmodifiable)),
        currentPageIndex: _currentPageIndex,
        currentIndex: _isStoryComplete ? -1 : _currentIndex,
        isStoryComplete: _isStoryComplete,
      );

  /// Applies one tracker event, mutating internal state and returning the
  /// resulting [WordStateResult].
  ///
  /// Once the story is complete, every subsequent call is inert: state is
  /// unchanged and both `pageCompleted`/`storyCompleted` report `false` (the
  /// completion signal fires exactly once, on the apply() call that finished
  /// the last page).
  WordStateResult apply(TrackerEvent event) {
    if (_isStoryComplete) {
      return _inertResult();
    }
    if (event is WordAccepted) {
      return _applyAcceptance(event.index, WordResolution.accepted);
    }
    if (event is WordAcceptedNearMiss) {
      return _applyAcceptance(event.index, WordResolution.acceptedNearMiss);
    }
    if (event is WordHelped) {
      return _applyHelped(event.index, event.tier);
    }
    if (event is StruggleDetected) {
      return _applyStruggle(event.index);
    }
    // Silence (and any future event type) carries no state-machine logic --
    // timing/struggle-escalation decisions belong to Unit 6, not here.
    return _inertResult();
  }

  /// Handles `wordAccepted` / `wordAcceptedNearMiss`.
  ///
  /// - Out-of-range or already-done ([index] < the current index) targets
  ///   are no-ops (negative test coverage).
  /// - [index] == the current index resolves it directly.
  /// - [index] > the current index is a lookahead back-fill: every word from
  ///   the current index up to (but not including) [index] is silently
  ///   resolved as a plain [WordResolution.accepted] confirmation (it was
  ///   never itself heard), then [index] resolves with [resolution] -- the
  ///   grade the event that actually fired carries.
  WordStateResult _applyAcceptance(int index, WordResolution resolution) {
    final page = _pages[_currentPageIndex];
    if (index < 0 || index >= page.length || index < _currentIndex) {
      return _inertResult();
    }
    for (var i = _currentIndex; i < index; i++) {
      page[i] = page[i].copyWith(
        lifecycle: WordLifecycle.done,
        resolution: WordResolution.accepted,
        struggling: false,
      );
    }
    page[index] = page[index].copyWith(
      lifecycle: WordLifecycle.done,
      resolution: resolution,
      struggling: false,
    );
    _currentIndex = index + 1;
    return _advanceAfterResolution();
  }

  /// Handles `wordHelped`. Only ever resolves the CURRENT word -- unlike
  /// acceptance, help never back-fills or targets an already-done word
  /// (the stuck-word scaffold only ever helps the word the reader is
  /// actually stuck on).
  WordStateResult _applyHelped(int index, HelpLevel tier) {
    if (index != _currentIndex) {
      return _inertResult();
    }
    final page = _pages[_currentPageIndex];
    page[index] = page[index].copyWith(
      lifecycle: WordLifecycle.done,
      resolution: WordResolution.helped,
      helpTier: tier,
      struggling: false,
    );
    _currentIndex = index + 1;
    return _advanceAfterResolution();
  }

  /// Handles `struggleDetected`: marks the current word `struggling` with no
  /// lifecycle change. Ignored for any non-current index.
  WordStateResult _applyStruggle(int index) {
    if (index != _currentIndex) {
      return _inertResult();
    }
    final page = _pages[_currentPageIndex];
    page[index] = page[index].copyWith(struggling: true);
    return WordStateResult(snapshot: snapshot, pageCompleted: false, storyCompleted: false);
  }

  /// After a word resolves, checks whether the page (and possibly the
  /// story) just completed, and promotes the new current word / turns the
  /// page / signals story completion as needed.
  WordStateResult _advanceAfterResolution() {
    final page = _pages[_currentPageIndex];
    if (_currentIndex < page.length) {
      page[_currentIndex] = page[_currentIndex].copyWith(lifecycle: WordLifecycle.current);
      return WordStateResult(snapshot: snapshot, pageCompleted: false, storyCompleted: false);
    }

    final isFinalPage = _currentPageIndex == _pages.length - 1;
    if (isFinalPage) {
      _isStoryComplete = true;
      return WordStateResult(snapshot: snapshot, pageCompleted: false, storyCompleted: true);
    }

    _currentPageIndex += 1;
    _currentIndex = 0;
    final nextPage = _pages[_currentPageIndex];
    if (nextPage.isNotEmpty) {
      nextPage[0] = nextPage[0].copyWith(lifecycle: WordLifecycle.current);
    }
    return WordStateResult(snapshot: snapshot, pageCompleted: true, storyCompleted: false);
  }

  WordStateResult _inertResult() =>
      WordStateResult(snapshot: snapshot, pageCompleted: false, storyCompleted: false);
}

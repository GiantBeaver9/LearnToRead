# Reading Screen (Unit 5 — text rendering, word state, listen-first, handoff)

## Overview

The centrepiece screen: the child reads a story aloud and watches their own
words turn green. It is a **pure composition unit** — it contains no
recognition logic, no help logic, and no celebration logic. Each of those
arrives through one narrow seam:

| Concern | Owner | How it reaches this screen |
| --- | --- | --- |
| Recognition / matching | Unit 4 | `ReadingTrackerHandle.eventsStream` |
| Tiered help + sound-out | Unit 6 | `ReadingScreen.helpState` (a `HelpState`) |
| Celebration + collectible | Unit 8 | `ReadingScreen.onStoryComplete` callback |
| Vocabulary card | Unit 7 | `VocabCardOpener` (a future that completes on close) |
| Session / abandonment | Unit 12 | `ReadingScreen.onReadingExited` callback |
| Word/page state machine | Unit 5 (merged) | `WordStateMachine`, reused verbatim |

Everything visible is styled from `DesignTokens` only; the token lint
(`test/design/token_lint_test.dart`) and the negative-feedback scanner
(`test/features/reading/no_negative_feedback_test.dart`) both gate this
directory on every run.

## Files

### `reading_controller.dart`

```dart
abstract class ReadingTrackerHandle {
  Stream<TrackerEvent> get eventsStream;
  bool get isListening;
  void pause();
  void resume();
  void stop();
  void tapCurrentWord();
}

const Duration kCelebrationBeat = Duration(milliseconds: 400);

class ReadingController extends ChangeNotifier {
  ReadingController({
    required Story story,
    required Level level,
    required ReadingTrackerHandle tracker,
    required AnalyticsClient analytics,
    required String installId,
    required int profileOrdinal,
    required int levelOrdinal,
    VoidCallback? onStoryComplete,
    Clock clock = systemClock,
    Duration celebrationBeat = kCelebrationBeat,
  });

  WordStateSnapshot get snapshot;
  List<List<WordToken>> get pages;
  List<WordToken> get currentPageTokens;
  bool get isListening;
  bool get hasBegun;

  void beginListening();
  void pauseListening();
  void resumeListening();
  void tapCurrentWord();
}
```

The one place tracker events become rendered state. Each event is applied to
the merged `WordStateMachine`, then three things follow from the result:

1. **`word_read` per newly resolved word**, in reading order. A lookahead
   back-fill resolves several words at once: the silently confirmed words
   are graded `correct` (they were never themselves heard) and the word the
   event actually targeted carries its own grade — which is exactly what
   `WordState.resolution` already records, so the grading rule lives in one
   place, not two.
2. **Story completion**: `tracker.stop()` runs synchronously on the very
   event that resolved the last word, then `kCelebrationBeat` (~400 ms)
   later `onStoryComplete` fires — once.
3. `notifyListeners()`, which is what repaints the screen.

`story_started` is emitted in the constructor, i.e. on open.

#### ReadingTrackerHandle → ReadingTracker (app-shell adaptation)

`ReadingTrackerHandle` is deliberately narrower than Unit 4's
`ReadingTracker`: it exposes the five verbs and one stream this screen may
touch, and nothing about engines, matching, consent, metering, or tap mode.
`ReadingTracker` (`lib/features/listening/tracker/reading_tracker.dart`)
already has all six members with identical signatures and semantics, so the
app shell adapts it without any translation layer:

```dart
class TrackerHandle implements ReadingTrackerHandle {
  TrackerHandle(this._tracker);
  final ReadingTracker _tracker;

  @override Stream<TrackerEvent> get eventsStream => _tracker.eventsStream;
  @override bool get isListening => _tracker.isListening;
  @override void pause() => _tracker.pause();
  @override void resume() => _tracker.resume();
  @override void stop() => _tracker.stop();
  @override void tapCurrentWord() => _tracker.tapCurrentWord();
}
```

Two lifecycle facts the shell owns, because they are outside this screen:

- **`ReadingTracker.start()` is the shell's call**, made before the screen is
  pushed. The screen only ever `resume()`s the session it was handed, which
  is also what makes listen-first possible: at narration levels the screen
  simply does not resume until the recording has finished playing.
- **`isTapMode`, `updateMicConsent`, `helpCompleted`** stay on the tracker.
  Unit 6 calls `helpCompleted`; the resulting `WordHelped` event arrives here
  through the same stream as everything else.

### `reading_screen.dart`

```dart
typedef VocabCardOpener = Future<void> Function(String vocabCardId);

ReadingScreen({
  required Story story,
  required Level level,
  required ReadingTrackerHandle tracker,
  required AudioService audioService,
  required AnalyticsClient analytics,
  required String installId,
  required int profileOrdinal,
  required int levelOrdinal,
  required StoryStage stage,
  required VocabCardOpener vocabCardOpener,
  VoidCallback? onStoryComplete,
  VoidCallback? onReadingExited,
  HelpState helpState = kNoHelp,
});
```

Composition and lifecycle:

- **Layout** is the shared `ReadingLayout` (Unit 1): text region and stage
  region side by side in landscape (book-like), stacked in portrait. Reading
  text size comes from the sentence/paragraph tokens crossed with the
  phone/tablet layout class. The text region scrolls rather than overflowing,
  which is what `layout_classes_test.dart` verifies at all four classes with
  real sentence- and paragraph-length content.
- **Listen-first (A-11)**: when `level.narrationEnabled` and the current page
  has a `narrationAudioRef`, `NarrationController.playInitial` runs to
  completion *before* `beginListening()` — so the tracker stream is not even
  subscribed while the recording plays, and nothing the child says during it
  can move the cursor. An ear-icon button (`narration-replay-button`) replays
  the same recording at any time, pausing recognition for the duration.
  There is no per-word karaoke highlighting in v1.
- **Vocab tap**: pauses listening, awaits `vocabCardOpener`, resumes on
  close. Opening a card never resolves a word, so the cursor is by
  construction identical afterwards.
- **Dispose**: `onReadingExited` fires exactly once, and a story left
  mid-read pauses the tracker, so no microphone session outlives the screen
  that opened it. (The shell still owns stopping the tracker for good.)

### `word_text_view.dart`

Renders one page of `WordState`s. Widget-key vocabulary, which is the pinned
contract other units and tests address this screen by:

| Key | Present when |
| --- | --- |
| `word-text-$i` | always, except while word `$i` is being sounded out |
| `word-current-marker-$i` | word `$i` is the current word |
| `word-tap-$i` | word `$i` is current, or is vocab-tappable |
| `grapheme-$w-$g` | word `$w` is being sounded out (Tier 1) |
| `narration-replay-button` | this page has narration to replay |
| `page-$pageIndex` | supplied by the page builder |
| `listening-indicator-active` | the microphone session is open |

There is deliberately **no `helped-badge-$i`**, and no key of any kind for a
word that went badly: a helped word is pixel-identical to a word read
unaided, and only `WordState.resolution` (invisible) tells them apart.

Two structural details worth keeping:

- The current-word marker and the tap target are *positioned siblings* laid
  over the word, never wrappers around it. That keeps the animated text
  element identical across a lifecycle change, so the green sweep animates
  instead of being rebuilt from scratch as an instant recolor.
- Tap precedence: **vocab wins over the tap fallback**. A blue word is
  tappable at any point in its life, so where both would apply the card is
  what opens.

### `narration_controller.dart`, `page_turn.dart`, `listening_indicator.dart`

- `NarrationController` plays on `AudioChannel.narration` and always resumes
  listening after a replay — *including when playback throws*, because a
  missing clip is a content bug and must never strand a paused child.
- `PageTurn` is full-bleed: the built page is given the whole parent, with no
  gutter of its own. It turns pages at the boundaries the state machine
  reports (`WordStateResult.pageCompleted`), which is also why the last page
  never turns.
- `ListeningIndicator` reports exactly one fact, quietly: a small ink dot,
  no motion, no sound. It is incapable of saying anything about how the
  reading is going.

## Audio policy

The only sound this screen can make is the sentence narration. There is no
per-word sound of any kind — sound is reserved for help (Unit 6) and
celebration (Unit 8) so the child's own voice stays the primary audio.
`reading_screen_test.dart` asserts `FakeAudioService.callLog` stays empty
across ordinary acceptances.

## No negative feedback

Pinned, and enforced two ways on every test run:

1. A static scan of every string literal under `lib/features/reading/` for
   `wrong` / `incorrect` / `oops` / `try again` / an error word / the whole
   word for the colour at the hot end of the spectrum.
2. A widget-tree sweep that drives a struggle + help sequence and checks no
   rendered `Text` or `Icon` carries banned copy or a reddish hue (an
   HSV-hue heuristic, so it would catch a colour smuggled in under an
   innocuous token name).

## Analytics

| Event | When |
| --- | --- |
| `story_started` | on open, once |
| `word_read` | per newly resolved word, `correct` / `near_miss` / `helped` |

`story_abandoned` is Unit 12's `SessionTracker` judgement; this screen only
reports the fact it knows (`onReadingExited`). `vocab_card_opened` belongs to
Unit 7, which owns the card.

Analytics calls are handed to `Zone.root`: they are fire-and-forget
background writes, and keeping them out of the caller's zone means a queued
write always drains on the real event loop rather than being stranded by
whatever zone the caller happens to be running in.

## Known deviation from the frozen suite

`reading_screen_test.dart`, `Vocab tap: ... restores the exact cursor on
close` asserts, at line 526, that `tracker.isListening` is `true` when the
screen opens, and then at line 544 that the tracker's whole call log is
exactly `['pause', 'resume']`. Those two cannot both hold: the test double
only becomes listening via `resume()`, which records itself, so any log that
starts out listening necessarily begins with a `'resume'` entry. The
implementation produces `['resume', 'pause', 'resume']` and every other
assertion in that test passes. The minimal fix is a `tracker.calls.clear()`
after the open-state assertions — exactly what `narration_test.dart` does
before its own exact-log assertion on the replay path — and it needs a
test-owner decision, since the suite is frozen.

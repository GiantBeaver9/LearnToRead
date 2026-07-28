/// Lookahead back-fill and multi-page tests for the Unit 5 word state
/// machine (PRD §8 Unit 5 pinned_design: "Lookahead back-fill behavior is
/// defined by Unit 4's match policy; this machine consumes the tracker's
/// already-ordered events" / PRD §8 Unit 4: "lookahead 1 with back-fill
/// (hearing the next word confirms the current one)").
///
/// Companion to word_state_machine_test.dart; see that file's header for the
/// full pinned contract (WordState / WordStateMachine / WordStateSnapshot /
/// WordStateResult). This file exercises two accept criteria specifically:
///   - "wordAccepted(n+1) arriving while word n is current back-fills n to
///     done and advances current to n+2" (ticket accept #2).
///   - "Multi-page stories: the machine operates per-sentence/page sequence
///     and reports page-complete boundaries" (ticket accept #6, fixture with
///     2 pages).
///
/// Judgment call (documented, not pinned verbatim by the PRD): PRD/Unit 4
/// only pins *lookahead 1* (hearing word n+1 confirms word n). This suite's
/// EDGE group extrapolates a general back-fill sweep for gaps > 1 so the
/// machine degrades safely rather than corrupting state if the tracker ever
/// emits a larger jump; that generalization is a builder decision, not a
/// PRD-pinned behavior, and is called out in the build report as such.
///
/// Back-filled words resolve as WordResolution.accepted (a plain, silent
/// confirmation) regardless of what resolution the *confirming* word gets;
/// only the word whose own event actually arrived carries accepted /
/// acceptedNearMiss.
import 'package:flutter_test/flutter_test.dart';

import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/features/listening/contracts/fake_reading_tracker.dart';
import 'package:learn_to_read/features/listening/contracts/tracker_events.dart';
import 'package:learn_to_read/features/reading/word_state.dart';
import 'package:learn_to_read/features/reading/word_state_machine.dart';

WordToken _word(String text, {String? vocabCardId}) => WordToken(
      text: text,
      graphemePhonemeMap: [(graphemes: text, phonemeId: 'X')],
      pronunciationAudioRef: 'audio/$text.mp3',
      vocabCardId: vocabCardId,
    );

Level _level({bool vocabEnabled = false}) => Level(
      id: 'level-1',
      ordinal: 1,
      newSkills: const [],
      format: LevelFormat.sentence,
      vocabEnabled: vocabEnabled,
    );

WordStateMachine _machine(List<List<String>> pages) {
  final pageTokens = pages.map((page) => page.map(_word).toList()).toList();
  return WordStateMachine(pages: pageTokens, level: _level());
}

void main() {
  group('POSITIVE: lookahead back-fill (accept #2, pinned lookahead-1)', () {
    test('wordAccepted(1) while word 0 is current back-fills 0 to done and advances current to 2', () {
      final machine = _machine([
        ['the', 'cat', 'sat', 'down'],
      ]);

      final result = machine.apply(const WordAccepted(index: 1));

      expect(result.snapshot.currentPageWords, [
        WordState(
          index: 0,
          lifecycle: WordLifecycle.done,
          resolution: WordResolution.accepted,
        ),
        WordState(
          index: 1,
          lifecycle: WordLifecycle.done,
          resolution: WordResolution.accepted,
        ),
        WordState(index: 2, lifecycle: WordLifecycle.current),
        WordState(index: 3, lifecycle: WordLifecycle.unread),
      ]);
      expect(result.snapshot.currentIndex, 2);
    });

    test('the confirming event\'s own resolution type is preserved on the word that actually fired it', () {
      final machine = _machine([
        ['the', 'cat', 'sat'],
      ]);

      // Near-miss on word 1 while word 0 is current: word 0 back-fills as a
      // plain (non-near-miss) accepted confirmation; word 1 itself carries
      // the near-miss resolution.
      final result = machine.apply(const WordAcceptedNearMiss(index: 1));

      expect(result.snapshot.currentPageWords[0].resolution, WordResolution.accepted);
      expect(result.snapshot.currentPageWords[1].resolution, WordResolution.acceptedNearMiss);
      expect(
        result.snapshot.currentPageWords[0].renderColor,
        result.snapshot.currentPageWords[1].renderColor,
        reason: 'both render identically as green regardless of resolution flavor',
      );
    });

    test('back-fill landing on the final word of the story signals story completion', () {
      final machine = _machine([
        ['hop', 'skip'],
      ]);

      // Word 0 is current; hearing word 1 (the LAST word) back-fills 0 and
      // resolves 1, completing the story in a single apply() call.
      final result = machine.apply(const WordAccepted(index: 1));

      expect(result.storyCompleted, isTrue);
      expect(result.snapshot.currentIndex, -1);
      expect(
        result.snapshot.currentPageWords.every((w) => w.lifecycle == WordLifecycle.done),
        isTrue,
      );
    });

    test('sequential back-fills across a realistic tracker script settle the whole sentence', () async {
      // 4 words; tracker only ever emits events for the ODD-indexed words,
      // relying on back-fill to resolve the even-indexed ones -- exactly the
      // "hearing the next word confirms the current one" policy.
      final machine = _machine([
        ['a', 'b', 'c', 'd'],
      ]);
      final tracker = FakeReadingTracker(
        script: const [
          WordAccepted(index: 1),
          WordAccepted(index: 3),
        ],
      );

      WordStateResult? last;
      await for (final event in tracker.eventsStream) {
        last = machine.apply(event);
      }

      expect(last!.storyCompleted, isTrue);
      expect(
        machine.snapshot.currentPageWords.map((w) => w.resolution).toList(),
        [
          WordResolution.accepted, // back-filled by hearing word 1
          WordResolution.accepted, // explicit event
          WordResolution.accepted, // back-filled by hearing word 3
          WordResolution.accepted, // explicit event
        ],
      );
    });
  });

  group('EDGE: back-fill sweeps a gap larger than lookahead-1 (builder extrapolation, see file header)', () {
    test('wordAccepted(index: current + 2) resolves both skipped words as accepted back-fills', () {
      final machine = _machine([
        ['w0', 'w1', 'w2', 'w3'],
      ]);

      final result = machine.apply(const WordAccepted(index: 2));

      expect(result.snapshot.currentPageWords[0].lifecycle, WordLifecycle.done);
      expect(result.snapshot.currentPageWords[0].resolution, WordResolution.accepted);
      expect(result.snapshot.currentPageWords[1].lifecycle, WordLifecycle.done);
      expect(result.snapshot.currentPageWords[1].resolution, WordResolution.accepted);
      expect(result.snapshot.currentPageWords[2].lifecycle, WordLifecycle.done);
      expect(result.snapshot.currentIndex, 3);
    });
  });

  group('NEGATIVE: an out-of-range index does not trigger a partial back-fill', () {
    test('an event far beyond the page length leaves every word untouched (no partial sweep)', () {
      final machine = _machine([
        ['w0', 'w1', 'w2'],
      ]);
      final before = machine.snapshot.currentPageWords;

      final result = machine.apply(const WordAccepted(index: 500));

      expect(result.snapshot.currentPageWords, before);
      expect(result.snapshot.currentIndex, 0);
    });
  });

  group('POSITIVE: multi-page stories report page-complete boundaries (accept #6, 2-page fixture)', () {
    // AMENDED 2026-07-28: page-turn-hold ruling (PRD §8 Unit 5): completing
    // a non-final page no longer auto-advances -- the machine HOLDS
    // (isPageComplete) and only turnPage() (the child's page-curl gesture)
    // moves onto the next page.
    test('completing the first of two pages sets pageCompleted and HOLDS; turnPage() '
        'moves to page 2 and preserves page 1', () {
      final machine = _machine([
        ['see', 'spot'], // page 0: 2 words
        ['spot', 'runs', 'fast'], // page 1: 3 words
      ]);

      expect(machine.snapshot.pages, hasLength(2));
      expect(machine.snapshot.currentPageIndex, 0);

      machine.apply(const WordAccepted(index: 0));
      final pageBoundaryResult = machine.apply(const WordAccepted(index: 1));

      expect(pageBoundaryResult.pageCompleted, isTrue);
      expect(pageBoundaryResult.storyCompleted, isFalse);
      // AMENDED 2026-07-28: page-turn-hold ruling (PRD §8 Unit 5) -- the
      // page does NOT advance at resolution time.
      expect(pageBoundaryResult.snapshot.currentPageIndex, 0);
      expect(pageBoundaryResult.snapshot.isPageComplete, isTrue);
      expect(pageBoundaryResult.snapshot.currentIndex, -1,
          reason: 'no current word while holding at a completed page');

      // Page 0's words are preserved, done, and do not regress.
      expect(pageBoundaryResult.snapshot.pages[0], [
        WordState(index: 0, lifecycle: WordLifecycle.done, resolution: WordResolution.accepted),
        WordState(index: 1, lifecycle: WordLifecycle.done, resolution: WordResolution.accepted),
      ]);

      // The child turns the page.
      machine.turnPage();
      final turned = machine.snapshot;
      expect(turned.currentPageIndex, 1);
      expect(turned.currentIndex, 0);
      expect(turned.isPageComplete, isFalse);

      // Page 1 starts fresh: first word current, rest unread.
      expect(turned.pages[1], [
        WordState(index: 0, lifecycle: WordLifecycle.current),
        WordState(index: 1, lifecycle: WordLifecycle.unread),
        WordState(index: 2, lifecycle: WordLifecycle.unread),
      ]);
      expect(turned.currentPageWords, turned.pages[1]);
    });

    test('completing the FINAL page signals storyCompleted, not pageCompleted (no page-turn needed)', () {
      final machine = _machine([
        ['see', 'spot'],
        ['spot', 'runs', 'fast'],
      ]);
      machine.apply(const WordAccepted(index: 0));
      machine.apply(const WordAccepted(index: 1)); // page 0 complete -> hold
      // AMENDED 2026-07-28: page-turn-hold ruling (PRD §8 Unit 5): the
      // turn gesture, not the resolution, moves onto page 1.
      machine.turnPage();

      machine.apply(const WordAccepted(index: 0));
      machine.apply(const WordAccepted(index: 1));
      final finalResult = machine.apply(const WordAccepted(index: 2));

      expect(finalResult.storyCompleted, isTrue);
      expect(
        finalResult.pageCompleted,
        isFalse,
        reason: 'the last page hands off to celebration, not a page-turn',
      );
      expect(finalResult.snapshot.currentIndex, -1);
      expect(finalResult.snapshot.pages[1].every((w) => w.lifecycle == WordLifecycle.done), isTrue);
      // Page 0 remains untouched/done from earlier -- no regression across pages.
      expect(finalResult.snapshot.pages[0].every((w) => w.lifecycle == WordLifecycle.done), isTrue);
    });

    test('lookahead back-fill works across the boundary of a single page (does not spill into the next page)',
        () {
      final machine = _machine([
        ['see', 'spot', 'run'], // page 0: 3 words
        ['go', 'spot'], // page 1: 2 words
      ]);

      // Back-fill within page 0: hearing word 1 confirms word 0.
      machine.apply(const WordAccepted(index: 1));
      expect(machine.snapshot.currentPageIndex, 0);
      expect(machine.snapshot.currentIndex, 2);

      // Finish page 0 normally.
      final boundary = machine.apply(const WordAccepted(index: 2));
      expect(boundary.pageCompleted, isTrue);
      // AMENDED 2026-07-28: page-turn-hold ruling (PRD §8 Unit 5): the
      // machine holds at the completed page; the back-fill never spilled
      // into page 1, whose words only start once the page is turned.
      expect(boundary.snapshot.currentPageIndex, 0);
      expect(boundary.snapshot.isPageComplete, isTrue);
      expect(boundary.snapshot.pages[1][0].lifecycle, WordLifecycle.unread);
      machine.turnPage();
      expect(machine.snapshot.currentPageIndex, 1);
      expect(machine.snapshot.currentIndex, 0);
      expect(machine.snapshot.pages[1][0].lifecycle, WordLifecycle.current);
      expect(machine.snapshot.pages[1][1].lifecycle, WordLifecycle.unread);
    });

    test('a full 2-page story driven end-to-end via a scripted FakeReadingTracker completes correctly', () async {
      final machine = _machine([
        ['once', 'upon'], // page 0
        ['a', 'time'], // page 1
      ]);
      final tracker = FakeReadingTracker(
        script: const [
          WordAccepted(index: 0),
          WordAccepted(index: 1), // completes page 0
          WordAccepted(index: 0),
          WordAccepted(index: 1), // completes page 1 == story
        ],
      );

      final results = <WordStateResult>[];
      await for (final event in tracker.eventsStream) {
        final result = machine.apply(event);
        results.add(result);
        // AMENDED 2026-07-28: page-turn-hold ruling (PRD §8 Unit 5): the
        // machine holds at the page boundary; the harness plays the child's
        // turn gesture so the scripted page-1 events land on page 1.
        if (result.pageCompleted) machine.turnPage();
      }

      expect(results, hasLength(4));
      expect(results.map((r) => r.pageCompleted).toList(), [false, true, false, false]);
      expect(results.map((r) => r.storyCompleted).toList(), [false, false, false, true]);
      expect(machine.snapshot.isStoryComplete, isTrue);
    });
  });
}

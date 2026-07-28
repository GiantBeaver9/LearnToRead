/// Unit tests for the Unit 5 word state machine (PRD §8 Unit 5, docs/tickets/
/// word-state-machine.json).
///
/// Pins the CONTRACT this ticket's implementation must satisfy (the files do
/// not exist yet -- red-for-right-reason is "target of URI doesn't exist"):
///
///   lib/features/reading/word_state.dart
///     enum WordLifecycle { unread, current, done }
///     enum WordResolution { none, accepted, acceptedNearMiss, helped }
///     class WordState {
///       final int index;
///       final WordLifecycle lifecycle;
///       final WordResolution resolution; // default: WordResolution.none
///       final HelpLevel? helpTier;        // default: null
///       final bool vocabTappable;         // default: false
///       final bool struggling;            // default: false
///       Color get renderColor;            // pinned to DesignTokens, below
///       // value equality (==, hashCode) over all fields.
///     }
///
///   lib/features/reading/word_state_machine.dart
///     class WordStateSnapshot {
///       final List<List<WordState>> pages; // ALL pages, incl. completed ones
///       final int currentPageIndex;
///       final int currentIndex;   // index within pages[currentPageIndex]; -1 when story complete
///       final bool isStoryComplete;
///       List<WordState> get currentPageWords; // == pages[currentPageIndex]
///     }
///     class WordStateResult {
///       final WordStateSnapshot snapshot;
///       final bool pageCompleted;  // true only when a NON-final page just finished
///       final bool storyCompleted; // true only on the apply() that finishes the LAST page
///     }
///     class WordStateMachine {
///       WordStateMachine({required List<List<WordToken>> pages, required Level level});
///       WordStateSnapshot get snapshot;
///       WordStateResult apply(TrackerEvent event);
///     }
///
/// Design notes pinned by these tests (judgment calls made by the test
/// author where the ticket/PRD text left the exact shape open -- see the
/// builder's final report for the full rationale):
///  - `pages` is `List<List<WordToken>>`: a page's words already flattened
///    (the reading-screen ticket is responsible for flattening
///    Page.sentences -> words when wiring real Story content in).
///  - render color is derived SOLELY from `lifecycle` (+ `vocabTappable`
///    while unread): unread -> ink (or vocab blue), current -> current ink,
///    done -> read-green, regardless of *which* resolution produced `done`
///    (accepted / acceptedNearMiss / helped all render identically -- this
///    is the literal Unit 1/5/6 ratification under test).
///  - `vocabTappable` is a static per-word flag (WordToken.vocabCardId != null
///    && Level.vocabEnabled) that does NOT change with lifecycle -- vocab
///    words are tappable "at any time" per PRD -- but it only affects
///    `renderColor` while the word is still `unread` (PRD Unit 1: "Vocabulary
///    word (unread): blue").
import 'package:flutter_test/flutter_test.dart';

import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/features/listening/contracts/fake_reading_tracker.dart';
import 'package:learn_to_read/features/listening/contracts/tracker_events.dart';
import 'package:learn_to_read/features/reading/word_state.dart';
import 'package:learn_to_read/features/reading/word_state_machine.dart';

/// Builds a [WordToken] with a minimal, valid graphemePhonemeMap.
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

/// Builds a machine from plain word-text pages, with an optional set of
/// words that carry a vocabCardId.
WordStateMachine _machine(
  List<List<String>> pages, {
  bool vocabEnabled = false,
  Set<String> vocabWords = const {},
}) {
  final pageTokens = pages
      .map(
        (page) => page
            .map(
              (text) => _word(
                text,
                vocabCardId: vocabWords.contains(text) ? 'vocab.$text' : null,
              ),
            )
            .toList(),
      )
      .toList();
  return WordStateMachine(pages: pageTokens, level: _level(vocabEnabled: vocabEnabled));
}

/// Asserts that exactly one word across [words] is WordLifecycle.current.
void _expectExactlyOneCurrent(List<WordState> words) {
  final currentCount = words.where((w) => w.lifecycle == WordLifecycle.current).length;
  expect(currentCount, 1, reason: 'expected exactly one current word in $words');
}

void main() {
  group('POSITIVE: initial construction', () {
    test('a fresh 3-word single-page story starts unread → current → unread…unread', () {
      final machine = _machine([
        ['the', 'cat', 'sat'],
      ]);

      final words = machine.snapshot.currentPageWords;
      expect(words, [
        WordState(index: 0, lifecycle: WordLifecycle.current),
        WordState(index: 1, lifecycle: WordLifecycle.unread),
        WordState(index: 2, lifecycle: WordLifecycle.unread),
      ]);
      expect(machine.snapshot.currentIndex, 0);
      expect(machine.snapshot.currentPageIndex, 0);
      expect(machine.snapshot.isStoryComplete, isFalse);
      expect(machine.snapshot.pages, hasLength(1));
      expect(machine.snapshot.pages.single, hasLength(3));
    });

    test('vocabTappable true only when BOTH vocabCardId is set AND Level.vocabEnabled', () {
      final withBoth = _machine(
        [
          ['see', 'the', 'telescope'],
        ],
        vocabEnabled: true,
        vocabWords: {'telescope'},
      );
      expect(withBoth.snapshot.currentPageWords[2].vocabTappable, isTrue);
      expect(withBoth.snapshot.currentPageWords[0].vocabTappable, isFalse);

      final vocabCardButLevelDisabled = _machine(
        [
          ['see', 'the', 'telescope'],
        ],
        vocabWords: {'telescope'}, // vocabEnabled defaults false
      );
      expect(vocabCardButLevelDisabled.snapshot.currentPageWords[2].vocabTappable, isFalse);

      final levelEnabledButNoVocabCard = _machine(
        [
          ['see', 'the', 'telescope'],
        ],
        vocabEnabled: true,
        // no vocabWords supplied: 'telescope' has no vocabCardId.
      );
      expect(levelEnabledButNoVocabCard.snapshot.currentPageWords[2].vocabTappable, isFalse);
    });
  });

  group('POSITIVE: state-to-color mapping pinned to DesignTokens', () {
    test('unread, non-vocab word renders wordUnreadInk', () {
      final machine = _machine([
        ['dog', 'runs'],
      ]);
      // index 1 is unread (index 0 is current).
      expect(machine.snapshot.currentPageWords[1].renderColor, DesignTokens.wordUnreadInk);
    });

    test('current word renders wordCurrentInk', () {
      final machine = _machine([
        ['dog', 'runs'],
      ]);
      expect(machine.snapshot.currentPageWords[0].lifecycle, WordLifecycle.current);
      expect(machine.snapshot.currentPageWords[0].renderColor, DesignTokens.wordCurrentInk);
    });

    test('unread vocab word (vocabEnabled level) renders wordVocabBlue', () {
      final machine = _machine(
        [
          ['a', 'telescope'],
        ],
        vocabEnabled: true,
        vocabWords: {'telescope'},
      );
      expect(machine.snapshot.currentPageWords[1].renderColor, DesignTokens.wordVocabBlue);
    });

    test('accepted word renders wordReadGreen', () {
      final machine = _machine([
        ['dog', 'runs'],
      ]);
      machine.apply(const WordAccepted(index: 0));
      expect(machine.snapshot.currentPageWords[0].renderColor, DesignTokens.wordReadGreen);
    });

    test('near-miss accepted word renders wordReadGreen (identical to accepted)', () {
      final machine = _machine([
        ['dog', 'runs'],
      ]);
      machine.apply(const WordAcceptedNearMiss(index: 0));
      expect(machine.snapshot.currentPageWords[0].renderColor, DesignTokens.wordReadGreen);
    });

    test('helped word renders wordReadGreen == wordHelpedGreen (identical to accepted)', () {
      final machine = _machine([
        ['dog', 'runs'],
      ]);
      machine.apply(const WordHelped(index: 0, tier: HelpLevel.soundOut));
      expect(machine.snapshot.currentPageWords[0].renderColor, DesignTokens.wordHelpedGreen);
      expect(machine.snapshot.currentPageWords[0].renderColor, DesignTokens.wordReadGreen);
    });

    // AMENDED 2026-07-28: vocab-read purple ruling (PRD §8 Unit 1)
    test('a done vocab word renders vocab-read purple, not blue and not green '
        '(blue is unread-only; vocab words never turn green)', () {
      final machine = _machine(
        [
          ['a', 'telescope'],
        ],
        vocabEnabled: true,
        vocabWords: {'telescope'},
      );
      machine.apply(const WordAccepted(index: 0));
      machine.apply(const WordAccepted(index: 1));
      final telescope = machine.snapshot.currentPageWords[1];
      expect(telescope.vocabTappable, isTrue, reason: 'tappability persists regardless of lifecycle');
      expect(telescope.renderColor, DesignTokens.wordVocabReadPurple);
      expect(telescope.renderColor, isNot(DesignTokens.wordVocabBlue));
      expect(telescope.renderColor, isNot(DesignTokens.wordReadGreen));
    });
  });

  group('POSITIVE: wordAccepted transitions current word to done(green) and advances', () {
    test('accepting the current word resolves it and advances current to the next word', () {
      final machine = _machine([
        ['the', 'cat', 'sat'],
      ]);

      final result = machine.apply(const WordAccepted(index: 0));

      expect(result.snapshot.currentPageWords, [
        WordState(index: 0, lifecycle: WordLifecycle.done, resolution: WordResolution.accepted),
        WordState(index: 1, lifecycle: WordLifecycle.current),
        WordState(index: 2, lifecycle: WordLifecycle.unread),
      ]);
      expect(result.snapshot.currentIndex, 1);
      expect(result.pageCompleted, isFalse);
      expect(result.storyCompleted, isFalse);
    });

    test('accepting every word in order settles the whole sentence, exactly one current at a time', () {
      final machine = _machine([
        ['a', 'b', 'c', 'd'],
      ]);

      for (var i = 0; i < 3; i++) {
        final result = machine.apply(WordAccepted(index: i));
        _expectExactlyOneCurrent(result.snapshot.currentPageWords);
        expect(result.storyCompleted, isFalse, reason: 'word $i is not the last word');
      }

      final finalResult = machine.apply(const WordAccepted(index: 3));
      expect(finalResult.storyCompleted, isTrue);
      expect(finalResult.snapshot.isStoryComplete, isTrue);
      expect(finalResult.snapshot.currentIndex, -1);
      expect(
        finalResult.snapshot.currentPageWords.every((w) => w.lifecycle == WordLifecycle.done),
        isTrue,
      );
    });
  });

  group('POSITIVE: wordAcceptedNearMiss exposes the near-miss distinction to observers', () {
    test('resolution is acceptedNearMiss, not plain accepted (for analytics/near-miss prompt)', () {
      final machine = _machine([
        ['gat', 'sat'], // "gat" near-miss accepted as "cat"-like word for fixture purposes
      ]);
      final result = machine.apply(const WordAcceptedNearMiss(index: 0));

      final word0 = result.snapshot.currentPageWords[0];
      expect(word0.lifecycle, WordLifecycle.done);
      expect(word0.resolution, WordResolution.acceptedNearMiss);
      expect(word0.resolution, isNot(WordResolution.accepted));
    });
  });

  group('POSITIVE: wordHelped transitions to helped → done(green), tier retained for WordHelpRecord', () {
    test('Tier 1 (soundOut) help resolves the word and retains the tier', () {
      final machine = _machine([
        ['the', 'cat'],
      ]);
      final result = machine.apply(const WordHelped(index: 0, tier: HelpLevel.soundOut));

      final word0 = result.snapshot.currentPageWords[0];
      expect(word0.lifecycle, WordLifecycle.done);
      expect(word0.resolution, WordResolution.helped);
      expect(word0.helpTier, HelpLevel.soundOut);
      expect(result.snapshot.currentIndex, 1);
    });

    test('Tier 2 (modeled) help resolves the word and retains the tier', () {
      final machine = _machine([
        ['the', 'cat'],
      ]);
      final result = machine.apply(const WordHelped(index: 0, tier: HelpLevel.modeled));

      final word0 = result.snapshot.currentPageWords[0];
      expect(word0.resolution, WordResolution.helped);
      expect(word0.helpTier, HelpLevel.modeled);
    });

    test('accepted and helped words are visually indistinguishable (render-state parity)', () {
      final acceptedMachine = _machine([
        ['cat'],
      ]);
      acceptedMachine.apply(const WordAccepted(index: 0));

      final helpedMachine = _machine([
        ['cat'],
      ]);
      helpedMachine.apply(const WordHelped(index: 0, tier: HelpLevel.modeled));

      final acceptedRender = acceptedMachine.snapshot.currentPageWords[0].renderColor;
      final helpedRender = helpedMachine.snapshot.currentPageWords[0].renderColor;
      expect(
        helpedRender,
        acceptedRender,
        reason: 'helped renders identically to accepted (Unit 1/6 ratified, no visible marker)',
      );
      // But the underlying resolution DOES differ, for WordHelpRecord writers:
      expect(
        acceptedMachine.snapshot.currentPageWords[0].resolution,
        isNot(helpedMachine.snapshot.currentPageWords[0].resolution),
      );
    });
  });

  group('POSITIVE: struggleDetected sets a current-word marker', () {
    test('struggleDetected on the current word sets struggling without changing lifecycle', () {
      final machine = _machine([
        ['the', 'cat'],
      ]);
      final result = machine.apply(const StruggleDetected(index: 0));

      final word0 = result.snapshot.currentPageWords[0];
      expect(word0.lifecycle, WordLifecycle.current);
      expect(word0.struggling, isTrue);
      expect(result.pageCompleted, isFalse);
      expect(result.storyCompleted, isFalse);
    });

    test('struggling clears once the word resolves (accepted after being struggled)', () {
      final machine = _machine([
        ['the', 'cat'],
      ]);
      machine.apply(const StruggleDetected(index: 0));
      final result = machine.apply(const WordAccepted(index: 0));

      final word0 = result.snapshot.currentPageWords[0];
      expect(word0.lifecycle, WordLifecycle.done);
      expect(word0.struggling, isFalse);
    });

    test('struggling clears once the word resolves via help', () {
      final machine = _machine([
        ['the', 'cat'],
      ]);
      machine.apply(const StruggleDetected(index: 0));
      final result = machine.apply(const WordHelped(index: 0, tier: HelpLevel.soundOut));

      expect(result.snapshot.currentPageWords[0].struggling, isFalse);
    });
  });

  group('POSITIVE: fixture event stream drives the machine (no recognition logic of its own)', () {
    test('a realistic mixed script (accept, struggle+help, accept) produces the exact expected sequence', () async {
      final machine = _machine([
        ['the', 'dog', 'ran', 'fast'],
      ]);
      final tracker = FakeReadingTracker(
        script: const [
          WordAccepted(index: 0),
          StruggleDetected(index: 1),
          WordHelped(index: 1, tier: HelpLevel.soundOut),
          WordAcceptedNearMiss(index: 2),
          WordAccepted(index: 3),
        ],
      );

      WordStateResult? lastResult;
      await for (final event in tracker.eventsStream) {
        lastResult = machine.apply(event);
      }

      expect(lastResult, isNotNull);
      expect(lastResult!.storyCompleted, isTrue);
      expect(machine.snapshot.currentPageWords, [
        WordState(index: 0, lifecycle: WordLifecycle.done, resolution: WordResolution.accepted),
        WordState(
          index: 1,
          lifecycle: WordLifecycle.done,
          resolution: WordResolution.helped,
          helpTier: HelpLevel.soundOut,
        ),
        WordState(index: 2, lifecycle: WordLifecycle.done, resolution: WordResolution.acceptedNearMiss),
        WordState(index: 3, lifecycle: WordLifecycle.done, resolution: WordResolution.accepted),
      ]);
    });
  });

  group('NEGATIVE: out-of-range indices are ignored without state corruption', () {
    test('wordAccepted with a negative index is a no-op', () {
      final machine = _machine([
        ['the', 'cat'],
      ]);
      final before = machine.snapshot.currentPageWords;
      final result = machine.apply(const WordAccepted(index: -1));

      expect(result.snapshot.currentPageWords, before);
      expect(result.snapshot.currentIndex, 0);
      expect(result.pageCompleted, isFalse);
      expect(result.storyCompleted, isFalse);
    });

    test('wordAccepted with an index beyond the page length is a no-op', () {
      final machine = _machine([
        ['the', 'cat'],
      ]);
      final before = machine.snapshot.currentPageWords;
      final result = machine.apply(const WordAccepted(index: 99));

      expect(result.snapshot.currentPageWords, before);
      expect(result.snapshot.currentIndex, 0);
    });

    test('wordAcceptedNearMiss out of range is a no-op', () {
      final machine = _machine([
        ['the', 'cat'],
      ]);
      final before = machine.snapshot.currentPageWords;
      machine.apply(const WordAcceptedNearMiss(index: 50));
      expect(machine.snapshot.currentPageWords, before);
    });

    test('wordHelped out of range is a no-op', () {
      final machine = _machine([
        ['the', 'cat'],
      ]);
      final before = machine.snapshot.currentPageWords;
      machine.apply(const WordHelped(index: -5, tier: HelpLevel.soundOut));
      expect(machine.snapshot.currentPageWords, before);
    });

    test('struggleDetected out of range is a no-op', () {
      final machine = _machine([
        ['the', 'cat'],
      ]);
      final before = machine.snapshot.currentPageWords;
      machine.apply(const StruggleDetected(index: 100));
      expect(machine.snapshot.currentPageWords, before);
    });

    test('applying an in-range event does not throw even immediately after an out-of-range one', () {
      final machine = _machine([
        ['the', 'cat'],
      ]);
      machine.apply(const WordAccepted(index: -1));
      expect(() => machine.apply(const WordAccepted(index: 0)), returnsNormally);
      expect(machine.snapshot.currentPageWords[0].lifecycle, WordLifecycle.done);
    });
  });

  group('NEGATIVE: done words never revert (no state regression)', () {
    test('re-applying wordAccepted to an already-done word does not corrupt state or move current backwards', () {
      final machine = _machine([
        ['the', 'cat', 'sat'],
      ]);
      machine.apply(const WordAccepted(index: 0));
      final afterFirst = machine.snapshot.currentPageWords;
      expect(machine.snapshot.currentIndex, 1);

      final result = machine.apply(const WordAccepted(index: 0));

      expect(result.snapshot.currentPageWords, afterFirst);
      expect(result.snapshot.currentIndex, 1, reason: 'current must not regress to an already-done index');
    });

    test('re-applying an event to an already-helped word does not overwrite its resolution to accepted', () {
      final machine = _machine([
        ['the', 'cat'],
      ]);
      machine.apply(const WordHelped(index: 0, tier: HelpLevel.modeled));
      expect(machine.snapshot.currentPageWords[0].resolution, WordResolution.helped);

      machine.apply(const WordAccepted(index: 0));

      expect(
        machine.snapshot.currentPageWords[0].resolution,
        WordResolution.helped,
        reason: 'a done word\'s resolution must never be overwritten by a later event',
      );
      expect(machine.snapshot.currentPageWords[0].helpTier, HelpLevel.modeled);
    });

    test('wordHelped targeting an already-accepted word does not flip its resolution to helped', () {
      final machine = _machine([
        ['the', 'cat'],
      ]);
      machine.apply(const WordAccepted(index: 0));

      machine.apply(const WordHelped(index: 0, tier: HelpLevel.soundOut));

      expect(machine.snapshot.currentPageWords[0].resolution, WordResolution.accepted);
      expect(machine.snapshot.currentPageWords[0].helpTier, isNull);
    });
  });

  group('NEGATIVE: events targeting a non-current, not-yet-reached word are ignored', () {
    test('wordHelped for a future unread word does not prematurely resolve it', () {
      final machine = _machine([
        ['the', 'cat', 'sat'],
      ]);
      // currentIndex is 0; target index 2 is still unread and not current.
      machine.apply(const WordHelped(index: 2, tier: HelpLevel.soundOut));

      expect(machine.snapshot.currentPageWords[2].lifecycle, WordLifecycle.unread);
      expect(machine.snapshot.currentIndex, 0);
    });

    test('struggleDetected for a non-current index does not set struggling on any word', () {
      final machine = _machine([
        ['the', 'cat', 'sat'],
      ]);
      machine.apply(const StruggleDetected(index: 2));

      expect(machine.snapshot.currentPageWords.any((w) => w.struggling), isFalse);
    });
  });

  group('NEGATIVE: silence carries no state-machine logic (no timers here)', () {
    test('a silence event never changes any word state (Unit 6 owns silence→struggle timing)', () {
      final machine = _machine([
        ['the', 'cat'],
      ]);
      final before = machine.snapshot.currentPageWords;
      final result = machine.apply(const Silence(duration: Duration(seconds: 4)));

      expect(result.snapshot.currentPageWords, before);
      expect(result.snapshot.currentIndex, 0);
      expect(result.pageCompleted, isFalse);
      expect(result.storyCompleted, isFalse);
    });
  });

  group('NEGATIVE: events after story completion are inert', () {
    test('apply() after the story is complete does not throw, re-signal completion, or mutate state', () {
      final machine = _machine([
        ['only'],
      ]);
      final completion = machine.apply(const WordAccepted(index: 0));
      expect(completion.storyCompleted, isTrue);

      final after = machine.apply(const WordAccepted(index: 0));

      expect(after.storyCompleted, isFalse, reason: 'completion signals fire once, not repeatedly');
      expect(after.snapshot.isStoryComplete, isTrue);
      expect(after.snapshot.currentIndex, -1);
      expect(after.snapshot.currentPageWords, completion.snapshot.currentPageWords);
    });
  });

  group('EDGE: single-word story completes on the very first event', () {
    test('one word, one wordAccepted event -> immediate story completion', () {
      final machine = _machine([
        ['done'],
      ]);
      final result = machine.apply(const WordAccepted(index: 0));

      expect(result.storyCompleted, isTrue);
      expect(result.pageCompleted, isFalse);
      expect(result.snapshot.currentIndex, -1);
      expect(result.snapshot.currentPageWords.single.lifecycle, WordLifecycle.done);
    });
  });

  group('EDGE: exactly-one-current invariant holds across a full run', () {
    test('at every step of a 5-word sentence exactly one word is current, until completion', () {
      final machine = _machine([
        ['one', 'two', 'three', 'four', 'five'],
      ]);
      for (var i = 0; i < 5; i++) {
        _expectExactlyOneCurrent(machine.snapshot.currentPageWords);
        machine.apply(WordAccepted(index: i));
      }
      // After the final word resolves, no word is current any more.
      expect(
        machine.snapshot.currentPageWords.any((w) => w.lifecycle == WordLifecycle.current),
        isFalse,
      );
    });
  });
}

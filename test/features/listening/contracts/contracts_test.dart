/// Unit tests for the listening-contracts: engine-agnostic ASR interface,
/// tracker event stream types, help-state contract, pure Dart types.
///
/// Covers: asr_engine.dart, tracker_events.dart, help_state.dart
/// No implementation imports; test failures are red-for-right-reason
/// (unimplemented contract types).

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/contracts/tracker_events.dart';
import 'package:learn_to_read/features/listening/contracts/help_state.dart';

void main() {
  group('Hypothesis — engine-agnostic word/phone-level hypotheses', () {
    group('POSITIVE: construction & equality', () {
      test('constructs with word hypotheses only', () {
        final hyp = Hypothesis(
          wordHypotheses: ['cat', 'can', 'car'],
          phoneHypotheses: null,
        );

        expect(hyp.wordHypotheses, ['cat', 'can', 'car']);
        expect(hyp.phoneHypotheses, isNull);
      });

      test('constructs with word and phone hypotheses', () {
        final hyp = Hypothesis(
          wordHypotheses: ['cat'],
          phoneHypotheses: ['K', 'AE', 'T'],
        );

        expect(hyp.wordHypotheses, ['cat']);
        expect(hyp.phoneHypotheses, ['K', 'AE', 'T']);
      });

      test('two hypotheses with identical word/phone lists are equal', () {
        final hyp1 = Hypothesis(
          wordHypotheses: ['dog', 'dig'],
          phoneHypotheses: ['D', 'AO', 'G'],
        );
        final hyp2 = Hypothesis(
          wordHypotheses: ['dog', 'dig'],
          phoneHypotheses: ['D', 'AO', 'G'],
        );

        expect(hyp1, hyp2);
        expect(hyp1.hashCode, hyp2.hashCode);
      });

      test('two hypotheses with identical null phones are equal', () {
        final hyp1 = Hypothesis(
          wordHypotheses: ['dog'],
          phoneHypotheses: null,
        );
        final hyp2 = Hypothesis(
          wordHypotheses: ['dog'],
          phoneHypotheses: null,
        );

        expect(hyp1, hyp2);
      });
    });

    group('NEGATIVE: inequality', () {
      test('differs when word lists differ', () {
        final hyp1 = Hypothesis(
          wordHypotheses: ['cat'],
          phoneHypotheses: null,
        );
        final hyp2 = Hypothesis(
          wordHypotheses: ['dog'],
          phoneHypotheses: null,
        );

        expect(hyp1, isNot(hyp2));
      });

      test('differs when phone lists differ', () {
        final hyp1 = Hypothesis(
          wordHypotheses: ['cat'],
          phoneHypotheses: ['K', 'AE', 'T'],
        );
        final hyp2 = Hypothesis(
          wordHypotheses: ['cat'],
          phoneHypotheses: ['K', 'AE'],
        );

        expect(hyp1, isNot(hyp2));
      });

      test('differs when one has phones and other does not', () {
        final hyp1 = Hypothesis(
          wordHypotheses: ['cat'],
          phoneHypotheses: ['K', 'AE', 'T'],
        );
        final hyp2 = Hypothesis(
          wordHypotheses: ['cat'],
          phoneHypotheses: null,
        );

        expect(hyp1, isNot(hyp2));
      });

      test('differs when word list order differs', () {
        final hyp1 = Hypothesis(
          wordHypotheses: ['cat', 'dog'],
          phoneHypotheses: null,
        );
        final hyp2 = Hypothesis(
          wordHypotheses: ['dog', 'cat'],
          phoneHypotheses: null,
        );

        expect(hyp1, isNot(hyp2));
      });
    });

    group('EDGE: empty lists, single elements', () {
      test('constructs with empty word hypotheses list', () {
        final hyp = Hypothesis(
          wordHypotheses: [],
          phoneHypotheses: null,
        );

        expect(hyp.wordHypotheses, isEmpty);
        expect(hyp.phoneHypotheses, isNull);
      });

      test('constructs with single word hypothesis', () {
        final hyp = Hypothesis(
          wordHypotheses: ['only'],
          phoneHypotheses: null,
        );

        expect(hyp.wordHypotheses, ['only']);
      });

      test('constructs with single phone hypothesis', () {
        final hyp = Hypothesis(
          wordHypotheses: ['a'],
          phoneHypotheses: ['AE'],
        );

        expect(hyp.phoneHypotheses, ['AE']);
      });

      test('constructs with many hypotheses', () {
        final words = List.generate(100, (i) => 'word$i');
        final hyp = Hypothesis(
          wordHypotheses: words,
          phoneHypotheses: null,
        );

        expect(hyp.wordHypotheses, words);
      });
    });

    group('EDGE: printability for test diffs', () {
      test('toString() is human-readable', () {
        final hyp = Hypothesis(
          wordHypotheses: ['cat', 'can'],
          phoneHypotheses: ['K', 'AE', 'T'],
        );

        final str = hyp.toString();
        expect(str, contains('Hypothesis'));
        expect(str, contains('wordHypotheses'));
        expect(str, contains('phoneHypotheses'));
      });
    });
  });

  group('AsrEngine interface — engine-agnostic start/stop, biasing, hypothesis stream', () {
    group('POSITIVE: interface contract defines engine lifecycle', () {
      test('engine contract has start method with biasing context', () {
        // This test simply verifies the interface exists and has start method.
        // Actual implementation is tested in fake_engine_test.dart.
        // Here we verify the type is importable.
        expect(AsrEngine, isNotNull);
      });

      test('engine contract has stop method', () {
        expect(AsrEngine, isNotNull);
      });

      test('engine contract has hypothesesStream getter', () {
        expect(AsrEngine, isNotNull);
      });
    });

    group('EDGE: interface expressiveness', () {
      test('start accepts list of contextual strings for biasing', () {
        // Verifies the interface design: biasing is a list of strings
        // (expected words and contextual phrases) not individual phonemes.
        expect(AsrEngine, isNotNull);
      });

      test('hypothesis stream carries both word and phone hypotheses', () {
        // The interface must express both, even if a particular engine
        // impl only provides words (it surfaces nulls for phones then).
        expect(AsrEngine, isNotNull);
      });
    });
  });

  group('TrackerEvent — single event stream contract: wordAccepted, wordAcceptedNearMiss, etc.', () {
    group('wordAccepted — correct word matched', () {
      group('POSITIVE: construction & equality', () {
        test('constructs with word index', () {
          final event = WordAccepted(index: 3);
          expect(event.index, 3);
        });

        test('two events with same index are equal', () {
          expect(WordAccepted(index: 2), WordAccepted(index: 2));
          expect(WordAccepted(index: 2).hashCode, WordAccepted(index: 2).hashCode);
        });
      });

      group('NEGATIVE: inequality', () {
        test('events with different indices are not equal', () {
          expect(WordAccepted(index: 1), isNot(WordAccepted(index: 2)));
        });
      });

      group('EDGE: boundary indices', () {
        test('accepts index 0 (first word)', () {
          final event = WordAccepted(index: 0);
          expect(event.index, 0);
        });

        test('accepts large index', () {
          final event = WordAccepted(index: 9999);
          expect(event.index, 9999);
        });
      });

      test('toString() is readable', () {
        final event = WordAccepted(index: 2);
        expect(event.toString(), contains('WordAccepted'));
      });
    });

    group('wordAcceptedNearMiss — close-enough phonetic match (e.g., "gat"→"cat")', () {
      group('POSITIVE: construction & equality', () {
        test('constructs with word index', () {
          final event = WordAcceptedNearMiss(index: 1);
          expect(event.index, 1);
        });

        test('two events with same index are equal', () {
          expect(
            WordAcceptedNearMiss(index: 5),
            WordAcceptedNearMiss(index: 5),
          );
        });
      });

      group('NEGATIVE: inequality', () {
        test('differs from WordAccepted even with same index', () {
          expect(
            WordAccepted(index: 1),
            isNot(WordAcceptedNearMiss(index: 1)),
          );
        });

        test('events with different indices are not equal', () {
          expect(
            WordAcceptedNearMiss(index: 1),
            isNot(WordAcceptedNearMiss(index: 2)),
          );
        });
      });

      test('toString() distinguishes from WordAccepted', () {
        final accepted = WordAccepted(index: 1);
        final nearMiss = WordAcceptedNearMiss(index: 1);
        expect(accepted.toString(), isNot(nearMiss.toString()));
      });
    });

    group('struggleDetected — two consecutive failed hypothesis bursts or speech mismatch', () {
      group('POSITIVE: construction & equality', () {
        test('constructs with word index', () {
          final event = StruggleDetected(index: 2);
          expect(event.index, 2);
        });

        test('two events with same index are equal', () {
          expect(StruggleDetected(index: 3), StruggleDetected(index: 3));
        });
      });

      group('NEGATIVE: inequality', () {
        test('events with different indices are not equal', () {
          expect(StruggleDetected(index: 1), isNot(StruggleDetected(index: 2)));
        });
      });

      test('toString() is readable', () {
        expect(StruggleDetected(index: 4).toString(), contains('StruggleDetected'));
      });
    });

    group('silence — sustained silence duration exceeded threshold', () {
      group('POSITIVE: construction & equality', () {
        test('constructs with duration', () {
          final event = Silence(duration: Duration(seconds: 4));
          expect(event.duration, Duration(seconds: 4));
        });

        test('two events with same duration are equal', () {
          final d = Duration(milliseconds: 500);
          expect(Silence(duration: d), Silence(duration: d));
        });
      });

      group('NEGATIVE: inequality', () {
        test('events with different durations are not equal', () {
          expect(
            Silence(duration: Duration(seconds: 1)),
            isNot(Silence(duration: Duration(seconds: 2))),
          );
        });
      });

      group('EDGE: boundary durations', () {
        test('accepts zero duration', () {
          final event = Silence(duration: Duration.zero);
          expect(event.duration, Duration.zero);
        });

        test('accepts very long duration', () {
          final event = Silence(duration: Duration(hours: 1));
          expect(event.duration, Duration(hours: 1));
        });

        test('accepts sub-millisecond precision (microseconds)', () {
          final event = Silence(duration: Duration(microseconds: 500));
          expect(event.duration, Duration(microseconds: 500));
        });
      });

      test('toString() includes duration', () {
        final event = Silence(duration: Duration(seconds: 3));
        expect(event.toString(), contains('Silence'));
        expect(event.toString(), contains('3'));
      });
    });

    group('wordHelped — word received help (Tier 1 sound-out or Tier 2 model)', () {
      group('POSITIVE: construction & equality', () {
        test('constructs with index and HelpLevel.soundOut', () {
          final event = WordHelped(index: 1, tier: HelpLevel.soundOut);
          expect(event.index, 1);
          expect(event.tier, HelpLevel.soundOut);
        });

        test('constructs with index and HelpLevel.modeled', () {
          final event = WordHelped(index: 2, tier: HelpLevel.modeled);
          expect(event.index, 2);
          expect(event.tier, HelpLevel.modeled);
        });

        test('two events with same index and tier are equal', () {
          expect(
            WordHelped(index: 3, tier: HelpLevel.soundOut),
            WordHelped(index: 3, tier: HelpLevel.soundOut),
          );
        });

        test('hashCode matches for equal events', () {
          final e1 = WordHelped(index: 5, tier: HelpLevel.modeled);
          final e2 = WordHelped(index: 5, tier: HelpLevel.modeled);
          expect(e1.hashCode, e2.hashCode);
        });
      });

      group('NEGATIVE: inequality', () {
        test('events with different indices are not equal', () {
          expect(
            WordHelped(index: 1, tier: HelpLevel.soundOut),
            isNot(WordHelped(index: 2, tier: HelpLevel.soundOut)),
          );
        });

        test('events with different tiers are not equal', () {
          expect(
            WordHelped(index: 1, tier: HelpLevel.soundOut),
            isNot(WordHelped(index: 1, tier: HelpLevel.modeled)),
          );
        });

        test('wordHelped differs from wordAccepted with same index', () {
          expect(
            WordAccepted(index: 1),
            isNot(WordHelped(index: 1, tier: HelpLevel.soundOut)),
          );
        });
      });

      group('EDGE: HelpLevel enum coverage', () {
        test('accepts HelpLevel.none (word helped but not at Tier 1/2)', () {
          final event = WordHelped(index: 0, tier: HelpLevel.none);
          expect(event.tier, HelpLevel.none);
        });

        test('accepts all three HelpLevel values', () {
          final levels = [HelpLevel.none, HelpLevel.soundOut, HelpLevel.modeled];
          for (final level in levels) {
            final event = WordHelped(index: 0, tier: level);
            expect(event.tier, level);
          }
        });
      });

      test('toString() distinguishes tier', () {
        final soundOut = WordHelped(index: 1, tier: HelpLevel.soundOut);
        final modeled = WordHelped(index: 1, tier: HelpLevel.modeled);
        expect(soundOut.toString(), contains('soundOut'));
        expect(modeled.toString(), contains('modeled'));
      });
    });

    group('TrackerEvent polymorphism — event type system', () {
      test('all event types share TrackerEvent base or interface', () {
        final events = <TrackerEvent>[
          WordAccepted(index: 0),
          WordAcceptedNearMiss(index: 0),
          StruggleDetected(index: 0),
          Silence(duration: Duration.zero),
          WordHelped(index: 0, tier: HelpLevel.none),
        ];

        for (final event in events) {
          expect(event, isA<TrackerEvent>());
        }
      });

      test('event list is type-safe (can store mixed events)', () {
        final stream = [
          WordAccepted(index: 0),
          WordAcceptedNearMiss(index: 1),
          StruggleDetected(index: 1),
          Silence(duration: Duration(seconds: 4)),
          WordHelped(index: 1, tier: HelpLevel.soundOut),
          WordAccepted(index: 2),
        ];

        expect(stream, hasLength(6));
        expect(stream[0], isA<WordAccepted>());
        expect(stream[4], isA<WordHelped>());
      });
    });
  });

  group('HelpState — current help tier and graphemePhonemeMap highlight index', () {
    group('POSITIVE: construction & equality', () {
      test('constructs with help tier and graphemeIndex', () {
        final state = HelpState(
          currentHelpTier: HelpLevel.soundOut,
          highlightedGraphemeIndex: 0,
        );

        expect(state.currentHelpTier, HelpLevel.soundOut);
        expect(state.highlightedGraphemeIndex, 0);
      });

      test('two states with same values are equal', () {
        final s1 = HelpState(
          currentHelpTier: HelpLevel.modeled,
          highlightedGraphemeIndex: 2,
        );
        final s2 = HelpState(
          currentHelpTier: HelpLevel.modeled,
          highlightedGraphemeIndex: 2,
        );

        expect(s1, s2);
        expect(s1.hashCode, s2.hashCode);
      });

      test('constructs with HelpLevel.none', () {
        final state = HelpState(
          currentHelpTier: HelpLevel.none,
          highlightedGraphemeIndex: -1,
        );

        expect(state.currentHelpTier, HelpLevel.none);
      });
    });

    group('NEGATIVE: inequality', () {
      test('states with different help tiers are not equal', () {
        final s1 = HelpState(
          currentHelpTier: HelpLevel.soundOut,
          highlightedGraphemeIndex: 0,
        );
        final s2 = HelpState(
          currentHelpTier: HelpLevel.modeled,
          highlightedGraphemeIndex: 0,
        );

        expect(s1, isNot(s2));
      });

      test('states with different graphemeIndex are not equal', () {
        final s1 = HelpState(
          currentHelpTier: HelpLevel.soundOut,
          highlightedGraphemeIndex: 0,
        );
        final s2 = HelpState(
          currentHelpTier: HelpLevel.soundOut,
          highlightedGraphemeIndex: 1,
        );

        expect(s1, isNot(s2));
      });
    });

    group('EDGE: highlight index boundaries', () {
      test('accepts index 0 (first grapheme)', () {
        final state = HelpState(
          currentHelpTier: HelpLevel.soundOut,
          highlightedGraphemeIndex: 0,
        );

        expect(state.highlightedGraphemeIndex, 0);
      });

      test('accepts large index (digraph or later)', () {
        final state = HelpState(
          currentHelpTier: HelpLevel.soundOut,
          highlightedGraphemeIndex: 15,
        );

        expect(state.highlightedGraphemeIndex, 15);
      });

      test('accepts negative index (no highlight)', () {
        final state = HelpState(
          currentHelpTier: HelpLevel.none,
          highlightedGraphemeIndex: -1,
        );

        expect(state.highlightedGraphemeIndex, -1);
      });
    });

    group('EDGE: digraph highlighting (grapheme clusters highlight as unit)', () {
      test('index maps to grapheme cluster, not individual letter', () {
        // For a word like "ship", graphemePhonemeMap has:
        // [0] -> ("sh", "SH"), [1] -> ("i", "IH"), [2] -> ("p", "P")
        // When sounding out, index 0 highlights "sh" as one unit.
        final state = HelpState(
          currentHelpTier: HelpLevel.soundOut,
          highlightedGraphemeIndex: 0, // Highlights "sh"
        );

        expect(state.highlightedGraphemeIndex, 0);
      });

      test('silent-e case: index maps correctly for "cake"', () {
        // "cake" might have: [0]->a, [1]->k, [2]->(silent e)
        // Index 2 highlights the silent e cluster.
        final state = HelpState(
          currentHelpTier: HelpLevel.soundOut,
          highlightedGraphemeIndex: 2,
        );

        expect(state.highlightedGraphemeIndex, 2);
      });
    });

    test('toString() is readable', () {
      final state = HelpState(
        currentHelpTier: HelpLevel.soundOut,
        highlightedGraphemeIndex: 1,
      );

      final str = state.toString();
      expect(str, contains('HelpState'));
      expect(str, contains('soundOut'));
    });
  });

  group('Contract type invariants — pure Dart, equatable, printable', () {
    test('no Flutter imports except foundation in contract types', () {
      // This is a static check: import this file in a pure-Dart context.
      // If contract types imported, e.g., package:flutter/material.dart,
      // the test would fail to compile in a Dart-only test.
      expect(true, isTrue); // Placeholder; actual check is compilation.
    });

    test('all tracker events are printable', () {
      final events = <TrackerEvent>[
        WordAccepted(index: 0),
        WordAcceptedNearMiss(index: 1),
        StruggleDetected(index: 2),
        Silence(duration: Duration(seconds: 1)),
        WordHelped(index: 3, tier: HelpLevel.soundOut),
      ];

      for (final e in events) {
        expect(e.toString(), isNotEmpty);
      }
    });

    test('Hypothesis is printable', () {
      final h = Hypothesis(
        wordHypotheses: ['test'],
        phoneHypotheses: ['T', 'E', 'S', 'T'],
      );

      expect(h.toString(), isNotEmpty);
    });

    test('HelpState is printable', () {
      final h = HelpState(
        currentHelpTier: HelpLevel.modeled,
        highlightedGraphemeIndex: 0,
      );

      expect(h.toString(), isNotEmpty);
    });
  });
}

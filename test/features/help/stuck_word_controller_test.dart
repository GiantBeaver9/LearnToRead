// Pins the API of lib/features/help/stuck_word_controller.dart (PRD §8
// Unit 6 "Stuck-word scaffold (tiered help)"; §5 WordHelpRecord; §7 R7;
// ticket stuck-word-scaffold accept entries 1, 3, 4, 8, 9). This suite is
// authored before the implementation exists, so it is EXPECTED to fail to
// compile until stuck_word_controller.dart (and its sibling files
// sound_out_sequence.dart, near_miss_prompt.dart, help_recorder.dart) are
// written with exactly the shapes exercised below.
//
// Pinned API surface this suite requires (the whole Unit 6 feature -- other
// suites in this ticket import the same shapes; this header is the primary
// reference, restated more briefly in the sibling test files):
//
//   // lib/features/help/sound_out_sequence.dart
//   class SoundOutSequence {
//     SoundOutSequence({required PhonemeSequencer phonemeSequencer});
//     Stream<HelpState> play(WordToken word, {AudioChannel channel = AudioChannel.help});
//   }
//
//   // lib/features/help/near_miss_prompt.dart
//   class NearMissPrompt {
//     NearMissPrompt({required AudioService audioService, required AudioRef promptLineAudioRef});
//     Future<void> play(WordToken word);
//   }
//
//   // lib/features/help/help_recorder.dart
//   abstract class HelpRecorderApi {
//     Future<void> recordResolution({required WordToken word, required HelpLevel tier});
//   }
//   class HelpRecorder implements HelpRecorderApi {
//     HelpRecorder({required WordHelpDao wordHelpDao, required String profileId});
//   }
//
//   // lib/features/help/stuck_word_controller.dart
//   class StuckWordController {
//     StuckWordController({
//       required Stream<TrackerEvent> events,
//       required SoundOutSequence soundOutSequence,
//       required AudioService audioService,
//       required NearMissPrompt nearMissPrompt,
//       required HelpRecorderApi helpRecorder,
//       required AudioRef yourTurnPromptAudioRef,
//       Duration t1 = kStruggleT1,
//       Duration t2 = kTier2WaitT2,
//       void Function(int index, HelpLevel tier)? onHelpGiven,
//     });
//     Stream<HelpState> get helpState;
//     Stream<WordHelped> get wordHelpedStream;
//     void watchWord({required int index, required WordToken word});
//     void dispose();
//   }
//
// Contract this suite locks in (builder-mechanical design choices made by
// this test suite, since the ticket leaves exact shapes to the builder and
// only pins behavior):
//  - `watchWord` marks (index, word) as the word currently being read and
//    (re)starts its own T1 silence timer from that call -- listening-tracker
//    (Unit 4's sustained-silence-driven struggleDetected) is not a merged
//    dependency of this ticket, so the controller owns a direct T1 timer as
//    the "sustained silence" half of the pinned trigger; an incoming
//    `StruggleDetected` for the watched index, or a `Silence` event for the
//    watched index whose `duration >= t1`, short-circuits that timer and
//    starts Tier 1 immediately. A `Silence` event with `duration < t1` is
//    informational only.
//  - Calling `watchWord` again (a new current word) cancels any still-
//    pending timer/subscription for the previous word -- no stale Tier 1/2
//    can fire for a word that is no longer current.
//  - `WordAccepted(index)` for the watched index before Tier 1 has started
//    resolves the word as plain-accepted: `tier = HelpLevel.none`,
//    `helpRecorder.recordResolution` is called (so the §4.3 encounter
//    denominator always increments) but NO `WordHelped` is emitted on
//    `wordHelpedStream` and no help audio ever plays.
//  - `WordAccepted(index)` for the watched index at any point once Tier 1
//    has started (during the phoneme playback itself or during the
//    following T2 wait) resolves the word `helped(soundOut)`:
//    `wordHelpedStream` emits `WordHelped(index, HelpLevel.soundOut)`,
//    `onHelpGiven(index, HelpLevel.soundOut)` fires, and
//    `helpRecorder.recordResolution(tier: HelpLevel.soundOut)` is called.
//    Any still-pending phoneme playback for that word is not force-played
//    further once resolved.
//  - If Tier 1's sound-out finishes (the `SoundOutSequence.play` stream
//    closes) with no accepting event, the controller waits `t2` and then
//    starts Tier 2: plays the word's whole pronunciation
//    (`WordToken.pronunciationAudioRef`) on `AudioChannel.help`, then the
//    injected `yourTurnPromptAudioRef`, also on `AudioChannel.help`.
//  - Once Tier 2's own audio has been dispatched, `WordAccepted(index)`
//    resolves `helped(modeled)` the same way as the soundOut case above
//    (repeat-accepted path).
//  - If Tier 2's own two clips finish with no accepting event, the
//    controller waits one more `t2` and, with still no accepting event,
//    resolves the word `helped(modeled)` on its own (timeout-accepted
//    path) -- this is the "never hard-blocks" guarantee (see also
//    never_blocked_test.dart).
//  - `HelpState` is published on `helpState` throughout Tier 1 (tier
//    `soundOut`, one event per played grapheme cluster, forwarded verbatim
//    from `SoundOutSequence` -- see sound_out_highlight_test.dart) and at
//    the start of Tier 2 (a single `HelpState(currentHelpTier: modeled,
//    highlightedGraphemeIndex: -1)`, since Tier 2 has no per-grapheme
//    highlight). On any resolution the controller publishes
//    `HelpState(currentHelpTier: none, highlightedGraphemeIndex: -1)`.
//  - Events for an index other than the currently-watched one are ignored
//    entirely (no state change, no audio, no recorder call). Events for an
//    index that has already resolved are likewise ignored (no double
//    recording, no duplicate `WordHelped`).
//  - `t1`/`t2` are optional constructor overrides (default to
//    `kStruggleT1`/`kTier2WaitT2` from tuning.dart) supporting per-level
//    timing profiles (PRD §7 R7) without touching this controller's code.
//  - `onHelpGiven` is the `help_given(tier)` analytics emission hook
//    (ticket accept entry 8); it fires synchronously alongside every
//    `WordHelped` emission and never fires for a tier-`none` resolution.
//  - All help audio (phonemes, Tier 2's word + "your turn" line) is played
//    via the injected `AudioService` tagged `AudioChannel.help`, so it
//    ducks any active `ambient`/`celebration` playback per the pinned
//    `DuckingPolicy` (ticket accept entry 9) -- asserted here via
//    `FakeAudioService.callLog`'s `DuckLogEntry`s, never a hardcoded rule
//    reimplemented in this controller.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/domain/tuning.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/audio/phoneme_sequencer.dart';
import 'package:learn_to_read/features/help/help_recorder.dart';
import 'package:learn_to_read/features/help/near_miss_prompt.dart';
import 'package:learn_to_read/features/help/sound_out_sequence.dart';
import 'package:learn_to_read/features/help/stuck_word_controller.dart';
import 'package:learn_to_read/features/listening/contracts/help_state.dart';
import 'package:learn_to_read/features/listening/contracts/tracker_events.dart';

// ---------------------------------------------------------------------------
// Fixtures.
// ---------------------------------------------------------------------------

WordToken _wordShip() => WordToken(
  text: 'ship',
  graphemePhonemeMap: const [
    (graphemes: 'sh', phonemeId: 'SH'),
    (graphemes: 'i', phonemeId: 'IH'),
    (graphemes: 'p', phonemeId: 'P'),
  ],
  pronunciationAudioRef: 'audio/words/ship.wav',
);

WordToken _wordCat() => WordToken(
  text: 'cat',
  graphemePhonemeMap: const [
    (graphemes: 'c', phonemeId: 'K'),
    (graphemes: 'a', phonemeId: 'AE'),
    (graphemes: 't', phonemeId: 'T'),
  ],
  pronunciationAudioRef: 'audio/words/cat.wav',
);

const _phonemeAudioRefs = {
  'SH': 'audio/phonemes/SH.wav',
  'IH': 'audio/phonemes/IH.wav',
  'P': 'audio/phonemes/P.wav',
  'K': 'audio/phonemes/K.wav',
  'AE': 'audio/phonemes/AE.wav',
  'T': 'audio/phonemes/T.wav',
};

const _yourTurnRef = 'audio/prompts/your_turn.wav';
const _nearMissPromptRef = 'audio/prompts/that_is_it.wav';

/// A trivial, DB-free `HelpRecorderApi` test double: records every call it
/// receives in order, in memory. Keeps this suite's timer-choreography
/// tests decoupled from Drift/async-IO concerns (help_recorder_test.dart
/// covers the real `HelpRecorder` against an in-memory database).
class _RecordingHelpRecorder implements HelpRecorderApi {
  final List<({WordToken word, HelpLevel tier})> calls = [];

  @override
  Future<void> recordResolution({
    required WordToken word,
    required HelpLevel tier,
  }) async {
    calls.add((word: word, tier: tier));
  }
}

/// Bundles a freshly-wired `StuckWordController` with its collaborators and
/// a running collection of everything it has emitted, so tests can just
/// assert against `h.helpedEvents` / `h.helpStates` / `h.recorder.calls` /
/// `h.fake.callLog` without repeating the wiring.
class _Harness {
  _Harness({
    required this.fake,
    required this.recorder,
    required this.eventsController,
    required this.controller,
  }) {
    controller.helpState.listen(helpStates.add);
    controller.wordHelpedStream.listen(helpedEvents.add);
  }

  final FakeAudioService fake;
  final _RecordingHelpRecorder recorder;
  final StreamController<TrackerEvent> eventsController;
  final StuckWordController controller;

  final List<HelpState> helpStates = [];
  final List<WordHelped> helpedEvents = [];

  void dispose() {
    controller.dispose();
    unawaited(eventsController.close());
  }
}

_Harness _harness({
  Duration t1 = kStruggleT1,
  Duration t2 = kTier2WaitT2,
  List<(int, HelpLevel)>? onHelpGivenLog,
}) {
  final fake = FakeAudioService();
  final recorder = _RecordingHelpRecorder();
  final eventsController = StreamController<TrackerEvent>();
  final sequencer = PhonemeSequencer(
    audioService: fake,
    phonemeAudioRefs: _phonemeAudioRefs,
  );
  final controller = StuckWordController(
    events: eventsController.stream,
    soundOutSequence: SoundOutSequence(phonemeSequencer: sequencer),
    audioService: fake,
    nearMissPrompt: NearMissPrompt(
      audioService: fake,
      promptLineAudioRef: _nearMissPromptRef,
    ),
    helpRecorder: recorder,
    yourTurnPromptAudioRef: _yourTurnRef,
    t1: t1,
    t2: t2,
    onHelpGiven: onHelpGivenLog == null
        ? null
        : (index, tier) => onHelpGivenLog.add((index, tier)),
  );
  return _Harness(
    fake: fake,
    recorder: recorder,
    eventsController: eventsController,
    controller: controller,
  );
}

/// The handle of the most recently-started help-channel playback -- used to
/// drive a phoneme (or Tier 2 clip) to "natural completion" from the test.
PlaybackHandle _lastHelpPlay(FakeAudioService fake) => fake.callLog
    .whereType<PlayLogEntry>()
    .lastWhere((e) => e.channel == AudioChannel.help)
    .handle;

/// Completes the currently-playing help-channel clip and flushes
/// microtasks so the next queued clip (if any) starts, [count] times.
/// Models an idealized zero-latency audio engine so tests can focus on the
/// surrounding T1/T2 timers rather than on driving playback manually.
void _drainHelpClips(FakeAudioService fake, FakeAsync async, int count) {
  for (var i = 0; i < count; i++) {
    fake.completePlayback(_lastHelpPlay(fake));
    async.flushMicrotasks();
  }
}

void main() {
  group('POSITIVE: T1 trigger boundary (silence, no qualifying event)', () {
    test('Tier 1 does NOT start at 3.9s of silence', () {
      fakeAsync((async) {
        final h = _harness();
        h.controller.watchWord(index: 0, word: _wordShip());

        async.elapse(const Duration(milliseconds: 3900));

        expect(h.fake.callLog, isEmpty);
        h.dispose();
      });
    });

    test('Tier 1 starts at exactly T1 (4.0s) with no prior event', () {
      fakeAsync((async) {
        final h = _harness();
        h.controller.watchWord(index: 0, word: _wordShip());

        async.elapse(kStruggleT1);

        final plays = h.fake.callLog.whereType<PlayLogEntry>();
        expect(plays, hasLength(1));
        expect(plays.first.ref, 'audio/phonemes/SH.wav');
        expect(plays.first.channel, AudioChannel.help);
        expect(async.elapsed, kStruggleT1);
        h.dispose();
      });
    });

    test('Tier 1 has started by 4.1s of silence', () {
      fakeAsync((async) {
        final h = _harness();
        h.controller.watchWord(index: 0, word: _wordShip());

        async.elapse(const Duration(milliseconds: 4100));

        expect(h.fake.callLog.whereType<PlayLogEntry>(), hasLength(1));
        h.dispose();
      });
    });
  });

  group('POSITIVE: struggleDetected/Silence short-circuit the T1 timer', () {
    test('struggleDetected at 1s starts Tier 1 immediately, not at T1', () {
      fakeAsync((async) {
        final h = _harness();
        h.controller.watchWord(index: 0, word: _wordShip());
        async.elapse(const Duration(seconds: 1));

        h.eventsController.add(const StruggleDetected(index: 0));
        async.flushMicrotasks();

        expect(h.fake.callLog.whereType<PlayLogEntry>(), hasLength(1));
        expect(async.elapsed, const Duration(seconds: 1));
        h.dispose();
      });
    });

    test(
      'a Silence event with duration >= T1 for the watched word triggers Tier 1 immediately',
      () {
        fakeAsync((async) {
          final h = _harness();
          h.controller.watchWord(index: 0, word: _wordShip());
          async.elapse(const Duration(milliseconds: 500));

          h.eventsController.add(Silence(duration: kStruggleT1));
          async.flushMicrotasks();

          expect(h.fake.callLog.whereType<PlayLogEntry>(), hasLength(1));
          expect(async.elapsed, const Duration(milliseconds: 500));
          h.dispose();
        });
      },
    );

    test(
      'a Silence event with duration < T1 is informational only -- the T1 timer still governs',
      () {
        fakeAsync((async) {
          final h = _harness();
          h.controller.watchWord(index: 0, word: _wordShip());
          async.elapse(const Duration(seconds: 1));

          h.eventsController.add(
            const Silence(duration: Duration(seconds: 2)),
          );
          async.flushMicrotasks();
          expect(h.fake.callLog, isEmpty);

          async.elapse(const Duration(seconds: 3)); // total 4s == T1
          expect(h.fake.callLog.whereType<PlayLogEntry>(), hasLength(1));
          h.dispose();
        });
      },
    );
  });

  group(
    'POSITIVE: Tier 1 grapheme highlight is published via HelpState (soundOut tier)',
    () {
      test('helpState carries HelpLevel.soundOut for every Tier 1 event', () {
        fakeAsync((async) {
          final h = _harness();
          h.controller.watchWord(index: 0, word: _wordShip());
          async.elapse(kStruggleT1);
          _drainHelpClips(h.fake, async, 3);

          expect(h.helpStates, isNotEmpty);
          expect(
            h.helpStates
                .where((s) => s.highlightedGraphemeIndex >= 0)
                .every((s) => s.currentHelpTier == HelpLevel.soundOut),
            isTrue,
          );
          h.dispose();
        });
      });
    },
  );

  group(
    'POSITIVE: child speaks after Tier 1 -- no Tier 2, helped(soundOut)',
    () {
      test(
        'WordAccepted during the post-Tier-1 T2 window resolves helped(soundOut), no Tier 2 audio',
        () {
          fakeAsync((async) {
            final h = _harness();
            h.controller.watchWord(index: 0, word: _wordShip());
            async.elapse(kStruggleT1);
            _drainHelpClips(h.fake, async, 3);

            async.elapse(const Duration(seconds: 2)); // partway into T2
            h.eventsController.add(const WordAccepted(index: 0));
            async.flushMicrotasks();

            expect(h.helpedEvents, hasLength(1));
            expect(h.helpedEvents.single.index, 0);
            expect(h.helpedEvents.single.tier, HelpLevel.soundOut);
            expect(h.recorder.calls, hasLength(1));
            expect(h.recorder.calls.single.tier, HelpLevel.soundOut);
            expect(h.recorder.calls.single.word.text, 'ship');

            expect(
              h.fake.callLog
                  .whereType<PlayLogEntry>()
                  .any((e) => e.ref == 'audio/words/ship.wav'),
              isFalse,
              reason: 'Tier 2 must never start once resolved via Tier 1',
            );
            expect(
              h.fake.callLog
                  .whereType<PlayLogEntry>()
                  .any((e) => e.ref == _yourTurnRef),
              isFalse,
            );

            // Elapsing well past T2 causes nothing further.
            async.elapse(const Duration(seconds: 10));
            expect(h.helpedEvents, hasLength(1));
            h.dispose();
          });
        },
      );

      test(
        'WordAccepted WHILE Tier 1 phoneme audio is still playing also resolves helped(soundOut), and remaining phonemes never play',
        () {
          fakeAsync((async) {
            final h = _harness();
            h.controller.watchWord(index: 0, word: _wordShip());
            async.elapse(kStruggleT1); // only "SH" has started

            h.eventsController.add(const WordAccepted(index: 0));
            async.flushMicrotasks();

            expect(h.helpedEvents, hasLength(1));
            expect(h.helpedEvents.single.tier, HelpLevel.soundOut);
            expect(
              h.fake.callLog
                  .whereType<PlayLogEntry>()
                  .where((e) => e.ref.contains('phonemes')),
              hasLength(1),
              reason: 'IH and P must not play after resolution',
            );
            h.dispose();
          });
        },
      );
    },
  );

  group('POSITIVE: Tier 2 -- model it', () {
    test(
      'full silence through Tier 1 and T2 escalates to Tier 2; repeat accepted -> helped(modeled)',
      () {
        fakeAsync((async) {
          final h = _harness();
          h.controller.watchWord(index: 0, word: _wordCat());
          async.elapse(kStruggleT1);
          _drainHelpClips(h.fake, async, 3);

          async.elapse(kTier2WaitT2); // full T2 silence -> Tier 2 begins

          expect(
            h.fake.callLog
                .whereType<PlayLogEntry>()
                .any((e) => e.ref == 'audio/words/cat.wav'),
            isTrue,
            reason: 'Tier 2 plays the whole word first',
          );
          _drainHelpClips(h.fake, async, 1); // word pronunciation finishes

          expect(
            h.fake.callLog
                .whereType<PlayLogEntry>()
                .any((e) => e.ref == _yourTurnRef),
            isTrue,
            reason: 'then the "your turn" prompt line',
          );
          _drainHelpClips(h.fake, async, 1); // "your turn" line finishes

          async.elapse(const Duration(seconds: 1)); // partway into 2nd T2
          h.eventsController.add(const WordAccepted(index: 0));
          async.flushMicrotasks();

          expect(h.helpedEvents, hasLength(1));
          expect(h.helpedEvents.single.tier, HelpLevel.modeled);
          expect(h.recorder.calls, hasLength(1));
          expect(h.recorder.calls.single.tier, HelpLevel.modeled);
          h.dispose();
        });
      },
    );

    test(
      'full silence through Tier 2 as well: auto-accepted after the final T2 -- never hard-blocks',
      () {
        fakeAsync((async) {
          final h = _harness();
          h.controller.watchWord(index: 0, word: _wordCat());
          async.elapse(kStruggleT1);
          _drainHelpClips(h.fake, async, 3);
          async.elapse(kTier2WaitT2);
          _drainHelpClips(h.fake, async, 2); // word audio + "your turn" line

          expect(
            h.helpedEvents,
            isEmpty,
            reason: 'still waiting out the final T2',
          );

          async.elapse(kTier2WaitT2); // no repeat ever arrives

          expect(h.helpedEvents, hasLength(1));
          expect(h.helpedEvents.single.tier, HelpLevel.modeled);
          expect(h.recorder.calls.single.tier, HelpLevel.modeled);
          h.dispose();
        });
      },
    );
  });

  group('POSITIVE: plain acceptance with no struggle at all', () {
    test(
      'WordAccepted before T1 elapses: tier none recorded, no WordHelped, no help audio',
      () {
        fakeAsync((async) {
          final h = _harness();
          h.controller.watchWord(index: 0, word: _wordCat());
          async.elapse(const Duration(seconds: 1));

          h.eventsController.add(const WordAccepted(index: 0));
          async.flushMicrotasks();

          expect(h.fake.callLog, isEmpty);
          expect(h.helpedEvents, isEmpty);
          expect(h.recorder.calls, hasLength(1));
          expect(h.recorder.calls.single.tier, HelpLevel.none);

          async.elapse(const Duration(seconds: 10));
          expect(
            h.fake.callLog,
            isEmpty,
            reason: 'a resolved word must never later trigger Tier 1',
          );
          h.dispose();
        });
      },
    );
  });

  group('NEGATIVE: events for a non-watched word index are ignored', () {
    test('StruggleDetected for a different index does not start Tier 1', () {
      fakeAsync((async) {
        final h = _harness();
        h.controller.watchWord(index: 2, word: _wordShip());

        h.eventsController.add(const StruggleDetected(index: 5));
        async.flushMicrotasks();

        expect(h.fake.callLog, isEmpty);
        h.dispose();
      });
    });

    test(
      'WordAccepted for a different index does not resolve the watched word',
      () {
        fakeAsync((async) {
          final h = _harness();
          h.controller.watchWord(index: 2, word: _wordCat());

          h.eventsController.add(const WordAccepted(index: 5));
          async.flushMicrotasks();

          expect(h.recorder.calls, isEmpty);
          expect(h.helpedEvents, isEmpty);
          h.dispose();
        });
      },
    );
  });

  group('NEGATIVE: no double-resolution from late/duplicate events', () {
    test(
      'a WordAccepted arriving after a plain-accept resolution is a no-op',
      () {
        fakeAsync((async) {
          final h = _harness();
          h.controller.watchWord(index: 0, word: _wordCat());
          h.eventsController.add(const WordAccepted(index: 0));
          async.flushMicrotasks();
          expect(h.recorder.calls, hasLength(1));

          h.eventsController.add(const WordAccepted(index: 0));
          async.flushMicrotasks();

          expect(
            h.recorder.calls,
            hasLength(1),
            reason: 'must not double-record a resolved word',
          );
          h.dispose();
        });
      },
    );

    test(
      'a WordAccepted arriving after a helped(soundOut) resolution does not emit a second WordHelped',
      () {
        fakeAsync((async) {
          final h = _harness();
          h.controller.watchWord(index: 0, word: _wordShip());
          async.elapse(kStruggleT1);
          _drainHelpClips(h.fake, async, 3);
          h.eventsController.add(const WordAccepted(index: 0));
          async.flushMicrotasks();
          expect(h.helpedEvents, hasLength(1));

          h.eventsController.add(const WordAccepted(index: 0));
          async.flushMicrotasks();

          expect(h.helpedEvents, hasLength(1));
          expect(h.recorder.calls, hasLength(1));
          h.dispose();
        });
      },
    );
  });

  group('EDGE: watchWord supersedes a still-pending previous word', () {
    test(
      'calling watchWord for a new word cancels the previous word\'s pending T1 timer',
      () {
        fakeAsync((async) {
          final h = _harness();
          h.controller.watchWord(index: 0, word: _wordCat());
          async.elapse(const Duration(seconds: 2));

          h.controller.watchWord(index: 1, word: _wordShip());
          async.elapse(const Duration(seconds: 3)); // total 5s

          // Word 0's T1 (would fire at 6s total) never fires; word 1's T1
          // (fires at 2s + 4s = 6s total) hasn't fired yet either at 5s.
          expect(h.fake.callLog, isEmpty);

          async.elapse(const Duration(seconds: 1)); // total 6s
          final plays = h.fake.callLog.whereType<PlayLogEntry>();
          expect(plays, hasLength(1));
          expect(plays.first.ref, 'audio/phonemes/SH.wav');
          h.dispose();
        });
      },
    );
  });

  group('EDGE: injected per-level T1/T2 timing override (PRD §7 R7)', () {
    test(
      'a shorter injected T1 fires Tier 1 earlier than the tuning-file default',
      () {
        fakeAsync((async) {
          final h = _harness(t1: const Duration(seconds: 2));
          h.controller.watchWord(index: 0, word: _wordShip());

          async.elapse(const Duration(milliseconds: 1900));
          expect(h.fake.callLog, isEmpty);

          async.elapse(const Duration(milliseconds: 100));
          expect(h.fake.callLog.whereType<PlayLogEntry>(), hasLength(1));
          h.dispose();
        });
      },
    );

    test(
      'a shorter injected T2 shortens the wait before Tier 2 escalation',
      () {
        fakeAsync((async) {
          final h = _harness(t2: const Duration(seconds: 1));
          h.controller.watchWord(index: 0, word: _wordCat());
          async.elapse(kStruggleT1);
          _drainHelpClips(h.fake, async, 3);

          async.elapse(const Duration(seconds: 1));

          expect(
            h.fake.callLog
                .whereType<PlayLogEntry>()
                .any((e) => e.ref == 'audio/words/cat.wav'),
            isTrue,
          );
          h.dispose();
        });
      },
    );
  });

  group(
    'EDGE: a word whose entire graphemePhonemeMap is silent letters',
    () {
      test(
        'Tier 1 produces no phoneme audio at all, but the T2 wait still starts right after T1',
        () {
          fakeAsync((async) {
            final silentWord = WordToken(
              text: 'xx',
              graphemePhonemeMap: const [
                (graphemes: 'x', phonemeId: ''),
                (graphemes: 'x', phonemeId: ''),
              ],
              pronunciationAudioRef: 'audio/words/xx.wav',
            );
            final h = _harness();
            h.controller.watchWord(index: 0, word: silentWord);
            async.elapse(kStruggleT1);
            async.flushMicrotasks();

            expect(
              h.fake.callLog.whereType<PlayLogEntry>().where(
                (e) => e.ref.contains('phonemes'),
              ),
              isEmpty,
            );

            async.elapse(kTier2WaitT2 - const Duration(milliseconds: 1));
            expect(
              h.fake.callLog
                  .whereType<PlayLogEntry>()
                  .any((e) => e.ref == 'audio/words/xx.wav'),
              isFalse,
            );
            async.elapse(const Duration(milliseconds: 1));
            expect(
              h.fake.callLog
                  .whereType<PlayLogEntry>()
                  .any((e) => e.ref == 'audio/words/xx.wav'),
              isTrue,
            );
            h.dispose();
          });
        },
      );
    },
  );

  group('EDGE: help_given(tier) analytics emission hook', () {
    test(
      'onHelpGiven fires exactly once per WordHelped, with the resolved tier',
      () {
        fakeAsync((async) {
          final log = <(int, HelpLevel)>[];
          final h = _harness(onHelpGivenLog: log);
          h.controller.watchWord(index: 3, word: _wordShip());
          async.elapse(kStruggleT1);
          _drainHelpClips(h.fake, async, 3);

          h.eventsController.add(const WordAccepted(index: 3));
          async.flushMicrotasks();

          expect(log, [(3, HelpLevel.soundOut)]);
          h.dispose();
        });
      },
    );

    test('onHelpGiven does not fire for a plain accepted (unaided) word', () {
      fakeAsync((async) {
        final log = <(int, HelpLevel)>[];
        final h = _harness(onHelpGivenLog: log);
        h.controller.watchWord(index: 0, word: _wordCat());

        h.eventsController.add(const WordAccepted(index: 0));
        async.flushMicrotasks();

        expect(log, isEmpty);
        h.dispose();
      });
    });
  });

  group(
    'EDGE / accept 9: help audio ducks an active ambient/celebration channel',
    () {
      test('Tier 1 sound-out audio ducks an active ambient loop', () {
        fakeAsync((async) {
          final h = _harness();
          unawaited(
            h.fake.play('audio/ambient/forest.wav', channel: AudioChannel.ambient),
          );

          h.controller.watchWord(index: 0, word: _wordShip());
          async.elapse(kStruggleT1);
          async.flushMicrotasks();

          final ducks = h.fake.callLog.whereType<DuckLogEntry>();
          expect(
            ducks.any(
              (e) =>
                  e.duckedChannel == AudioChannel.ambient &&
                  e.byChannel == AudioChannel.help,
            ),
            isTrue,
          );
          h.dispose();
        });
      });

      test('Tier 2 audio ducks an active celebration line', () {
        fakeAsync((async) {
          final h = _harness();
          h.controller.watchWord(index: 0, word: _wordCat());
          async.elapse(kStruggleT1);
          _drainHelpClips(h.fake, async, 3);

          unawaited(
            h.fake.play(
              'audio/celebration/sting.wav',
              channel: AudioChannel.celebration,
            ),
          );
          async.elapse(kTier2WaitT2);
          async.flushMicrotasks();

          final ducks = h.fake.callLog.whereType<DuckLogEntry>();
          expect(
            ducks.any(
              (e) =>
                  e.duckedChannel == AudioChannel.celebration &&
                  e.byChannel == AudioChannel.help,
            ),
            isTrue,
          );
          h.dispose();
        });
      });
    },
  );
}

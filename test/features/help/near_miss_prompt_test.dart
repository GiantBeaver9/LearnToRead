// Pins the API of lib/features/help/near_miss_prompt.dart (PRD §8 Unit 6
// "Near-miss prompt (ratified in concept)"; §8 Unit 4 (near-miss); ticket
// stuck-word-scaffold accept entry 7). This suite is authored before the
// implementation exists, so it is EXPECTED to fail to compile until
// near_miss_prompt.dart is written with exactly the shape exercised below
// (it also exercises stuck_word_controller.dart's near-miss wiring, whose
// full pinned surface lives in stuck_word_controller_test.dart's header).
//
// Pinned API surface this suite requires:
//   class NearMissPrompt {
//     NearMissPrompt({required AudioService audioService, required AudioRef promptLineAudioRef});
//     Future<void> play(WordToken word);
//   }
//
// Contract this suite locks in (builder-mechanical design choice: exact
// prompt copy/audio is authored content -- Unit 3 -- out of scope here;
// this suite pins placeholder refs and the *ordering*/*channel*/*non-
// escalation* behavior, per the ticket's own note that tests use fixture
// refs):
//  - `play(word)` plays [promptLineAudioRef] first (the generic "that's
//    it..." line, reusable across words), waits for it to finish, then
//    plays `word.pronunciationAudioRef` (the specific word) -- together
//    forming "that's it -- cat!" from two recorded clips. Both are tagged
//    `AudioChannel.help`, so they duck ambient/celebration per the pinned
//    `DuckingPolicy` the same way Tier 1/2 help audio does.
//  - `NearMissPrompt` itself has no concept of a tier, a timer, or
//    escalation -- it is a strictly lighter-touch, single audio sequence
//    with no state machine at all (the "never escalates" guarantee is
//    structural: there is nothing here *to* escalate).
//  - `StuckWordController` calls `nearMissPrompt.play(word)` when a
//    `WordAcceptedNearMiss(index)` event arrives for the currently-watched
//    word: the word is NOT marked helped (`tier = HelpLevel.none` is
//    passed to `helpRecorder.recordResolution` -- an encounter is still
//    recorded, per accept entry 10's denominator fix, but `helpCount`/
//    `lastHelpLevel` are untouched), no `WordHelped` is emitted, no Tier
//    1/2 timer is ever started for that word, and reading is never
//    blocked -- elapsing arbitrarily far past T1/T2 afterwards changes
//    nothing.

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

WordToken _wordCat() => WordToken(
  text: 'cat',
  graphemePhonemeMap: const [
    (graphemes: 'c', phonemeId: 'K'),
    (graphemes: 'a', phonemeId: 'AE'),
    (graphemes: 't', phonemeId: 'T'),
  ],
  pronunciationAudioRef: 'audio/words/cat.wav',
);

const _promptLineRef = 'audio/prompts/that_is_it.wav';
const _yourTurnRef = 'audio/prompts/your_turn.wav';

const _phonemeAudioRefs = {'K': 'audio/phonemes/K.wav', 'AE': 'audio/phonemes/AE.wav', 'T': 'audio/phonemes/T.wav'};

class _RecordingHelpRecorder implements HelpRecorderApi {
  final List<({WordToken word, HelpLevel tier})> calls = [];

  @override
  Future<void> recordResolution({required WordToken word, required HelpLevel tier}) async {
    calls.add((word: word, tier: tier));
  }
}

void main() {
  group('POSITIVE: NearMissPrompt plays the prompt line then the word, both on help', () {
    test('play() plays promptLineAudioRef, then (after it completes) the word pronunciation', () async {
      final fake = FakeAudioService();
      final prompt = NearMissPrompt(audioService: fake, promptLineAudioRef: _promptLineRef);

      final future = prompt.play(_wordCat());
      // Complete each clip as it starts, mirroring the other suites' drain pattern.
      await pumpAndComplete(fake, expectedRefs: [_promptLineRef, 'audio/words/cat.wav']);
      await future;

      final refs = fake.callLog.whereType<PlayLogEntry>().map((e) => e.ref).toList();
      expect(refs, [_promptLineRef, 'audio/words/cat.wav']);
    });

    test('both clips are tagged AudioChannel.help', () async {
      final fake = FakeAudioService();
      final prompt = NearMissPrompt(audioService: fake, promptLineAudioRef: _promptLineRef);

      final future = prompt.play(_wordCat());
      await pumpAndComplete(fake, expectedRefs: [_promptLineRef, 'audio/words/cat.wav']);
      await future;

      final channels = fake.callLog.whereType<PlayLogEntry>().map((e) => e.channel).toSet();
      expect(channels, {AudioChannel.help});
    });

    test('ducks an active ambient channel per the pinned DuckingPolicy', () async {
      final fake = FakeAudioService();
      await fake.play('audio/ambient/forest.wav', channel: AudioChannel.ambient);
      final prompt = NearMissPrompt(audioService: fake, promptLineAudioRef: _promptLineRef);

      final future = prompt.play(_wordCat());
      await pumpAndComplete(fake, expectedRefs: [_promptLineRef, 'audio/words/cat.wav']);
      await future;

      final ducks = fake.callLog.whereType<DuckLogEntry>();
      expect(ducks.any((e) => e.duckedChannel == AudioChannel.ambient && e.byChannel == AudioChannel.help), isTrue);
    });

    test('play() future does not complete until both clips have finished', () async {
      final fake = FakeAudioService();
      final prompt = NearMissPrompt(audioService: fake, promptLineAudioRef: _promptLineRef);

      var completed = false;
      final future = prompt.play(_wordCat())..then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      expect(completed, isFalse, reason: 'the prompt line has not even started completing yet');

      await pumpAndComplete(fake, expectedRefs: [_promptLineRef, 'audio/words/cat.wav']);
      await future;
      expect(completed, isTrue);
    });
  });

  group('NEGATIVE: missing audio refs', () {
    test('a missing promptLineAudioRef throws and the word pronunciation is never played', () async {
      final fake = FakeAudioService(missingRefs: const {_promptLineRef});
      final prompt = NearMissPrompt(audioService: fake, promptLineAudioRef: _promptLineRef);

      await expectLater(prompt.play(_wordCat()), throwsA(isA<AudioRefNotFoundException>()));
      expect(fake.callLog, isEmpty);
    });

    test('a missing word pronunciation ref throws after the prompt line has already played', () async {
      final fake = FakeAudioService(missingRefs: const {'audio/words/cat.wav'});
      final prompt = NearMissPrompt(audioService: fake, promptLineAudioRef: _promptLineRef);

      final future = prompt.play(_wordCat());
      // Complete only the prompt line; the word pronunciation play() itself throws.
      final promptHandle = await _waitForPlay(fake, _promptLineRef);
      fake.completePlayback(promptHandle);

      await expectLater(future, throwsA(isA<AudioRefNotFoundException>()));
      expect(fake.callLog.whereType<PlayLogEntry>().map((e) => e.ref), [_promptLineRef]);
    });
  });

  group('EDGE: independent, sequential calls', () {
    test('two consecutive play() calls for different words do not interleave', () async {
      final fake = FakeAudioService();
      final prompt = NearMissPrompt(audioService: fake, promptLineAudioRef: _promptLineRef);
      final dog = WordToken(
        text: 'dog',
        graphemePhonemeMap: const [(graphemes: 'd', phonemeId: 'D')],
        pronunciationAudioRef: 'audio/words/dog.wav',
      );

      final first = prompt.play(_wordCat());
      await pumpAndComplete(fake, expectedRefs: [_promptLineRef, 'audio/words/cat.wav']);
      await first;

      final second = prompt.play(dog);
      await pumpAndComplete(fake, expectedRefs: [_promptLineRef, 'audio/words/dog.wav']);
      await second;

      final refs = fake.callLog.whereType<PlayLogEntry>().map((e) => e.ref).toList();
      expect(refs, [_promptLineRef, 'audio/words/cat.wav', _promptLineRef, 'audio/words/dog.wav']);
    });
  });

  // ---------------------------------------------------------------------
  // Controller integration: the near-miss PATH itself (ticket accept 7).
  // ---------------------------------------------------------------------

  group('POSITIVE / controller: near-miss path never escalates and never blocks', () {
    test('WordAcceptedNearMiss plays the warm model, no tier starts, no WordHelped, encounter recorded', () {
      fakeAsync((async) {
        final fake = FakeAudioService();
        final recorder = _RecordingHelpRecorder();
        final eventsController = StreamController<TrackerEvent>();
        final helpStates = <HelpState>[];
        final helpedEvents = <WordHelped>[];
        final controller = StuckWordController(
          events: eventsController.stream,
          soundOutSequence: SoundOutSequence(
            phonemeSequencer: PhonemeSequencer(audioService: fake, phonemeAudioRefs: _phonemeAudioRefs),
          ),
          audioService: fake,
          nearMissPrompt: NearMissPrompt(audioService: fake, promptLineAudioRef: _promptLineRef),
          helpRecorder: recorder,
          yourTurnPromptAudioRef: _yourTurnRef,
        );
        controller.helpState.listen(helpStates.add);
        controller.wordHelpedStream.listen(helpedEvents.add);

        controller.watchWord(index: 0, word: _wordCat());
        eventsController.add(const WordAcceptedNearMiss(index: 0));
        async.flushMicrotasks();

        // The warm model played: prompt line then the word.
        final helpRefs = fake.callLog.whereType<PlayLogEntry>().where((e) => e.channel == AudioChannel.help).map((e) => e.ref).toList();
        expect(helpRefs, [_promptLineRef, 'audio/words/cat.wav']);

        // Recorded as an encounter, NOT as help.
        expect(recorder.calls, hasLength(1));
        expect(recorder.calls.single.tier, HelpLevel.none);
        expect(helpedEvents, isEmpty);

        // Never escalates, never blocks: elapsing arbitrarily far past
        // T1/T2 afterwards starts no Tier 1/2 sequence for this word.
        async.elapse(kStruggleT1 + kTier2WaitT2 + kTier2WaitT2 + const Duration(seconds: 10));
        final phonemeRefs = fake.callLog.whereType<PlayLogEntry>().where((e) => e.ref.contains('phonemes'));
        expect(phonemeRefs, isEmpty);
        expect(helpedEvents, isEmpty);
        expect(recorder.calls, hasLength(1));

        controller.dispose();
        unawaited(eventsController.close());
      });
    });

    test('near-miss on a word not yet struggled-on does not consume/alter the T1 timer of a later word', () {
      fakeAsync((async) {
        final fake = FakeAudioService();
        final recorder = _RecordingHelpRecorder();
        final eventsController = StreamController<TrackerEvent>();
        final controller = StuckWordController(
          events: eventsController.stream,
          soundOutSequence: SoundOutSequence(
            phonemeSequencer: PhonemeSequencer(audioService: fake, phonemeAudioRefs: _phonemeAudioRefs),
          ),
          audioService: fake,
          nearMissPrompt: NearMissPrompt(audioService: fake, promptLineAudioRef: _promptLineRef),
          helpRecorder: recorder,
          yourTurnPromptAudioRef: _yourTurnRef,
        );

        controller.watchWord(index: 0, word: _wordCat());
        eventsController.add(const WordAcceptedNearMiss(index: 0));
        async.flushMicrotasks();

        // Move on to the next word; its own T1 timer starts fresh from now.
        final ship = WordToken(
          text: 'ship',
          graphemePhonemeMap: const [(graphemes: 'sh', phonemeId: 'SH')],
          pronunciationAudioRef: 'audio/words/ship.wav',
        );
        controller.watchWord(index: 1, word: ship);
        async.elapse(const Duration(milliseconds: 3900));
        expect(
          fake.callLog.whereType<PlayLogEntry>().where((e) => e.ref.contains('phonemes')),
          isEmpty,
        );
        async.elapse(const Duration(milliseconds: 100));
        expect(
          fake.callLog.whereType<PlayLogEntry>().where((e) => e.ref.contains('phonemes')),
          hasLength(1),
        );

        controller.dispose();
        unawaited(eventsController.close());
      });
    });
  });
}

/// Waits (via real microtask/event-loop turns) until [fake] has logged a
/// `play()` call for [ref], then returns its handle. Used outside
/// `fakeAsync` for this file's plain-`async` NearMissPrompt-only tests.
Future<PlaybackHandle> _waitForPlay(FakeAudioService fake, String ref) async {
  for (var i = 0; i < 10; i++) {
    final match = fake.callLog.whereType<PlayLogEntry>().where((e) => e.ref == ref);
    if (match.isNotEmpty) {
      return match.last.handle;
    }
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError('play() for "$ref" was never logged');
}

/// Drives [fake] through a real (non-fake-clock) sequential play chain:
/// waits for each ref in [expectedRefs] to be played, in order, completing
/// it before waiting for the next -- mirrors how `NearMissPrompt.play`
/// (and `PhonemeSequencer`/`SoundOutSequence`) await `completionOf` between
/// clips.
Future<void> pumpAndComplete(FakeAudioService fake, {required List<String> expectedRefs}) async {
  for (final ref in expectedRefs) {
    final handle = await _waitForPlay(fake, ref);
    fake.completePlayback(handle);
  }
}

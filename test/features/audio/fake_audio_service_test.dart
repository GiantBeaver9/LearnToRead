// Pins the API of lib/features/audio/audio_service.dart (the AudioService
// contract itself -- there is no separate audio_service_test.dart per the
// ticket's file split, so its shape is pinned here through the fake) and
// lib/features/audio/fake_audio_service.dart (PRD §8 Unit 13 pinned design;
// ticket audio-playback accept entries 1 and 4). This suite is authored
// before the implementation exists, so it is EXPECTED to fail to compile
// until both files are written with exactly the shapes exercised below.
//
// Pinned API surface this suite requires:
//   typedef AudioRef = String;
//   enum AudioChannel { help, narration, celebration, ambient }
//   class PlaybackHandle { const PlaybackHandle(int id); }
//   class AudioRefNotFoundException implements Exception { AudioRef ref; }
//   abstract class AudioService {
//     Future<PlaybackHandle> play(AudioRef ref, {required AudioChannel channel});
//     Future<void> stop(PlaybackHandle handle);
//     Future<void> completionOf(PlaybackHandle handle);
//   }
//   sealed class AudioCallLogEntry { Duration timestamp; }
//   class PlayLogEntry extends AudioCallLogEntry { AudioRef ref; AudioChannel channel; PlaybackHandle handle; }
//   class StopLogEntry extends AudioCallLogEntry { PlaybackHandle handle; }
//   class DuckLogEntry extends AudioCallLogEntry { AudioChannel duckedChannel; AudioChannel byChannel; }
//   class UnduckLogEntry extends AudioCallLogEntry { AudioChannel channel; }
//   class FakeAudioService implements AudioService {
//     FakeAudioService({
//       Set<AudioRef> missingRefs = const {},
//       Duration Function()? clock,
//       DuckingPolicy duckingPolicy = const DuckingPolicy(),
//     });
//     List<AudioCallLogEntry> get callLog;
//     void completePlayback(PlaybackHandle handle); // test-control: simulate natural end
//   }
//
// Contract this suite locks in (builder-mechanical design choices made by
// this test suite, since the ticket leaves exact shapes to the builder and
// only pins behavior):
//  - play() logs a PlayLogEntry synchronously (before any await inside it
//    resolves) and returns a fresh, previously-unused PlaybackHandle.
//  - play() with a ref in `missingRefs` throws AudioRefNotFoundException
//    and logs nothing -- the "error paths (missing ref)" ticket wording.
//  - stop(handle) logs a StopLogEntry, resolves completionOf(handle), and
//    is a safe no-op for an unknown or already-finished handle.
//  - completePlayback(handle) is the fake's test-control hook simulating a
//    clip reaching its natural end (as opposed to an explicit stop()):
//    resolves completionOf(handle) the same way stop() does, without
//    logging a StopLogEntry (nothing called stop).
//  - Ducking is composed internally from DuckingPolicy against which
//    channels currently have an active (unstopped, uncompleted) handle:
//    starting a play() on a channel that DuckingPolicy.channelsDuckedBy
//    names logs one DuckLogEntry per currently-active matching channel
//    (never one per handle -- a channel is "active" or not). When the last
//    active ducking-capable handle ends (stop or completePlayback) and a
//    previously-ducked channel is still active, an UnduckLogEntry is
//    logged for it.
//  - callLog is an ordered, defensively-copied snapshot (mutating the
//    returned list never affects the service's internal log).
//  - The clock is injectable (`clock` param) for deterministic timestamp
//    assertions; the default clock is monotonically increasing so ordering
//    can always be asserted from timestamps alone, not just list position.
//  - Nothing here is text-to-speech: play() takes only a pre-existing
//    AudioRef (a plain String) and a channel tag -- there is no text,
//    locale, or voice parameter anywhere on AudioService, and a
//    conventionally-"future TTS" ref (e.g. "tts://...") is handled
//    identically to a recorded-file ref (ticket accept 4, "asserted by API
//    shape").

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/ducking_policy.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';

void main() {
  group('POSITIVE: construction', () {
    test('constructs with no arguments', () {
      final fake = FakeAudioService();
      expect(fake, isNotNull);
      expect(fake.callLog, isEmpty);
    });

    test('implements the AudioService contract', () {
      final fake = FakeAudioService();
      expect(fake, isA<AudioService>());
    });
  });

  group('POSITIVE: play() dispatch and logging', () {
    test('play() returns a PlaybackHandle', () async {
      final fake = FakeAudioService();

      final handle = await fake.play('audio/help/soundout.wav', channel: AudioChannel.help);

      expect(handle, isA<PlaybackHandle>());
    });

    test('play() logs a PlayLogEntry with the exact ref and channel', () async {
      final fake = FakeAudioService();

      final handle = await fake.play('audio/celebration/story1.wav', channel: AudioChannel.celebration);

      expect(fake.callLog, hasLength(1));
      final entry = fake.callLog.single as PlayLogEntry;
      expect(entry.ref, 'audio/celebration/story1.wav');
      expect(entry.channel, AudioChannel.celebration);
      expect(entry.handle, handle);
    });

    test('successive play() calls return distinct handles', () async {
      final fake = FakeAudioService();

      final h1 = await fake.play('a.wav', channel: AudioChannel.ambient);
      final h2 = await fake.play('b.wav', channel: AudioChannel.ambient);

      expect(h1, isNot(h2));
    });

    test('callLog preserves call order', () async {
      final fake = FakeAudioService();

      await fake.play('one.wav', channel: AudioChannel.narration);
      await fake.play('two.wav', channel: AudioChannel.help);
      await fake.play('three.wav', channel: AudioChannel.ambient);

      final refs = fake.callLog.whereType<PlayLogEntry>().map((e) => e.ref).toList();
      expect(refs, ['one.wav', 'two.wav', 'three.wav']);
    });

    test('play() logs synchronously -- entry exists before the returned Future settles', () async {
      final fake = FakeAudioService();

      // Deliberately not awaited yet: assert the log already reflects the
      // call in this same synchronous turn. This is the same guarantee
      // phoneme_sequencer_test.dart's latency proxy relies on.
      final future = fake.play('instant.wav', channel: AudioChannel.help);
      expect(fake.callLog, hasLength(1));
      final handle = await future;
      expect(handle, isA<PlaybackHandle>());
    });
  });

  group('POSITIVE: stop()', () {
    test('stop() logs a StopLogEntry for the handle', () async {
      final fake = FakeAudioService();
      final handle = await fake.play('a.wav', channel: AudioChannel.ambient);

      await fake.stop(handle);

      final stopEntries = fake.callLog.whereType<StopLogEntry>();
      expect(stopEntries, hasLength(1));
      expect(stopEntries.single.handle, handle);
    });

    test('stop() resolves completionOf() for the same handle', () async {
      final fake = FakeAudioService();
      final handle = await fake.play('a.wav', channel: AudioChannel.ambient);

      var completed = false;
      unawaited(fake.completionOf(handle).then((_) => completed = true));
      await fake.stop(handle);
      await Future<void>.delayed(Duration.zero);

      expect(completed, isTrue);
    });
  });

  group('POSITIVE: completionOf() and completePlayback() test control', () {
    test('completionOf() resolves once completePlayback() is called', () async {
      final fake = FakeAudioService();
      final handle = await fake.play('a.wav', channel: AudioChannel.help);

      var completed = false;
      unawaited(fake.completionOf(handle).then((_) => completed = true));
      expect(completed, isFalse);

      fake.completePlayback(handle);
      await Future<void>.delayed(Duration.zero);

      expect(completed, isTrue);
    });

    test('completePlayback() does not log a StopLogEntry (nothing called stop)', () async {
      final fake = FakeAudioService();
      final handle = await fake.play('a.wav', channel: AudioChannel.help);

      fake.completePlayback(handle);

      expect(fake.callLog.whereType<StopLogEntry>(), isEmpty);
    });
  });

  group('POSITIVE: ducking composed from DuckingPolicy', () {
    test('starting help while ambient is active logs a duck of ambient', () async {
      final fake = FakeAudioService();
      await fake.play('ambient/loop.wav', channel: AudioChannel.ambient);

      await fake.play('help/soundout.wav', channel: AudioChannel.help);

      final duckEntries = fake.callLog.whereType<DuckLogEntry>();
      expect(duckEntries, hasLength(1));
      expect(duckEntries.single.duckedChannel, AudioChannel.ambient);
      expect(duckEntries.single.byChannel, AudioChannel.help);
    });

    test('starting help while celebration is active logs a duck of celebration', () async {
      final fake = FakeAudioService();
      await fake.play('celebration/yay.wav', channel: AudioChannel.celebration);

      await fake.play('help/soundout.wav', channel: AudioChannel.help);

      final duckEntries = fake.callLog.whereType<DuckLogEntry>();
      expect(duckEntries, hasLength(1));
      expect(duckEntries.single.duckedChannel, AudioChannel.celebration);
    });

    test('starting help while both ambient and celebration are active logs both ducks', () async {
      final fake = FakeAudioService();
      await fake.play('ambient/loop.wav', channel: AudioChannel.ambient);
      await fake.play('celebration/yay.wav', channel: AudioChannel.celebration);

      await fake.play('help/soundout.wav', channel: AudioChannel.help);

      final duckedChannels = fake.callLog.whereType<DuckLogEntry>().map((e) => e.duckedChannel).toSet();
      expect(duckedChannels, {AudioChannel.ambient, AudioChannel.celebration});
    });

    test('starting narration while ambient is active does NOT duck anything', () async {
      final fake = FakeAudioService();
      await fake.play('ambient/loop.wav', channel: AudioChannel.ambient);

      await fake.play('narration/sentence1.wav', channel: AudioChannel.narration);

      expect(fake.callLog.whereType<DuckLogEntry>(), isEmpty);
    });

    test('ending the ducking help playback logs an unduck for a still-active ducked channel', () async {
      final fake = FakeAudioService();
      final ambientHandle = await fake.play('ambient/loop.wav', channel: AudioChannel.ambient);
      final helpHandle = await fake.play('help/soundout.wav', channel: AudioChannel.help);
      expect(fake.callLog.whereType<DuckLogEntry>(), hasLength(1));

      fake.completePlayback(helpHandle);

      final unduckEntries = fake.callLog.whereType<UnduckLogEntry>();
      expect(unduckEntries, hasLength(1));
      expect(unduckEntries.single.channel, AudioChannel.ambient);
      // Sanity: the ambient handle itself was never stopped/completed.
      expect(ambientHandle, isNotNull);
    });

    test('ending help does not unduck a channel that already stopped on its own', () async {
      final fake = FakeAudioService();
      final ambientHandle = await fake.play('ambient/loop.wav', channel: AudioChannel.ambient);
      final helpHandle = await fake.play('help/soundout.wav', channel: AudioChannel.help);
      await fake.stop(ambientHandle); // ambient ends first, independently

      fake.completePlayback(helpHandle);

      // Nothing to restore: ambient was already stopped before help ended.
      expect(fake.callLog.whereType<UnduckLogEntry>(), isEmpty);
    });

    test('EDGE: a second concurrent help play keeps ducking active until BOTH end', () async {
      final fake = FakeAudioService();
      await fake.play('ambient/loop.wav', channel: AudioChannel.ambient);
      final help1 = await fake.play('help/tier1.wav', channel: AudioChannel.help);
      final help2 = await fake.play('help/tier1-repeat.wav', channel: AudioChannel.help);

      fake.completePlayback(help1);
      expect(fake.callLog.whereType<UnduckLogEntry>(), isEmpty, reason: 'help2 still active -- ambient stays ducked');

      fake.completePlayback(help2);
      expect(fake.callLog.whereType<UnduckLogEntry>(), hasLength(1));
    });

    test('EDGE: two simultaneously-active ambient handles are ducked once, not twice', () async {
      final fake = FakeAudioService();
      await fake.play('ambient/loop1.wav', channel: AudioChannel.ambient);
      await fake.play('ambient/loop2.wav', channel: AudioChannel.ambient);

      await fake.play('help/soundout.wav', channel: AudioChannel.help);

      expect(fake.callLog.whereType<DuckLogEntry>(), hasLength(1));
    });
  });

  group('NEGATIVE: missing ref error path', () {
    test('play() with a ref in missingRefs throws AudioRefNotFoundException', () async {
      final fake = FakeAudioService(missingRefs: {'audio/ghost.wav'});

      await expectLater(
        fake.play('audio/ghost.wav', channel: AudioChannel.help),
        throwsA(isA<AudioRefNotFoundException>().having((e) => e.ref, 'ref', 'audio/ghost.wav')),
      );
    });

    test('a failed play() for a missing ref logs nothing', () async {
      final fake = FakeAudioService(missingRefs: {'audio/ghost.wav'});

      await fake.play('audio/ghost.wav', channel: AudioChannel.help).catchError((Object _) => const PlaybackHandle(-1));

      expect(fake.callLog, isEmpty);
    });

    test('the service remains usable after a missing-ref error', () async {
      final fake = FakeAudioService(missingRefs: {'audio/ghost.wav'});

      await fake.play('audio/ghost.wav', channel: AudioChannel.help).catchError((Object _) => const PlaybackHandle(-1));
      final handle = await fake.play('audio/real.wav', channel: AudioChannel.help);

      expect(fake.callLog, hasLength(1));
      expect((fake.callLog.single as PlayLogEntry).ref, 'audio/real.wav');
      expect(handle, isNotNull);
    });
  });

  group('NEGATIVE: unknown-handle operations are safe no-ops', () {
    test('stop() on a handle never returned by play() does not throw', () async {
      final fake = FakeAudioService();

      await expectLater(fake.stop(const PlaybackHandle(999)), completes);
      expect(fake.callLog, isEmpty);
    });

    test('completionOf() on an unknown handle resolves rather than hanging', () async {
      final fake = FakeAudioService();

      await expectLater(fake.completionOf(const PlaybackHandle(999)), completes);
    });

    test('stop() on an already-stopped handle is idempotent (no duplicate StopLogEntry)', () async {
      final fake = FakeAudioService();
      final handle = await fake.play('a.wav', channel: AudioChannel.ambient);

      await fake.stop(handle);
      await fake.stop(handle);

      expect(fake.callLog.whereType<StopLogEntry>(), hasLength(1));
    });
  });

  group('EDGE: clock injection and ordering', () {
    test('default clock produces non-decreasing timestamps across entries', () async {
      final fake = FakeAudioService();

      await fake.play('a.wav', channel: AudioChannel.narration);
      await fake.play('b.wav', channel: AudioChannel.narration);
      await fake.play('c.wav', channel: AudioChannel.narration);

      final timestamps = fake.callLog.map((e) => e.timestamp).toList();
      for (var i = 1; i < timestamps.length; i++) {
        expect(timestamps[i], greaterThanOrEqualTo(timestamps[i - 1]));
      }
    });

    test('a custom clock is used verbatim for every log entry', () async {
      var tick = Duration.zero;
      final fake = FakeAudioService(clock: () {
        tick += const Duration(seconds: 1);
        return tick;
      });

      await fake.play('a.wav', channel: AudioChannel.narration);
      await fake.play('b.wav', channel: AudioChannel.narration);

      final timestamps = fake.callLog.map((e) => e.timestamp).toList();
      expect(timestamps, [const Duration(seconds: 1), const Duration(seconds: 2)]);
    });

    test('a custom DuckingPolicy is honored instead of the default', () async {
      // A policy where nothing ever ducks -- proves FakeAudioService
      // delegates to the injected policy rather than hardcoding the rule.
      final neverDucks = _NeverDucksPolicy();
      final fake = FakeAudioService(duckingPolicy: neverDucks);
      await fake.play('ambient/loop.wav', channel: AudioChannel.ambient);

      await fake.play('help/soundout.wav', channel: AudioChannel.help);

      expect(fake.callLog.whereType<DuckLogEntry>(), isEmpty);
    });
  });

  group('EDGE: callLog is an immutable snapshot', () {
    test('mutating the returned callLog list does not affect the service', () async {
      final fake = FakeAudioService();
      await fake.play('a.wav', channel: AudioChannel.narration);

      final snapshot = fake.callLog;
      expect(
        () => snapshot.add(StopLogEntry(handle: const PlaybackHandle(0), timestamp: Duration.zero)),
        throwsUnsupportedError,
      );
      expect(fake.callLog, hasLength(1));
    });
  });

  group('EDGE: scale', () {
    test('handles a long sequence of play() calls with distinct handles and full log fidelity', () async {
      final fake = FakeAudioService();

      final handles = <PlaybackHandle>[];
      for (var i = 0; i < 50; i++) {
        handles.add(await fake.play('clip$i.wav', channel: AudioChannel.narration));
      }

      expect(handles.toSet(), hasLength(50));
      expect(fake.callLog.whereType<PlayLogEntry>(), hasLength(50));
    });
  });

  group('Audio refs are source-agnostic; no TTS runtime generation (asserted by API shape)', () {
    test('play() accepts a plain String ref -- no text/voice/locale parameter exists', () async {
      final fake = FakeAudioService();

      // If play() required anything beyond (ref, channel), this call would
      // fail to compile with exactly this argument list.
      final handle = await fake.play('audio/words/cat.wav', channel: AudioChannel.help);

      expect(handle, isNotNull);
    });

    test('a conventionally-future-TTS-style ref is handled identically to a recorded ref', () async {
      final fake = FakeAudioService();

      final handle = await fake.play('tts://future-engine/clip-id', channel: AudioChannel.narration);

      expect(fake.callLog.single, isA<PlayLogEntry>());
      expect((fake.callLog.single as PlayLogEntry).ref, 'tts://future-engine/clip-id');
      expect(handle, isNotNull);
    });
  });
}

/// Test-only DuckingPolicy stand-in proving FakeAudioService's constructor
/// actually delegates ducking decisions rather than hardcoding them.
class _NeverDucksPolicy implements DuckingPolicy {
  @override
  Set<AudioChannel> channelsDuckedBy(AudioChannel playingChannel) => const {};

  @override
  bool shouldDuck({required AudioChannel active, required AudioChannel candidate}) => false;
}

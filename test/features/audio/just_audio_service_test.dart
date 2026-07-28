// Unit tests for lib/features/audio/just_audio_service.dart -- the
// just_audio-backed production AudioService adapter.
//
// Everything here runs headlessly: the two injected seams
// (AudioPlayerFactory and AudioSessionConfigurator) are faked, so no
// platform channels, audio devices, or real files are touched. Real audible
// playback / latency remain DEVICE-VERIFIED per ticket audio-playback (A-17).
//
// Covered here:
// - Unknown ref throws AudioRefNotFoundException without creating a player
//   (and without configuring the session).
// - Handle allocation is monotonic from 0; one player per play() call.
// - stop() of an unknown/finished handle is a safe no-op.
// - completionOf() resolves immediately for unknown handles, on natural
//   completion, on stop(), and on player error (errors never escape play()).
// - Players are stopped and disposed on completion/stop/error.
// - Ducking bookkeeping per DuckingPolicy: help ducks live ambient and
//   celebration players (never narration), clips starting on an
//   already-ducked channel begin at the ducked gain, and restore happens
//   only when the LAST overlapping ducking clip ends.
// - Session configuration happens once, before first playback, and a
//   throwing configurator does not break playback.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/just_audio_service.dart';

/// A headless stand-in for the just_audio player wrapper. Playback is
/// test-controlled: `play()` stays pending until [finishPlayback],
/// [failPlayback], or `stop()` resolves it.
class FakePlayer implements JustAudioPlayerApi {
  String? filePath;
  bool playCalled = false;
  bool stopped = false;
  bool disposed = false;
  final List<double> volumeCalls = [];
  Object? setFilePathError;

  Completer<void>? _playCompleter;

  /// Simulates the clip reaching its natural end.
  void finishPlayback() {
    if (_playCompleter != null && !_playCompleter!.isCompleted) {
      _playCompleter!.complete();
    }
  }

  /// Simulates a playback error surfacing from the player.
  void failPlayback(Object error) {
    if (_playCompleter != null && !_playCompleter!.isCompleted) {
      _playCompleter!.completeError(error);
    }
  }

  @override
  Future<void> setFilePath(String path) async {
    filePath = path;
    final error = setFilePathError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> play() {
    playCalled = true;
    _playCompleter = Completer<void>();
    return _playCompleter!.future;
  }

  @override
  Future<void> stop() async {
    stopped = true;
    finishPlayback(); // just_audio: stop() resolves the pending play() future.
  }

  @override
  Future<void> setVolume(double volume) async {
    volumeCalls.add(volume);
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

/// Test harness: a JustAudioService wired to fake players and a counting
/// session configurator, with a resolver that knows every ref except those
/// in [missingRefs].
class Harness {
  Harness({Set<String> missingRefs = const {}, bool sessionThrows = false})
      : _missingRefs = missingRefs,
        _sessionThrows = sessionThrows {
    service = JustAudioService(
      resolveRef: (ref) => _missingRefs.contains(ref) ? null : '/packs/audio/$ref',
      sessionConfigurator: () async {
        sessionConfigureCalls++;
        if (_sessionThrows) {
          throw StateError('no platform channels');
        }
      },
      playerFactory: () {
        final player = FakePlayer();
        players.add(player);
        return player;
      },
    );
  }

  final Set<String> _missingRefs;
  final bool _sessionThrows;
  final List<FakePlayer> players = [];
  int sessionConfigureCalls = 0;
  late final JustAudioService service;
}

/// Lets the fire-and-forget load+play (and finish) chains run.
Future<void> settle() => pumpEventQueue();

void main() {
  group('ref resolution', () {
    test('unknown ref throws AudioRefNotFoundException without creating a player', () async {
      final h = Harness(missingRefs: {'missing.mp3'});

      await expectLater(
        h.service.play('missing.mp3', channel: AudioChannel.narration),
        throwsA(isA<AudioRefNotFoundException>()
            .having((e) => e.ref, 'ref', 'missing.mp3')),
      );

      expect(h.players, isEmpty, reason: 'no player may exist for an unresolved ref');
      expect(h.sessionConfigureCalls, 0,
          reason: 'resolution failure happens before any session work');
    });

    test('resolved ref is loaded from the resolver-provided absolute path', () async {
      final h = Harness();

      await h.service.play('help/sound_out_cat.mp3', channel: AudioChannel.help);
      await settle();

      expect(h.players, hasLength(1));
      expect(h.players.single.filePath, '/packs/audio/help/sound_out_cat.mp3');
      expect(h.players.single.playCalled, isTrue);
    });
  });

  group('handles', () {
    test('handle ids are monotonic ints from 0, one player per play()', () async {
      final h = Harness();

      final a = await h.service.play('a.mp3', channel: AudioChannel.narration);
      final b = await h.service.play('b.mp3', channel: AudioChannel.ambient);
      final c = await h.service.play('c.mp3', channel: AudioChannel.help);

      expect([a.id, b.id, c.id], [0, 1, 2]);
      expect(h.players, hasLength(3));
    });
  });

  group('stop / completionOf', () {
    test('completionOf resolves immediately for an unknown handle', () async {
      final h = Harness();

      var resolved = false;
      unawaited(h.service.completionOf(const PlaybackHandle(999)).then((_) => resolved = true));
      await settle();

      expect(resolved, isTrue);
    });

    test('stop of an unknown handle is a safe no-op', () async {
      final h = Harness();

      await h.service.stop(const PlaybackHandle(42)); // Must not throw.
      expect(h.players, isEmpty);
    });

    test('completionOf resolves on natural completion; player is disposed', () async {
      final h = Harness();
      final handle = await h.service.play('a.mp3', channel: AudioChannel.narration);
      await settle();

      var resolved = false;
      unawaited(h.service.completionOf(handle).then((_) => resolved = true));
      await settle();
      expect(resolved, isFalse, reason: 'still playing');

      h.players.single.finishPlayback();
      await settle();

      expect(resolved, isTrue);
      expect(h.players.single.disposed, isTrue);
    });

    test('stop() resolves completionOf, stops and disposes the player', () async {
      final h = Harness();
      final handle = await h.service.play('a.mp3', channel: AudioChannel.narration);
      await settle();

      var resolved = false;
      unawaited(h.service.completionOf(handle).then((_) => resolved = true));

      await h.service.stop(handle);
      await settle();

      expect(resolved, isTrue);
      expect(h.players.single.stopped, isTrue);
      expect(h.players.single.disposed, isTrue);
    });

    test('stop() twice on the same handle is a safe no-op the second time', () async {
      final h = Harness();
      final handle = await h.service.play('a.mp3', channel: AudioChannel.narration);
      await settle();

      await h.service.stop(handle);
      await h.service.stop(handle); // Finished handle: must not throw.

      // And completionOf a finished handle resolves immediately.
      var resolved = false;
      unawaited(h.service.completionOf(handle).then((_) => resolved = true));
      await settle();
      expect(resolved, isTrue);
    });
  });

  group('error swallowing', () {
    test('a load error never escapes play(); the handle just completes', () async {
      final failing = FakePlayer()..setFilePathError = StateError('corrupt file');
      final service = JustAudioService(
        resolveRef: (ref) => '/packs/audio/$ref',
        sessionConfigurator: () async {},
        playerFactory: () => failing,
      );

      final handle = await service.play('a.mp3', channel: AudioChannel.help);
      await settle();

      var resolved = false;
      unawaited(service.completionOf(handle).then((_) => resolved = true));
      await settle();

      expect(resolved, isTrue, reason: 'error completes the handle');
      expect(failing.disposed, isTrue);
    });

    test('a mid-playback error completes the handle without throwing anywhere', () async {
      final h = Harness();
      final handle = await h.service.play('a.mp3', channel: AudioChannel.narration);
      await settle();

      var resolved = false;
      unawaited(h.service.completionOf(handle).then((_) => resolved = true));

      h.players.single.failPlayback(StateError('decoder died'));
      await settle();

      expect(resolved, isTrue);
      expect(h.players.single.disposed, isTrue);
    });
  });

  group('ducking', () {
    test('help ducks live ambient and celebration players, then restores both', () async {
      final h = Harness();
      await h.service.play('loop.mp3', channel: AudioChannel.ambient);
      await h.service.play('yay.mp3', channel: AudioChannel.celebration);
      await settle();
      final ambient = h.players[0];
      final celebration = h.players[1];
      expect(ambient.volumeCalls, isEmpty, reason: 'nothing ducked yet');
      expect(celebration.volumeCalls, isEmpty);

      final help = await h.service.play('hint.mp3', channel: AudioChannel.help);
      await settle();
      expect(ambient.volumeCalls, [JustAudioService.defaultDuckedVolume]);
      expect(celebration.volumeCalls, [JustAudioService.defaultDuckedVolume]);

      h.players[2].finishPlayback(); // help ends naturally
      await settle();
      expect(ambient.volumeCalls, [JustAudioService.defaultDuckedVolume, 1.0]);
      expect(celebration.volumeCalls, [JustAudioService.defaultDuckedVolume, 1.0]);

      // help handle finished; its completion resolved too
      await h.service.completionOf(help);
    });

    test('narration is never ducked', () async {
      final h = Harness();
      await h.service.play('story.mp3', channel: AudioChannel.narration);
      await h.service.play('hint.mp3', channel: AudioChannel.help);
      await settle();

      expect(h.players[0].volumeCalls, isEmpty);
    });

    test('no non-help channel ducks anything', () async {
      final h = Harness();
      await h.service.play('loop.mp3', channel: AudioChannel.ambient);
      await h.service.play('yay.mp3', channel: AudioChannel.celebration);
      await h.service.play('story.mp3', channel: AudioChannel.narration);
      await settle();

      for (final player in h.players) {
        expect(player.volumeCalls, isEmpty);
      }
    });

    test('a clip starting on an already-ducked channel begins at the ducked gain', () async {
      final h = Harness();
      await h.service.play('hint.mp3', channel: AudioChannel.help);
      await settle();

      await h.service.play('loop.mp3', channel: AudioChannel.ambient);
      await settle();
      final ambient = h.players[1];

      expect(ambient.volumeCalls, [JustAudioService.defaultDuckedVolume],
          reason: 'exactly one volume call: starts ducked, not full-then-ducked');
    });

    test('overlapping help clips: restore only when the last one ends', () async {
      final h = Harness();
      await h.service.play('loop.mp3', channel: AudioChannel.ambient);
      final help1 = await h.service.play('hint1.mp3', channel: AudioChannel.help);
      await h.service.play('hint2.mp3', channel: AudioChannel.help);
      await settle();
      final ambient = h.players[0];
      expect(ambient.volumeCalls, [JustAudioService.defaultDuckedVolume],
          reason: 'second overlapping help clip ducks nothing anew');

      await h.service.stop(help1);
      await settle();
      expect(ambient.volumeCalls, [JustAudioService.defaultDuckedVolume],
          reason: 'help2 still live: no restore yet');

      h.players[2].finishPlayback(); // help2 ends
      await settle();
      expect(ambient.volumeCalls, [JustAudioService.defaultDuckedVolume, 1.0],
          reason: 'last ducking clip ended: restore');
    });

    test('ducked channel ending on its own gets no restore call (player is gone)', () async {
      final h = Harness();
      final ambient = await h.service.play('loop.mp3', channel: AudioChannel.ambient);
      await h.service.play('hint.mp3', channel: AudioChannel.help);
      await settle();
      final ambientPlayer = h.players[0];
      expect(ambientPlayer.volumeCalls, [JustAudioService.defaultDuckedVolume]);

      await h.service.stop(ambient); // ambient ends while still ducked
      h.players[1].finishPlayback(); // help ends
      await settle();

      expect(ambientPlayer.volumeCalls, [JustAudioService.defaultDuckedVolume],
          reason: 'no volume restore is sent to a disposed player');
    });

    test('custom duckedVolume is honored', () async {
      final players = <FakePlayer>[];
      final service = JustAudioService(
        resolveRef: (ref) => '/packs/audio/$ref',
        sessionConfigurator: () async {},
        playerFactory: () {
          final player = FakePlayer();
          players.add(player);
          return player;
        },
        duckedVolume: 0.15,
      );

      await service.play('loop.mp3', channel: AudioChannel.ambient);
      await service.play('hint.mp3', channel: AudioChannel.help);
      await settle();

      expect(players[0].volumeCalls, [0.15]);
    });
  });

  group('audio session', () {
    test('configured exactly once, before first playback, across many plays', () async {
      final h = Harness();
      expect(h.sessionConfigureCalls, 0, reason: 'lazy: nothing until first play');

      await h.service.play('a.mp3', channel: AudioChannel.narration);
      expect(h.sessionConfigureCalls, 1);

      await h.service.play('b.mp3', channel: AudioChannel.help);
      await h.service.play('c.mp3', channel: AudioChannel.ambient);
      expect(h.sessionConfigureCalls, 1, reason: 'never re-configured');
    });

    test('a throwing configurator is swallowed and playback proceeds', () async {
      final h = Harness(sessionThrows: true);

      final handle = await h.service.play('a.mp3', channel: AudioChannel.narration);
      await settle();

      expect(h.sessionConfigureCalls, 1);
      expect(h.players.single.playCalled, isTrue);

      h.players.single.finishPlayback();
      await h.service.completionOf(handle);
    });
  });
}

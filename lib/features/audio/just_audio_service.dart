/// Device-side `AudioService` adapter backed by just_audio + audio_session
/// (PRD §8 Unit 13; ticket audio-playback notes / A-17: "the concrete impl is
/// a thin adapter behind AudioService, owner-verified on device").
///
/// What this file is:
/// - The production implementation of the `AudioService` seam
///   (`audio_service.dart`). Everything else in the app keeps talking to the
///   interface; only composition-root wiring names this class.
/// - Behavior-compatible with `FakeAudioService` (the fake every downstream
///   unit was tested against): monotonic int handle ids starting at 0,
///   `stop()` a safe no-op for unknown/finished handles, `completionOf()`
///   resolving immediately for unknown handles and never hanging, ducking
///   delegated to the injected `DuckingPolicy` and recomputed from which
///   channels currently have a live clip.
///
/// What is verified where:
/// - Real audible playback, latency ("phoneme sound-out must feel instant"),
///   and gapless feel are DEVICE-VERIFIED by the owner per A-17 -- CI has no
///   audio device, no platform channels, and no shipped audio files.
/// - Unit tests (`test/features/audio/just_audio_service_test.dart`) cover
///   everything headless: ref resolution failure (throws before any player
///   exists), handle allocation, stop/completion semantics, error swallowing,
///   session-configuration once-and-fault-tolerant behavior, and the full
///   ducking bookkeeping (which players get their volume ducked/restored and
///   when), by faking the two injected seams below.
///
/// The two injectable seams (so tests never touch platform channels):
/// - [AudioPlayerFactory]: returns a [JustAudioPlayerApi] per `play()` call.
///   The default factory wraps a real `just_audio.AudioPlayer`; tests inject
///   fakes.
/// - [AudioSessionConfigurator]: configures the OS audio session on first
///   play. The default uses `audio_session`; any throw is swallowed so
///   headless/test environments still play.
library;

import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart' as ja;

import 'audio_service.dart';
import 'ducking_policy.dart';

/// Configures the OS audio session (called once, before the first playback).
/// Injectable so tests never touch platform channels.
typedef AudioSessionConfigurator = Future<void> Function();

/// Creates one player per in-flight `play()` call. Injectable so tests can
/// substitute fakes; the default returns real just_audio players.
typedef AudioPlayerFactory = JustAudioPlayerApi Function();

/// The minimal slice of `just_audio.AudioPlayer`'s surface this adapter uses.
/// Exists purely as the fakeable seam behind [AudioPlayerFactory]; the
/// default implementation ([RealJustAudioPlayer]) forwards every member 1:1
/// to a real `just_audio.AudioPlayer`.
abstract class JustAudioPlayerApi {
  /// Loads the clip at [path] (an absolute file path).
  Future<void> setFilePath(String path);

  /// Starts playback; the returned future resolves when playback finishes
  /// naturally or the player is stopped (just_audio's `play()` contract).
  Future<void> play();

  /// Stops playback, causing any pending [play] future to resolve.
  Future<void> stop();

  /// Sets this player's volume (1.0 = full, used for ducking).
  Future<void> setVolume(double volume);

  /// Releases the player's platform resources.
  Future<void> dispose();
}

/// Default [JustAudioPlayerApi]: a thin 1:1 wrapper over a real
/// `just_audio.AudioPlayer`. Never constructed in unit tests (no platform
/// channels in CI); exercised on device.
class RealJustAudioPlayer implements JustAudioPlayerApi {
  RealJustAudioPlayer() : _player = ja.AudioPlayer();

  final ja.AudioPlayer _player;

  @override
  Future<void> setFilePath(String path) => _player.setFilePath(path);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> dispose() => _player.dispose();
}

/// Default [AudioSessionConfigurator]: configures `audio_session` for spoken
/// audio playback (speech preset -- appropriate for a kids reading app whose
/// audio is narration/phonics voice clips; it requests the platform's spoken
/// audio routing/interruption behavior). Wrapped in try/catch by the service,
/// so environments without platform channels are unaffected.
Future<void> defaultAudioSessionConfigurator() async {
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.speech());
}

/// One live (started, not yet finished) playback.
class _LivePlayback {
  _LivePlayback({required this.player, required this.channel});

  final JustAudioPlayerApi player;
  final AudioChannel channel;
}

/// Production `AudioService` backed by just_audio. See the library header for
/// the device-verified vs unit-tested split.
class JustAudioService implements AudioService {
  JustAudioService({
    required String? Function(AudioRef ref) resolveRef,
    AudioSessionConfigurator? sessionConfigurator,
    AudioPlayerFactory? playerFactory,
    DuckingPolicy duckingPolicy = const DuckingPolicy(),
    double duckedVolume = defaultDuckedVolume,
  })  : _resolveRef = resolveRef,
        _sessionConfigurator = sessionConfigurator ?? defaultAudioSessionConfigurator,
        _playerFactory = playerFactory ?? RealJustAudioPlayer.new,
        _duckingPolicy = duckingPolicy,
        _duckedVolume = duckedVolume;

  /// The gain a ducked channel's players are reduced to while a ducking clip
  /// is live. `DuckingPolicy` pins WHICH channels duck which but no gain
  /// value; 0.3 keeps ambient/celebration audible-but-clearly-behind help
  /// audio. Overridable via the constructor if the owner tunes it on device.
  static const double defaultDuckedVolume = 0.3;

  static const double _fullVolume = 1.0;

  final String? Function(AudioRef ref) _resolveRef;
  final AudioSessionConfigurator _sessionConfigurator;
  final AudioPlayerFactory _playerFactory;
  final DuckingPolicy _duckingPolicy;
  final double _duckedVolume;

  final Map<int, _LivePlayback> _live = {};
  final Map<int, Completer<void>> _completers = {};
  final Set<AudioChannel> _duckedChannels = {};
  int _nextId = 0;
  bool _sessionConfigureAttempted = false;

  @override
  Future<PlaybackHandle> play(AudioRef ref, {required AudioChannel channel}) async {
    // Resolve BEFORE any player (or session work) exists: an unknown ref is
    // a pack-integrity bug, thrown straight out of play()'s future.
    final path = _resolveRef(ref);
    if (path == null) {
      throw AudioRefNotFoundException(ref);
    }

    await _ensureSessionConfigured();

    final player = _playerFactory();
    final handle = PlaybackHandle(_nextId++);
    _live[handle.id] = _LivePlayback(player: player, channel: channel);

    // If this clip's own channel is already ducked (e.g. ambient starting
    // while help is live), it must start at the ducked gain, not full.
    if (_duckedChannels.contains(channel)) {
      unawaited(_safeSetVolume(player, _duckedVolume));
    }
    // Then recompute ducking with this clip counted as live. If this clip's
    // channel is only NOW becoming ducked, _recomputeDucking covers it (the
    // two branches are mutually exclusive, so volume is never set twice).
    _recomputeDucking();

    // Fire-and-forget the load+play chain: once the handle is returned, a
    // playback error must never throw out of play()'s future -- it just
    // completes the handle (same swallow-and-resume posture as
    // NarrationController).
    unawaited(_runPlayback(handle, player, path));
    return handle;
  }

  Future<void> _runPlayback(PlaybackHandle handle, JustAudioPlayerApi player, String path) async {
    try {
      await player.setFilePath(path);
      await player.play(); // Resolves on natural completion or stop().
    } catch (_) {
      // Swallowed by design: the handle completes below either way.
    } finally {
      await _finish(handle);
    }
  }

  @override
  Future<void> stop(PlaybackHandle handle) async {
    // _finish is a safe no-op for unknown/already-finished handles.
    await _finish(handle);
  }

  @override
  Future<void> completionOf(PlaybackHandle handle) {
    if (!_live.containsKey(handle.id)) {
      return Future.value(); // Unknown/finished handle: resolve immediately.
    }
    final completer = _completers.putIfAbsent(handle.id, Completer<void>.new);
    return completer.future;
  }

  /// Tears down [handle]'s playback: stops + disposes the player, recomputes
  /// ducking (restoring volume only when the LAST overlapping ducking clip
  /// has ended), and resolves `completionOf`. Idempotent -- the natural-end
  /// chain and an explicit `stop()` can both call it; the second is a no-op.
  Future<void> _finish(PlaybackHandle handle) async {
    final playback = _live.remove(handle.id);
    if (playback == null) {
      return;
    }
    try {
      await playback.player.stop();
    } catch (_) {
      // Teardown must never throw out of stop()/completion.
    }
    try {
      await playback.player.dispose();
    } catch (_) {
      // Ditto.
    }
    _recomputeDucking();
    _completers.remove(handle.id)?.complete();
  }

  /// Recomputes the set of ducked channels from the injected policy against
  /// currently-live channels, and applies only the DELTA: newly-ducked
  /// channels' live players drop to the ducked gain; channels no longer
  /// needing ducking are restored to full volume. Because the set is derived
  /// from all live clips, overlapping ducking clips naturally keep targets
  /// ducked until the last one ends.
  void _recomputeDucking() {
    final active = <AudioChannel>{for (final p in _live.values) p.channel};
    final needed = <AudioChannel>{};
    for (final channel in active) {
      needed.addAll(_duckingPolicy.channelsDuckedBy(channel));
    }

    final newlyDucked = needed.difference(_duckedChannels);
    final restored = _duckedChannels.difference(needed);
    _duckedChannels
      ..clear()
      ..addAll(needed);

    for (final playback in _live.values) {
      if (newlyDucked.contains(playback.channel)) {
        unawaited(_safeSetVolume(playback.player, _duckedVolume));
      } else if (restored.contains(playback.channel)) {
        unawaited(_safeSetVolume(playback.player, _fullVolume));
      }
    }
  }

  /// Configures the OS audio session once, before the first playback. Any
  /// throw (e.g. no platform channels in tests/headless runs) is swallowed
  /// and the attempt is not retried -- playback proceeds with platform
  /// defaults.
  Future<void> _ensureSessionConfigured() async {
    if (_sessionConfigureAttempted) {
      return;
    }
    _sessionConfigureAttempted = true;
    try {
      await _sessionConfigurator();
    } catch (_) {
      // Headless/test environments have no audio platform channels; playback
      // (real or faked) must still proceed.
    }
  }

  Future<void> _safeSetVolume(JustAudioPlayerApi player, double volume) async {
    try {
      await player.setVolume(volume);
    } catch (_) {
      // A volume failure must never break playback or teardown.
    }
  }
}

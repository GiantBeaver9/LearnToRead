import 'dart:async';

import 'audio_service.dart';
import 'ducking_policy.dart';

/// One entry in `FakeAudioService.callLog` (ticket audio-playback accept
/// entry 1: "FakeAudioService records an ordered log of play/stop/duck
/// calls with fake-clock timing"). Every subtype carries [timestamp] from
/// the service's injectable clock so ordering can be asserted from
/// timestamps alone, not just list position.
sealed class AudioCallLogEntry {
  const AudioCallLogEntry({required this.timestamp});

  final Duration timestamp;
}

/// Logged synchronously by every `play()` call that does not throw.
class PlayLogEntry extends AudioCallLogEntry {
  const PlayLogEntry({
    required this.ref,
    required this.channel,
    required this.handle,
    required super.timestamp,
  });

  final AudioRef ref;
  final AudioChannel channel;
  final PlaybackHandle handle;
}

/// Logged by an explicit `stop()` call. Never logged for a clip that ends
/// naturally via `completePlayback()` -- nothing called stop.
class StopLogEntry extends AudioCallLogEntry {
  const StopLogEntry({required this.handle, required super.timestamp});

  final PlaybackHandle handle;
}

/// Logged when starting playback on [byChannel] causes [duckedChannel] (a
/// currently-active channel named by the injected `DuckingPolicy`) to be
/// ducked. One entry per newly-ducked channel, never one per handle.
class DuckLogEntry extends AudioCallLogEntry {
  const DuckLogEntry({
    required this.duckedChannel,
    required this.byChannel,
    required super.timestamp,
  });

  final AudioChannel duckedChannel;
  final AudioChannel byChannel;
}

/// Logged when [channel] no longer needs to stay ducked (every channel that
/// was ducking it has ended) and [channel] itself is still active.
class UnduckLogEntry extends AudioCallLogEntry {
  const UnduckLogEntry({required this.channel, required super.timestamp});

  final AudioChannel channel;
}

/// A headless, in-memory `AudioService` for tests (ticket audio-playback
/// accept entry 1). Records every play/stop/duck/unduck call in order with
/// clock-stamped timestamps, and exposes `completePlayback` as test-control
/// for simulating a clip reaching its natural end.
///
/// Ducking is composed from the injected [DuckingPolicy] against which
/// channels currently have an active (unstopped, uncompleted) handle -- this
/// class never hardcodes the ducking rule itself.
class FakeAudioService implements AudioService {
  FakeAudioService({
    Set<AudioRef> missingRefs = const {},
    Duration Function()? clock,
    DuckingPolicy duckingPolicy = const DuckingPolicy(),
  })  : _missingRefs = missingRefs,
        _clock = clock ?? _defaultClock(),
        _duckingPolicy = duckingPolicy;

  final Set<AudioRef> _missingRefs;
  final Duration Function() _clock;
  final DuckingPolicy _duckingPolicy;

  final List<AudioCallLogEntry> _callLog = [];
  final Map<int, AudioChannel> _activeHandles = {};
  final Map<int, Completer<void>> _completers = {};
  final Set<AudioChannel> _duckedChannels = {};
  int _nextId = 0;

  /// An ordered, defensively-copied snapshot of every call this service has
  /// logged. Mutating the returned list never affects internal state.
  List<AudioCallLogEntry> get callLog => List.unmodifiable(_callLog);

  static Duration Function() _defaultClock() {
    final stopwatch = Stopwatch()..start();
    return () => stopwatch.elapsed;
  }

  void _append(AudioCallLogEntry Function(Duration timestamp) build) {
    _callLog.add(build(_clock()));
  }

  Set<AudioChannel> _activeChannels() => _activeHandles.values.toSet();

  Set<AudioChannel> _neededDuckTargets(Set<AudioChannel> active) {
    final needed = <AudioChannel>{};
    for (final channel in active) {
      needed.addAll(_duckingPolicy.channelsDuckedBy(channel));
    }
    return needed.intersection(active);
  }

  @override
  Future<PlaybackHandle> play(AudioRef ref, {required AudioChannel channel}) async {
    if (_missingRefs.contains(ref)) {
      throw AudioRefNotFoundException(ref);
    }

    final handle = PlaybackHandle(_nextId++);
    _activeHandles[handle.id] = channel;
    _append((ts) => PlayLogEntry(ref: ref, channel: channel, handle: handle, timestamp: ts));

    final active = _activeChannels();
    final needed = _neededDuckTargets(active);
    for (final target in needed.difference(_duckedChannels)) {
      _duckedChannels.add(target);
      _append((ts) => DuckLogEntry(duckedChannel: target, byChannel: channel, timestamp: ts));
    }

    return handle;
  }

  void _finish(PlaybackHandle handle, {required bool logStop}) {
    final channel = _activeHandles.remove(handle.id);
    if (channel == null) {
      return; // Unknown or already-finished handle: safe no-op.
    }

    if (logStop) {
      _append((ts) => StopLogEntry(handle: handle, timestamp: ts));
    }

    final active = _activeChannels();
    final needed = _neededDuckTargets(active);
    for (final target in _duckedChannels.difference(needed).toList()) {
      _duckedChannels.remove(target);
      if (active.contains(target)) {
        _append((ts) => UnduckLogEntry(channel: target, timestamp: ts));
      }
    }

    _completers.remove(handle.id)?.complete();
  }

  @override
  Future<void> stop(PlaybackHandle handle) async {
    _finish(handle, logStop: true);
  }

  /// Test-control hook: simulates [handle]'s clip reaching its natural end
  /// (as opposed to an explicit [stop]). Resolves `completionOf(handle)` the
  /// same way `stop` does, without logging a [StopLogEntry].
  void completePlayback(PlaybackHandle handle) {
    _finish(handle, logStop: false);
  }

  @override
  Future<void> completionOf(PlaybackHandle handle) {
    if (!_activeHandles.containsKey(handle.id)) {
      return Future.value();
    }
    final completer = _completers.putIfAbsent(handle.id, () => Completer<void>());
    return completer.future;
  }
}

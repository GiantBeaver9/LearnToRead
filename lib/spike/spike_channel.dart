// Unit 0 recognition spike — Dart-side platform channel wrapper.
//
// DISPOSABLE spike code (PRD.md §8 Unit 0). Talks to the native
// SpikeSpeechHandler (ios/Runner/SpikeSpeechHandler.swift,
// android/.../SpikeSpeechHandler.kt) over a method channel (start/stop) and
// an event channel (streamed hypotheses). The wire contract here — channel
// names, method names, payload shapes — is pinned by
// test/spike/spike_channel_test.dart and test/spike/hypothesis_log_test.dart
// and mirrored in the native handler doc comments; do not change one side
// without the other.

import 'package:flutter/services.dart';

import 'hypothesis_log.dart';

/// Thrown when the platform side reports an error, either from a method
/// call (`start`/`stop`) or as an error event on the hypothesis stream.
/// Wraps the underlying [PlatformException] so callers never see a raw
/// platform exception from [SpikeChannel].
class SpikeChannelException implements Exception {
  const SpikeChannelException({required this.code, this.message});

  /// The platform error code (e.g. `MIC_PERMISSION_DENIED`,
  /// `ENGINE_UNAVAILABLE`, `STOP_FAILED`).
  final String code;

  /// A human-readable detail message, if the platform provided one.
  final String? message;

  @override
  String toString() => 'SpikeChannelException($code${message != null ? ': $message' : ''})';
}

/// Dart-side wrapper around the Unit 0 spike's platform channels.
///
/// - Method channel [methodChannelName]: `start` (with `sentence` and
///   `biasingWords` arguments) and `stop`.
/// - Event channel [eventChannelName]: streams raw hypothesis payloads,
///   decoded here into [HypothesisEvent]s.
class SpikeChannel {
  const SpikeChannel();

  /// Method channel name shared with the native handlers. Must match
  /// SpikeSpeechHandler.swift / SpikeSpeechHandler.kt exactly.
  static const String methodChannelName = 'learn_to_read/spike/method';

  /// Event channel name shared with the native handlers. Must match
  /// SpikeSpeechHandler.swift / SpikeSpeechHandler.kt exactly.
  static const String eventChannelName = 'learn_to_read/spike/events';

  static const MethodChannel _methodChannel = MethodChannel(methodChannelName);
  static const EventChannel _eventChannel = EventChannel(eventChannelName);

  /// Starts on-device recognition with contextual biasing set to
  /// [biasingWords] (the hardcoded sentence's words; see
  /// spikeBiasingWordsFor in spike_screen.dart).
  Future<void> start({required String sentence, required List<String> biasingWords}) async {
    try {
      await _methodChannel.invokeMethod<void>('start', <String, Object?>{
        'sentence': sentence,
        'biasingWords': biasingWords,
      });
    } on PlatformException catch (e) {
      throw SpikeChannelException(code: e.code, message: e.message);
    }
  }

  /// Stops on-device recognition.
  Future<void> stop() async {
    try {
      await _methodChannel.invokeMethod<void>('stop');
    } on PlatformException catch (e) {
      throw SpikeChannelException(code: e.code, message: e.message);
    }
  }

  /// A stream of decoded hypothesis events from the platform recognizer.
  /// Platform-side errors surface as [SpikeChannelException], never as a
  /// raw [PlatformException].
  ///
  /// Implemented as a synchronous `map`/`handleError` transform (not an
  /// `async*` generator) deliberately: `async*` schedules each yielded
  /// value via a microtask, adding a scheduling hop between a platform
  /// event arriving and a listener's callback running. In a single-`pump()`
  /// widget test that hop can land after that pump's build phase, so a
  /// `setState` triggered by the event doesn't show up until a second
  /// pump. `map`/`handleError` forward events synchronously within the
  /// same microtask instead.
  Stream<HypothesisEvent> hypotheses() {
    return _eventChannel
        .receiveBroadcastStream()
        .map<HypothesisEvent>(
          (dynamic raw) => HypothesisEvent.fromChannelPayload(raw as Map<Object?, Object?>),
        )
        .handleError((Object error, StackTrace stackTrace) {
          if (error is PlatformException) {
            throw SpikeChannelException(code: error.code, message: error.message);
          }
          throw error;
        });
  }
}

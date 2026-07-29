// PlatformAsrEngine — Dart-side adapter tests (PRD §9 A-10;
// platform-asr-adapter).
//
// Pins the wire contract of lib/features/listening/engine/
// platform_asr_engine.dart against the native AsrSpeechHandler.kt:
// channel names, method names, payload shapes, and the AsrEngine stream
// semantics the app shell depends on (sharedAsrEngineProvider's header:
// a real engine hands back the SAME long-lived stream on every access,
// alive across stop/start cycles).
//
// All platform interaction is via Flutter's standard mock-messenger hooks
// (TestDefaultBinaryMessengerBinding) — no native code runs in this
// container. Actual recognition quality on a device is a [DEVICE] task; see
// docs/platform-asr-adapter.md.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/engine/platform_asr_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel(PlatformAsrEngine.methodChannelName);
  const eventChannel = EventChannel(PlatformAsrEngine.eventChannelName);

  TestDefaultBinaryMessengerBinding messenger() =>
      TestDefaultBinaryMessengerBinding.instance;

  tearDown(() {
    messenger().defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
    messenger().defaultBinaryMessenger
        .setMockStreamHandler(eventChannel, null);
  });

  /// Mocks the method channel, recording every call.
  List<MethodCall> mockMethods() {
    final calls = <MethodCall>[];
    messenger().defaultBinaryMessenger.setMockMethodCallHandler(
      methodChannel,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    return calls;
  }

  /// Mocks the event channel, exposing the sink once the engine subscribes.
  ///
  /// The sink arrives asynchronously (on the engine's first start); await
  /// [pumpEventQueue] after start() before pushing events through it.
  MockStreamHandlerEventSink? capturedSink;
  void mockEvents() {
    capturedSink = null;
    messenger().defaultBinaryMessenger.setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(
        onListen: (Object? arguments, MockStreamHandlerEventSink events) {
          capturedSink = events;
        },
      ),
    );
  }

  group('channel identity', () {
    test('production channel names are fixed, distinct, and not the spike\'s',
        () {
      expect(
        PlatformAsrEngine.methodChannelName,
        'learn_to_read/asr/method',
      );
      expect(
        PlatformAsrEngine.eventChannelName,
        'learn_to_read/asr/events',
      );
      expect(
        PlatformAsrEngine.methodChannelName,
        isNot(PlatformAsrEngine.eventChannelName),
      );
    });
  });

  group('start — positive', () {
    test('invokes "start" with the biasing words (expected-text hybrid)',
        () async {
      final calls = mockMethods();
      mockEvents();
      final engine = PlatformAsrEngine();

      engine.start(const ['the', 'cat', 'sat']);
      await pumpEventQueue();

      expect(calls, hasLength(1));
      expect(calls.single.method, 'start');
      final args = calls.single.arguments as Map;
      expect(args['biasingWords'], ['the', 'cat', 'sat']);

      engine.dispose();
    });

    test('an empty biasing context is still sent (edge)', () async {
      final calls = mockMethods();
      mockEvents();
      final engine = PlatformAsrEngine();

      engine.start(const <String>[]);
      await pumpEventQueue();

      expect(calls.single.method, 'start');
      expect((calls.single.arguments as Map)['biasingWords'], isEmpty);

      engine.dispose();
    });
  });

  group('hypotheses — payload mapping (positive)', () {
    test('partial and final payloads both map to Hypothesis in order, '
        'alternatives preserved best-first, phoneHypotheses null', () async {
      mockMethods();
      mockEvents();
      final engine = PlatformAsrEngine();
      final received = <Hypothesis>[];
      engine.hypothesesStream.listen(received.add);

      engine.start(const ['the', 'cat']);
      await pumpEventQueue();
      expect(capturedSink, isNotNull);

      // A partial burst...
      capturedSink!.success(<String, Object?>{
        'words': <String>['the'],
        'isFinal': false,
      });
      // ...then a final burst with multiple ranked alternatives.
      capturedSink!.success(<String, Object?>{
        'words': <String>['the cat', 'the can', 'a cat'],
        'isFinal': true,
      });
      await pumpEventQueue();

      expect(received, const [
        Hypothesis(wordHypotheses: ['the'], phoneHypotheses: null),
        Hypothesis(
          wordHypotheses: ['the cat', 'the can', 'a cat'],
          phoneHypotheses: null,
        ),
      ]);

      engine.dispose();
    });

    test('malformed payloads are dropped, not errored (negative)', () async {
      mockMethods();
      mockEvents();
      final engine = PlatformAsrEngine();
      final received = <Hypothesis>[];
      final errors = <Object>[];
      engine.hypothesesStream.listen(received.add, onError: errors.add);

      engine.start(const ['cat']);
      await pumpEventQueue();

      capturedSink!.success('not a map');
      capturedSink!.success(<String, Object?>{'isFinal': true}); // no words
      capturedSink!.success(<String, Object?>{
        'words': <String>[], // empty burst
        'isFinal': false,
      });
      capturedSink!.success(<String, Object?>{
        'words': <String>['cat'],
        'isFinal': true,
      });
      await pumpEventQueue();

      expect(errors, isEmpty);
      expect(received, const [
        Hypothesis(wordHypotheses: ['cat'], phoneHypotheses: null),
      ]);

      engine.dispose();
    });
  });

  group('stream identity — sharedAsrEngineProvider contract', () {
    test('hypothesesStream is the SAME object on every access', () {
      final engine = PlatformAsrEngine();
      expect(
        identical(engine.hypothesesStream, engine.hypothesesStream),
        isTrue,
      );
      engine.dispose();
    });

    test('the stream object survives start/stop cycles', () async {
      mockMethods();
      mockEvents();
      final engine = PlatformAsrEngine();
      final before = engine.hypothesesStream;

      engine.start(const ['cat']);
      await pumpEventQueue();
      engine.stop();
      await pumpEventQueue();

      expect(identical(before, engine.hypothesesStream), isTrue);

      engine.dispose();
    });
  });

  group('stop — positive', () {
    test('invokes "stop" natively and keeps the stream alive', () async {
      final calls = mockMethods();
      mockEvents();
      final engine = PlatformAsrEngine();
      var done = false;
      engine.hypothesesStream.listen((_) {}, onDone: () => done = true);

      engine.start(const ['cat']);
      await pumpEventQueue();
      engine.stop();
      await pumpEventQueue();

      expect(calls.map((c) => c.method), ['start', 'stop']);
      expect(done, isFalse, reason: 'stop must not close the stream');

      engine.dispose();
    });
  });

  group('restart — a second start() after stop() works', () {
    test('start/stop/start reaches the platform in order and hypotheses '
        'flow after the restart', () async {
      final calls = mockMethods();
      mockEvents();
      final engine = PlatformAsrEngine();
      final received = <Hypothesis>[];
      engine.hypothesesStream.listen(received.add);

      engine.start(const ['the', 'cat']);
      await pumpEventQueue();
      engine.stop();
      await pumpEventQueue();
      engine.start(const ['sat', 'down']);
      await pumpEventQueue();

      expect(calls.map((c) => c.method), ['start', 'stop', 'start']);
      expect((calls.last.arguments as Map)['biasingWords'], ['sat', 'down']);

      capturedSink!.success(<String, Object?>{
        'words': <String>['sat'],
        'isFinal': true,
      });
      await pumpEventQueue();

      expect(received, const [
        Hypothesis(wordHypotheses: ['sat'], phoneHypotheses: null),
      ]);

      engine.dispose();
    });
  });

  group('errors — the tracker owns fallback policy (negative)', () {
    test('a platform error event is forwarded as a stream error and the '
        'stream stays alive for later hypotheses', () async {
      mockMethods();
      mockEvents();
      final engine = PlatformAsrEngine();
      final received = <Hypothesis>[];
      final errors = <Object>[];
      var done = false;
      engine.hypothesesStream.listen(
        received.add,
        onError: errors.add,
        onDone: () => done = true,
      );

      engine.start(const ['cat']);
      await pumpEventQueue();

      capturedSink!.error(
        code: 'ENGINE_UNAVAILABLE',
        message: 'recognizer gave up',
      );
      await pumpEventQueue();

      expect(errors, hasLength(1));
      expect(
        errors.single,
        isA<PlatformException>()
            .having((e) => e.code, 'code', 'ENGINE_UNAVAILABLE'),
      );
      expect(done, isFalse, reason: 'an error event must not close the stream');

      // The stream is still live: a later burst (post-restart) still arrives.
      capturedSink!.success(<String, Object?>{
        'words': <String>['cat'],
        'isFinal': true,
      });
      await pumpEventQueue();
      expect(received, const [
        Hypothesis(wordHypotheses: ['cat'], phoneHypotheses: null),
      ]);

      engine.dispose();
    });

    test('a PlatformException from the start call itself surfaces as a '
        'stream error, never a throw (the tracker degrades to tap)', () async {
      messenger().defaultBinaryMessenger.setMockMethodCallHandler(
        methodChannel,
        (call) async {
          if (call.method == 'start') {
            throw PlatformException(
              code: 'ENGINE_UNAVAILABLE',
              message: 'no recognition service',
            );
          }
          return null;
        },
      );
      mockEvents();
      final engine = PlatformAsrEngine();
      final errors = <Object>[];
      var done = false;
      engine.hypothesesStream.listen(
        (_) {},
        onError: errors.add,
        onDone: () => done = true,
      );

      engine.start(const ['cat']); // must not throw
      await pumpEventQueue();

      expect(errors, hasLength(1));
      expect(
        errors.single,
        isA<PlatformException>()
            .having((e) => e.code, 'code', 'ENGINE_UNAVAILABLE'),
      );
      expect(done, isFalse);

      engine.dispose();
    });
  });

  group('MissingPluginException — non-Android host is silent-safe (edge)', () {
    test('with no native handler at all, start/stop succeed silently and '
        'the stream stays open and empty', () async {
      // Deliberately NO mock handlers: every channel interaction raises
      // MissingPluginException, exactly as on desktop/test hosts.
      final engine = PlatformAsrEngine();
      final received = <Hypothesis>[];
      final errors = <Object>[];
      var done = false;
      engine.hypothesesStream.listen(
        received.add,
        onError: errors.add,
        onDone: () => done = true,
      );

      engine.start(const ['the', 'cat']); // must not throw
      await pumpEventQueue();
      engine.stop(); // must not throw
      await pumpEventQueue();
      engine.start(const ['again']); // restart is equally safe
      await pumpEventQueue();

      expect(received, isEmpty);
      expect(errors, isEmpty,
          reason: 'MissingPluginException must be swallowed, not forwarded');
      expect(done, isFalse);

      engine.dispose();
    });
  });
}

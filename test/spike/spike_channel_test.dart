// Unit 0 recognition spike — platform-channel + UI smoke tests.
//
// Pins the interface of:
//   - lib/spike/spike_channel.dart (SpikeChannel, SpikeChannelException)
//   - lib/spike/spike_screen.dart (kSpikeSentence, spikeBiasingWordsFor,
//     the spike*Key widget keys, SpikeScreen)
//   - lib/spike/spike_main.dart (SpikeApp)
//
// All platform interaction is via Flutter's standard MethodChannel /
// EventChannel mock-messenger testing hooks (TestDefaultBinaryMessengerBinding
// .setMockMethodCallHandler / .setMockStreamHandler) — no native code runs in
// this container, so no plugin registration or physical mic is required.
//
// This file is TEST-ONLY; the lib/spike/* implementation files do not exist
// yet. These tests are expected to fail to compile/run until they are
// implemented, pinning the exact Dart-side API and channel wire contract.
//
// Ticket accepts covered here:
//   - "A separate Flutter entrypoint ... shows a bare-bones screen with one
//     hardcoded sentence, a mic start/stop control, and a live scrolling
//     view of raw hypotheses." (UI smoke, mocked channel)
//   - "spike_channel.dart streams hypotheses from a platform event channel
//     fed by the on-device recognizer ... with contextual biasing set to the
//     hardcoded sentence's words; Dart-side behavior verified headlessly
//     with a mocked platform channel emitting scripted hypothesis payloads."
//
// PRD refs: §8 Unit 0, §9 A-10, §7 R1.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/spike/hypothesis_log.dart';
import 'package:learn_to_read/spike/spike_channel.dart';
import 'package:learn_to_read/spike/spike_main.dart';
import 'package:learn_to_read/spike/spike_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final methodChannel = MethodChannel(SpikeChannel.methodChannelName);
  final eventChannel = EventChannel(SpikeChannel.eventChannelName);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(eventChannel, null);
  });

  group('SpikeChannel — channel identity', () {
    test('method and event channel names are fixed, distinct strings', () {
      expect(SpikeChannel.methodChannelName, isNotEmpty);
      expect(SpikeChannel.eventChannelName, isNotEmpty);
      expect(SpikeChannel.methodChannelName, isNot(SpikeChannel.eventChannelName));
    });
  });

  group('SpikeChannel.start — positive', () {
    test('invokes "start" on the method channel with sentence + biasingWords', () async {
      MethodCall? captured;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
        captured = call;
        return null;
      });

      const channel = SpikeChannel();
      await channel.start(
        sentence: 'The quick fox runs.',
        biasingWords: const ['the', 'quick', 'fox', 'runs'],
      );

      expect(captured, isNotNull);
      expect(captured!.method, 'start');
      final args = captured!.arguments as Map;
      expect(args['sentence'], 'The quick fox runs.');
      expect(args['biasingWords'], ['the', 'quick', 'fox', 'runs']);
    });
  });

  group('SpikeChannel.stop — positive', () {
    test('invokes "stop" on the method channel', () async {
      MethodCall? captured;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
        captured = call;
        return null;
      });

      const channel = SpikeChannel();
      await channel.stop();

      expect(captured, isNotNull);
      expect(captured!.method, 'stop');
    });
  });

  group('SpikeChannel — error propagation (negative)', () {
    test('start() wraps a PlatformException from the platform as SpikeChannelException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
        throw PlatformException(code: 'MIC_PERMISSION_DENIED', message: 'no mic access');
      });

      const channel = SpikeChannel();

      await expectLater(
        () => channel.start(sentence: 'S', biasingWords: const ['s']),
        throwsA(
          isA<SpikeChannelException>().having((e) => e.code, 'code', 'MIC_PERMISSION_DENIED'),
        ),
      );
    });

    test('stop() wraps a PlatformException from the platform as SpikeChannelException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
        throw PlatformException(code: 'STOP_FAILED', message: 'engine already stopped');
      });

      const channel = SpikeChannel();

      await expectLater(
        () => channel.stop(),
        throwsA(isA<SpikeChannelException>().having((e) => e.code, 'code', 'STOP_FAILED')),
      );
    });
  });

  group('SpikeChannel.hypotheses — positive stream decoding', () {
    test('a single scripted final-hypothesis event decodes on the stream', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (Object? arguments, MockStreamHandlerEventSink events) {
            events.success(<String, Object?>{
              'isFinal': true,
              'text': 'the quick fox runs',
              'confidence': 0.9,
              'biasingWords': <String>['the', 'quick', 'fox', 'runs'],
            });
            events.endOfStream();
          },
        ),
      );

      const channel = SpikeChannel();
      final received = await channel.hypotheses().toList();

      expect(received, hasLength(1));
      expect(received.single, isA<HypothesisEvent>());
      expect(received.single.text, 'the quick fox runs');
      expect(received.single.isFinal, isTrue);
      expect(received.single.confidence, 0.9);
    });

    test('scripted partial-then-final events decode in order', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (Object? arguments, MockStreamHandlerEventSink events) {
            events.success(<String, Object?>{'isFinal': false, 'text': 'the'});
            events.success(<String, Object?>{'isFinal': false, 'text': 'the quick'});
            events.success(<String, Object?>{'isFinal': true, 'text': 'the quick fox runs'});
            events.endOfStream();
          },
        ),
      );

      const channel = SpikeChannel();
      final received = await channel.hypotheses().toList();

      expect(received.map((e) => e.text).toList(), [
        'the',
        'the quick',
        'the quick fox runs',
      ]);
      expect(received.map((e) => e.isFinal).toList(), [false, false, true]);
    });

    test('a scripted event with phoneDetail decodes phoneDetailPresent true', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (Object? arguments, MockStreamHandlerEventSink events) {
            events.success(<String, Object?>{
              'isFinal': true,
              'text': 'sh sh sh',
              'phoneDetail': <Map<String, Object?>>[
                {'phone': 'SH', 'confidence': 0.3},
              ],
            });
            events.endOfStream();
          },
        ),
      );

      const channel = SpikeChannel();
      final received = await channel.hypotheses().toList();

      expect(received.single.phoneDetailPresent, isTrue);
    });
  });

  group('SpikeChannel.hypotheses — error propagation (negative)', () {
    test('a platform error event surfaces as SpikeChannelException, not a raw PlatformException', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (Object? arguments, MockStreamHandlerEventSink events) {
            events.error(code: 'ENGINE_UNAVAILABLE', message: 'recognizer unavailable');
          },
        ),
      );

      const channel = SpikeChannel();

      await expectLater(
        channel.hypotheses(),
        emitsError(
          isA<SpikeChannelException>().having((e) => e.code, 'code', 'ENGINE_UNAVAILABLE'),
        ),
      );
    });
  });

  group('spikeBiasingWordsFor — hardcoded-sentence config (positive/negative/edge)', () {
    test('splits a plain sentence into its words', () {
      expect(
        spikeBiasingWordsFor('The quick fox runs'),
        ['The', 'quick', 'fox', 'runs'],
      );
    });

    test('strips trailing sentence punctuation from words', () {
      expect(
        spikeBiasingWordsFor('The quick fox runs.'),
        ['The', 'quick', 'fox', 'runs'],
      );
    });

    test('collapses repeated whitespace between words (edge)', () {
      expect(
        spikeBiasingWordsFor('The   quick  fox runs.'),
        ['The', 'quick', 'fox', 'runs'],
      );
    });

    test('empty sentence yields an empty biasing list (edge)', () {
      expect(spikeBiasingWordsFor(''), isEmpty);
    });

    test('kSpikeSentence itself yields a non-empty biasing word list', () {
      expect(kSpikeSentence, isNotEmpty);
      expect(spikeBiasingWordsFor(kSpikeSentence), isNotEmpty);
    });
  });

  group('SpikeScreen — UI smoke (mocked channel via TestDefaultBinaryMessenger)', () {
    Future<void> mockSilentChannels(WidgetTester tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async => null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(onListen: (Object? arguments, MockStreamHandlerEventSink events) {}),
      );
    }

    testWidgets('renders the hardcoded sentence and a record button', (tester) async {
      await mockSilentChannels(tester);

      await tester.pumpWidget(const MaterialApp(home: SpikeScreen()));
      await tester.pump();

      expect(find.byKey(spikeSentenceTextKey), findsOneWidget);
      expect(find.text(kSpikeSentence), findsOneWidget);
      expect(find.byKey(spikeRecordButtonKey), findsOneWidget);
      expect(find.byKey(spikeHypothesisListKey), findsOneWidget);
    });

    testWidgets('renders with an empty hypothesis list and no crash when nothing has arrived (edge)', (
      tester,
    ) async {
      await mockSilentChannels(tester);

      await tester.pumpWidget(const MaterialApp(home: SpikeScreen()));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byKey(spikeHypothesisListKey), findsOneWidget);
    });

    testWidgets('tapping the record button starts, then stops, the platform channel', (tester) async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
        calls.add(call.method);
        return null;
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(onListen: (Object? arguments, MockStreamHandlerEventSink events) {}),
      );

      await tester.pumpWidget(const MaterialApp(home: SpikeScreen()));
      await tester.pump();

      await tester.tap(find.byKey(spikeRecordButtonKey));
      await tester.pumpAndSettle();
      expect(calls, contains('start'));

      await tester.tap(find.byKey(spikeRecordButtonKey));
      await tester.pumpAndSettle();
      expect(calls, containsAllInOrder(['start', 'stop']));
    });

    testWidgets('a live hypothesis pushed on the event channel appears in the scrolling view', (
      tester,
    ) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async => null);

      late MockStreamHandlerEventSink sink;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (Object? arguments, MockStreamHandlerEventSink events) {
            sink = events;
          },
        ),
      );

      await tester.pumpWidget(const MaterialApp(home: SpikeScreen()));
      await tester.pump();

      sink.success(<String, Object?>{'isFinal': false, 'text': 'zebra-hypothesis-marker'});
      await tester.pump();

      expect(find.textContaining('zebra-hypothesis-marker'), findsOneWidget);
    });
  });

  group('SpikeApp — entrypoint UI smoke (lib/spike/spike_main.dart)', () {
    testWidgets('boots to a MaterialApp showing the spike screen sentence', (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async => null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(onListen: (Object? arguments, MockStreamHandlerEventSink events) {}),
      );

      await tester.pumpWidget(const SpikeApp());
      await tester.pump();

      expect(find.byType(MaterialApp), findsOneWidget);
      expect(find.text(kSpikeSentence), findsOneWidget);
    });
  });

  group('documentation accept — not code-testable, skipped with reason', () {
    test(
      'docs/spike/README.md tells the owner how to run the spike, register native '
      'handlers, collect >= 3 sessions, and where the verdict goes',
      () {},
      skip:
          'Prose/documentation content, not Dart behavior — there is no Dart API to pin '
          'and asserting on doc substrings would test wording, not code. Verified by '
          'human review of docs/spike/README.md during PR review, not by flutter test.',
    );
  });

  group('[DEVICE] not testable headlessly — skipped with reason', () {
    test(
      'iOS SFSpeechRecognizer contextualStrings wiring produces real hypotheses from live audio',
      () {},
      skip:
          'DEVICE: requires a physical iOS device, microphone input, and the native '
          'SpikeSpeechHandler.swift registered per docs/spike/README.md. The Dart-side '
          'decode/contract for hypotheses fed by this handler is covered above with a '
          'mocked EventChannel; only real audio capture + native recognizer output is '
          'untestable in this container.',
    );

    test(
      'Android SpeechRecognizer biasing wiring produces real hypotheses from live audio',
      () {},
      skip:
          'DEVICE: requires a physical Android device, microphone input, and the native '
          'SpikeSpeechHandler.kt registered per docs/spike/README.md. The Dart-side '
          'decode/contract for hypotheses fed by this handler is covered above with a '
          'mocked EventChannel; only real audio capture + native recognizer output is '
          'untestable in this container.',
    );

    test(
      '>= 3 real children\'s logged sessions and the written keep/swap/hybrid verdict '
      '(go/no-go on A-10 and on phone-level availability)',
      () {},
      skip:
          'DEVICE + OWNER-COORDINATED: requires a physical device and real children with '
          'parental permission (per ticket notes); the verdict document is an explicit '
          'OWNER deliverable, not this ticket\'s. Not fakeable headlessly — this is the '
          'entire point of the spike being owner-run.',
    );
  });
}

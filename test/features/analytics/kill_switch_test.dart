/// Unit tests for the analytics kill switch (PRD §8 Unit 12: "A single
/// build flag disables all analytics"; accept: "Kill-switch build emits
/// zero network calls to the analytics endpoint (network-recording
/// test)... the client becomes a no-op").
///
/// AnalyticsClient is exercised end-to-end (client -> queue -> transport)
/// against a real, temp-dir-backed EventQueue and a recording fake
/// transport, so the "zero network calls" claim is verified for the full
/// pipeline, not just one layer in isolation. No real network is
/// involved anywhere — the transport is a fake.
///
/// Imports lib/features/analytics/{events,event_schema,event_queue,
/// transport,analytics_client}.dart, none of which exist yet: this file
/// fails to compile until they exist — the expected red state.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/features/analytics/analytics_client.dart';
import 'package:learn_to_read/features/analytics/event_queue.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/analytics/events.dart';
import 'package:learn_to_read/features/analytics/transport.dart';

class _FakeClock {
  _FakeClock(this._now);
  DateTime _now;
  DateTime call() => _now;
}

class _RecordingTransport implements AnalyticsTransport {
  final List<List<Map<String, Object?>>> calls = [];

  @override
  Future<TransportResult> send(List<Map<String, Object?>> batch) async {
    calls.add(batch);
    return TransportResult.success;
  }
}

AnalyticsEvent _sessionStartEvent() => AnalyticsEvent(
      name: AnalyticsEventName.sessionStart,
      timestamp: DateTime.utc(2026, 1, 1),
      installId: 'a1b2c3d4-1234-4abc-8def-0123456789ab',
      profileOrdinal: 1,
      levelOrdinal: 1,
    );

AnalyticsEvent _wordReadEvent() => AnalyticsEvent(
      name: AnalyticsEventName.wordRead,
      timestamp: DateTime.utc(2026, 1, 1),
      installId: 'a1b2c3d4-1234-4abc-8def-0123456789ab',
      profileOrdinal: 1,
      levelOrdinal: 1,
      storyId: 's1',
      fields: {
        'result': WordReadResult.correct.wireValue,
        'wordHash': hashWord('cat'),
      },
    );

void main() {
  late Directory tempDir;
  late _RecordingTransport transport;
  late EventQueue queue;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('kill_switch_test_');
    transport = _RecordingTransport();
    queue = EventQueue(
      transport: transport,
      clock: _FakeClock(DateTime.utc(2026, 1, 1)),
      storageDirectory: tempDir,
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('POSITIVE control: with the kill switch OFF, a tracked event '
      'really does reach the transport (proves the harness works and '
      'the negative tests below are not vacuously true)', () {
    test('enabled client: track + flush reaches the fake transport',
        () async {
      final client = AnalyticsClient(enabled: true, queue: queue);

      await client.track(_sessionStartEvent());
      await client.flush();

      expect(transport.calls, isNotEmpty);
      expect(transport.calls.single.single['event'], 'session_start');
    });
  });

  group('KILL SWITCH ON: zero network calls, client is a no-op', () {
    test('track() on a disabled client never reaches the transport, even '
        'after an explicit flush()', () async {
      final client = AnalyticsClient(enabled: false, queue: queue);

      await client.track(_sessionStartEvent());
      await client.track(_wordReadEvent());
      await client.flush();

      expect(transport.calls, isEmpty);
    });

    test('track() on a disabled client does not even persist to the '
        'offline queue (a true no-op, not just "queued but never sent")',
        () async {
      final client = AnalyticsClient(enabled: false, queue: queue);

      await client.track(_sessionStartEvent());

      expect(await queue.pendingEvents(), isEmpty);
    });

    test('flush() on a disabled client is itself a no-op and touches '
        'neither the queue nor the transport', () async {
      final client = AnalyticsClient(enabled: false, queue: queue);

      await client.flush();

      expect(transport.calls, isEmpty);
      expect(await queue.pendingEvents(), isEmpty);
    });

    test('many repeated track() calls on a disabled client accumulate '
        'zero network calls (not just the first call)', () async {
      final client = AnalyticsClient(enabled: false, queue: queue);

      for (var i = 0; i < 25; i++) {
        await client.track(_wordReadEvent());
      }
      await client.flush();

      expect(transport.calls, isEmpty);
      expect(await queue.pendingEvents(), isEmpty);
    });

    test('EDGE: a disabled client does not throw even when handed a '
        'structurally malformed event — the kill switch short-circuits '
        'before schema validation runs', () async {
      final malformed = AnalyticsEvent(
        name: AnalyticsEventName.wordRead,
        timestamp: DateTime.utc(2026, 1, 1),
        installId: 'not-a-valid-uuid-at-all',
        profileOrdinal: 99, // out of the pinned 1-4 range
        levelOrdinal: -1,
        // missing required word_read fields (result, wordHash) entirely
      );
      final client = AnalyticsClient(enabled: false, queue: queue);

      await expectLater(client.track(malformed), completes);
      expect(transport.calls, isEmpty);
    });

    test('EDGE: AnalyticsClient.enabled reports false when constructed '
        'with the kill switch on', () {
      final client = AnalyticsClient(enabled: false, queue: queue);
      expect(client.enabled, isFalse);
    });
  });

  group('EDGE: AnalyticsClient.enabled reports true when the kill switch '
      'is off', () {
    test('enabled getter reflects the constructor flag', () {
      final client = AnalyticsClient(enabled: true, queue: queue);
      expect(client.enabled, isTrue);
    });
  });
}

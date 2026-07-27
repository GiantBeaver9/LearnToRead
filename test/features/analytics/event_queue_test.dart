/// Unit tests for the offline analytics event queue (PRD §8 Unit 12:
/// "Offline queue: events queue when transport unavailable, flush in
/// batches over HTTPS when available... events unsent after 30 days are
/// DROPPED, verified with clock manipulation").
///
/// Covers: event_queue.dart against a recording fake transport
/// (transport.dart's AnalyticsTransport interface) and a real, temp-dir
/// backed file store (per the ticket's notes: "Queue persistence: use its
/// own small file-based store via path_provider-injected directory...
/// injection makes tests temp-dir based"). No real network, no real
/// timers — the transport is a fake and the clock is injected.
///
/// Imports lib/features/analytics/{events,event_schema,event_queue,
/// transport}.dart, none of which exist yet: this file fails to compile
/// until they exist — the expected red state.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/features/analytics/event_queue.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/analytics/events.dart';
import 'package:learn_to_read/features/analytics/transport.dart';

/// A settable fake clock usable directly as a [Clock] (`DateTime
/// Function()`) via `call()`.
class _FakeClock {
  _FakeClock(this._now);
  DateTime _now;
  DateTime call() => _now;
  void advance(Duration d) => _now = _now.add(d);
}

/// Records every batch handed to it; `online` toggles whether sends
/// succeed (simulating airplane-mode on/off).
class _RecordingTransport implements AnalyticsTransport {
  bool online = true;
  final List<List<Map<String, Object?>>> calls = [];

  @override
  Future<TransportResult> send(List<Map<String, Object?>> batch) async {
    calls.add(batch);
    return online ? TransportResult.success : TransportResult.failure;
  }
}

/// Succeeds for the first [succeedForFirstNCalls] calls, then fails —
/// simulates connectivity dropping mid-flush across multiple batches.
class _FlakyTransport implements AnalyticsTransport {
  _FlakyTransport({required this.succeedForFirstNCalls});
  final int succeedForFirstNCalls;
  final List<List<Map<String, Object?>>> calls = [];

  @override
  Future<TransportResult> send(List<Map<String, Object?>> batch) async {
    calls.add(batch);
    return calls.length <= succeedForFirstNCalls
        ? TransportResult.success
        : TransportResult.failure;
  }
}

Map<String, Object?> _payload({
  required DateTime timestamp,
  String storyId = 's1',
  AnalyticsEventName name = AnalyticsEventName.storyCompleted,
}) {
  return AnalyticsEvent(
    name: name,
    timestamp: timestamp,
    installId: 'a1b2c3d4-1234-4abc-8def-0123456789ab',
    profileOrdinal: 1,
    levelOrdinal: 1,
    storyId: storyId,
  ).toPayload();
}

void main() {
  late Directory tempDir;
  late _FakeClock clock;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('event_queue_test_');
    clock = _FakeClock(DateTime.utc(2026, 1, 1));
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('POSITIVE: enqueue never touches the transport by itself', () {
    test('enqueue() alone (no flush) makes zero transport calls', () async {
      final transport = _RecordingTransport();
      final queue = EventQueue(
        transport: transport,
        clock: clock,
        storageDirectory: tempDir,
      );

      await queue.enqueue(_payload(timestamp: clock()));

      expect(transport.calls, isEmpty);
      expect(await queue.pendingEvents(), hasLength(1));
    });
  });

  group('POSITIVE/NEGATIVE: offline queue, online flush', () {
    test('events enqueued while transport is offline remain queued after '
        'a failed flush attempt (airplane mode)', () async {
      final transport = _RecordingTransport()..online = false;
      final queue = EventQueue(
        transport: transport,
        clock: clock,
        storageDirectory: tempDir,
      );

      await queue.enqueue(_payload(timestamp: clock(), storyId: 's1'));
      await queue.enqueue(_payload(timestamp: clock(), storyId: 's2'));

      final result = await queue.flush();

      expect(transport.calls, isNotEmpty, reason: 'a send should be attempted');
      expect(result.sent, 0);
      expect(await queue.pendingEvents(), hasLength(2));
    });

    test('flushing after transport comes back online sends the queued '
        'batch and clears it (airplane mode toggled off)', () async {
      final transport = _RecordingTransport()..online = false;
      final queue = EventQueue(
        transport: transport,
        clock: clock,
        storageDirectory: tempDir,
      );

      await queue.enqueue(_payload(timestamp: clock(), storyId: 's1'));
      await queue.enqueue(_payload(timestamp: clock(), storyId: 's2'));
      await queue.flush(); // still offline: no-op beyond the attempt

      transport.online = true;
      final result = await queue.flush();

      expect(result.sent, 2);
      expect(result.dropped, 0);
      expect(await queue.pendingEvents(), isEmpty);
      expect(transport.calls.last, hasLength(2));
    });

    test('POSITIVE: batching respects the configured batch size', () async {
      final transport = _RecordingTransport();
      final queue = EventQueue(
        transport: transport,
        clock: clock,
        storageDirectory: tempDir,
        batchSize: 2,
      );

      for (var i = 0; i < 5; i++) {
        await queue.enqueue(_payload(timestamp: clock(), storyId: 's$i'));
      }

      final result = await queue.flush();

      expect(result.sent, 5);
      // 5 events at batch size 2 => batches of [2, 2, 1].
      expect(transport.calls, hasLength(3));
      expect(transport.calls[0], hasLength(2));
      expect(transport.calls[1], hasLength(2));
      expect(transport.calls[2], hasLength(1));
    });

    test('flush stops after the first failed batch, leaving later batches '
        'queued (connectivity drops mid-flush)', () async {
      final transport = _FlakyTransport(succeedForFirstNCalls: 1);
      final queue = EventQueue(
        transport: transport,
        clock: clock,
        storageDirectory: tempDir,
        batchSize: 2,
      );

      for (var i = 0; i < 6; i++) {
        await queue.enqueue(_payload(timestamp: clock(), storyId: 's$i'));
      }

      final result = await queue.flush();

      expect(result.sent, 2, reason: 'only the first batch succeeded');
      expect(transport.calls, hasLength(2),
          reason: 'batch 1 succeeds, batch 2 fails, batch 3 is never '
              'attempted');
      expect(await queue.pendingEvents(), hasLength(4));
    });
  });

  group('POSITIVE: file-based persistence survives across instances '
      '(app relaunch)', () {
    test('a fresh EventQueue instance pointed at the same storage '
        'directory sees events enqueued by a prior instance', () async {
      final transportA = _RecordingTransport()..online = false;
      final queueA = EventQueue(
        transport: transportA,
        clock: clock,
        storageDirectory: tempDir,
      );
      await queueA.enqueue(_payload(timestamp: clock(), storyId: 'durable-1'));

      // Simulate app relaunch: a brand new EventQueue, same directory.
      final transportB = _RecordingTransport();
      final queueB = EventQueue(
        transport: transportB,
        clock: clock,
        storageDirectory: tempDir,
      );

      final pending = await queueB.pendingEvents();
      expect(pending, hasLength(1));
      expect(pending.single['storyId'], 'durable-1');
    });

    test('a fresh instance can successfully flush events persisted by a '
        'prior instance', () async {
      final transportA = _RecordingTransport()..online = false;
      final queueA = EventQueue(
        transport: transportA,
        clock: clock,
        storageDirectory: tempDir,
      );
      await queueA.enqueue(_payload(timestamp: clock(), storyId: 'durable-2'));

      final transportB = _RecordingTransport();
      final queueB = EventQueue(
        transport: transportB,
        clock: clock,
        storageDirectory: tempDir,
      );
      final result = await queueB.flush();

      expect(result.sent, 1);
      expect(transportB.calls.single.single['storyId'], 'durable-2');
      expect(await queueB.pendingEvents(), isEmpty);
    });
  });

  group('EDGE: 30-day drop, verified with clock manipulation', () {
    test('an event 29 days old is still retained (not yet dropped)',
        () async {
      final transport = _RecordingTransport()..online = false;
      final queue = EventQueue(
        transport: transport,
        clock: clock,
        storageDirectory: tempDir,
      );

      await queue.enqueue(_payload(timestamp: clock(), storyId: 'aging'));
      clock.advance(const Duration(days: 29));

      final result = await queue.flush();

      expect(result.dropped, 0);
      expect(await queue.pendingEvents(), hasLength(1));
    });

    test('an event 31 days old is DROPPED, never delivered even once '
        'transport comes back online', () async {
      final transport = _RecordingTransport()..online = false;
      final queue = EventQueue(
        transport: transport,
        clock: clock,
        storageDirectory: tempDir,
      );

      await queue.enqueue(_payload(timestamp: clock(), storyId: 'stale'));
      clock.advance(const Duration(days: 31));

      final resultWhileOffline = await queue.flush();
      expect(resultWhileOffline.dropped, 1);
      expect(resultWhileOffline.sent, 0);
      expect(await queue.pendingEvents(), isEmpty);

      // Even now that transport is available, the stale event must never
      // have been (and can never be) transmitted.
      transport.online = true;
      final resultOnceOnline = await queue.flush();
      expect(resultOnceOnline.sent, 0);
      expect(resultOnceOnline.dropped, 0, reason: 'nothing left to drop');
      for (final batch in transport.calls) {
        for (final sentPayload in batch) {
          expect(sentPayload['storyId'], isNot('stale'));
        }
      }
    });

    test('a mixed batch drops the expired event and sends only the '
        'still-valid one', () async {
      final transport = _RecordingTransport();
      final queue = EventQueue(
        transport: transport,
        clock: clock,
        storageDirectory: tempDir,
      );

      await queue.enqueue(_payload(timestamp: clock(), storyId: 'old-one'));
      clock.advance(const Duration(days: 31));
      await queue.enqueue(_payload(timestamp: clock(), storyId: 'fresh-one'));

      final result = await queue.flush();

      expect(result.dropped, 1);
      expect(result.sent, 1);
      final sentStoryIds =
          transport.calls.expand((batch) => batch).map((p) => p['storyId']);
      expect(sentStoryIds, contains('fresh-one'));
      expect(sentStoryIds, isNot(contains('old-one')));
    });
  });

  group('EDGE: empty-queue flush is a true no-op', () {
    test('flushing an empty queue makes zero transport calls and reports '
        'zero sent/dropped', () async {
      final transport = _RecordingTransport();
      final queue = EventQueue(
        transport: transport,
        clock: clock,
        storageDirectory: tempDir,
      );

      final result = await queue.flush();

      expect(result.sent, 0);
      expect(result.dropped, 0);
      expect(transport.calls, isEmpty);
    });
  });

  group('EDGE: enqueue order is preserved (FIFO) within a batch', () {
    test('events are sent in the order they were enqueued', () async {
      final transport = _RecordingTransport();
      final queue = EventQueue(
        transport: transport,
        clock: clock,
        storageDirectory: tempDir,
      );

      await queue.enqueue(_payload(timestamp: clock(), storyId: 'first'));
      await queue.enqueue(_payload(timestamp: clock(), storyId: 'second'));
      await queue.enqueue(_payload(timestamp: clock(), storyId: 'third'));

      await queue.flush();

      final order =
          transport.calls.expand((batch) => batch).map((p) => p['storyId']);
      expect(order, ['first', 'second', 'third']);
    });
  });
}

/// The offline-first analytics event queue (PRD §8 Unit 12: "queued
/// offline, dropped (not persisted forever) after 30 days unsent").
///
/// Shape of the contract, in one sentence: **[EventQueue.enqueue] never
/// touches the network, [EventQueue.flush] is the only thing that does.**
/// Enqueue appends to a small append-only file in an injected directory;
/// flush prunes anything older than [kMaxQueuedEventAge], then hands the
/// survivors to the transport in batches, stopping at the first batch the
/// transport refuses so a connectivity drop mid-flush costs nothing.
///
/// Persistence deliberately uses its own file store rather than the Drift
/// user database: file ownership stays disjoint from user data, and
/// injecting the directory (from `path_provider` in the app, a temp dir in
/// tests) keeps the whole thing headless-testable.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'event_schema.dart';
import 'transport.dart';

/// Events still unsent after this long are dropped, never transmitted
/// (PRD §8 Unit 12).
const Duration kMaxQueuedEventAge = Duration(days: 30);

/// Default number of payloads per HTTPS request.
const int kDefaultAnalyticsBatchSize = 50;

/// Name of the append-only queue file inside the storage directory.
const String kQueueFileName = 'analytics_queue.jsonl';

/// A durable FIFO queue of analytics payloads with batched flushing.
class EventQueue {
  /// Creates a queue persisting into [storageDirectory] (created on demand)
  /// and flushing through [transport].
  ///
  /// [clock] drives 30-day expiry; [batchSize] is the max payloads per
  /// transport call.
  EventQueue({
    required AnalyticsTransport transport,
    required Clock clock,
    required Directory storageDirectory,
    this.batchSize = kDefaultAnalyticsBatchSize,
    this.maxAge = kMaxQueuedEventAge,
  })  : _transport = transport,
        _clock = clock,
        _storageDirectory = storageDirectory,
        assert(batchSize > 0, 'batchSize must be positive');

  final AnalyticsTransport _transport;
  final Clock _clock;
  final Directory _storageDirectory;

  /// Max payloads handed to the transport in one call.
  final int batchSize;

  /// How long an unsent event may sit in the queue before it is dropped.
  final Duration maxAge;

  /// Serializes file access so concurrent enqueue/flush calls cannot
  /// interleave a read-modify-write.
  Future<void> _lock = Future<void>.value();

  File get _file => File('${_storageDirectory.path}/$kQueueFileName');

  /// Appends [payload] to the durable queue. Never contacts the transport.
  Future<void> enqueue(Map<String, Object?> payload) {
    return _synchronized(() async {
      final records = await _read();
      records.add(_QueuedEvent(enqueuedAt: _clock(), payload: payload));
      await _write(records);
    });
  }

  /// The payloads currently queued, oldest first.
  Future<List<Map<String, Object?>>> pendingEvents() {
    return _synchronized(() async {
      final records = await _read();
      return records.map((record) => record.payload).toList();
    });
  }

  /// Prunes expired events, then sends the rest in batches.
  ///
  /// Returns how many payloads were accepted by the transport (`sent`) and
  /// how many were discarded for being older than [maxAge] (`dropped`).
  /// Stops at the first batch the transport refuses; everything from that
  /// batch on stays queued for the next flush.
  Future<({int sent, int dropped})> flush() {
    return _synchronized(() async {
      final records = await _read();
      final now = _clock();

      final live = <_QueuedEvent>[];
      var dropped = 0;
      for (final record in records) {
        if (now.difference(record.enqueuedAt) > maxAge) {
          dropped++;
        } else {
          live.add(record);
        }
      }
      if (dropped > 0) {
        // Persist the pruning immediately: an expired event must never be
        // transmitted, even if the flush below fails or the app dies.
        await _write(live);
      }

      var sent = 0;
      var remaining = live;
      while (remaining.isNotEmpty) {
        final batch = remaining.take(batchSize).toList();
        final result =
            await _transport.send(batch.map((r) => r.payload).toList());
        if (result != TransportResult.success) break;
        sent += batch.length;
        remaining = remaining.sublist(batch.length);
        await _write(remaining);
      }

      return (sent: sent, dropped: dropped);
    });
  }

  /// Discards everything queued (used by the kill switch's cleanup path).
  Future<void> clear() => _synchronized(() => _write(const []));

  Future<List<_QueuedEvent>> _read() async {
    final file = _file;
    if (!await file.exists()) return <_QueuedEvent>[];
    final records = <_QueuedEvent>[];
    for (final line in await file.readAsLines()) {
      if (line.trim().isEmpty) continue;
      final record = _QueuedEvent.tryParse(line);
      // A corrupt line (partial write, truncated file) is skipped rather
      // than allowed to poison every future flush.
      if (record != null) records.add(record);
    }
    return records;
  }

  Future<void> _write(List<_QueuedEvent> records) async {
    final file = _file;
    if (!await _storageDirectory.exists()) {
      await _storageDirectory.create(recursive: true);
    }
    final buffer =
        StringBuffer(records.map((record) => record.encode()).join('\n'));
    if (records.isNotEmpty) buffer.write('\n');
    await file.writeAsString(buffer.toString(), flush: true);
  }

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final previous = _lock;
    final completer = Completer<void>();
    _lock = completer.future;
    return previous.then((_) => action()).whenComplete(completer.complete);
  }
}

/// One queued payload plus the time it entered the queue (which is what
/// the 30-day expiry is measured against — "unsent after 30 days").
class _QueuedEvent {
  const _QueuedEvent({required this.enqueuedAt, required this.payload});

  final DateTime enqueuedAt;
  final Map<String, Object?> payload;

  String encode() => jsonEncode(<String, Object?>{
        'enqueuedAt': enqueuedAt.toUtc().toIso8601String(),
        'payload': payload,
      });

  static _QueuedEvent? tryParse(String line) {
    try {
      final decoded = jsonDecode(line);
      if (decoded is! Map) return null;
      final enqueuedAt = DateTime.tryParse(decoded['enqueuedAt'] as String);
      final payload = decoded['payload'];
      if (enqueuedAt == null || payload is! Map) return null;
      return _QueuedEvent(
        enqueuedAt: enqueuedAt,
        payload: Map<String, Object?>.from(payload),
      );
    } on Object {
      return null;
    }
  }
}

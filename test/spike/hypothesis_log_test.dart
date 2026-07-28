// Unit 0 recognition spike — hypothesis log tests.
//
// Pins the interface of lib/spike/hypothesis_log.dart:
//   - HypothesisEvent: decodes a raw platform-channel hypothesis payload,
//     and round-trips through JSON for the persisted log format.
//   - SpikeSessionLog: timestamped, per-session, JSON-lines shareable log
//     with a deterministic, filesystem-safe file name.
//   - SpikeSessionLogRotator: starts a fresh SpikeSessionLog per recording
//     session ("rotation") without losing prior sessions' events.
//
// This file is TEST-ONLY. lib/spike/hypothesis_log.dart does not exist yet;
// these tests are expected to fail to compile/run until it is implemented,
// pinning the exact API the implementer must produce.
//
// Ticket accepts covered here:
//   - "Every hypothesis event (partial and final, with word detail and any
//     phone-level/confidence detail the platform exposes) is appended to a
//     timestamped, shareable log file (JSON lines) named per session; log
//     format round-trip tested headlessly."
//   - "The log records whether phone-level detail was present in platform
//     output ... field exists and is populated from the channel payload;
//     asserted with mocked payloads with and without phone detail."
//
// PRD refs: §8 Unit 0, §9 A-10.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/spike/hypothesis_log.dart';

void main() {
  group('HypothesisEvent.fromChannelPayload — positive', () {
    test('decodes a full final hypothesis payload', () {
      final event = HypothesisEvent.fromChannelPayload({
        'timestampMs': 1700000000000,
        'isFinal': true,
        'text': 'the cat sat',
        'confidence': 0.87,
        'biasingWords': <String>['the', 'cat', 'sat', 'on', 'the', 'mat'],
        'phoneDetail': <Map<String, Object?>>[
          {'phone': 'DH', 'start': 0.0, 'end': 0.08, 'confidence': 0.5},
        ],
      });

      expect(
        event.timestamp,
        DateTime.fromMillisecondsSinceEpoch(1700000000000, isUtc: true),
      );
      expect(event.isFinal, isTrue);
      expect(event.text, 'the cat sat');
      expect(event.confidence, 0.87);
      expect(
        event.biasingWords,
        <String>['the', 'cat', 'sat', 'on', 'the', 'mat'],
      );
      expect(event.phoneDetailPresent, isTrue);
      expect(event.phoneDetail, hasLength(1));
      expect(event.phoneDetail![0]['phone'], 'DH');
    });

    test('decodes a partial (non-final) hypothesis payload', () {
      final event = HypothesisEvent.fromChannelPayload({
        'timestampMs': 1700000001000,
        'isFinal': false,
        'text': 'the ca',
        'biasingWords': <String>['the', 'cat', 'sat'],
      });

      expect(event.isFinal, isFalse);
      expect(event.text, 'the ca');
    });

    test('integer confidence from platform is coerced to double', () {
      final event = HypothesisEvent.fromChannelPayload({
        'isFinal': true,
        'text': 'the cat sat',
        'confidence': 1,
      });

      expect(event.confidence, isA<double>());
      expect(event.confidence, 1.0);
    });
  });

  group('HypothesisEvent.fromChannelPayload — negative / missing fields', () {
    test('missing confidence key decodes to null, not a crash', () {
      final event = HypothesisEvent.fromChannelPayload({
        'isFinal': true,
        'text': 'the cat sat',
      });

      expect(event.confidence, isNull);
    });

    test('missing biasingWords key decodes to an empty list, not null', () {
      final event = HypothesisEvent.fromChannelPayload({
        'isFinal': true,
        'text': 'the cat sat',
      });

      expect(event.biasingWords, isEmpty);
    });

    test('missing isFinal key defaults to false (treated as partial)', () {
      final event = HypothesisEvent.fromChannelPayload({'text': 'the cat'});

      expect(event.isFinal, isFalse);
    });

    test('missing text key decodes to empty string, not a crash', () {
      final event = HypothesisEvent.fromChannelPayload({'isFinal': true});

      expect(event.text, '');
    });

    test('missing timestampMs falls back to a local "now" rather than throwing', () {
      final before = DateTime.now().subtract(const Duration(seconds: 2));

      final event = HypothesisEvent.fromChannelPayload({
        'isFinal': true,
        'text': 'the cat sat',
      });

      final after = DateTime.now().add(const Duration(seconds: 2));
      expect(event.timestamp.isAfter(before), isTrue);
      expect(event.timestamp.isBefore(after), isTrue);
    });
  });

  group('HypothesisEvent.fromChannelPayload — phone-level detail (Unit 14 question)', () {
    test('phoneDetail key present with entries -> phoneDetailPresent true', () {
      final event = HypothesisEvent.fromChannelPayload({
        'isFinal': true,
        'text': 'sh sh sh',
        'phoneDetail': <Map<String, Object?>>[
          {'phone': 'SH', 'confidence': 0.4},
        ],
      });

      expect(event.phoneDetailPresent, isTrue);
      expect(event.phoneDetail, isNotNull);
      expect(event.phoneDetail, hasLength(1));
    });

    test('phoneDetail key absent -> phoneDetailPresent false and phoneDetail null', () {
      final event = HypothesisEvent.fromChannelPayload({
        'isFinal': true,
        'text': 'the cat sat',
      });

      expect(event.phoneDetailPresent, isFalse);
      expect(event.phoneDetail, isNull);
    });

    test(
      'phoneDetail key present but empty (platform supports it, found nothing) '
      'still counts as present — distinct from key absent (platform does not expose it)',
      () {
        final event = HypothesisEvent.fromChannelPayload({
          'isFinal': true,
          'text': 'the cat sat',
          'phoneDetail': <Map<String, Object?>>[],
        });

        expect(event.phoneDetailPresent, isTrue);
        expect(event.phoneDetail, isEmpty);
      },
    );
  });

  group('HypothesisEvent JSON round trip (persisted log record shape)', () {
    test('a full event survives toJson -> fromJson unchanged', () {
      final original = HypothesisEvent(
        timestamp: DateTime.utc(2026, 7, 27, 10, 30, 0, 123),
        isFinal: true,
        text: 'the cat sat',
        confidence: 0.91,
        biasingWords: const ['the', 'cat', 'sat', 'on', 'the', 'mat'],
        phoneDetailPresent: true,
        phoneDetail: const [
          {'phone': 'DH', 'confidence': 0.5},
        ],
      );

      final roundTripped = HypothesisEvent.fromJson(original.toJson());

      expect(roundTripped.timestamp, original.timestamp);
      expect(roundTripped.isFinal, original.isFinal);
      expect(roundTripped.text, original.text);
      expect(roundTripped.confidence, original.confidence);
      expect(roundTripped.biasingWords, original.biasingWords);
      expect(roundTripped.phoneDetailPresent, original.phoneDetailPresent);
      expect(roundTripped.phoneDetail, hasLength(1));
      expect(roundTripped.phoneDetail![0]['phone'], 'DH');
    });

    test('toJson output is directly JSON-encodable (jsonEncode does not throw)', () {
      final event = HypothesisEvent(
        timestamp: DateTime.utc(2026, 7, 27),
        isFinal: false,
        text: 'th',
        biasingWords: const ['the'],
      );

      expect(() => jsonEncode(event.toJson()), returnsNormally);
    });

    test('an event with no confidence and no phone detail round-trips as null, not a crash', () {
      final original = HypothesisEvent(
        timestamp: DateTime.utc(2026, 7, 27, 9),
        isFinal: false,
        text: 'th',
        biasingWords: const [],
      );

      final roundTripped = HypothesisEvent.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      expect(roundTripped.confidence, isNull);
      expect(roundTripped.phoneDetailPresent, isFalse);
      expect(roundTripped.phoneDetail, isNull);
      expect(roundTripped.biasingWords, isEmpty);
    });

    test('fromJson tolerates a map missing optional keys entirely', () {
      final roundTripped = HypothesisEvent.fromJson({
        'timestamp': DateTime.utc(2026, 7, 27).toIso8601String(),
        'isFinal': true,
        'text': 'the cat sat',
      });

      expect(roundTripped.text, 'the cat sat');
      expect(roundTripped.confidence, isNull);
      expect(roundTripped.biasingWords, isEmpty);
      expect(roundTripped.phoneDetailPresent, isFalse);
    });
  });

  group('SpikeSessionLog — file naming', () {
    test('fileNameFor is deterministic for the same sessionId + startedAt', () {
      final startedAt = DateTime.utc(2026, 7, 27, 14, 5, 30);
      final a = SpikeSessionLog.fileNameFor(
        sessionId: 'session-abc',
        startedAt: startedAt,
      );
      final b = SpikeSessionLog.fileNameFor(
        sessionId: 'session-abc',
        startedAt: startedAt,
      );

      expect(a, b);
    });

    test('fileNameFor ends in .jsonl and contains the sessionId', () {
      final name = SpikeSessionLog.fileNameFor(
        sessionId: 'session-abc',
        startedAt: DateTime.utc(2026, 7, 27, 14, 5, 30),
      );

      expect(name, endsWith('.jsonl'));
      expect(name, contains('session-abc'));
    });

    test('fileNameFor produces a filesystem-safe name (no colons or slashes)', () {
      final name = SpikeSessionLog.fileNameFor(
        sessionId: 'session-abc',
        startedAt: DateTime.utc(2026, 7, 27, 14, 5, 30),
      );

      expect(name.contains(':'), isFalse);
      expect(name.contains('/'), isFalse);
      expect(name.contains(r'\'), isFalse);
    });

    test('different startedAt values (same sessionId) produce different names', () {
      final a = SpikeSessionLog.fileNameFor(
        sessionId: 'session-abc',
        startedAt: DateTime.utc(2026, 7, 27, 14, 0, 0),
      );
      final b = SpikeSessionLog.fileNameFor(
        sessionId: 'session-abc',
        startedAt: DateTime.utc(2026, 7, 27, 14, 0, 1),
      );

      expect(a, isNot(b));
    });

    test('instance fileName getter matches the static fileNameFor computation', () {
      final startedAt = DateTime.utc(2026, 7, 27, 8, 0, 0);
      final log = SpikeSessionLog(
        sentence: 'The quick fox runs.',
        biasingWords: const ['the', 'quick', 'fox', 'runs'],
        sessionId: 'fixed-session',
        startedAt: startedAt,
      );

      expect(
        log.fileName,
        SpikeSessionLog.fileNameFor(sessionId: 'fixed-session', startedAt: startedAt),
      );
    });

    test('omitting sessionId generates distinct ids across instances (edge: uniqueness)', () {
      final logA = SpikeSessionLog(
        sentence: 'The quick fox runs.',
        biasingWords: const ['the', 'quick', 'fox', 'runs'],
      );
      final logB = SpikeSessionLog(
        sentence: 'The quick fox runs.',
        biasingWords: const ['the', 'quick', 'fox', 'runs'],
      );

      expect(logA.sessionId, isNotEmpty);
      expect(logB.sessionId, isNotEmpty);
      expect(logA.sessionId, isNot(logB.sessionId));
    });
  });

  group('SpikeSessionLog — appending events and JSON-lines serialization', () {
    test('appendEvent adds to events in call order', () {
      final log = SpikeSessionLog(
        sentence: 'The quick fox runs.',
        biasingWords: const ['the', 'quick', 'fox', 'runs'],
        sessionId: 's1',
        startedAt: DateTime.utc(2026, 7, 27),
      );

      final e1 = HypothesisEvent(
        timestamp: DateTime.utc(2026, 7, 27, 0, 0, 1),
        isFinal: false,
        text: 'the',
        biasingWords: const ['the', 'quick', 'fox', 'runs'],
      );
      final e2 = HypothesisEvent(
        timestamp: DateTime.utc(2026, 7, 27, 0, 0, 2),
        isFinal: true,
        text: 'the quick fox runs',
        biasingWords: const ['the', 'quick', 'fox', 'runs'],
      );

      log.appendEvent(e1);
      log.appendEvent(e2);

      expect(log.events, hasLength(2));
      expect(log.events[0].text, 'the');
      expect(log.events[1].text, 'the quick fox runs');
    });

    test('toJsonLines emits one JSON-decodable line per (header + event)', () {
      final log = SpikeSessionLog(
        sentence: 'The quick fox runs.',
        biasingWords: const ['the', 'quick', 'fox', 'runs'],
        sessionId: 's1',
        startedAt: DateTime.utc(2026, 7, 27),
      );
      log.appendEvent(
        HypothesisEvent(
          timestamp: DateTime.utc(2026, 7, 27, 0, 0, 1),
          isFinal: false,
          text: 'the',
          biasingWords: const ['the', 'quick', 'fox', 'runs'],
        ),
      );
      log.appendEvent(
        HypothesisEvent(
          timestamp: DateTime.utc(2026, 7, 27, 0, 0, 2),
          isFinal: true,
          text: 'the quick fox runs',
          biasingWords: const ['the', 'quick', 'fox', 'runs'],
        ),
      );

      final lines = log
          .toJsonLines()
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList();

      // header + 2 events
      expect(lines, hasLength(3));
      for (final line in lines) {
        expect(() => jsonDecode(line), returnsNormally);
      }
    });

    test(
      'shareable format is JSON-lines, not a single JSON array '
      '(the whole blob does not parse as one JSON value)',
      () {
        final log = SpikeSessionLog(
          sentence: 'The quick fox runs.',
          biasingWords: const ['the', 'quick', 'fox', 'runs'],
          sessionId: 's1',
          startedAt: DateTime.utc(2026, 7, 27),
        );
        log.appendEvent(
          HypothesisEvent(
            timestamp: DateTime.utc(2026, 7, 27, 0, 0, 1),
            isFinal: true,
            text: 'the quick fox runs',
            biasingWords: const ['the', 'quick', 'fox', 'runs'],
          ),
        );

        expect(() => jsonDecode(log.toJsonLines()), throwsA(isA<FormatException>()));
      },
    );

    test('round trip: toJsonLines -> fromJsonLines preserves session metadata and events', () {
      final original = SpikeSessionLog(
        sentence: 'The quick fox runs.',
        biasingWords: const ['the', 'quick', 'fox', 'runs'],
        sessionId: 'round-trip-session',
        startedAt: DateTime.utc(2026, 7, 27, 12, 0, 0),
      );
      original.appendEvent(
        HypothesisEvent(
          timestamp: DateTime.utc(2026, 7, 27, 12, 0, 1),
          isFinal: false,
          text: 'the',
          confidence: 0.4,
          biasingWords: const ['the', 'quick', 'fox', 'runs'],
        ),
      );
      original.appendEvent(
        HypothesisEvent(
          timestamp: DateTime.utc(2026, 7, 27, 12, 0, 3),
          isFinal: true,
          text: 'the quick fox runs',
          confidence: 0.93,
          biasingWords: const ['the', 'quick', 'fox', 'runs'],
          phoneDetailPresent: true,
          phoneDetail: const [
            {'phone': 'DH'},
          ],
        ),
      );

      final restored = SpikeSessionLog.fromJsonLines(original.toJsonLines());

      expect(restored.sessionId, original.sessionId);
      expect(restored.startedAt, original.startedAt);
      expect(restored.sentence, original.sentence);
      expect(restored.biasingWords, original.biasingWords);
      expect(restored.events, hasLength(2));
      expect(restored.events[0].text, 'the');
      expect(restored.events[0].isFinal, isFalse);
      expect(restored.events[1].text, 'the quick fox runs');
      expect(restored.events[1].isFinal, isTrue);
      expect(restored.events[1].phoneDetailPresent, isTrue);
    });

    test('fromJsonLines on a header-only log (no events yet) yields an empty events list', () {
      final original = SpikeSessionLog(
        sentence: 'The quick fox runs.',
        biasingWords: const ['the', 'quick', 'fox', 'runs'],
        sessionId: 'header-only',
        startedAt: DateTime.utc(2026, 7, 27),
      );

      final restored = SpikeSessionLog.fromJsonLines(original.toJsonLines());

      expect(restored.events, isEmpty);
      expect(restored.sessionId, 'header-only');
    });

    test('fromJsonLines tolerates a trailing newline', () {
      final original = SpikeSessionLog(
        sentence: 'The quick fox runs.',
        biasingWords: const ['the', 'quick', 'fox', 'runs'],
        sessionId: 'trailing-nl',
        startedAt: DateTime.utc(2026, 7, 27),
      );
      original.appendEvent(
        HypothesisEvent(
          timestamp: DateTime.utc(2026, 7, 27, 0, 0, 1),
          isFinal: true,
          text: 'the quick fox runs',
          biasingWords: const ['the', 'quick', 'fox', 'runs'],
        ),
      );

      final restored = SpikeSessionLog.fromJsonLines('${original.toJsonLines()}\n');

      expect(restored.events, hasLength(1));
    });

    test('fromJsonLines on empty content throws FormatException (negative)', () {
      expect(() => SpikeSessionLog.fromJsonLines(''), throwsFormatException);
    });

    test('fromJsonLines on content with no header (garbage) throws FormatException (negative)', () {
      expect(
        () => SpikeSessionLog.fromJsonLines('not json at all'),
        throwsFormatException,
      );
    });
  });

  group('SpikeSessionLogRotator — session rotation', () {
    test('starts with no current session and empty history', () {
      final rotator = SpikeSessionLogRotator();

      expect(rotator.current, isNull);
      expect(rotator.history, isEmpty);
    });

    test('startSession creates and returns the current session', () {
      final rotator = SpikeSessionLogRotator();

      final log = rotator.startSession(
        sentence: 'The quick fox runs.',
        biasingWords: const ['the', 'quick', 'fox', 'runs'],
        sessionId: 'first',
        startedAt: DateTime.utc(2026, 7, 27, 9),
      );

      expect(rotator.current, isNotNull);
      expect(rotator.current!.sessionId, 'first');
      expect(log.sessionId, 'first');
      expect(rotator.history, isEmpty);
    });

    test('starting a second session rotates the first into history, preserving its events', () {
      final rotator = SpikeSessionLogRotator();

      rotator.startSession(
        sentence: 'The quick fox runs.',
        biasingWords: const ['the', 'quick', 'fox', 'runs'],
        sessionId: 'first',
        startedAt: DateTime.utc(2026, 7, 27, 9),
      );
      rotator.current!.appendEvent(
        HypothesisEvent(
          timestamp: DateTime.utc(2026, 7, 27, 9, 0, 1),
          isFinal: true,
          text: 'the quick fox runs',
          biasingWords: const ['the', 'quick', 'fox', 'runs'],
        ),
      );

      rotator.startSession(
        sentence: 'The quick fox runs.',
        biasingWords: const ['the', 'quick', 'fox', 'runs'],
        sessionId: 'second',
        startedAt: DateTime.utc(2026, 7, 27, 10),
      );

      expect(rotator.current!.sessionId, 'second');
      expect(rotator.history, hasLength(1));
      expect(rotator.history.first.sessionId, 'first');
      expect(rotator.history.first.events, hasLength(1));
    });

    test('rotating twice keeps history in start order', () {
      final rotator = SpikeSessionLogRotator();

      rotator.startSession(
        sentence: 'S',
        biasingWords: const ['s'],
        sessionId: 'a',
        startedAt: DateTime.utc(2026, 7, 27, 9),
      );
      rotator.startSession(
        sentence: 'S',
        biasingWords: const ['s'],
        sessionId: 'b',
        startedAt: DateTime.utc(2026, 7, 27, 10),
      );
      rotator.startSession(
        sentence: 'S',
        biasingWords: const ['s'],
        sessionId: 'c',
        startedAt: DateTime.utc(2026, 7, 27, 11),
      );

      expect(rotator.history.map((l) => l.sessionId).toList(), ['a', 'b']);
      expect(rotator.current!.sessionId, 'c');
    });
  });
}

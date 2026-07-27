// Unit 0 recognition spike — hypothesis event model and shareable session log.
//
// DISPOSABLE spike code (PRD.md §8 Unit 0 pinned design): "Code is
// disposable — do not architect it into the main app". This file exists
// solely to answer, for the Unit 0 spike:
//   (1) are on-device word hypotheses granular/reliable enough for the
//       close-enough matcher with young voices? (A-10)
//   (2) is any usable phone-level detail exposed (Unit 14 sound mode)?
//
// The Dart-side API here is pinned by test/spike/hypothesis_log_test.dart —
// see that file for the exact contract this implements.

import 'dart:convert';

/// A single hypothesis event decoded from the platform recognizer's event
/// channel payload, or restored from a persisted JSON-lines log line.
///
/// [phoneDetailPresent] is the Unit 0 spike's key output field: it records
/// whether the platform payload included a `phoneDetail` key at all
/// (distinct from the key being present-but-empty), independent of whether
/// [phoneDetail] itself has entries. This is what answers the "is any
/// usable phone-level detail exposed" question (PRD §8 Unit 0, §9 A-10,
/// referenced by Unit 14's tongue-twister sound mode).
class HypothesisEvent {
  HypothesisEvent({
    required this.timestamp,
    required this.isFinal,
    required this.text,
    this.confidence,
    this.biasingWords = const <String>[],
    this.phoneDetailPresent = false,
    this.phoneDetail,
  });

  /// Decodes a raw payload as delivered on [SpikeChannel]'s event channel
  /// (see lib/spike/spike_channel.dart). Tolerant of missing optional keys
  /// — a hypothesis payload with only `text`/`isFinal` is still valid.
  factory HypothesisEvent.fromChannelPayload(Map<Object?, Object?> payload) {
    final rawTimestampMs = payload['timestampMs'];
    final timestamp = rawTimestampMs is num
        ? DateTime.fromMillisecondsSinceEpoch(rawTimestampMs.toInt(), isUtc: true)
        : DateTime.now().toUtc();

    final rawConfidence = payload['confidence'];
    final confidence = rawConfidence is num ? rawConfidence.toDouble() : null;

    final rawBiasingWords = payload['biasingWords'];
    final biasingWords = rawBiasingWords is List
        ? rawBiasingWords.map((word) => word.toString()).toList()
        : const <String>[];

    // Presence of the key (not the emptiness of its value) is what marks
    // phone-level detail as available from the platform.
    final phoneDetailPresent = payload.containsKey('phoneDetail');
    List<Map<String, Object?>>? phoneDetail;
    if (phoneDetailPresent) {
      final rawPhoneDetail = payload['phoneDetail'];
      phoneDetail = rawPhoneDetail is List
          ? rawPhoneDetail
              .map((entry) => Map<String, Object?>.from(entry as Map))
              .toList()
          : const <Map<String, Object?>>[];
    }

    return HypothesisEvent(
      timestamp: timestamp,
      isFinal: payload['isFinal'] as bool? ?? false,
      text: payload['text'] as String? ?? '',
      confidence: confidence,
      biasingWords: biasingWords,
      phoneDetailPresent: phoneDetailPresent,
      phoneDetail: phoneDetail,
    );
  }

  /// Restores an event previously produced by [toJson] (persisted log
  /// record shape).
  factory HypothesisEvent.fromJson(Map<String, dynamic> json) {
    final rawPhoneDetail = json['phoneDetail'];
    return HypothesisEvent(
      timestamp: DateTime.parse(json['timestamp'] as String),
      isFinal: json['isFinal'] as bool? ?? false,
      text: json['text'] as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble(),
      biasingWords:
          (json['biasingWords'] as List?)?.map((w) => w.toString()).toList() ??
              const <String>[],
      phoneDetailPresent: json['phoneDetailPresent'] as bool? ?? false,
      phoneDetail: rawPhoneDetail == null
          ? null
          : (rawPhoneDetail as List)
              .map((entry) => Map<String, Object?>.from(entry as Map))
              .toList(),
    );
  }

  /// When this hypothesis was produced (UTC).
  final DateTime timestamp;

  /// Whether this is the recognizer's final result for an utterance, as
  /// opposed to a partial/interim hypothesis.
  final bool isFinal;

  /// The raw recognized text for this hypothesis.
  final String text;

  /// Platform-reported confidence, if any (0.0-1.0 typically; not
  /// normalized further — the spike reports it as-is).
  final double? confidence;

  /// The contextual-biasing words that were active when this hypothesis was
  /// produced (echoes the sentence's word list; see spikeBiasingWordsFor).
  final List<String> biasingWords;

  /// True iff the platform payload included a `phoneDetail` key at all.
  final bool phoneDetailPresent;

  /// Phone-level detail entries, if [phoneDetailPresent]; null otherwise.
  final List<Map<String, Object?>>? phoneDetail;

  /// The persisted log record shape: directly JSON-encodable, and the exact
  /// inverse of [fromJson].
  Map<String, dynamic> toJson() => <String, dynamic>{
        'timestamp': timestamp.toIso8601String(),
        'isFinal': isFinal,
        'text': text,
        'confidence': confidence,
        'biasingWords': biasingWords,
        'phoneDetailPresent': phoneDetailPresent,
        'phoneDetail': phoneDetail,
      };
}

/// A timestamped, per-session, JSON-lines shareable log of hypothesis
/// events (PRD §8 Unit 0: "raw hypothesis logging ... appended to a
/// timestamped, shareable log file (JSON lines) named per session").
///
/// Serialized shape (one JSON value per line, in order):
///   1. a header line: `{"type": "session", "sessionId", "startedAt",
///      "sentence", "biasingWords"}`
///   2. one line per appended [HypothesisEvent], via [HypothesisEvent.toJson]
///
/// This is JSON-**lines**, not a single JSON document — see
/// [toJsonLines]/[fromJsonLines].
class SpikeSessionLog {
  SpikeSessionLog({
    required this.sentence,
    required this.biasingWords,
    String? sessionId,
    DateTime? startedAt,
  })  : sessionId = sessionId ?? _generateSessionId(),
        startedAt = (startedAt ?? DateTime.now()).toUtc(),
        _events = <HypothesisEvent>[];

  SpikeSessionLog._restore({
    required this.sentence,
    required this.biasingWords,
    required this.sessionId,
    required this.startedAt,
    required List<HypothesisEvent> events,
  }) : _events = events;

  static int _sessionIdCounter = 0;

  static String _generateSessionId() {
    // Timestamp + monotonic counter: unique even when two sessions are
    // constructed within the same microsecond (no uuid dependency needed
    // for a disposable spike).
    _sessionIdCounter += 1;
    return 'session-${DateTime.now().microsecondsSinceEpoch}-$_sessionIdCounter';
  }

  /// The hardcoded sentence the child was asked to read for this session.
  final String sentence;

  /// The contextual-biasing words active for this session.
  final List<String> biasingWords;

  /// A unique identifier for this recording session.
  final String sessionId;

  /// When this session started (UTC).
  final DateTime startedAt;

  final List<HypothesisEvent> _events;

  /// Hypothesis events appended so far, in call order.
  List<HypothesisEvent> get events => List.unmodifiable(_events);

  /// Appends a decoded hypothesis event to this session's log.
  void appendEvent(HypothesisEvent event) => _events.add(event);

  /// The filesystem-safe, deterministic file name for this session's log.
  String get fileName => SpikeSessionLog.fileNameFor(sessionId: sessionId, startedAt: startedAt);

  /// Computes the deterministic, filesystem-safe (`.jsonl`) file name for a
  /// session, without needing an instance.
  static String fileNameFor({required String sessionId, required DateTime startedAt}) {
    final safeTimestamp = startedAt.toUtc().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    return 'spike_${sessionId}_$safeTimestamp.jsonl';
  }

  Map<String, dynamic> _headerJson() => <String, dynamic>{
        'type': 'session',
        'sessionId': sessionId,
        'startedAt': startedAt.toIso8601String(),
        'sentence': sentence,
        'biasingWords': biasingWords,
      };

  /// Serializes this session (header + events) as JSON lines: one JSON
  /// value per line, newline-separated — NOT a single JSON array/object.
  String toJsonLines() {
    final lines = <String>[jsonEncode(_headerJson())];
    for (final event in _events) {
      lines.add(jsonEncode(event.toJson()));
    }
    return lines.join('\n');
  }

  /// Restores a [SpikeSessionLog] (metadata + events) from [toJsonLines]
  /// output. Tolerates a trailing newline. Throws [FormatException] on
  /// empty content, invalid JSON, or a first line that isn't a session
  /// header.
  static SpikeSessionLog fromJsonLines(String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('SpikeSessionLog.fromJsonLines: empty content');
    }

    final lines = trimmed.split('\n').where((line) => line.trim().isNotEmpty).toList();

    final header = jsonDecode(lines.first);
    if (header is! Map || header['type'] != 'session') {
      throw const FormatException(
        'SpikeSessionLog.fromJsonLines: first line is not a session header',
      );
    }

    final events = lines
        .skip(1)
        .map((line) => HypothesisEvent.fromJson(jsonDecode(line) as Map<String, dynamic>))
        .toList();

    return SpikeSessionLog._restore(
      sentence: header['sentence'] as String? ?? '',
      biasingWords:
          (header['biasingWords'] as List?)?.map((w) => w.toString()).toList() ??
              const <String>[],
      sessionId: header['sessionId'] as String,
      startedAt: DateTime.parse(header['startedAt'] as String),
      events: events,
    );
  }
}

/// Starts a fresh [SpikeSessionLog] per recording session ("rotation"),
/// keeping prior sessions (with their events intact) in [history].
///
/// One rotator instance backs a spike run across multiple start/stop
/// cycles (e.g. one per child), so the owner can collect >= 3 children's
/// sessions from a single app run (PRD §8 Unit 0 acceptance).
class SpikeSessionLogRotator {
  final List<SpikeSessionLog> _history = <SpikeSessionLog>[];
  SpikeSessionLog? _current;

  /// The in-progress session, or null if [startSession] has never been
  /// called.
  SpikeSessionLog? get current => _current;

  /// Prior sessions, oldest first, in start order.
  List<SpikeSessionLog> get history => List.unmodifiable(_history);

  /// Starts a new session, rotating any in-progress session into [history]
  /// (preserving its events) first.
  SpikeSessionLog startSession({
    required String sentence,
    required List<String> biasingWords,
    String? sessionId,
    DateTime? startedAt,
  }) {
    final previous = _current;
    if (previous != null) {
      _history.add(previous);
    }
    final log = SpikeSessionLog(
      sentence: sentence,
      biasingWords: biasingWords,
      sessionId: sessionId,
      startedAt: startedAt,
    );
    _current = log;
    return log;
  }
}

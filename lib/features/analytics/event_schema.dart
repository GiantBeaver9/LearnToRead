/// The analytics wire schema: the in-memory event record, the A-14 word
/// hash, and the strict payload validator that is the project's PII
/// tripwire (PRD §5, §8 Unit 12, §9 A-14).
///
/// Two rules make this file the privacy gate for the whole app:
///
/// 1. **Word text is never transmitted.** [hashWord] is the only way a
///    word reaches a payload, and A-14 pins it: SHA-256 of the *lowercased*
///    word text, truncated to 16 hex chars.
/// 2. **The payload schema is a strict allowlist, not a blocklist.**
///    [validateEventPayload] rejects *any* key it does not explicitly
///    declare for that event type. A new PII-shaped field cannot sneak in
///    by not being on a banned list — it has to be added here on purpose.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'events.dart';

/// An injectable "what time is it" function.
///
/// Every component in this feature that cares about time takes one of
/// these instead of calling [DateTime.now] directly, so tests drive the
/// clock (30-day queue expiry, 120 s session timeout, 30 s help window)
/// without sleeping.
typedef Clock = DateTime Function();

/// The default production clock.
DateTime systemClock() => DateTime.now().toUtc();

/// Thrown by [validateEventPayload] when a payload does not match the
/// schema for its event type.
class SchemaViolation implements Exception {
  /// Creates a violation describing [message].
  SchemaViolation(this.message);

  /// Human-readable description of what was wrong with the payload.
  final String message;

  @override
  String toString() => 'SchemaViolation: $message';
}

/// A-14: the analytics word hash — SHA-256 of the lowercased word text,
/// truncated to 16 hex chars (lowercase).
///
/// The lowercasing is load-bearing: it makes "Cat", "CAT" and "cat" one
/// bucket for the §4.3 learning signal, and it is pinned by test vectors
/// computed outside this codebase.
String hashWord(String word) {
  final digest = sha256.convert(utf8.encode(word.toLowerCase()));
  return digest.toString().substring(0, 16);
}

/// One analytics event, in memory, before it becomes a wire payload.
///
/// The base fields are exactly the §5 payload contract — event name,
/// timestamp, per-install UUID, profile ordinal, level ordinal, story id —
/// and [fields] carries the (closed, per-event) event-specific extras.
class AnalyticsEvent {
  /// Creates an event. [fields] must only contain the extras that
  /// [validateEventPayload] declares for [name].
  const AnalyticsEvent({
    required this.name,
    required this.timestamp,
    required this.installId,
    required this.profileOrdinal,
    required this.levelOrdinal,
    this.storyId,
    this.fields = const <String, Object?>{},
  });

  /// Which of the §5 events this is.
  final AnalyticsEventName name;

  /// When the event happened. Serialized as UTC ISO-8601.
  final DateTime timestamp;

  /// The random per-install UUID (never a device identifier).
  final String installId;

  /// Which of the (at most four) on-device profiles, as an ordinal 1-4.
  /// Deliberately an ordinal, not a profile id or name.
  final int profileOrdinal;

  /// The profile's current level ordinal (positive).
  final int levelOrdinal;

  /// The story this event belongs to, when the event happens inside a
  /// story. Omitted entirely from the payload when null.
  final String? storyId;

  /// Event-specific fields (e.g. `result`/`wordHash`, `tier`, `matched`,
  /// `helpInLast30s`), merged into the payload as top-level keys.
  final Map<String, Object?> fields;

  /// Serializes to the wire payload: base fields plus [fields].
  ///
  /// A null [storyId] is *omitted*, never emitted as a null-valued key.
  Map<String, Object?> toPayload() {
    return <String, Object?>{
      'event': name.wireName,
      'timestamp': timestamp.toUtc().toIso8601String(),
      'installId': installId,
      'profileOrdinal': profileOrdinal,
      'levelOrdinal': levelOrdinal,
      if (storyId != null) 'storyId': storyId,
      ...fields,
    };
  }

  @override
  String toString() => 'AnalyticsEvent(${toPayload()})';
}

/// Whether a given event type may/must carry a `storyId`.
enum _StoryIdRule {
  /// The event only happens inside a story: `storyId` is mandatory.
  required,

  /// The event may or may not happen inside a story.
  optional,

  /// The event never happens inside a story: `storyId` is rejected.
  forbidden,
}

/// A single event-specific field: how to check its value.
///
/// Every declared field is mandatory — an event type that "sometimes"
/// carries a field would make the payload shape unverifiable, so a
/// genuinely optional dimension gets its own event instead.
class _FieldSpec {
  const _FieldSpec(this.isValid);

  final bool Function(Object? value) isValid;
}

/// The declared shape of one event type.
class _EventSpec {
  const _EventSpec({
    this.storyId = _StoryIdRule.forbidden,
    this.fields = const <String, _FieldSpec>{},
  });

  final _StoryIdRule storyId;
  final Map<String, _FieldSpec> fields;
}

const _wordHashPattern = r'^[0-9a-f]{16}$';
const _uuidPattern =
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{12}$';
const _iso8601Pattern =
    r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})$';

bool _isBool(Object? value) => value is bool;

bool _isWordHash(Object? value) =>
    value is String && RegExp(_wordHashPattern).hasMatch(value);

bool _isWordReadResult(Object? value) =>
    value is String &&
    WordReadResult.values.any((result) => result.wireValue == value);

bool _isHelpTier(Object? value) =>
    value is String && HelpTier.values.any((tier) => tier.wireValue == value);

/// The closed schema: exactly which keys each §5 event may carry.
///
/// Everything not listed here is rejected — that is the whole point (see
/// `pii_guard_test.dart`).
final Map<AnalyticsEventName, _EventSpec> _schema = {
  AnalyticsEventName.sessionStart: const _EventSpec(),
  AnalyticsEventName.storyStarted:
      const _EventSpec(storyId: _StoryIdRule.required),
  AnalyticsEventName.wordRead: _EventSpec(
    storyId: _StoryIdRule.required,
    fields: {
      'result': _FieldSpec(_isWordReadResult),
      'wordHash': _FieldSpec(_isWordHash),
    },
  ),
  AnalyticsEventName.helpGiven: _EventSpec(
    storyId: _StoryIdRule.required,
    fields: {'tier': _FieldSpec(_isHelpTier)},
  ),
  AnalyticsEventName.storyCompleted:
      const _EventSpec(storyId: _StoryIdRule.required),
  AnalyticsEventName.storyAbandoned: _EventSpec(
    storyId: _StoryIdRule.required,
    fields: {'helpInLast30s': _FieldSpec(_isBool)},
  ),
  AnalyticsEventName.vocabCardOpened:
      const _EventSpec(storyId: _StoryIdRule.optional),
  AnalyticsEventName.collectibleEarned:
      const _EventSpec(storyId: _StoryIdRule.optional),
  AnalyticsEventName.twisterStarted: const _EventSpec(),
  AnalyticsEventName.twisterCompleted: const _EventSpec(),
  AnalyticsEventName.soundCardPlayed: const _EventSpec(),
  AnalyticsEventName.soundCardEcho: _EventSpec(
    fields: {'matched': _FieldSpec(_isBool)},
  ),
};

/// The base keys every payload carries, regardless of event type.
const _baseKeys = <String>{
  'event',
  'timestamp',
  'installId',
  'profileOrdinal',
  'levelOrdinal',
};

/// Lowest and highest valid profile ordinal (§8 Unit 10: max 4 profiles).
const int _minProfileOrdinal = 1;
const int _maxProfileOrdinal = 4;

/// Validates a wire payload against the §5/§8 schema for its event type.
///
/// Throws [SchemaViolation] if anything is wrong: an unknown event name, a
/// malformed base field, a missing or ill-typed event-specific field, or —
/// the PII tripwire — *any* key the event type does not declare.
void validateEventPayload(Map<String, Object?> payload) {
  // 1. Event name.
  final rawEvent = payload['event'];
  if (rawEvent == null) {
    throw SchemaViolation('payload is missing the required "event" key');
  }
  if (rawEvent is! String) {
    throw SchemaViolation('"event" must be a String, got ${rawEvent.runtimeType}');
  }
  final name = analyticsEventNameFromWire(rawEvent);
  if (name == null) {
    throw SchemaViolation('"$rawEvent" is not one of the §5 analytics events');
  }
  final spec = _schema[name]!;

  // 2. Base fields.
  final timestamp = payload['timestamp'];
  if (timestamp == null) {
    throw SchemaViolation('$rawEvent is missing the required "timestamp" key');
  }
  if (timestamp is! String ||
      !RegExp(_iso8601Pattern).hasMatch(timestamp) ||
      DateTime.tryParse(timestamp) == null) {
    throw SchemaViolation(
        '$rawEvent "timestamp" must be an ISO-8601 timestamp, got $timestamp');
  }

  final installId = payload['installId'];
  if (installId == null) {
    throw SchemaViolation('$rawEvent is missing the required "installId" key');
  }
  if (installId is! String || !RegExp(_uuidPattern).hasMatch(installId)) {
    throw SchemaViolation(
        '$rawEvent "installId" must be a random per-install UUID');
  }

  final profileOrdinal = payload['profileOrdinal'];
  if (profileOrdinal is! int ||
      profileOrdinal < _minProfileOrdinal ||
      profileOrdinal > _maxProfileOrdinal) {
    throw SchemaViolation('$rawEvent "profileOrdinal" must be an int in '
        '$_minProfileOrdinal-$_maxProfileOrdinal, got $profileOrdinal');
  }

  final levelOrdinal = payload['levelOrdinal'];
  if (levelOrdinal is! int || levelOrdinal < 1) {
    throw SchemaViolation('$rawEvent "levelOrdinal" must be a positive int, '
        'got $levelOrdinal');
  }

  // 3. storyId, per this event type's rule.
  final hasStoryId = payload.containsKey('storyId');
  switch (spec.storyId) {
    case _StoryIdRule.required:
      if (!hasStoryId) {
        throw SchemaViolation('$rawEvent requires a "storyId"');
      }
    case _StoryIdRule.forbidden:
      if (hasStoryId) {
        throw SchemaViolation('$rawEvent does not happen inside a story and '
            'must not carry a "storyId"');
      }
    case _StoryIdRule.optional:
      break;
  }
  if (hasStoryId) {
    final storyId = payload['storyId'];
    if (storyId is! String || storyId.isEmpty) {
      throw SchemaViolation('$rawEvent "storyId" must be a non-empty String');
    }
  }

  // 4. Event-specific fields.
  for (final entry in spec.fields.entries) {
    if (!payload.containsKey(entry.key)) {
      throw SchemaViolation('$rawEvent is missing the required field '
          '"${entry.key}"');
    }
    if (!entry.value.isValid(payload[entry.key])) {
      throw SchemaViolation('$rawEvent field "${entry.key}" has an invalid '
          'value: ${payload[entry.key]}');
    }
  }

  // 5. THE TRIPWIRE: strict allowlist. Any key not declared above — a
  // name, raw word text, a device id, audio, a transcript, coordinates, an
  // age, or just an unplanned extra — fails the schema here.
  final allowed = <String>{
    ..._baseKeys,
    if (spec.storyId != _StoryIdRule.forbidden) 'storyId',
    ...spec.fields.keys,
  };
  final unknown = payload.keys.where((key) => !allowed.contains(key)).toList();
  if (unknown.isNotEmpty) {
    throw SchemaViolation('$rawEvent carries undeclared field(s) '
        '${unknown.join(", ")} — the analytics payload schema is a strict '
        'allowlist (PRD §8 Unit 12: no PII-shaped fields, ever)');
  }
}

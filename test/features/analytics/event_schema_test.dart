/// Unit tests for the analytics event vocabulary and schema (PRD §5, §8
/// Unit 12, §9 A-14).
///
/// Covers: events.dart (the exact §5 event set + result/tier vocabularies)
/// and event_schema.dart (AnalyticsEvent, the word-hash function pinned by
/// A-14, and validateEventPayload — the schema gate every emitted payload
/// must pass).
///
/// This file imports lib/features/analytics/events.dart and
/// lib/features/analytics/event_schema.dart, neither of which exists yet:
/// the whole file fails to compile until they are created — the expected
/// red state ("red for the right reason").
///
/// PII-shaped-field rejection gets its own dedicated density in
/// pii_guard_test.dart (the CI tripwire); this file focuses on the
/// positive shape of each of the 12 events and the word-hash contract.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/features/analytics/events.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';

/// The exact §5 event set, in PRD order. Any drift from this exact set
/// (extra event, missing event, renamed wire string) should fail the
/// "exactly the §5 event set exists, no more" acceptance criterion.
const _expectedWireNames = <String>[
  'session_start',
  'story_started',
  'word_read',
  'help_given',
  'story_completed',
  'story_abandoned',
  'vocab_card_opened',
  'collectible_earned',
  'twister_started',
  'twister_completed',
  'sound_card_played',
  'sound_card_echo',
];

DateTime _t([int minute = 0]) => DateTime.utc(2026, 1, 1, 12, minute);

void main() {
  group('AnalyticsEventName — exactly the §5 event set, no more', () {
    test('POSITIVE: has exactly 12 values', () {
      expect(AnalyticsEventName.values, hasLength(12));
    });

    test('POSITIVE: wire names are exactly the §5 set (order-independent)', () {
      final wireNames =
          AnalyticsEventName.values.map((e) => e.wireName).toSet();
      expect(wireNames, equals(_expectedWireNames.toSet()));
    });

    test('NEGATIVE: wire names contain no duplicates', () {
      final wireNames = AnalyticsEventName.values.map((e) => e.wireName);
      expect(wireNames.toSet(), hasLength(AnalyticsEventName.values.length));
    });

    test('EDGE: every wire name is snake_case (no camelCase leakage)', () {
      for (final name in AnalyticsEventName.values) {
        expect(
          name.wireName,
          matches(RegExp(r'^[a-z]+(_[a-z]+)*$')),
          reason: '${name.wireName} is not snake_case',
        );
      }
    });
  });

  group('WordReadResult — correct | near_miss | helped', () {
    test('POSITIVE: exactly 3 values with the pinned wire strings', () {
      expect(WordReadResult.values, hasLength(3));
      expect(WordReadResult.correct.wireValue, 'correct');
      expect(WordReadResult.nearMiss.wireValue, 'near_miss');
      expect(WordReadResult.helped.wireValue, 'helped');
    });
  });

  group('HelpTier — sound_out | modeled (help_given only fires when help '
      'was actually given, so "none" is not a valid tier)', () {
    test('POSITIVE: exactly 2 values with the pinned wire strings', () {
      expect(HelpTier.values, hasLength(2));
      expect(HelpTier.soundOut.wireValue, 'sound_out');
      expect(HelpTier.modeled.wireValue, 'modeled');
    });
  });

  group('hashWord — A-14: SHA-256 of the lowercased word text, truncated '
      'to 16 hex chars', () {
    // Vectors computed independently via `sha256sum` (bash), not via the
    // crypto package, so they are a true external oracle for A-14.
    test('POSITIVE: known vector — "cat"', () {
      expect(hashWord('cat'), '77af778b51abd4a3');
    });

    test('POSITIVE: known vector — "the"', () {
      expect(hashWord('the'), 'b9776d7ddf459c9a');
    });

    test('POSITIVE: known vector — "elephant"', () {
      expect(hashWord('elephant'), 'cd08c4c4316df20d');
    });

    test('POSITIVE: known vector — single-char word "a" (edge length)', () {
      expect(hashWord('a'), 'ca978112ca1bbdca');
    });

    test('POSITIVE: hash is always exactly 16 lowercase hex chars', () {
      for (final word in ['cat', 'a', 'elephant', 'Sh', 'ANTIDISESTABLISH']) {
        expect(hashWord(word), matches(RegExp(r'^[0-9a-f]{16}$')));
      }
    });

    test('NEGATIVE: "CAT" hashes to the SAME value as "cat" (lowercased '
        'before hashing, per A-14 — NOT the raw-case SHA-256)', () {
      expect(hashWord('CAT'), hashWord('cat'));
      expect(hashWord('CAT'), '77af778b51abd4a3');
      // Sanity: this is NOT the SHA-256 of the raw uppercase string.
      expect(hashWord('CAT'), isNot('15b89a569474240a'));
    });

    test('NEGATIVE: "Cat" (mixed case) also hashes to the "cat" value', () {
      expect(hashWord('Cat'), hashWord('cat'));
    });

    test('NEGATIVE: the hash never equals the raw word text itself', () {
      // Orchestrator test-fix: the contains() leak check is meaningless for
      // single hex characters -- this file's own pinned vector for 'a'
      // (ca978112ca1bbdca, the true A-14 value) necessarily contains 'a',
      // so the two assertions could never both hold. Equality still checked
      // for all words; substring leakage only for multi-char words.
      for (final word in ['cat', 'the', 'elephant', 'a']) {
        expect(hashWord(word), isNot(word));
      }
      for (final word in ['cat', 'the', 'elephant']) {
        expect(hashWord(word), isNot(contains(word)));
      }
    });

    test('EDGE: different words produce different hashes (no accidental '
        'collision among this fixture set)', () {
      final words = ['cat', 'dog', 'the', 'a', 'elephant', 'sun'];
      final hashes = words.map(hashWord).toSet();
      expect(hashes, hasLength(words.length));
    });
  });

  group('AnalyticsEvent.toPayload() — wire shape', () {
    test('POSITIVE: base fields serialize with correct wire types', () {
      final event = AnalyticsEvent(
        name: AnalyticsEventName.storyCompleted,
        timestamp: DateTime.utc(2026, 1, 1, 12, 30, 5),
        installId: 'a1b2c3d4-1234-4abc-8def-0123456789ab',
        profileOrdinal: 2,
        levelOrdinal: 5,
        storyId: 'story-42',
      );
      final payload = event.toPayload();

      expect(payload['event'], 'story_completed');
      expect(payload['timestamp'], '2026-01-01T12:30:05.000Z');
      expect(payload['installId'], 'a1b2c3d4-1234-4abc-8def-0123456789ab');
      expect(payload['profileOrdinal'], 2);
      expect(payload['levelOrdinal'], 5);
      expect(payload['storyId'], 'story-42');
    });

    test('EDGE: null storyId is OMITTED from the payload entirely (not '
        'present as a null-valued key)', () {
      final event = AnalyticsEvent(
        name: AnalyticsEventName.soundCardPlayed,
        timestamp: _t(),
        installId: 'a1b2c3d4-1234-4abc-8def-0123456789ab',
        profileOrdinal: 1,
        levelOrdinal: 1,
      );
      final payload = event.toPayload();
      expect(payload.containsKey('storyId'), isFalse);
    });

    test('POSITIVE: event-specific fields are merged into the payload', () {
      final event = AnalyticsEvent(
        name: AnalyticsEventName.wordRead,
        timestamp: _t(),
        installId: 'a1b2c3d4-1234-4abc-8def-0123456789ab',
        profileOrdinal: 1,
        levelOrdinal: 3,
        storyId: 'story-1',
        fields: {
          'result': WordReadResult.helped.wireValue,
          'wordHash': hashWord('cat'),
        },
      );
      final payload = event.toPayload();
      expect(payload['result'], 'helped');
      expect(payload['wordHash'], '77af778b51abd4a3');
    });
  });

  group('validateEventPayload — POSITIVE: one valid payload per §5 event '
      'type validates without throwing', () {
    const installId = 'a1b2c3d4-1234-4abc-8def-0123456789ab';

    Map<String, Object?> base(
      AnalyticsEventName name, {
      String? storyId,
      Map<String, Object?> fields = const {},
    }) {
      return AnalyticsEvent(
        name: name,
        timestamp: _t(),
        installId: installId,
        profileOrdinal: 1,
        levelOrdinal: 2,
        storyId: storyId,
        fields: fields,
      ).toPayload();
    }

    test('session_start', () {
      expect(() => validateEventPayload(base(AnalyticsEventName.sessionStart)),
          returnsNormally);
    });

    test('story_started', () {
      expect(
        () => validateEventPayload(
          base(AnalyticsEventName.storyStarted, storyId: 's1'),
        ),
        returnsNormally,
      );
    });

    test('word_read (correct)', () {
      expect(
        () => validateEventPayload(base(
          AnalyticsEventName.wordRead,
          storyId: 's1',
          fields: {
            'result': WordReadResult.correct.wireValue,
            'wordHash': hashWord('cat'),
          },
        )),
        returnsNormally,
      );
    });

    test('word_read (near_miss)', () {
      expect(
        () => validateEventPayload(base(
          AnalyticsEventName.wordRead,
          storyId: 's1',
          fields: {
            'result': WordReadResult.nearMiss.wireValue,
            'wordHash': hashWord('cat'),
          },
        )),
        returnsNormally,
      );
    });

    test('word_read (helped)', () {
      expect(
        () => validateEventPayload(base(
          AnalyticsEventName.wordRead,
          storyId: 's1',
          fields: {
            'result': WordReadResult.helped.wireValue,
            'wordHash': hashWord('cat'),
          },
        )),
        returnsNormally,
      );
    });

    test('help_given (soundOut tier)', () {
      expect(
        () => validateEventPayload(base(
          AnalyticsEventName.helpGiven,
          storyId: 's1',
          fields: {'tier': HelpTier.soundOut.wireValue},
        )),
        returnsNormally,
      );
    });

    test('help_given (modeled tier)', () {
      expect(
        () => validateEventPayload(base(
          AnalyticsEventName.helpGiven,
          storyId: 's1',
          fields: {'tier': HelpTier.modeled.wireValue},
        )),
        returnsNormally,
      );
    });

    test('story_completed', () {
      expect(
        () => validateEventPayload(
          base(AnalyticsEventName.storyCompleted, storyId: 's1'),
        ),
        returnsNormally,
      );
    });

    test('story_abandoned (helpInLast30s: true)', () {
      expect(
        () => validateEventPayload(base(
          AnalyticsEventName.storyAbandoned,
          storyId: 's1',
          fields: {'helpInLast30s': true},
        )),
        returnsNormally,
      );
    });

    test('story_abandoned (helpInLast30s: false)', () {
      expect(
        () => validateEventPayload(base(
          AnalyticsEventName.storyAbandoned,
          storyId: 's1',
          fields: {'helpInLast30s': false},
        )),
        returnsNormally,
      );
    });

    test('vocab_card_opened', () {
      expect(
        () => validateEventPayload(
          base(AnalyticsEventName.vocabCardOpened, storyId: 's1'),
        ),
        returnsNormally,
      );
    });

    test('collectible_earned', () {
      expect(
        () => validateEventPayload(
          base(AnalyticsEventName.collectibleEarned, storyId: 's1'),
        ),
        returnsNormally,
      );
    });

    test('twister_started', () {
      expect(
        () => validateEventPayload(base(AnalyticsEventName.twisterStarted)),
        returnsNormally,
      );
    });

    test('twister_completed', () {
      expect(
        () => validateEventPayload(base(AnalyticsEventName.twisterCompleted)),
        returnsNormally,
      );
    });

    test('sound_card_played', () {
      expect(
        () => validateEventPayload(base(AnalyticsEventName.soundCardPlayed)),
        returnsNormally,
      );
    });

    test('sound_card_echo (matched: true)', () {
      expect(
        () => validateEventPayload(base(
          AnalyticsEventName.soundCardEcho,
          fields: {'matched': true},
        )),
        returnsNormally,
      );
    });

    test('sound_card_echo (matched: false)', () {
      expect(
        () => validateEventPayload(base(
          AnalyticsEventName.soundCardEcho,
          fields: {'matched': false},
        )),
        returnsNormally,
      );
    });
  });

  group('validateEventPayload — NEGATIVE: malformed base fields', () {
    Map<String, Object?> validSessionStart() => AnalyticsEvent(
          name: AnalyticsEventName.sessionStart,
          timestamp: _t(),
          installId: 'a1b2c3d4-1234-4abc-8def-0123456789ab',
          profileOrdinal: 1,
          levelOrdinal: 1,
        ).toPayload();

    test('profileOrdinal 0 is rejected (below the 1-4 range)', () {
      final payload = validSessionStart()..['profileOrdinal'] = 0;
      expect(() => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()));
    });

    test('profileOrdinal 5 is rejected (above the 1-4 range)', () {
      final payload = validSessionStart()..['profileOrdinal'] = 5;
      expect(() => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()));
    });

    test('profileOrdinal -1 is rejected', () {
      final payload = validSessionStart()..['profileOrdinal'] = -1;
      expect(() => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()));
    });

    test('EDGE: profileOrdinal 1 and 4 (the inclusive boundary values) '
        'are accepted', () {
      for (final ordinal in [1, 4]) {
        final payload = validSessionStart()..['profileOrdinal'] = ordinal;
        expect(() => validateEventPayload(payload), returnsNormally);
      }
    });

    test('levelOrdinal 0 is rejected (must be a positive ordinal)', () {
      final payload = validSessionStart()..['levelOrdinal'] = 0;
      expect(() => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()));
    });

    test('levelOrdinal negative is rejected', () {
      final payload = validSessionStart()..['levelOrdinal'] = -3;
      expect(() => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()));
    });

    test('missing "event" key is rejected', () {
      final payload = validSessionStart()..remove('event');
      expect(() => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()));
    });

    test('unrecognized "event" wire name is rejected', () {
      final payload = validSessionStart()..['event'] = 'ad_impression';
      expect(() => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()));
    });

    test('missing "timestamp" key is rejected', () {
      final payload = validSessionStart()..remove('timestamp');
      expect(() => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()));
    });

    test('non-ISO8601 "timestamp" is rejected', () {
      final payload = validSessionStart()..['timestamp'] = 'not-a-date';
      expect(() => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()));
    });

    test('missing "installId" key is rejected', () {
      final payload = validSessionStart()..remove('installId');
      expect(() => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()));
    });

    test('"installId" that is not UUID-shaped is rejected', () {
      final payload = validSessionStart()..['installId'] = 'not-a-uuid';
      expect(() => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()));
    });
  });

  group('validateEventPayload — NEGATIVE: malformed event-specific fields',
      () {
    Map<String, Object?> wordReadPayload({
      Object? result = 'correct',
      Object? wordHash,
    }) {
      final fields = <String, Object?>{};
      if (result != null) fields['result'] = result;
      if (wordHash != null) fields['wordHash'] = wordHash;
      return AnalyticsEvent(
        name: AnalyticsEventName.wordRead,
        timestamp: _t(),
        installId: 'a1b2c3d4-1234-4abc-8def-0123456789ab',
        profileOrdinal: 1,
        levelOrdinal: 1,
        storyId: 's1',
        fields: fields,
      ).toPayload();
    }

    test('word_read missing "wordHash" is rejected', () {
      final payload = wordReadPayload(wordHash: null);
      expect(() => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()));
    });

    test('word_read missing "result" is rejected', () {
      final payload = wordReadPayload(result: null, wordHash: hashWord('cat'));
      expect(() => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()));
    });

    test('word_read with an invalid "result" value is rejected', () {
      final payload =
          wordReadPayload(result: 'sort-of-correct', wordHash: hashWord('cat'));
      expect(() => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()));
    });

    test('word_read wordHash too short (15 hex chars) is rejected', () {
      final payload = wordReadPayload(wordHash: hashWord('cat').substring(0, 15));
      expect(() => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()));
    });

    test('word_read wordHash too long (17 hex chars) is rejected', () {
      final payload = wordReadPayload(wordHash: '${hashWord('cat')}a');
      expect(() => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()));
    });

    test('word_read wordHash with uppercase hex chars is rejected (A-14 '
        'pins lowercase)', () {
      final payload = wordReadPayload(wordHash: hashWord('cat').toUpperCase());
      expect(() => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()));
    });

    test('word_read wordHash with a non-hex character is rejected', () {
      final payload = wordReadPayload(wordHash: 'zzzzzzzzzzzzzzzz');
      expect(() => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()));
    });

    test('help_given with an invalid tier value is rejected', () {
      final payload = AnalyticsEvent(
        name: AnalyticsEventName.helpGiven,
        timestamp: _t(),
        installId: 'a1b2c3d4-1234-4abc-8def-0123456789ab',
        profileOrdinal: 1,
        levelOrdinal: 1,
        storyId: 's1',
        fields: {'tier': 'none'},
      ).toPayload();
      expect(() => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()));
    });

    test('sound_card_echo with a non-bool "matched" value is rejected', () {
      final payload = AnalyticsEvent(
        name: AnalyticsEventName.soundCardEcho,
        timestamp: _t(),
        installId: 'a1b2c3d4-1234-4abc-8def-0123456789ab',
        profileOrdinal: 1,
        levelOrdinal: 1,
        fields: {'matched': 'yes'},
      ).toPayload();
      expect(() => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()));
    });

    test('story_abandoned with a non-bool "helpInLast30s" value is '
        'rejected', () {
      final payload = AnalyticsEvent(
        name: AnalyticsEventName.storyAbandoned,
        timestamp: _t(),
        installId: 'a1b2c3d4-1234-4abc-8def-0123456789ab',
        profileOrdinal: 1,
        levelOrdinal: 1,
        storyId: 's1',
        fields: {'helpInLast30s': 1},
      ).toPayload();
      expect(() => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()));
    });

    test('EDGE: a field valid for one event type is rejected on a type '
        'that does not declare it (e.g. "tier" on session_start)', () {
      final payload = AnalyticsEvent(
        name: AnalyticsEventName.sessionStart,
        timestamp: _t(),
        installId: 'a1b2c3d4-1234-4abc-8def-0123456789ab',
        profileOrdinal: 1,
        levelOrdinal: 1,
        fields: {'tier': HelpTier.soundOut.wireValue},
      ).toPayload();
      expect(() => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()));
    });

    test('EDGE: a completely unknown extra key is rejected on an otherwise '
        'valid payload (strict allowlist, not merely a blocklist)', () {
      final payload = AnalyticsEvent(
        name: AnalyticsEventName.storyCompleted,
        timestamp: _t(),
        installId: 'a1b2c3d4-1234-4abc-8def-0123456789ab',
        profileOrdinal: 1,
        levelOrdinal: 1,
        storyId: 's1',
        fields: {'someUnplannedField': 'x'},
      ).toPayload();
      expect(() => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()));
    });
  });
}

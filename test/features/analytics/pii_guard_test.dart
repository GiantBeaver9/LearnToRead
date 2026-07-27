/// pii_guard_test — the CI tripwire (PRD §8 Unit 12 accept: "any
/// PII-shaped field... fails schema in CI"; §5 "never names, audio, or
/// device identifiers"; Unit 12 acceptance: "no third-party tracker SDK is
/// imported").
///
/// This file is deliberately the densest in the suite: every PII-shaped
/// field named in the ticket/PRD (a name string, raw word text, a
/// device-id-looking field, plus audio/transcript/location) is tried
/// against multiple event types and MUST be rejected by
/// validateEventPayload. It also statically scans
/// lib/features/analytics/*.dart for third-party tracker SDK imports.
///
/// Imports lib/features/analytics/events.dart and event_schema.dart, which
/// do not exist yet: this file fails to compile until they exist — the
/// expected red state.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/features/analytics/events.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';

const _installId = 'a1b2c3d4-1234-4abc-8def-0123456789ab';

DateTime _t() => DateTime.utc(2026, 1, 1, 12);

Map<String, Object?> _validSessionStart() => AnalyticsEvent(
      name: AnalyticsEventName.sessionStart,
      timestamp: _t(),
      installId: _installId,
      profileOrdinal: 1,
      levelOrdinal: 1,
    ).toPayload();

Map<String, Object?> _validWordRead() => AnalyticsEvent(
      name: AnalyticsEventName.wordRead,
      timestamp: _t(),
      installId: _installId,
      profileOrdinal: 1,
      levelOrdinal: 1,
      storyId: 's1',
      fields: {
        'result': WordReadResult.correct.wireValue,
        'wordHash': hashWord('cat'),
      },
    ).toPayload();

/// PII-shaped field names called out by the ticket and PRD §5/§8: a name
/// string, a device-identifier-looking field, and the never-collected
/// categories (audio, transcript, location). Raw word text is exercised
/// separately below because it is only meaningful layered onto word_read
/// (a payload that already, correctly, carries a wordHash).
const _piiFieldsAndSampleValues = <String, Object?>{
  'name': 'Timmy',
  'childName': 'Timmy',
  'displayName': 'Timmy',
  'deviceId': 'ABCDEF0123456789',
  'idfa': '00000000-0000-0000-0000-000000000000',
  'aaid': '00000000-0000-0000-0000-000000000000',
  'advertisingId': '00000000-0000-0000-0000-000000000000',
  'audio': <int>[1, 2, 3],
  'audioBlob': 'base64-encoded-audio-data',
  'transcript': 'the cat sat on the mat',
  'location': '37.7749,-122.4194',
  'latitude': 37.7749,
  'longitude': -122.4194,
  'ageExact': 7,
};

void main() {
  group('PII GUARD — a name-shaped field is rejected on any event', () {
    for (final entry in _piiFieldsAndSampleValues.entries) {
      test('"${entry.key}" added to an otherwise-valid session_start is '
          'rejected', () {
        final payload = _validSessionStart();
        payload[entry.key] = entry.value;
        expect(
          () => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()),
          reason: 'schema accepted PII-shaped field "${entry.key}"',
        );
      });
    }
  });

  group('PII GUARD — the same PII-shaped fields are rejected on word_read '
      '(a payload that already carries a legitimate hashed field, proving '
      'the guard is not merely "reject payloads with no hash")', () {
    for (final entry in _piiFieldsAndSampleValues.entries) {
      test('"${entry.key}" added alongside a valid wordHash is rejected',
          () {
        final payload = _validWordRead();
        payload[entry.key] = entry.value;
        expect(
          () => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()),
          reason: 'schema accepted PII-shaped field "${entry.key}"',
        );
      });
    }
  });

  group('PII GUARD — raw word text specifically (never raw word text, '
      'only the A-14 hash)', () {
    test('a "wordText" field carrying the raw word is rejected even '
        'though "wordHash" is also present and correct', () {
      final payload = _validWordRead();
      payload['wordText'] = 'cat';
      expect(() => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()));
    });

    test('a "word" field carrying the raw word is rejected', () {
      final payload = _validWordRead();
      payload['word'] = 'cat';
      expect(() => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()));
    });

    test('the raw word text under "wordHash" itself (i.e. someone passes '
        'the plaintext word instead of hashing it) is rejected — a '
        'plaintext word is not a 16-hex-char hash', () {
      final payload = AnalyticsEvent(
        name: AnalyticsEventName.wordRead,
        timestamp: _t(),
        installId: _installId,
        profileOrdinal: 1,
        levelOrdinal: 1,
        storyId: 's1',
        fields: {
          'result': WordReadResult.correct.wireValue,
          'wordHash': 'cat',
        },
      ).toPayload();
      expect(() => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()));
    });

    test('NEGATIVE control: the correctly-hashed word_read payload (no '
        'raw text anywhere) validates fine — proves the guard rejects '
        'raw text specifically, not word_read events in general', () {
      expect(() => validateEventPayload(_validWordRead()), returnsNormally);
    });
  });

  group('PII GUARD — age beyond age band is never collected (PRD §5/§8: '
      '"names, age beyond age band"; no event carries an age/ageBand '
      'field at all — age band lives only in the device-local Profile '
      'model, never in an analytics payload)', () {
    test('an "ageBand" field is rejected on session_start', () {
      final payload = _validSessionStart();
      payload['ageBand'] = '7-8';
      expect(() => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()));
    });

    test('an "age" field is rejected on session_start', () {
      final payload = _validSessionStart();
      payload['age'] = 7;
      expect(() => validateEventPayload(payload),
          throwsA(isA<SchemaViolation>()));
    });
  });

  group('PII GUARD — hashWord sanity (defense in depth, complements the '
      'A-14 vector tests in event_schema_test.dart)', () {
    test('hashWord output is never equal to any plausible raw word input',
        () {
      for (final word in ['cat', 'the', 'elephant', 'a', 'jump', 'frog']) {
        expect(hashWord(word), isNot(equals(word)));
      }
    });
  });

  group('No third-party tracker SDK is imported under '
      'lib/features/analytics/ (Unit 12 acceptance)', () {
    // Known third-party analytics/tracker/ad-attribution SDK package
    // prefixes. Anything importing one of these under the analytics
    // feature directory would defeat the entire local-first, anonymous,
    // self-hosted-endpoint posture (A-5).
    const bannedPackagePrefixes = <String>[
      'firebase_analytics',
      'firebase_core',
      'firebase_crashlytics',
      'mixpanel',
      'segment',
      'amplitude',
      'google_analytics',
      'google_mobile_ads',
      'app_tracking_transparency',
      'facebook_app_events',
      'appsflyer',
      'adjust',
      'sentry',
      'posthog',
      'braze',
    ];

    final importRegExp =
        RegExp('''^\\s*import\\s+['"]package:([a-zA-Z0-9_]+)/''');

    List<String> _scanForBannedImports(Directory dir) {
      final violations = <String>[];
      if (!dir.existsSync()) return violations;
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        for (final line in entity.readAsLinesSync()) {
          final match = importRegExp.firstMatch(line);
          if (match == null) continue;
          final package = match.group(1)!;
          if (bannedPackagePrefixes.any((banned) => package == banned)) {
            violations.add('${entity.path}: imports package:$package');
          }
        }
      }
      return violations;
    }

    test('scanner correctness fixture (POSITIVE): flags a banned import '
        'in a throwaway temp dir', () {
      final tempDir =
          Directory.systemTemp.createTempSync('pii_guard_scanner_fixture_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      File('${tempDir.path}/bad.dart').writeAsStringSync(
        "import 'package:mixpanel_flutter/mixpanel_flutter.dart';\n",
      );

      final violations = _scanForBannedImports(tempDir);
      expect(violations, hasLength(1));
      expect(violations.single, contains('mixpanel_flutter'));
    });

    test('scanner correctness fixture (NEGATIVE): does NOT flag an '
        'allowed import (crypto, dart:io, first-party package) in a '
        'throwaway temp dir', () {
      final tempDir =
          Directory.systemTemp.createTempSync('pii_guard_scanner_fixture_');
      addTearDown(() => tempDir.deleteSync(recursive: true));

      File('${tempDir.path}/good.dart').writeAsStringSync(
        "import 'dart:io';\n"
        "import 'package:crypto/crypto.dart';\n"
        "import 'package:learn_to_read/features/analytics/events.dart';\n",
      );

      final violations = _scanForBannedImports(tempDir);
      expect(violations, isEmpty);
    });

    test('CI GATE: the real lib/features/analytics/ tree imports no '
        'third-party tracker SDK', () {
      final analyticsDir = Directory('lib/features/analytics');
      expect(
        analyticsDir.existsSync(),
        isTrue,
        reason: 'lib/features/analytics/ does not exist yet',
      );
      final violations = _scanForBannedImports(analyticsDir);
      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  });
}

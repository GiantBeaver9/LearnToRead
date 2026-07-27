/// Unit tests for session boundary semantics and story_abandoned triggers
/// (PRD §8 Unit 12, pinned verbatim):
///
/// - "a session starts at profile selection and ends when the app is
///   backgrounded for more than 120 s, is closed, or the profile
///   switches (timeout is a tunable constant)."
/// - "story_abandoned fires when the reading screen is exited after
///   story_started but before story_completed — including via session
///   end — and carries whether a help event occurred in the preceding
///   30 s."
///
/// Design note pinned by this test file (not literally spelled out in the
/// PRD, but required for a coherent, testable contract): SessionTracker
/// exposes one `startSession` entry point. Calling it while no session is
/// active simply starts one; calling it while a session IS active is, by
/// definition, a profile switch — it ends the old session (running the
/// same abandonment check as any other session end) and then starts the
/// new one. This lets one API surface cover both the "profile selection"
/// and "profile switch" endings pinned above.
///
/// All scenarios are driven by an injectable fake clock and scripted
/// lifecycle calls — no real timers, no wall-clock sleeps.
///
/// Imports lib/features/analytics/{events,event_schema,session_tracker}.dart,
/// none of which exist yet: this file fails to compile until they exist —
/// the expected red state.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/analytics/events.dart';
import 'package:learn_to_read/features/analytics/session_tracker.dart';

class _FakeClock {
  _FakeClock(this._now);
  DateTime _now;
  DateTime call() => _now;
  void advance(Duration d) => _now = _now.add(d);
}

void main() {
  late _FakeClock clock;
  late List<AnalyticsEvent> events;
  late SessionTracker tracker;

  setUp(() {
    clock = _FakeClock(DateTime.utc(2026, 1, 1, 9));
    events = [];
    tracker = SessionTracker(
      clock: clock,
      installId: 'a1b2c3d4-1234-4abc-8def-0123456789ab',
      onEvent: events.add,
    );
  });

  Iterable<AnalyticsEvent> abandonedEvents() =>
      events.where((e) => e.name == AnalyticsEventName.storyAbandoned);

  group('POSITIVE: session starts at profile selection', () {
    test('startSession emits exactly one session_start with the given '
        'profile/level ordinals and the tracker\'s installId', () {
      tracker.startSession(profileOrdinal: 2, levelOrdinal: 5);

      expect(events, hasLength(1));
      final event = events.single;
      expect(event.name, AnalyticsEventName.sessionStart);
      expect(event.profileOrdinal, 2);
      expect(event.levelOrdinal, 5);
      expect(event.installId, 'a1b2c3d4-1234-4abc-8def-0123456789ab');
      expect(event.timestamp, clock());
    });
  });

  group('Background timeout boundary: 119s vs 121s (default 120s '
      'constant)', () {
    test('NEGATIVE: backgrounded 119s then foregrounded does NOT end the '
        'session (no story_abandoned even though mid-story)', () {
      tracker.startSession(profileOrdinal: 1, levelOrdinal: 1);
      tracker.onStoryStarted(storyId: 's1');
      tracker.onBackground();
      clock.advance(const Duration(seconds: 119));
      tracker.onForeground();

      expect(abandonedEvents(), isEmpty);
    });

    test('EDGE: after a 119s background/foreground cycle the session is '
        'still the SAME continuous session — closing it mid-story fires '
        'exactly one abandonment (not zero, not a stale duplicate)', () {
      tracker.startSession(profileOrdinal: 1, levelOrdinal: 1);
      tracker.onStoryStarted(storyId: 's1');
      tracker.onBackground();
      clock.advance(const Duration(seconds: 119));
      tracker.onForeground();
      tracker.onClose();

      expect(abandonedEvents(), hasLength(1));
    });

    test('POSITIVE: backgrounded 121s then foregrounded DOES end the '
        'session — story_abandoned fires for the mid-story session', () {
      tracker.startSession(profileOrdinal: 1, levelOrdinal: 1);
      tracker.onStoryStarted(storyId: 's1');
      tracker.onBackground();
      clock.advance(const Duration(seconds: 121));
      tracker.onForeground();

      expect(abandonedEvents(), hasLength(1));
      expect(abandonedEvents().single.fields['helpInLast30s'], false);
    });

    test('NEGATIVE: backgrounded 121s then foregrounded while NOT '
        'mid-story emits no story_abandoned (nothing to abandon)', () {
      tracker.startSession(profileOrdinal: 1, levelOrdinal: 1);
      tracker.onBackground();
      clock.advance(const Duration(seconds: 121));
      tracker.onForeground();

      expect(abandonedEvents(), isEmpty);
    });

    test('EDGE: a completed story does not count as abandoned even after '
        'a session-ending background timeout', () {
      tracker.startSession(profileOrdinal: 1, levelOrdinal: 1);
      tracker.onStoryStarted(storyId: 's1');
      tracker.onStoryCompleted();
      tracker.onBackground();
      clock.advance(const Duration(seconds: 121));
      tracker.onForeground();

      expect(abandonedEvents(), isEmpty);
    });

    test('EDGE: backgroundTimeout is a tunable constant — a custom 10s '
        'timeout ends the session at 11s but not at 9s', () {
      final customEvents = <AnalyticsEvent>[];
      final customClock = _FakeClock(DateTime.utc(2026, 1, 1, 9));
      final customTracker = SessionTracker(
        clock: customClock,
        installId: 'a1b2c3d4-1234-4abc-8def-0123456789ab',
        onEvent: customEvents.add,
        backgroundTimeout: const Duration(seconds: 10),
      );

      customTracker.startSession(profileOrdinal: 1, levelOrdinal: 1);
      customTracker.onStoryStarted(storyId: 's1');
      customTracker.onBackground();
      customClock.advance(const Duration(seconds: 9));
      customTracker.onForeground();
      expect(
        customEvents
            .where((e) => e.name == AnalyticsEventName.storyAbandoned),
        isEmpty,
      );

      customTracker.onBackground();
      customClock.advance(const Duration(seconds: 11));
      customTracker.onForeground();
      expect(
        customEvents
            .where((e) => e.name == AnalyticsEventName.storyAbandoned),
        hasLength(1),
      );
    });
  });

  group('story_abandoned trigger: session ends via app close', () {
    test('POSITIVE: onClose while mid-story fires story_abandoned', () {
      tracker.startSession(profileOrdinal: 1, levelOrdinal: 1);
      tracker.onStoryStarted(storyId: 's1');
      tracker.onClose();

      expect(abandonedEvents(), hasLength(1));
    });

    test('NEGATIVE: onClose while NOT mid-story fires no story_abandoned',
        () {
      tracker.startSession(profileOrdinal: 1, levelOrdinal: 1);
      tracker.onClose();

      expect(abandonedEvents(), isEmpty);
    });

    test('NEGATIVE: onClose after story_completed fires no '
        'story_abandoned', () {
      tracker.startSession(profileOrdinal: 1, levelOrdinal: 1);
      tracker.onStoryStarted(storyId: 's1');
      tracker.onStoryCompleted();
      tracker.onClose();

      expect(abandonedEvents(), isEmpty);
    });
  });

  group('story_abandoned trigger: session ends via profile switch', () {
    test('POSITIVE: starting a new session while mid-story in the old one '
        'fires story_abandoned for the OLD profile, then session_start '
        'for the NEW profile, in that order', () {
      tracker.startSession(profileOrdinal: 1, levelOrdinal: 2);
      tracker.onStoryStarted(storyId: 's1');
      tracker.startSession(profileOrdinal: 3, levelOrdinal: 4);

      expect(events, hasLength(3));
      expect(events[0].name, AnalyticsEventName.sessionStart);
      expect(events[0].profileOrdinal, 1);
      expect(events[1].name, AnalyticsEventName.storyAbandoned);
      expect(events[1].profileOrdinal, 1,
          reason: 'the abandonment belongs to the OLD (switched-away-from) '
              'profile');
      expect(events[2].name, AnalyticsEventName.sessionStart);
      expect(events[2].profileOrdinal, 3);
      expect(events[2].levelOrdinal, 4);
    });

    test('NEGATIVE: starting a new session while NOT mid-story emits no '
        'story_abandoned, just the two session_start events', () {
      tracker.startSession(profileOrdinal: 1, levelOrdinal: 1);
      tracker.startSession(profileOrdinal: 2, levelOrdinal: 1);

      expect(abandonedEvents(), isEmpty);
      expect(
        events.where((e) => e.name == AnalyticsEventName.sessionStart),
        hasLength(2),
      );
    });

    test('EDGE: the abandonment event\'s timestamp is the clock time at '
        'the moment of the switch, not the original session start', () {
      tracker.startSession(profileOrdinal: 1, levelOrdinal: 1);
      tracker.onStoryStarted(storyId: 's1');
      clock.advance(const Duration(minutes: 3));
      tracker.startSession(profileOrdinal: 2, levelOrdinal: 1);

      expect(abandonedEvents().single.timestamp,
          DateTime.utc(2026, 1, 1, 9, 3));
    });
  });

  group('story_abandoned trigger: direct exit (reading screen exited '
      'while the session itself continues)', () {
    test('POSITIVE: exiting the reading screen mid-story fires '
        'story_abandoned without ending the session', () {
      tracker.startSession(profileOrdinal: 1, levelOrdinal: 1);
      tracker.onStoryStarted(storyId: 's1');
      tracker.onReadingScreenExited();

      expect(abandonedEvents(), hasLength(1));
    });

    test('EDGE: exiting after the story already completed fires no '
        'story_abandoned', () {
      tracker.startSession(profileOrdinal: 1, levelOrdinal: 1);
      tracker.onStoryStarted(storyId: 's1');
      tracker.onStoryCompleted();
      tracker.onReadingScreenExited();

      expect(abandonedEvents(), isEmpty);
    });

    test('EDGE: a direct-exit abandonment does not double-fire if the '
        'session later ends by another route (close)', () {
      tracker.startSession(profileOrdinal: 1, levelOrdinal: 1);
      tracker.onStoryStarted(storyId: 's1');
      tracker.onReadingScreenExited();
      tracker.onClose();

      expect(abandonedEvents(), hasLength(1));
    });
  });

  group('help-within-30s flag: 29s vs 31s (default 30s window)', () {
    test('POSITIVE: help given 29s before abandonment => helpInLast30s '
        'is true', () {
      tracker.startSession(profileOrdinal: 1, levelOrdinal: 1);
      tracker.onStoryStarted(storyId: 's1');
      tracker.onHelpGiven();
      clock.advance(const Duration(seconds: 29));
      tracker.onReadingScreenExited();

      expect(abandonedEvents().single.fields['helpInLast30s'], true);
    });

    test('NEGATIVE: help given 31s before abandonment => helpInLast30s '
        'is false', () {
      tracker.startSession(profileOrdinal: 1, levelOrdinal: 1);
      tracker.onStoryStarted(storyId: 's1');
      tracker.onHelpGiven();
      clock.advance(const Duration(seconds: 31));
      tracker.onReadingScreenExited();

      expect(abandonedEvents().single.fields['helpInLast30s'], false);
    });

    test('NEGATIVE: no help was ever given => helpInLast30s is false',
        () {
      tracker.startSession(profileOrdinal: 1, levelOrdinal: 1);
      tracker.onStoryStarted(storyId: 's1');
      tracker.onReadingScreenExited();

      expect(abandonedEvents().single.fields['helpInLast30s'], false);
    });

    test('POSITIVE: helpInLast30s true also applies to a timeout-triggered '
        'abandonment (the flag is orthogonal to the trigger path)', () {
      tracker.startSession(profileOrdinal: 1, levelOrdinal: 1);
      tracker.onStoryStarted(storyId: 's1');
      tracker.onHelpGiven();
      clock.advance(const Duration(seconds: 5));
      tracker.onBackground();
      clock.advance(const Duration(seconds: 121));
      tracker.onForeground();

      expect(abandonedEvents().single.fields['helpInLast30s'], true);
    });

    test('EDGE: helpWindow is independently tunable — a custom 5s window '
        'flags help given 4s prior but not 6s prior', () {
      final customEvents = <AnalyticsEvent>[];
      final customClock = _FakeClock(DateTime.utc(2026, 1, 1, 9));
      final customTracker = SessionTracker(
        clock: customClock,
        installId: 'a1b2c3d4-1234-4abc-8def-0123456789ab',
        onEvent: customEvents.add,
        helpWindow: const Duration(seconds: 5),
      );

      customTracker.startSession(profileOrdinal: 1, levelOrdinal: 1);
      customTracker.onStoryStarted(storyId: 's1');
      customTracker.onHelpGiven();
      customClock.advance(const Duration(seconds: 4));
      customTracker.onReadingScreenExited();
      expect(
        customEvents
            .firstWhere((e) => e.name == AnalyticsEventName.storyAbandoned)
            .fields['helpInLast30s'],
        true,
      );

      final customEvents2 = <AnalyticsEvent>[];
      final customTracker2 = SessionTracker(
        clock: customClock,
        installId: 'a1b2c3d4-1234-4abc-8def-0123456789ab',
        onEvent: customEvents2.add,
        helpWindow: const Duration(seconds: 5),
      );
      customTracker2.startSession(profileOrdinal: 1, levelOrdinal: 1);
      customTracker2.onStoryStarted(storyId: 's2');
      customTracker2.onHelpGiven();
      customClock.advance(const Duration(seconds: 6));
      customTracker2.onReadingScreenExited();
      expect(
        customEvents2
            .firstWhere((e) => e.name == AnalyticsEventName.storyAbandoned)
            .fields['helpInLast30s'],
        false,
      );
    });
  });
}

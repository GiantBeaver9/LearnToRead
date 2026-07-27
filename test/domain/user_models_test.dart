// Pins the API of lib/domain/models/user_models.dart (PRD §5 "Device-local
// user models", ticket domain-models accept entry 2 + the AgeBand entry).
// Fails to compile until user_models.dart exists with exactly these shapes.
//
// Pinned API surface:
//   enum AgeBand { fiveToSix, sevenToEight, nineToTen } with a `label`
//     getter/field returning '5-6' | '7-8' | '9-10' respectively.
//   class Profile { localId, displayName, ageBand: AgeBand, currentLevelId,
//                    micConsent: bool, cloudAsrConsent: bool, createdAt: DateTime }
//   const int kMaxProfilesPerDevice = 4; // enforcement is local-storage/UI,
//     the constant itself lives here per the ticket's pinned_design.
//   enum StoryStatus { locked, available, completed }
//   class StoryProgress { profileId, storyId, status: StoryStatus,
//                          completedAt: DateTime?, timesRead: int }
//   enum HelpLevel { none, soundOut, modeled }
//   class WordHelpRecord { profileId, wordText, encounterCount: int,
//                           helpCount: int, lastHelpLevel: HelpLevel }
//   class TwisterProgress { profileId, twisterId, timesCompleted: int }
//   class CollectionState { profileId, earnedCollectibles: List<String> }
//
// Per the ticket's pinned_design ("No JSON for user models is needed beyond
// what Drift/analytics tickets do themselves"), this suite deliberately does
// NOT test toJson/fromJson for any user model -- persistence is owned by the
// local-storage ticket, not this one.

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/user_models.dart';

void main() {
  group('AgeBand (positive)', () {
    test('exposes exactly the three pinned bands and nothing else', () {
      expect(AgeBand.values, hasLength(3));
      expect(
        AgeBand.values.map((b) => b.name).toSet(),
        {'fiveToSix', 'sevenToEight', 'nineToTen'},
      );
    });

    test('each band exposes its pinned human-readable label', () {
      expect(AgeBand.fiveToSix.label, '5-6');
      expect(AgeBand.sevenToEight.label, '7-8');
      expect(AgeBand.nineToTen.label, '9-10');
    });
  });

  group('Profile (positive)', () {
    test('constructs with exactly the pinned fields', () {
      final createdAt = DateTime(2026, 1, 1, 9, 30);
      final profile = Profile(
        localId: 'profile.1',
        displayName: 'Ada',
        ageBand: AgeBand.sevenToEight,
        currentLevelId: 'level.3',
        micConsent: true,
        cloudAsrConsent: false,
        createdAt: createdAt,
      );
      expect(profile.localId, 'profile.1');
      expect(profile.displayName, 'Ada');
      expect(profile.ageBand, AgeBand.sevenToEight);
      expect(profile.currentLevelId, 'level.3');
      expect(profile.micConsent, isTrue);
      expect(profile.cloudAsrConsent, isFalse);
      expect(profile.createdAt, createdAt);
    });

    test('two profiles built from equal args are value-equal', () {
      final createdAt = DateTime(2026, 1, 1);
      Profile build() => Profile(
            localId: 'p1',
            displayName: 'Ada',
            ageBand: AgeBand.fiveToSix,
            currentLevelId: 'level.1',
            micConsent: true,
            cloudAsrConsent: true,
            createdAt: createdAt,
          );
      expect(build(), equals(build()));
    });
  });

  group('Profile (edge: consent flags default to no permission)', () {
    test('micConsent=false and cloudAsrConsent=false are both valid, independent flags', () {
      final profile = Profile(
        localId: 'p2',
        displayName: 'Kid',
        ageBand: AgeBand.nineToTen,
        currentLevelId: 'level.12',
        micConsent: false,
        cloudAsrConsent: false,
        createdAt: DateTime(2026, 1, 1),
      );
      expect(profile.micConsent, isFalse);
      expect(profile.cloudAsrConsent, isFalse);
    });

    test('micConsent and cloudAsrConsent vary independently (mic yes, cloud no)', () {
      final profile = Profile(
        localId: 'p3',
        displayName: 'Kid',
        ageBand: AgeBand.nineToTen,
        currentLevelId: 'level.12',
        micConsent: true,
        cloudAsrConsent: false,
        createdAt: DateTime(2026, 1, 1),
      );
      expect(profile.micConsent, isTrue);
      expect(profile.cloudAsrConsent, isFalse);
    });
  });

  group('kMaxProfilesPerDevice (positive: pinned default)', () {
    test('is exactly 4', () {
      expect(kMaxProfilesPerDevice, 4);
    });
  });

  group('StoryStatus (positive)', () {
    test('exposes exactly the three pinned statuses', () {
      expect(StoryStatus.values, hasLength(3));
      expect(
        StoryStatus.values.map((s) => s.name).toSet(),
        {'locked', 'available', 'completed'},
      );
    });
  });

  group('StoryProgress (positive)', () {
    test('constructs with exactly the pinned fields, completedAt set when completed', () {
      final completedAt = DateTime(2026, 2, 1);
      final progress = StoryProgress(
        profileId: 'profile.1',
        storyId: 'story.1',
        status: StoryStatus.completed,
        completedAt: completedAt,
        timesRead: 3,
      );
      expect(progress.profileId, 'profile.1');
      expect(progress.storyId, 'story.1');
      expect(progress.status, StoryStatus.completed);
      expect(progress.completedAt, completedAt);
      expect(progress.timesRead, 3);
    });
  });

  group('StoryProgress (edge: not-yet-completed and boundary counts)', () {
    test('completedAt is nullable for locked/available stories', () {
      final progress = StoryProgress(
        profileId: 'profile.1',
        storyId: 'story.2',
        status: StoryStatus.available,
        timesRead: 0,
      );
      expect(progress.completedAt, isNull);
      expect(progress.timesRead, 0);
    });

    test('a locked story has never been read (timesRead=0, completedAt=null)', () {
      final progress = StoryProgress(
        profileId: 'profile.1',
        storyId: 'story.3',
        status: StoryStatus.locked,
        timesRead: 0,
      );
      expect(progress.status, StoryStatus.locked);
      expect(progress.completedAt, isNull);
      expect(progress.timesRead, 0);
    });
  });

  group('HelpLevel (positive)', () {
    test('exposes exactly the three pinned tiers', () {
      expect(HelpLevel.values, hasLength(3));
      expect(
        HelpLevel.values.map((h) => h.name).toSet(),
        {'none', 'soundOut', 'modeled'},
      );
    });
  });

  group('WordHelpRecord (positive)', () {
    test('constructs with exactly the pinned fields', () {
      final record = WordHelpRecord(
        profileId: 'profile.1',
        wordText: 'cat',
        encounterCount: 5,
        helpCount: 2,
        lastHelpLevel: HelpLevel.soundOut,
      );
      expect(record.profileId, 'profile.1');
      expect(record.wordText, 'cat');
      expect(record.encounterCount, 5);
      expect(record.helpCount, 2);
      expect(record.lastHelpLevel, HelpLevel.soundOut);
    });
  });

  group('WordHelpRecord (edge: never-helped and zero-encounter boundaries)', () {
    test('a word never encountered has zero counts and lastHelpLevel none', () {
      final record = WordHelpRecord(
        profileId: 'profile.1',
        wordText: 'new',
        encounterCount: 0,
        helpCount: 0,
        lastHelpLevel: HelpLevel.none,
      );
      expect(record.encounterCount, 0);
      expect(record.helpCount, 0);
      expect(record.lastHelpLevel, HelpLevel.none);
    });

    test('helpCount may equal encounterCount (helped every single time)', () {
      final record = WordHelpRecord(
        profileId: 'profile.1',
        wordText: 'tricky',
        encounterCount: 4,
        helpCount: 4,
        lastHelpLevel: HelpLevel.modeled,
      );
      expect(record.helpCount, record.encounterCount);
    });
  });

  group('TwisterProgress (positive + edge)', () {
    test('constructs with exactly the pinned fields', () {
      final progress = TwisterProgress(
        profileId: 'profile.1',
        twisterId: 'twister.1',
        timesCompleted: 2,
      );
      expect(progress.profileId, 'profile.1');
      expect(progress.twisterId, 'twister.1');
      expect(progress.timesCompleted, 2);
    });

    test('a never-completed twister has timesCompleted=0', () {
      final progress = TwisterProgress(
        profileId: 'profile.1',
        twisterId: 'twister.2',
        timesCompleted: 0,
      );
      expect(progress.timesCompleted, 0);
    });
  });

  group('CollectionState (positive)', () {
    test('constructs with exactly the pinned fields', () {
      final state = CollectionState(
        profileId: 'profile.1',
        earnedCollectibles: ['collectible.cat', 'collectible.dog'],
      );
      expect(state.profileId, 'profile.1');
      expect(state.earnedCollectibles, ['collectible.cat', 'collectible.dog']);
    });
  });

  group('CollectionState (edge: empty collection + immutability)', () {
    test('a brand-new profile has an empty collection', () {
      final state = CollectionState(profileId: 'profile.1', earnedCollectibles: const []);
      expect(state.earnedCollectibles, isEmpty);
    });

    test('earnedCollectibles is defensively copied', () {
      final ids = <String>['collectible.cat'];
      final state = CollectionState(profileId: 'profile.1', earnedCollectibles: ids);
      ids.add('collectible.dog');
      expect(state.earnedCollectibles, ['collectible.cat']);
    });
  });
}

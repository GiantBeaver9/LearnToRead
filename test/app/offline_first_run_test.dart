// Offline first-run acceptance at the APP level (PRD §6 "Offline: the app is
// fully functional having never seen the network"; §8 Unit 11 "Fresh install
// in airplane mode: full starter-pack experience end-to-end"; §9 A-9; ticket
// app-shell accept entry 4).
//
// content-delivery's own `offline_e2e_test.dart` proves the repository layer
// offline. This suite proves the same thing one layer up, through the real
// shell: a fresh install (empty database, never-installed packs directory,
// every network seam faked into airplane mode) boots, reaches the map, reads a
// starter story start to finish, and browses the Sound Garden -- with the
// launch catalog check failing silently beside it and changing nothing.
//
// The starter pack here is a REAL on-disk bundle directory read back through
// the real `loadPackFromDirectory`, which is exactly the shape that ships
// inside the binary (A-9).
//
// NOTHING under lib/app/ exists yet: this suite fails to compile/analyze until
// lib/app/{providers,router,app}.dart are written -- the expected red state.
// See shell_integration_test.dart's header for the full pinned provider
// surface; this file additionally pins:
//
//   /// The launch-time catalog check (PRD §8 Unit 11). Fire-and-forget: it is
//   /// kicked off at boot, its failure is silent, and nothing the child can
//   /// see depends on it. Reading it from a test is what proves it ran.
//   final FutureProvider<CatalogFetchResult> launchCatalogCheckProvider;
//
//   /// With no fetcher configured (the default), the check resolves to a
//   /// failure result rather than throwing or hanging.
//   final Provider<CatalogFetcher?> catalogFetcherProvider;
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:learn_to_read/app/app.dart';
import 'package:learn_to_read/app/providers.dart';
import 'package:learn_to_read/app/router.dart';
import 'package:learn_to_read/data/content/catalog_client.dart';
import 'package:learn_to_read/data/content/pack_installer.dart';
import 'package:learn_to_read/data/content/pack_loader.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/pack_manifest.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/domain/phonics/scope_sequence_loader.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/analytics/events.dart';
import 'package:learn_to_read/features/analytics/transport.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/celebration/celebration_controller.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/design/page_curl.dart';
import 'package:learn_to_read/features/listening/contracts/fake_asr_engine.dart';
import 'package:learn_to_read/features/parent/consent_controller.dart';
import 'package:learn_to_read/features/profiles/profile_picker_screen.dart';
import 'package:learn_to_read/features/reading/reading_controller.dart';
import 'package:learn_to_read/features/sound_garden/sound_garden_screen.dart';

// ---------------------------------------------------------------------------
// Fixtures (file-local, per this codebase's convention).
// ---------------------------------------------------------------------------

const String _installId = 'a1b2c3d4-1234-4abc-8def-0123456789ab';

const Map<String, String> _phonemeForLetter = <String, String>{
  'a': 'AE', 'c': 'K', 'e': 'EH', 'h': 'H', 'i': 'IH', 'n': 'N', 'o': 'AA',
  'r': 'R', 's': 'S', 't': 'T', 'u': 'AH', 'w': 'W',
};

const Map<String, AudioRef> _phonemeAudioRefs = <String, AudioRef>{
  'AE': 'audio/phonemes/AE.wav', 'K': 'audio/phonemes/K.wav',
  'EH': 'audio/phonemes/EH.wav', 'H': 'audio/phonemes/H.wav',
  'IH': 'audio/phonemes/IH.wav', 'N': 'audio/phonemes/N.wav',
  'AA': 'audio/phonemes/AA.wav', 'R': 'audio/phonemes/R.wav',
  'S': 'audio/phonemes/S.wav', 'T': 'audio/phonemes/T.wav',
  'AH': 'audio/phonemes/AH.wav', 'W': 'audio/phonemes/W.wav',
};

List<({String graphemes, String phonemeId})> _gpm(String text) => <({
  String graphemes,
  String phonemeId,
})>[
  for (final ch in text.split(''))
    (graphemes: ch, phonemeId: _phonemeForLetter[ch] ?? 'AH'),
];

WordToken _w(String text) => WordToken(
  text: text,
  graphemePhonemeMap: _gpm(text),
  pronunciationAudioRef: 'audio/words/$text.wav',
);

const List<String> _starterStoryWords = <String>['the', 'cat', 'sat'];

Story _story(String id, List<String> words) => Story(
  id: id,
  levelId: 'level.1',
  title: 'Starter $id',
  pages: <Page>[
    Page(
      sentences: <Sentence>[
        Sentence(words: <WordToken>[for (final t in words) _w(t)]),
      ],
    ),
  ],
  riveAnimationRef: 'rive/$id.riv',
  celebrationAudioRef: 'audio/celebration/$id.wav',
  collectibleRef: 'collectible.$id',
  skillsExercised: const <PhonicsSkill>[],
  packId: 'pack.starter',
  contentVersion: '1',
);

final String _phonicsJson = jsonEncode(<String, Object?>{
  'levels': <Object?>[
    <String, Object?>{
      'id': 'level.1',
      'ordinal': 1,
      'format': 'multiSentence',
      'vocabEnabled': false,
      'heartWords': <String>[],
      'skills': <Object?>[
        <String, Object?>{
          'id': 'skill.1',
          'name': 'CVC',
          'sequenceOrder': 1,
          'introducesGraphemes': <String>['a', 'c', 't', 's'],
        },
      ],
    },
  ],
  'stories': <Object?>[
    <String, Object?>{'id': 'story.1', 'levelId': 'level.1'},
    <String, Object?>{'id': 'story.2', 'levelId': 'level.1'},
  ],
});

/// The pack that ships inside the binary (A-9), written to a real directory
/// in exactly the installed-pack shape and read back through the real loader.
///
/// `sat` has its example-word audio on disk; `sit` deliberately does not --
/// the Unit 15 "shows only words it has audio for" filter is a first-run,
/// offline-relevant behavior, so it is exercised here rather than assumed.
StoryPack _starterStoryPack() => StoryPack(
  id: 'pack.starter',
  version: '1.0.0',
  minAppVersion: '1.0.0',
  stories: <Story>[
    _story('story.1', _starterStoryWords),
    _story('story.2', const <String>['we', 'ran']),
  ],
  twisters: const <TongueTwister>[],
  vocabCards: const <VocabCard>[],
  collectibles: <Collectible>[
    for (var i = 1; i <= 2; i++)
      Collectible(
        id: 'collectible.story.$i',
        storyId: 'story.$i',
        riveRef: 'rive/collectibles/$i.riv',
        sceneSlot: '0:${i - 1}',
      ),
  ],
  graphemeSounds: <GraphemeSound>[
    GraphemeSound(
      id: 'grapheme.s',
      grapheme: 's',
      phonemeIds: const <String>['S'],
      introducedAtLevelId: 'level.1',
      exampleWords: const <
        ({String wordText, String pronunciationAudioRef, String minLevelId})
      >[
        (
          wordText: 'sat',
          pronunciationAudioRef: 'audio/words/sat-example.wav',
          minLevelId: 'level.1',
        ),
        (
          wordText: 'sit',
          pronunciationAudioRef: 'audio/words/sit-example.wav',
          minLevelId: 'level.1',
        ),
      ],
    ),
  ],
  assetRefs: const <String>[],
  checksum: '',
);

Profile _profile(String id, String name) => Profile(
  localId: id,
  displayName: name,
  ageBand: AgeBand.fiveToSix,
  currentLevelId: 'level.1',
  micConsent: true,
  cloudAsrConsent: false,
  createdAt: DateTime.utc(2026, 1, 1),
);

List<Hypothesis> _scriptFor(List<String> words) => <Hypothesis>[
  for (final word in words)
    Hypothesis(
      wordHypotheses: <String>[word],
      phoneHypotheses: <String>[for (final e in _gpm(word)) e.phonemeId],
    ),
];

const Duration _kHypothesisGap = Duration(milliseconds: 100);

/// Airplane mode: every catalog fetch fails, exactly as a truly offline device
/// answers. Records the call count so "the check really ran" is observable.
class _AirplaneModeCatalogFetcher implements CatalogFetcher {
  int callCount = 0;

  @override
  Future<String?> fetchCatalogJson() async {
    callCount++;
    return null;
  }
}

/// Reachable network, but the body is junk -- the other silent-failure shape.
class _GarbageCatalogFetcher implements CatalogFetcher {
  int callCount = 0;

  @override
  Future<String?> fetchCatalogJson() async {
    callCount++;
    return 'not json at all {{{';
  }
}

class _NoNetworkTransport implements AnalyticsTransport {
  @override
  Future<TransportResult> send(List<Map<String, Object?>> batch) async =>
      TransportResult.success;
}

Future<void> _pumpFrames(
  WidgetTester tester, {
  int frames = 12,
  Duration step = const Duration(milliseconds: 16),
}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}

// AMENDED 2026-07-29: curl-closes-every-page ruling (PRD §8 Unit 5): the
// final/only page holds at completion with the dog-ear; the child's turn
// (the real corner gesture) is what hands control to the celebration beat.
Future<void> _turnFinalPage(WidgetTester tester) async {
  await _pumpFrames(tester, frames: 2);
  final corner =
      tester.getBottomRight(find.byType(PageCurlCorner)) - const Offset(8, 8);
  await tester.tapAt(corner);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400)); // curl completes
  await tester.pump();
}

void main() {
  late Directory analyticsDir;
  late Directory starterDir;
  late Directory installedDir;
  late LoadedPack starterPack;
  late FakeAudioService audio;
  late _AirplaneModeCatalogFetcher airplaneFetcher;
  late ProviderContainer container;
  late AppDatabase db;

  /// Writes the bundled starter pack to a real directory and reads it back
  /// through the real `loadPackFromDirectory`.
  Future<LoadedPack> writeStarterPack() async {
    final pack = _starterStoryPack();
    File(p.join(starterDir.path, 'manifest.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(pack.toJson()));
    // Only `sat`'s example audio exists on disk.
    final satAudio = File(p.join(starterDir.path, 'audio', 'words', 'sat-example.wav'));
    satAudio.parent.createSync(recursive: true);
    satAudio.writeAsBytesSync(const <int>[0, 1, 2, 3]);
    return loadPackFromDirectory(starterDir);
  }

  Future<void> buildContainer({
    CatalogFetcher? fetcher,
    List<String> script = const <String>[],
  }) async {
    audio = FakeAudioService();
    container = ProviderContainer(
      overrides: <Override>[
        databaseExecutorProvider.overrideWithValue(NativeDatabase.memory()),
        starterPackProvider.overrideWithValue(starterPack),
        packInstallerProvider.overrideWithValue(
          // A never-installed directory: a genuinely fresh install.
          PackInstaller(installedPacksDirectory: installedDir),
        ),
        phonicsContentProvider.overrideWithValue(loadPhonicsContent(_phonicsJson)),
        audioServiceProvider.overrideWithValue(audio),
        asrEngineProvider.overrideWithValue(
          FakeAsrEngine(
            script: _scriptFor(script),
            delayBetweenHypotheses: _kHypothesisGap,
          ),
        ),
        micPermissionServiceProvider.overrideWithValue(
          FakeMicPermissionService(MicPermissionStatus.granted),
        ),
        cloudEngineInUseProvider.overrideWithValue(false),
        phonemeAudioRefsProvider.overrideWithValue(_phonemeAudioRefs),
        installIdProvider.overrideWithValue(_installId),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 1, 1)),
        analyticsTransportProvider.overrideWithValue(_NoNetworkTransport()),
        analyticsStorageDirectoryProvider.overrideWithValue(analyticsDir),
        catalogFetcherProvider.overrideWithValue(fetcher),
        appVersionProvider.overrideWithValue('1.0.0'),
      ],
    );
    db = container.read(appDatabaseProvider);
  }

  Widget appOf(ProviderContainer c) =>
      UncontrolledProviderScope(container: c, child: const LearnToReadApp());

  String locationOf(ProviderContainer c) => c
      .read(appRouterProvider)
      .routerDelegate
      .currentConfiguration
      .uri
      .toString();

  setUp(() async {
    analyticsDir = Directory.systemTemp.createTempSync('offline_first_analytics_');
    starterDir = Directory.systemTemp.createTempSync('offline_first_starter_');
    installedDir = Directory.systemTemp.createTempSync('offline_first_installed_');
    airplaneFetcher = _AirplaneModeCatalogFetcher();
    starterPack = await writeStarterPack();
  });

  tearDown(() {
    container.dispose();
    for (final d in <Directory>[analyticsDir, starterDir, installedDir]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  });

  // =========================================================================
  group('fresh install, airplane mode (accept 4)', () {
    testWidgets(
      'POSITIVE: an empty database boots to the profile picker with no tiles '
      'and no error -- a first run has nothing to restore',
      (tester) async {
        await buildContainer(fetcher: airplaneFetcher);
        await tester.pumpWidget(appOf(container));
        await _pumpFrames(tester);

        expect(tester.takeException(), isNull);
        expect(find.byType(ProfilePickerScreen), findsOneWidget);
        expect(locationOf(container), kRoutePathProfilePicker);
      },
    );

    testWidgets(
      'POSITIVE: the launch catalog check is kicked off exactly once at boot '
      '(PRD §8 Unit 11 "catalog checked in background")',
      (tester) async {
        await buildContainer(fetcher: airplaneFetcher);
        await tester.pumpWidget(appOf(container));
        await _pumpFrames(tester);
        await tester.runAsync(() async {
          await container.read(launchCatalogCheckProvider.future);
        });

        expect(airplaneFetcher.callCount, 1);
      },
    );

    testWidgets(
      'NEGATIVE: offline, the catalog check fails SILENTLY -- it reports '
      'failure with no entries, throws nothing, and blocks nothing',
      (tester) async {
        await buildContainer(fetcher: airplaneFetcher);
        await tester.pumpWidget(appOf(container));
        await _pumpFrames(tester);

        late CatalogFetchResult result;
        await tester.runAsync(() async {
          result = await container.read(launchCatalogCheckProvider.future);
        });

        expect(result.success, isFalse);
        expect(result.entries, isEmpty);
        expect(tester.takeException(), isNull);
        expect(find.byType(ProfilePickerScreen), findsOneWidget);
      },
    );

    testWidgets(
      'EDGE: a reachable-but-malformed catalog is equally silent -- a '
      'half-understood catalog is treated as no catalog',
      (tester) async {
        final garbage = _GarbageCatalogFetcher();
        await buildContainer(fetcher: garbage);
        await tester.pumpWidget(appOf(container));
        await _pumpFrames(tester);

        late CatalogFetchResult result;
        await tester.runAsync(() async {
          result = await container.read(launchCatalogCheckProvider.future);
        });

        expect(garbage.callCount, 1);
        expect(result.success, isFalse);
        expect(result.entries, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'EDGE: with no catalog fetcher configured at all the app still boots and '
      'the check resolves to a failure rather than hanging',
      (tester) async {
        await buildContainer(fetcher: null);
        await tester.pumpWidget(appOf(container));
        await _pumpFrames(tester);

        late CatalogFetchResult result;
        await tester.runAsync(() async {
          result = await container.read(launchCatalogCheckProvider.future);
        });

        expect(result.success, isFalse);
        expect(find.byType(ProfilePickerScreen), findsOneWidget);
      },
    );
  });

  // =========================================================================
  group('the full starter-pack experience, never having seen a network', () {
    testWidgets(
      'POSITIVE: the map is built entirely from the bundled starter pack '
      'directory, with a never-installed packs directory beside it',
      (tester) async {
        await buildContainer(fetcher: airplaneFetcher);
        await db.profilesDao.insertProfile(_profile('profile.ada', 'Ada'));

        await tester.pumpWidget(appOf(container));
        await _pumpFrames(tester);
        await tester.tap(find.byKey(const Key('profile-picker-tile-profile.ada')));
        await _pumpFrames(tester);

        expect(locationOf(container), kRoutePathMap);
        expect(
          find.byKey(const ValueKey('map-node-awake-animation-story.1')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('map-node-awake-animation-story.2')),
          findsOneWidget,
        );

        late List<InstalledPackInfo> installed;
        await tester.runAsync(() async {
          installed = await container.read(packInstallerProvider).installedPacks();
        });
        expect(
          installed,
          isEmpty,
          reason: 'nothing was ever downloaded; the content came from the binary',
        );
      },
    );

    testWidgets(
      'POSITIVE: a starter story reads start to finish offline -- words turn '
      'green, the completion persists, the collectible is granted',
      (tester) async {
        await buildContainer(
          fetcher: airplaneFetcher,
          script: _starterStoryWords,
        );
        await db.profilesDao.insertProfile(_profile('profile.ada', 'Ada'));

        await tester.pumpWidget(appOf(container));
        await _pumpFrames(tester);
        await tester.tap(find.byKey(const Key('profile-picker-tile-profile.ada')));
        await _pumpFrames(tester);
        await tester.tap(find.byKey(const ValueKey('map-node-story-story.1')));
        await _pumpFrames(tester);

        await _pumpFrames(tester, frames: 6, step: _kHypothesisGap);
        for (var i = 0; i < _starterStoryWords.length; i++) {
          expect(
            tester
                .widget<Text>(find.byKey(ValueKey('word-text-$i')))
                .style
                ?.color,
            DesignTokens.wordReadGreen,
          );
        }

        // AMENDED 2026-07-29: curl-closes-every-page ruling (PRD §8 Unit 5).
        await _turnFinalPage(tester);
        await tester.pump(kCelebrationBeat + const Duration(milliseconds: 50));
        await tester.pump(kCelebrationDefaultAnimationDuration);
        await tester.pump(DesignTokens.collectibleFlightDuration);
        await _pumpFrames(tester, frames: 8);

        late CollectionState collection;
        late List<StoryProgress> progress;
        await tester.runAsync(() async {
          collection = await db.collectionDao.getCollectionState('profile.ada');
          progress = await db.storyProgressDao.allForProfile('profile.ada');
        });

        expect(collection.earnedCollectibles, <String>['collectible.story.1']);
        expect(
          progress.firstWhere((e) => e.storyId == 'story.1').status,
          StoryStatus.completed,
        );
        expect(locationOf(container), startsWith(kRoutePathMap));
      },
    );

    testWidgets(
      'POSITIVE: the Sound Garden renders the starter pack\'s grapheme '
      'inventory offline, showing only the example words it has audio for',
      (tester) async {
        await buildContainer(fetcher: airplaneFetcher);
        await db.profilesDao.insertProfile(_profile('profile.ada', 'Ada'));

        await tester.pumpWidget(appOf(container));
        await _pumpFrames(tester);
        await tester.tap(find.byKey(const Key('profile-picker-tile-profile.ada')));
        await _pumpFrames(tester);
        container.read(appRouterProvider).go(kRoutePathSoundGarden);
        await _pumpFrames(tester);

        expect(find.byType(SoundGardenScreen), findsOneWidget);
        expect(find.byKey(const ValueKey('sound-card-grapheme.s')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('example-word-highlight-sat')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('example-word-highlight-sit')),
          findsNothing,
          reason: '"sit" has no locally available audio and must not be offered',
        );
      },
    );

    testWidgets(
      'POSITIVE: nothing the child did offline was lost -- every analytics '
      'event stayed queued locally and is schema-valid',
      (tester) async {
        await buildContainer(
          fetcher: airplaneFetcher,
          script: _starterStoryWords,
        );
        await db.profilesDao.insertProfile(_profile('profile.ada', 'Ada'));

        await tester.pumpWidget(appOf(container));
        await _pumpFrames(tester);
        await tester.tap(find.byKey(const Key('profile-picker-tile-profile.ada')));
        await _pumpFrames(tester);
        await tester.tap(find.byKey(const ValueKey('map-node-story-story.1')));
        await _pumpFrames(tester, frames: 8, step: _kHypothesisGap);

        late List<Map<String, Object?>> events;
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          events = await container.read(eventQueueProvider).pendingEvents();
        });

        expect(events, isNotEmpty);
        expect(
          events.map((e) => e['event']),
          contains(AnalyticsEventName.storyStarted.wireName),
        );
        for (final payload in events) {
          expect(() => validateEventPayload(payload), returnsNormally);
        }
      },
    );
  });

  // =========================================================================
  group('the database executor seam (accept 2: providers.dart owns wiring)', () {
    testWidgets(
      'POSITIVE: AppDatabase is composed over databaseExecutorProvider, so a '
      'test swaps the file-backed executor for an in-memory one and nothing '
      'else changes -- the shell reads and writes through it',
      (tester) async {
        await buildContainer(fetcher: airplaneFetcher);
        await db.profilesDao.insertProfile(_profile('profile.ada', 'Ada'));

        await tester.pumpWidget(appOf(container));
        await _pumpFrames(tester);

        expect(
          find.byKey(const Key('profile-picker-tile-profile.ada')),
          findsOneWidget,
          reason: 'the picker read the profile out of the overridden executor',
        );
        expect(container.read(appDatabaseProvider), same(db));
      },
    );
  });
}

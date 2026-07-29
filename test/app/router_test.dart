// Router / navigation contract for the app shell (PRD §8 Unit 1 "App shell:
// Flutter, Riverpod, go_router... child-facing screens are Home/progress
// map, Reading, Collection, Sound Garden; all child-facing navigation is
// icon + voice prompt", §9 A-2; ticket app-shell accept entries 1 and 5).
//
// NOTHING under lib/app/ exists yet -- lib/app/router.dart,
// lib/app/providers.dart and lib/app/app.dart are this ticket's files, so
// this suite fails to compile/analyze until they are written. That failure
// IS the expected red state, and the shapes exercised below are what it
// pins.
//
// ---------------------------------------------------------------------------
// Pinned API surface this suite requires
// ---------------------------------------------------------------------------
//
// lib/app/router.dart
//
//   // Paths (go_router `path`s) -- exact strings.
//   const String kRoutePathProfilePicker = '/';
//   const String kRoutePathMap           = '/map';
//   const String kRoutePathReading       = '/reading/:storyId';
//   const String kRoutePathCollection    = '/collection';
//   const String kRoutePathSoundGarden   = '/garden';
//   const String kRoutePathTwister       = '/twister/:twisterId';
//   const String kRoutePathParentCorner  = '/parent';
//
//   // Names (go_router `name`s) -- exact strings, all distinct.
//   const String kRouteNameProfilePicker = 'profiles';
//   const String kRouteNameMap           = 'map';
//   const String kRouteNameReading       = 'reading';
//   const String kRouteNameCollection    = 'collection';
//   const String kRouteNameSoundGarden   = 'soundGarden';
//   const String kRouteNameTwister       = 'twister';
//   const String kRouteNameParentCorner  = 'parentCorner';
//
//   /// The child-facing destinations reachable from the shell's own nav
//   /// chrome, in render order. Reading is deliberately NOT here: a story is
//   /// entered by tapping its map node, never by a nav tab.
//   const List<String> kChildNavDestinationRouteNames;
//
//   /// Owner-recorded voice-prompt refs, keyed by route name. The refs are
//   /// owner content (PRD notes: "Voice-prompt recordings are owner content
//   /// -- refs only"); what is pinned here is that every navigable
//   /// destination HAS one, i.e. the audio hook exists.
//   const Map<String, AudioRef> kNavVoicePromptRefs;
//
//   /// The composed router. Redirect rule: every route except
//   /// [kRoutePathProfilePicker] and [kRoutePathParentCorner] requires an
//   /// active profile; without one it redirects to the picker. The parent
//   /// corner is exempt because on a fresh install it is the only way to
//   /// create the first profile.
//   final Provider<GoRouter> appRouterProvider;
//
// lib/app/providers.dart (the composition seams -- see the header of
// shell_integration_test.dart for the full list; this file uses only these)
//
//   final Provider<QueryExecutor>      databaseExecutorProvider;
//   final Provider<AppDatabase>        appDatabaseProvider;
//   final Provider<LoadedPack>         starterPackProvider;
//   final Provider<PackInstaller>      packInstallerProvider;
//   final Provider<ContentRepository>  contentRepositoryProvider;
//   final Provider<PhonicsContent>     phonicsContentProvider;
//   final Provider<AudioService>       audioServiceProvider;
//   final Provider<AsrEngine>          asrEngineProvider;
//   final Provider<MicPermissionService> micPermissionServiceProvider;
//   final Provider<Map<String, AudioRef>> phonemeAudioRefsProvider;
//   final Provider<String>             installIdProvider;
//   final Provider<Clock>              clockProvider;
//   final Provider<AnalyticsTransport> analyticsTransportProvider;
//   final Provider<Directory>          analyticsStorageDirectoryProvider;
//   final Provider<CatalogFetcher?>    catalogFetcherProvider;
//   final Provider<String>             appVersionProvider;
//   final NotifierProvider<ActiveProfileController, ActiveProfile?>
//       activeProfileProvider;
//   class ActiveProfile { final Profile profile; final int ordinal; }
//   class ActiveProfileController extends Notifier<ActiveProfile?> {
//     void select(Profile profile, int ordinal);   // also starts the session
//     void clear();                                // also ends the session
//   }
//
// lib/app/app.dart
//   class LearnToReadApp extends ConsumerWidget;   // MaterialApp.router
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:learn_to_read/app/app.dart';
import 'package:learn_to_read/app/providers.dart';
import 'package:learn_to_read/app/router.dart';
import 'package:learn_to_read/data/content/pack_installer.dart';
import 'package:learn_to_read/data/content/pack_loader.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/pack_manifest.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/domain/phonics/scope_sequence_loader.dart';
import 'package:learn_to_read/features/analytics/transport.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/collection/collection_screen.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/contracts/fake_asr_engine.dart';
import 'package:learn_to_read/features/map/progress_map_screen.dart';
import 'package:learn_to_read/features/parent/consent_controller.dart';
import 'package:learn_to_read/features/parent/parent_corner_screen.dart';
import 'package:learn_to_read/features/parent/parental_gate.dart';
import 'package:learn_to_read/features/profiles/profile_picker_screen.dart';
import 'package:learn_to_read/features/reading/reading_screen.dart';
import 'package:learn_to_read/features/sound_garden/sound_garden_screen.dart';

// ---------------------------------------------------------------------------
// Fixtures (file-local, per this codebase's convention).
// ---------------------------------------------------------------------------

const String _installId = 'a1b2c3d4-1234-4abc-8def-0123456789ab';

const Map<String, String> _phonemeForLetter = <String, String>{
  'a': 'AE', 'b': 'B', 'c': 'K', 'd': 'D', 'e': 'EH', 'f': 'F', 'g': 'G',
  'h': 'H', 'i': 'IH', 'j': 'JH', 'k': 'K', 'l': 'L', 'm': 'M', 'n': 'N',
  'o': 'AA', 'p': 'P', 'r': 'R', 's': 'S', 't': 'T', 'u': 'AH', 'w': 'W',
  'y': 'Y',
};

List<({String graphemes, String phonemeId})> _gpm(String text) => <({
  String graphemes,
  String phonemeId,
})>[
  for (final ch in text.split(''))
    (graphemes: ch, phonemeId: _phonemeForLetter[ch] ?? 'AH'),
];

WordToken _w(String text, {String? vocabCardId}) => WordToken(
  text: text,
  graphemePhonemeMap: _gpm(text),
  pronunciationAudioRef: 'audio/words/$text.wav',
  vocabCardId: vocabCardId,
);

Story _story(String id, String levelId, List<String> words) => Story(
  id: id,
  levelId: levelId,
  title: 'Story $id',
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

/// Four stories at one level plus one twister -- enough for the rolling
/// window (3 awake, 1 asleep) and a booster node.
final String _phonicsJson = jsonEncode(<String, Object?>{
  'levels': <Object?>[
    <String, Object?>{
      'id': 'level.1',
      'ordinal': 1,
      // multiSentence (not sentence) so `narrationEnabled` defaults false:
      // listen-first is the reading-screen unit's own pinned behavior and is
      // deliberately out of the way of these routing assertions.
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
    <String, Object?>{'id': 'story.3', 'levelId': 'level.1'},
    <String, Object?>{'id': 'story.4', 'levelId': 'level.1'},
  ],
});

StoryPack _starterStoryPack() => StoryPack(
  id: 'pack.starter',
  version: '1.0.0',
  minAppVersion: '1.0.0',
  stories: <Story>[
    _story('story.1', 'level.1', const <String>['the', 'cat', 'sat']),
    _story('story.2', 'level.1', const <String>['a', 'rat', 'ran']),
    _story('story.3', 'level.1', const <String>['we', 'sat']),
    _story('story.4', 'level.1', const <String>['it', 'is', 'hot']),
  ],
  twisters: <TongueTwister>[
    TongueTwister(
      id: 'twister.1',
      levelId: 'level.1',
      words: <WordToken>[_w('sam'), _w('sat')],
      targetPhonemeId: 'S',
      narrationAudioRef: 'audio/twisters/twister.1.wav',
      packId: 'pack.starter',
    ),
  ],
  vocabCards: const <VocabCard>[],
  collectibles: <Collectible>[
    for (var i = 1; i <= 4; i++)
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
      >[],
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

class _NoNetworkTransport implements AnalyticsTransport {
  @override
  Future<TransportResult> send(List<Map<String, Object?>> batch) async =>
      TransportResult.success;
}

/// Pumps a bounded number of frames.
///
/// `pumpAndSettle` is unusable anywhere the progress map is on screen: an
/// awake `MapNode` wraps itself in a forever-repeating pulse animation, so
/// the tree never settles. Every wait in this suite is therefore a bounded
/// frame pump.
Future<void> _pumpFrames(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

class _Harness {
  late final Directory analyticsDir;
  late final Directory starterDir;
  late final Directory installedDir;
  late final ProviderContainer container;
  late final AppDatabase db;
  late final FakeAudioService audio;

  Future<void> setUp({bool seedProfiles = true}) async {
    analyticsDir = Directory.systemTemp.createTempSync('router_test_analytics_');
    starterDir = Directory.systemTemp.createTempSync('router_test_starter_');
    installedDir = Directory.systemTemp.createTempSync('router_test_installed_');
    audio = FakeAudioService();

    container = ProviderContainer(
      overrides: <Override>[
        databaseExecutorProvider.overrideWithValue(NativeDatabase.memory()),
        starterPackProvider.overrideWithValue(
          LoadedPack(pack: _starterStoryPack(), directory: starterDir),
        ),
        packInstallerProvider.overrideWithValue(
          PackInstaller(installedPacksDirectory: installedDir),
        ),
        phonicsContentProvider.overrideWithValue(
          loadPhonicsContent(_phonicsJson),
        ),
        audioServiceProvider.overrideWithValue(audio),
        asrEngineProvider.overrideWithValue(
          FakeAsrEngine(script: const <Hypothesis>[]),
        ),
        micPermissionServiceProvider.overrideWithValue(
          FakeMicPermissionService(MicPermissionStatus.granted),
        ),
        phonemeAudioRefsProvider.overrideWithValue(
          const <String, AudioRef>{'S': 'audio/phonemes/S.wav'},
        ),
        installIdProvider.overrideWithValue(_installId),
        clockProvider.overrideWithValue(() => DateTime.utc(2026, 1, 1)),
        analyticsTransportProvider.overrideWithValue(_NoNetworkTransport()),
        analyticsStorageDirectoryProvider.overrideWithValue(analyticsDir),
        catalogFetcherProvider.overrideWithValue(null),
        appVersionProvider.overrideWithValue('1.0.0'),
      ],
    );

    db = container.read(appDatabaseProvider);
    if (seedProfiles) {
      await db.profilesDao.insertProfile(_profile('profile.ada', 'Ada'));
      await db.profilesDao.insertProfile(_profile('profile.bo', 'Bo'));
    }
  }

  void tearDown() {
    container.dispose();
    for (final d in <Directory>[analyticsDir, starterDir, installedDir]) {
      if (d.existsSync()) d.deleteSync(recursive: true);
    }
  }

  GoRouter get router => container.read(appRouterProvider);

  String get location =>
      router.routerDelegate.currentConfiguration.uri.toString();

  Widget get app =>
      UncontrolledProviderScope(container: container, child: const LearnToReadApp());

  Future<void> selectProfile(WidgetTester tester, String localId) async {
    await tester.tap(find.byKey(Key('profile-picker-tile-$localId')));
    await _pumpFrames(tester);
  }

  Future<void> selectFirstProfile(WidgetTester tester) =>
      selectProfile(tester, 'profile.ada');
}

void main() {
  late _Harness h;

  setUp(() async {
    h = _Harness();
    await h.setUp();
  });

  tearDown(() => h.tearDown());

  // -------------------------------------------------------------------------
  group('route table (accept 1)', () {
    test('POSITIVE: the pinned path constants are exactly these strings', () {
      expect(kRoutePathProfilePicker, '/');
      expect(kRoutePathMap, '/map');
      expect(kRoutePathReading, '/reading/:storyId');
      expect(kRoutePathCollection, '/collection');
      expect(kRoutePathSoundGarden, '/garden');
      expect(kRoutePathTwister, '/twister/:twisterId');
      expect(kRoutePathParentCorner, '/parent');
    });

    test('POSITIVE: every route name is distinct (go_router requires it)', () {
      const names = <String>[
        kRouteNameProfilePicker,
        kRouteNameMap,
        kRouteNameReading,
        kRouteNameCollection,
        kRouteNameSoundGarden,
        kRouteNameTwister,
        kRouteNameParentCorner,
      ];
      expect(names.toSet(), hasLength(names.length));
    });

    // AMENDED 2026-07-28: Unit 16 flashcards ruling (PRD §8) — the ratified
    // flashcards deck is the eighth pinned route.
    test(
      'POSITIVE: the shell registers exactly the eight pinned routes -- the '
      'five child-facing screens (map/reading/collection/garden/flashcards), '
      'the twister booster, the picker, and the gated parent corner',
      () {
        final configured = h.router.configuration.routes
            .whereType<GoRoute>()
            .map((r) => r.path)
            .toSet();
        expect(configured, <String>{
          kRoutePathProfilePicker,
          kRoutePathMap,
          kRoutePathReading,
          kRoutePathCollection,
          kRoutePathSoundGarden,
          kRoutePathTwister,
          kRoutePathFlashcards,
          kRoutePathParentCorner,
        });
      },
    );
  });

  // -------------------------------------------------------------------------
  group('redirect: no profile selected -> the picker (accept 1)', () {
    testWidgets('POSITIVE: launch lands on the profile picker', (tester) async {
      await tester.pumpWidget(h.app);
      await _pumpFrames(tester);

      expect(find.byType(ProfilePickerScreen), findsOneWidget);
      expect(h.location, kRoutePathProfilePicker);
    });

    testWidgets('POSITIVE: selecting a profile lands on the progress map', (
      tester,
    ) async {
      await tester.pumpWidget(h.app);
      await _pumpFrames(tester);
      await h.selectFirstProfile(tester);

      expect(h.location, kRoutePathMap);
      expect(find.byType(ProgressMapScreen), findsOneWidget);
      expect(find.byType(ProfilePickerScreen), findsNothing);
    });

    testWidgets('NEGATIVE: /map without a profile redirects to the picker', (
      tester,
    ) async {
      await tester.pumpWidget(h.app);
      await _pumpFrames(tester);

      h.router.go(kRoutePathMap);
      await _pumpFrames(tester);

      expect(h.location, kRoutePathProfilePicker);
      expect(find.byType(ProgressMapScreen), findsNothing);
    });

    testWidgets('NEGATIVE: /collection without a profile redirects', (
      tester,
    ) async {
      await tester.pumpWidget(h.app);
      await _pumpFrames(tester);

      h.router.go(kRoutePathCollection);
      await _pumpFrames(tester);

      expect(h.location, kRoutePathProfilePicker);
      expect(find.byType(CollectionScreen), findsNothing);
    });

    testWidgets('NEGATIVE: /garden without a profile redirects', (tester) async {
      await tester.pumpWidget(h.app);
      await _pumpFrames(tester);

      h.router.go(kRoutePathSoundGarden);
      await _pumpFrames(tester);

      expect(h.location, kRoutePathProfilePicker);
      expect(find.byType(SoundGardenScreen), findsNothing);
    });

    testWidgets(
      'NEGATIVE: a deep link straight into a reading route without a profile '
      'redirects rather than opening a microphone session for nobody',
      (tester) async {
        await tester.pumpWidget(h.app);
        await _pumpFrames(tester);

        h.router.go('/reading/story.1');
        await _pumpFrames(tester);

        expect(h.location, kRoutePathProfilePicker);
        expect(find.byType(ReadingScreen), findsNothing);
      },
    );

    testWidgets(
      'EDGE: the parent corner is the ONE route exempt from the redirect -- on '
      'a fresh install it is the only way to create the first profile',
      (tester) async {
        await tester.pumpWidget(h.app);
        await _pumpFrames(tester);

        h.router.go(kRoutePathParentCorner);
        await tester.pumpAndSettle();

        expect(h.location, kRoutePathParentCorner);
        expect(find.byType(ParentalGate), findsOneWidget);
      },
    );

    testWidgets('EDGE: an unknown path falls back to the picker, never a crash', (
      tester,
    ) async {
      await tester.pumpWidget(h.app);
      await _pumpFrames(tester);

      h.router.go('/no-such-route');
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(ProfilePickerScreen), findsOneWidget);
    });

    testWidgets(
      'POSITIVE: clearing the active profile pulls the app back to the picker '
      'from wherever it was (profile switch / session end)',
      (tester) async {
        await tester.pumpWidget(h.app);
        await _pumpFrames(tester);
        await h.selectFirstProfile(tester);
        expect(h.location, kRoutePathMap);

        h.container.read(activeProfileProvider.notifier).clear();
        await _pumpFrames(tester);

        expect(h.location, kRoutePathProfilePicker);
        expect(find.byType(ProfilePickerScreen), findsOneWidget);
      },
    );

    testWidgets('EDGE: an empty profile list still renders the picker, not a blank', (
      tester,
    ) async {
      h.tearDown();
      h = _Harness();
      await h.setUp(seedProfiles: false);

      await tester.pumpWidget(h.app);
      await _pumpFrames(tester);

      expect(tester.takeException(), isNull);
      expect(find.byType(ProfilePickerScreen), findsOneWidget);
    });

    // ADDED 2026-07-29: first-run dead-end regression (found on-device: a
    // fresh install rendered blank parchment with no reachable parent
    // corner — the only route that can create the first profile).
    testWidgets(
        'POSITIVE: fresh install shows the parent invitation and it opens '
        'the parent corner', (tester) async {
      h.tearDown();
      h = _Harness();
      await h.setUp(seedProfiles: false);

      await tester.pumpWidget(h.app);
      await _pumpFrames(tester);

      final invitation =
          find.byKey(const ValueKey<String>('picker-first-run-invitation'));
      expect(invitation, findsOneWidget);
      await tester.tap(invitation);
      await _pumpFrames(tester);
      expect(find.byType(ParentCornerScreen), findsOneWidget);
    });

    testWidgets(
        'POSITIVE: the discreet corner lock reaches the parent corner even '
        'with profiles present, and the invitation is gone', (tester) async {
      await tester.pumpWidget(h.app);
      await _pumpFrames(tester);

      expect(
        find.byKey(const ValueKey<String>('picker-first-run-invitation')),
        findsNothing,
      );
      final lock =
          find.byKey(const ValueKey<String>('picker-parent-corner-button'));
      expect(lock, findsOneWidget);
      await tester.tap(lock);
      await _pumpFrames(tester);
      expect(find.byType(ParentCornerScreen), findsOneWidget);
    });

    // ADDED 2026-07-29: second on-device dead end — the corner is reached
    // via context.go (no history), so without an on-screen exit the Android
    // back button closed the whole app.
    testWidgets(
        'POSITIVE: Done in the parent corner returns to the profile picker',
        (tester) async {
      await tester.pumpWidget(h.app);
      await _pumpFrames(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('picker-parent-corner-button')),
      );
      await _pumpFrames(tester);
      expect(find.byType(ParentCornerScreen), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('parent-corner-done-button')),
      );
      await _pumpFrames(tester);
      expect(find.byType(ProfilePickerScreen), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  group('icon + voice-prompt navigation, no reading required (accept 5)', () {
    // AMENDED 2026-07-28: Unit 16 flashcards ruling (PRD §8) — the ratified
    // fourth child destination joins the nav alongside map/collection/garden.
    test(
      'POSITIVE: the child nav destinations are exactly map, collection, '
      'sound garden and flashcards -- Reading is entered from a map node, '
      'never a nav tab',
      () {
        expect(kChildNavDestinationRouteNames, <String>[
          kRouteNameMap,
          kRouteNameCollection,
          kRouteNameSoundGarden,
          kRouteNameFlashcards,
        ]);
      },
    );

    test(
      'POSITIVE: every navigable destination has a voice-prompt audio ref '
      '(the recordings are owner content; the hook is what is pinned)',
      () {
        for (final name in <String>[
          ...kChildNavDestinationRouteNames,
          kRouteNameParentCorner,
        ]) {
          expect(
            kNavVoicePromptRefs[name],
            isNotNull,
            reason: '$name has no voice-prompt ref',
          );
          expect(kNavVoicePromptRefs[name], isNotEmpty);
        }
      },
    );

    testWidgets(
      'POSITIVE: each nav affordance is icon-only -- an Icon and no Text '
      'descendant, so nothing about navigating requires reading',
      (tester) async {
        await tester.pumpWidget(h.app);
        await _pumpFrames(tester);
        await h.selectFirstProfile(tester);

        for (final name in kChildNavDestinationRouteNames) {
          final destination = find.byKey(ValueKey<String>('nav-destination-$name'));
          expect(destination, findsOneWidget, reason: 'missing nav for $name');
          expect(
            find.descendant(of: destination, matching: find.byType(Icon)),
            findsWidgets,
            reason: '$name nav affordance must carry an icon',
          );
          expect(
            find.descendant(of: destination, matching: find.byType(Text)),
            findsNothing,
            reason: '$name nav affordance must not require reading',
          );
        }
      },
    );

    testWidgets(
      'POSITIVE: tapping a nav destination plays that destination\'s '
      'voice-prompt ref (the audio hook is really wired, not decorative)',
      (tester) async {
        await tester.pumpWidget(h.app);
        await _pumpFrames(tester);
        await h.selectFirstProfile(tester);

        await tester.tap(
          find.byKey(ValueKey<String>('nav-destination-$kRouteNameCollection')),
        );
        await _pumpFrames(tester);

        final played = h.audio.callLog
            .whereType<PlayLogEntry>()
            .map((e) => e.ref)
            .toList();
        expect(played, contains(kNavVoicePromptRefs[kRouteNameCollection]));
      },
    );

    testWidgets('POSITIVE: the collection destination navigates to /collection', (
      tester,
    ) async {
      await tester.pumpWidget(h.app);
      await _pumpFrames(tester);
      await h.selectFirstProfile(tester);

      await tester.tap(
        find.byKey(ValueKey<String>('nav-destination-$kRouteNameCollection')),
      );
      await _pumpFrames(tester);

      expect(h.location, kRoutePathCollection);
      expect(find.byType(CollectionScreen), findsOneWidget);
    });

    testWidgets('POSITIVE: the sound-garden destination navigates to /garden', (
      tester,
    ) async {
      await tester.pumpWidget(h.app);
      await _pumpFrames(tester);
      await h.selectFirstProfile(tester);

      await tester.tap(
        find.byKey(ValueKey<String>('nav-destination-$kRouteNameSoundGarden')),
      );
      await _pumpFrames(tester);

      expect(h.location, kRoutePathSoundGarden);
      expect(find.byType(SoundGardenScreen), findsOneWidget);
    });

    testWidgets('POSITIVE: the map destination navigates home from anywhere', (
      tester,
    ) async {
      await tester.pumpWidget(h.app);
      await _pumpFrames(tester);
      await h.selectFirstProfile(tester);

      h.router.go(kRoutePathCollection);
      await _pumpFrames(tester);
      await tester.tap(
        find.byKey(ValueKey<String>('nav-destination-$kRouteNameMap')),
      );
      await _pumpFrames(tester);

      expect(h.location, kRoutePathMap);
      expect(find.byType(ProgressMapScreen), findsOneWidget);
    });

    testWidgets(
      'POSITIVE: navigation to Reading exists and is icon-based -- tapping an '
      'awake story node on the map opens the reading route',
      (tester) async {
        await tester.pumpWidget(h.app);
        await _pumpFrames(tester);
        await h.selectFirstProfile(tester);

        await tester.tap(find.byKey(const ValueKey('map-node-story-story.1')));
        await _pumpFrames(tester);

        expect(h.location, '/reading/story.1');
        expect(find.byType(ReadingScreen), findsOneWidget);
      },
    );

    testWidgets(
      'POSITIVE: the parent-corner affordance is present on the child shell '
      'and lands on the gate, never on the corner contents',
      (tester) async {
        await tester.pumpWidget(h.app);
        await _pumpFrames(tester);
        await h.selectFirstProfile(tester);

        await tester.tap(
          find.byKey(
            ValueKey<String>('nav-destination-$kRouteNameParentCorner'),
          ),
        );
        await tester.pumpAndSettle();

        expect(h.location, kRoutePathParentCorner);
        expect(find.byType(ParentalGate), findsOneWidget);
      },
    );

    testWidgets(
      'NEGATIVE: the reading route carries no nav chrome -- a child mid-story '
      'cannot be one stray tap away from leaving the story',
      (tester) async {
        await tester.pumpWidget(h.app);
        await _pumpFrames(tester);
        await h.selectFirstProfile(tester);

        await tester.tap(find.byKey(const ValueKey('map-node-story-story.1')));
        await _pumpFrames(tester);

        for (final name in kChildNavDestinationRouteNames) {
          expect(
            find.byKey(ValueKey<String>('nav-destination-$name')),
            findsNothing,
            reason: 'the reading screen must not host the $name nav tab',
          );
        }
      },
    );

    testWidgets(
      'EDGE: the picker itself carries no child nav chrome -- there is no '
      'profile yet, so there is nowhere for it to navigate',
      (tester) async {
        await tester.pumpWidget(h.app);
        await _pumpFrames(tester);

        for (final name in kChildNavDestinationRouteNames) {
          expect(
            find.byKey(ValueKey<String>('nav-destination-$name')),
            findsNothing,
          );
        }
      },
    );
  });
}

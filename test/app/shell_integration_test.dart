// Whole-app integration for the composition shell (PRD §8 Unit 1 shell half,
// §8 Unit 12 session wiring, §8 Unit 15 fourth destination, §9 A-2; ticket
// app-shell accept entries 1, 2, 3 and 5).
//
// This is the integration ticket: every collaborator below is the REAL merged
// unit -- the real `WordMatcher`, the real `ReadingTracker`, the real
// `WordStateMachine`, the real `StuckWordController`, the real
// `VocabCardHost`, the real `CelebrationController`, the real
// `TwisterController`, the real `SoundGardenScreen`, the real `ParentalGate`,
// a real in-memory Drift `AppDatabase` and a real `AnalyticsClient`/
// `EventQueue`. Exactly ONE thing is faked in the reading loop -- the
// `AsrEngine`, injected through the provider override the ticket's validator
// note pins as this unit's responsibility -- plus the audio backend and the
// analytics transport, neither of which can exist headlessly.
//
// NOTHING under lib/app/ exists yet: this suite fails to compile/analyze
// until lib/app/{providers,router,app}.dart are written, which is the
// expected red state.
//
// ---------------------------------------------------------------------------
// Pinned API surface: lib/app/providers.dart
// ---------------------------------------------------------------------------
//
//   // --- composition seams. Every one is overridable; main() supplies the
//   // production value (file-backed executor, path_provider directories,
//   // just_audio service, platform ASR engine, HTTPS transport).
//   final Provider<QueryExecutor>          databaseExecutorProvider;
//   final Provider<AppDatabase>            appDatabaseProvider;   // over the executor
//   final Provider<LoadedPack>             starterPackProvider;
//   final Provider<PackInstaller>          packInstallerProvider;
//   final Provider<ContentRepository>      contentRepositoryProvider;
//   final Provider<PhonicsContent>         phonicsContentProvider;
//   final Provider<AudioService>           audioServiceProvider;
//   final Provider<Map<String, AudioRef>>  phonemeAudioRefsProvider;
//
//   /// THE ASR ENGINE SELECTION SEAM (ticket validator note): swapping the
//   /// engine -- platform on-device (A-10), a metered cloud engine, or a
//   /// scripted fake -- is a one-line override of this provider and nothing
//   /// else. Consent gating sits ABOVE it: with `micConsent == false` the
//   /// shell hands `micConsent: false` to `ReadingTracker`, which never calls
//   /// `engine.start` at all (tap-only).
//   final Provider<AsrEngine>              asrEngineProvider;
//   final Provider<MicPermissionService>   micPermissionServiceProvider;
//   final Provider<bool>                   cloudEngineInUseProvider;
//
//   final Provider<String>                 installIdProvider;   // per-install UUID
//   final Provider<Clock>                  clockProvider;
//   final Provider<AnalyticsTransport>     analyticsTransportProvider;
//   final Provider<Directory>              analyticsStorageDirectoryProvider;
//   final Provider<EventQueue>             eventQueueProvider;
//   final Provider<AnalyticsClient>        analyticsClientProvider;
//   final Provider<SessionTracker>         sessionTrackerProvider;
//
//   final Provider<CatalogFetcher?>        catalogFetcherProvider;
//   final Provider<String>                 appVersionProvider;
//   final FutureProvider<CatalogFetchResult> launchCatalogCheckProvider;
//
//   class ActiveProfile { const ActiveProfile({required this.profile,
//                                              required this.ordinal});
//     final Profile profile; final int ordinal; }
//
//   /// Selecting a profile is what starts a session (§8 Unit 12) and what
//   /// unlocks every child-facing route (see router_test.dart).
//   class ActiveProfileController extends Notifier<ActiveProfile?> {
//     void select(Profile profile, int ordinal);
//     void clear();
//   }
//   final NotifierProvider<ActiveProfileController, ActiveProfile?>
//       activeProfileProvider;
//
// ---------------------------------------------------------------------------
// Pinned widget-key vocabulary this ticket owns (the celebration VIEW that
// composes Unit 8's controller; the controller itself is merged and unchanged)
// ---------------------------------------------------------------------------
//
//   ValueKey('celebration-view')         present exactly while the
//                                        post-completion sequence is running
//   ValueKey('celebration-skip-button')  the skip affordance; wired to
//                                        `CelebrationController.skip()`
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
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/pack_manifest.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/domain/phonics/scope_sequence_loader.dart';
import 'package:learn_to_read/domain/tuning.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/analytics/events.dart';
import 'package:learn_to_read/features/analytics/session_tracker.dart';
import 'package:learn_to_read/features/analytics/transport.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/celebration/celebration_controller.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/contracts/fake_asr_engine.dart';
import 'package:learn_to_read/features/parent/consent_controller.dart';
import 'package:learn_to_read/features/parent/parental_gate.dart';
import 'package:learn_to_read/features/profiles/profile_picker_screen.dart';
import 'package:learn_to_read/features/reading/reading_controller.dart';
import 'package:learn_to_read/features/reading/reading_screen.dart';
import 'package:learn_to_read/features/sound_garden/sound_garden_screen.dart';
import 'package:learn_to_read/features/twister/twister_screen.dart';
import 'package:learn_to_read/features/vocab/vocab_card_opener.dart';

// ---------------------------------------------------------------------------
// Fixtures (file-local, per this codebase's convention).
// ---------------------------------------------------------------------------

const String _installId = 'a1b2c3d4-1234-4abc-8def-0123456789ab';

/// Wide enough for the real `ParentalGate`'s two-opposite-corners hold.
const Size _kGateScreenSize = Size(1080, 1920);

const Map<String, String> _phonemeForLetter = <String, String>{
  'a': 'AE', 'b': 'B', 'c': 'K', 'd': 'D', 'e': 'EH', 'f': 'F', 'g': 'G',
  'h': 'H', 'i': 'IH', 'j': 'JH', 'k': 'K', 'l': 'L', 'm': 'M', 'n': 'N',
  'o': 'AA', 'p': 'P', 'r': 'R', 's': 'S', 't': 'T', 'u': 'AH', 'w': 'W',
  'y': 'Y',
};

const Map<String, AudioRef> _phonemeAudioRefs = <String, AudioRef>{
  'AE': 'audio/phonemes/AE.wav', 'B': 'audio/phonemes/B.wav',
  'D': 'audio/phonemes/D.wav', 'EH': 'audio/phonemes/EH.wav',
  'F': 'audio/phonemes/F.wav', 'G': 'audio/phonemes/G.wav',
  'H': 'audio/phonemes/H.wav', 'IH': 'audio/phonemes/IH.wav',
  'JH': 'audio/phonemes/JH.wav', 'K': 'audio/phonemes/K.wav',
  'L': 'audio/phonemes/L.wav', 'M': 'audio/phonemes/M.wav',
  'N': 'audio/phonemes/N.wav', 'AA': 'audio/phonemes/AA.wav',
  'P': 'audio/phonemes/P.wav', 'R': 'audio/phonemes/R.wav',
  'S': 'audio/phonemes/S.wav', 'T': 'audio/phonemes/T.wav',
  'AH': 'audio/phonemes/AH.wav', 'W': 'audio/phonemes/W.wav',
  'Y': 'audio/phonemes/Y.wav',
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

Story _story(
  String id,
  String levelId,
  List<WordToken> words, {
  String? narrationAudioRef,
}) => Story(
  id: id,
  levelId: levelId,
  title: 'Story $id',
  pages: <Page>[
    Page(
      sentences: <Sentence>[
        Sentence(words: words, narrationAudioRef: narrationAudioRef),
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

/// story.1 "the cat sat" | story.2 "a rat ran" | story.3 "we sat"
/// | story.4 "it is hot" (asleep: outside the rolling window of 3)
/// | story.5 at the vocab-enabled paragraph level, carrying one blue word.
const List<String> _story1Words = <String>['the', 'cat', 'sat'];

final String _phonicsJson = jsonEncode(<String, Object?>{
  'levels': <Object?>[
    <String, Object?>{
      'id': 'level.1',
      'ordinal': 1,
      // multiSentence, not sentence: `narrationEnabled` therefore defaults
      // false, so listen-first gating (the reading-screen unit's own pinned
      // behavior) does not sit between these assertions and the tracker.
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
    <String, Object?>{
      'id': 'level.2',
      'ordinal': 2,
      'format': 'paragraph',
      'vocabEnabled': true,
      'heartWords': <String>[],
      'skills': <Object?>[
        <String, Object?>{
          'id': 'skill.2',
          'name': 'vowel teams',
          'sequenceOrder': 2,
          'introducesGraphemes': <String>['ea'],
        },
      ],
    },
  ],
  'stories': <Object?>[
    <String, Object?>{'id': 'story.1', 'levelId': 'level.1'},
    <String, Object?>{'id': 'story.2', 'levelId': 'level.1'},
    <String, Object?>{'id': 'story.3', 'levelId': 'level.1'},
    <String, Object?>{'id': 'story.4', 'levelId': 'level.1'},
    <String, Object?>{'id': 'story.5', 'levelId': 'level.2'},
  ],
});

StoryPack _starterStoryPack() => StoryPack(
  id: 'pack.starter',
  version: '1.0.0',
  minAppVersion: '1.0.0',
  stories: <Story>[
    _story('story.1', 'level.1', <WordToken>[for (final t in _story1Words) _w(t)]),
    _story('story.2', 'level.1', <WordToken>[_w('a'), _w('rat'), _w('ran')]),
    _story('story.3', 'level.1', <WordToken>[_w('we'), _w('sat')]),
    _story('story.4', 'level.1', <WordToken>[_w('it'), _w('is'), _w('hot')]),
    _story('story.5', 'level.2', <WordToken>[
      _w('the'),
      _w('otter', vocabCardId: 'vocab.otter'),
      _w('sat'),
    ]),
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
  vocabCards: <VocabCard>[
    VocabCard(
      id: 'vocab.otter',
      word: 'otter',
      definitionText: 'A furry animal that swims in rivers.',
      definitionAudioRef: 'audio/vocab/otter.wav',
    ),
  ],
  collectibles: <Collectible>[
    for (var i = 1; i <= 5; i++)
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
    GraphemeSound(
      id: 'grapheme.ea',
      grapheme: 'ea',
      phonemeIds: const <String>['EH'],
      introducedAtLevelId: 'level.2',
      exampleWords: const <
        ({String wordText, String pronunciationAudioRef, String minLevelId})
      >[],
    ),
  ],
  assetRefs: const <String>[],
  checksum: '',
);

Profile _profile(
  String id,
  String name, {
  bool micConsent = true,
  String levelId = 'level.1',
}) => Profile(
  localId: id,
  displayName: name,
  ageBand: AgeBand.fiveToSix,
  currentLevelId: levelId,
  micConsent: micConsent,
  cloudAsrConsent: false,
  createdAt: DateTime.utc(2026, 1, 1),
);

/// A script that reads [words] aloud, one finalized hypothesis per word.
///
/// The delay is load-bearing and deliberate: the shell calls
/// `ReadingTracker.start()` before pushing the reading screen (the pinned
/// lifecycle in docs/reading-screen.md), and `eventsStream` is a broadcast
/// stream with no replay. A zero-delay script would be drained inside
/// `start()`, before the screen has subscribed, and no word would ever turn
/// green -- for reasons that have nothing to do with the wiring under test.
List<Hypothesis> _scriptFor(List<String> words) => <Hypothesis>[
  for (final word in words)
    Hypothesis(
      wordHypotheses: <String>[word],
      phoneHypotheses: <String>[
        for (final e in _gpm(word)) e.phonemeId,
      ],
    ),
];

const Duration _kHypothesisGap = Duration(milliseconds: 100);

class _RecordingTransport implements AnalyticsTransport {
  final List<List<Map<String, Object?>>> batches = <List<Map<String, Object?>>>[];

  @override
  Future<TransportResult> send(List<Map<String, Object?>> batch) async {
    batches.add(batch);
    return TransportResult.success;
  }
}

/// A mutable clock so the >120 s background timeout (§8 Unit 12) can be
/// simulated without sleeping.
class _MutableClock {
  DateTime now = DateTime.utc(2026, 1, 1, 9);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

/// Bounded frame pump.
///
/// `pumpAndSettle` is unusable on any route hosting the progress map: an
/// awake `MapNode` wraps itself in a forever-repeating pulse, so the tree
/// never settles.
Future<void> _pumpFrames(
  WidgetTester tester, {
  int frames = 12,
  Duration step = const Duration(milliseconds: 16),
}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}

class _Harness {
  late final Directory analyticsDir;
  late final Directory starterDir;
  late final Directory installedDir;
  late final ProviderContainer container;
  late final AppDatabase db;
  late final FakeAudioService audio;
  late final FakeAsrEngine engine;
  late final FakeMicPermissionService micPermission;
  late final _RecordingTransport transport;
  final _MutableClock clock = _MutableClock();

  Future<void> setUp({
    List<String> script = const <String>[],
    List<Profile> profiles = const <Profile>[],
  }) async {
    analyticsDir = Directory.systemTemp.createTempSync('shell_analytics_');
    starterDir = Directory.systemTemp.createTempSync('shell_starter_');
    installedDir = Directory.systemTemp.createTempSync('shell_installed_');
    audio = FakeAudioService();
    transport = _RecordingTransport();
    micPermission = FakeMicPermissionService(MicPermissionStatus.granted);
    engine = FakeAsrEngine(
      script: _scriptFor(script),
      delayBetweenHypotheses: _kHypothesisGap,
    );

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
        asrEngineProvider.overrideWithValue(engine),
        micPermissionServiceProvider.overrideWithValue(micPermission),
        cloudEngineInUseProvider.overrideWithValue(false),
        phonemeAudioRefsProvider.overrideWithValue(_phonemeAudioRefs),
        installIdProvider.overrideWithValue(_installId),
        clockProvider.overrideWithValue(clock.call),
        analyticsTransportProvider.overrideWithValue(transport),
        analyticsStorageDirectoryProvider.overrideWithValue(analyticsDir),
        catalogFetcherProvider.overrideWithValue(null),
        appVersionProvider.overrideWithValue('1.0.0'),
      ],
    );

    db = container.read(appDatabaseProvider);
    for (final profile in profiles.isEmpty
        ? <Profile>[_profile('profile.ada', 'Ada')]
        : profiles) {
      await db.profilesDao.insertProfile(profile);
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

  Widget get app => UncontrolledProviderScope(
    container: container,
    child: const LearnToReadApp(),
  );

  Future<void> boot(WidgetTester tester) async {
    await tester.pumpWidget(app);
    await _pumpFrames(tester);
  }

  Future<void> selectProfile(WidgetTester tester, String localId) async {
    await tester.tap(find.byKey(Key('profile-picker-tile-$localId')));
    await _pumpFrames(tester);
  }

  Future<void> openStory(WidgetTester tester, String storyId) async {
    await tester.tap(find.byKey(ValueKey('map-node-story-$storyId')));
    await _pumpFrames(tester);
  }

  /// Real async gap so in-flight `EventQueue.enqueue()` file writes land
  /// before they are read back. Mirrors the pattern in
  /// test/features/reading/reading_screen_test.dart.
  Future<List<Map<String, Object?>>> analyticsEvents(WidgetTester tester) async {
    late List<Map<String, Object?>> events;
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 30));
      events = await container.read(eventQueueProvider).pendingEvents();
    });
    return events;
  }
}

Color? _colorOfWord(WidgetTester tester, int index) =>
    tester.widget<Text>(find.byKey(ValueKey('word-text-$index'))).style?.color;

/// Drives the REAL ParentalGate to completion (hold two opposite corners for
/// 3 s, then answer the multiplication challenge). No bypass seam exists in
/// the parent unit and none is added here.
Future<void> _passRealGate(WidgetTester tester) async {
  final gesture = await tester.startGesture(const Offset(20, 20), pointer: 1);
  final gesture2 = await tester.startGesture(
    Offset(_kGateScreenSize.width - 20, _kGateScreenSize.height - 20),
    pointer: 2,
  );
  await tester.pumpAndSettle(const Duration(seconds: 3));
  await gesture.up();
  await gesture2.up();
  await tester.pumpAndSettle();

  final challenge =
      find.byType(GateChallenge).evaluate().first.widget as GateChallenge;
  await tester.enterText(
    find.byType(TextField),
    (challenge.factor1 * challenge.factor2).toString(),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.byType(ElevatedButton));
  await tester.pumpAndSettle();
}

void main() {
  late _Harness h;

  tearDown(() => h.tearDown());

  // =========================================================================
  group('boot -> picker -> map (accept 1, 2)', () {
    testWidgets('POSITIVE: the picker lists every profile in the database', (
      tester,
    ) async {
      h = _Harness();
      await h.setUp(
        profiles: <Profile>[
          _profile('profile.ada', 'Ada'),
          _profile('profile.bo', 'Bo'),
        ],
      );
      await h.boot(tester);

      expect(find.byType(ProfilePickerScreen), findsOneWidget);
      expect(find.byKey(const Key('profile-picker-tile-profile.ada')),
          findsOneWidget);
      expect(find.byKey(const Key('profile-picker-tile-profile.bo')),
          findsOneWidget);
    });

    testWidgets(
      'POSITIVE: selecting a profile starts an analytics session carrying '
      'that profile\'s 1-based ordinal (§8 Unit 12)',
      (tester) async {
        h = _Harness();
        await h.setUp(
          profiles: <Profile>[
            _profile('profile.ada', 'Ada'),
            _profile('profile.bo', 'Bo'),
          ],
        );
        await h.boot(tester);
        await h.selectProfile(tester, 'profile.bo');

        final events = await h.analyticsEvents(tester);
        final sessions = events
            .where((e) => e['event'] == AnalyticsEventName.sessionStart.wireName)
            .toList();
        expect(sessions, hasLength(1));
        expect(sessions.single['profileOrdinal'], 2);
        expect(sessions.single['installId'], _installId);
      },
    );

    testWidgets(
      'POSITIVE: content_repository -> phonics-engine -> map: a fresh profile '
      'sees exactly the rolling window of 3 awake stories, the rest asleep',
      (tester) async {
        h = _Harness();
        await h.setUp();
        await h.boot(tester);
        await h.selectProfile(tester, 'profile.ada');

        for (final id in <String>['story.1', 'story.2', 'story.3']) {
          expect(
            find.byKey(ValueKey('map-node-awake-animation-$id')),
            findsOneWidget,
            reason: '$id is inside the rolling window and must be awake',
          );
        }
        for (final id in <String>['story.4', 'story.5']) {
          expect(
            find.byKey(ValueKey('map-node-asleep-marker-$id')),
            findsOneWidget,
            reason: '$id is outside the window and must be asleep',
          );
        }
      },
    );

    testWidgets(
      'NEGATIVE: an asleep story node cannot be opened -- tapping story.4 '
      'leaves the child on the map',
      (tester) async {
        h = _Harness();
        await h.setUp();
        await h.boot(tester);
        await h.selectProfile(tester, 'profile.ada');

        await tester.tap(find.byKey(const ValueKey('map-node-story-story.4')));
        await _pumpFrames(tester);

        expect(h.location, kRoutePathMap);
        expect(find.byType(ReadingScreen), findsNothing);
      },
    );

    testWidgets(
      'POSITIVE: the twister booster node opens the twister flow and emits '
      'twister_started with the narration modelling it first (Unit 14)',
      (tester) async {
        h = _Harness();
        await h.setUp();
        await h.boot(tester);
        await h.selectProfile(tester, 'profile.ada');

        await tester.tap(
          find.byKey(const ValueKey('map-node-twister-twister.1')),
        );
        await _pumpFrames(tester);

        expect(h.location, '/twister/twister.1');
        expect(find.byType(TwisterScreen), findsOneWidget);

        final played = h.audio.callLog.whereType<PlayLogEntry>().toList();
        expect(
          played.map((e) => e.ref),
          contains('audio/twisters/twister.1.wav'),
        );
        expect(
          played
              .where((e) => e.ref == 'audio/twisters/twister.1.wav')
              .single
              .channel,
          AudioChannel.narration,
        );

        final events = await h.analyticsEvents(tester);
        expect(
          events.where(
            (e) => e['event'] == AnalyticsEventName.twisterStarted.wireName,
          ),
          hasLength(1),
        );
      },
    );

    testWidgets(
      'POSITIVE: the Sound Garden route renders the starter pack\'s grapheme '
      'inventory; tapping a card plays its phoneme and reports it',
      (tester) async {
        h = _Harness();
        await h.setUp();
        await h.boot(tester);
        await h.selectProfile(tester, 'profile.ada');

        h.router.go(kRoutePathSoundGarden);
        await _pumpFrames(tester);
        expect(find.byType(SoundGardenScreen), findsOneWidget);
        expect(find.byKey(const ValueKey('sound-card-grapheme.s')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('sound-card-muted-grapheme.ea')),
          findsOneWidget,
          reason: 'grapheme.ea is introduced above this profile\'s level',
        );

        await tester.tap(find.byKey(const ValueKey('sound-card-grapheme.s')));
        await _pumpFrames(tester);

        expect(
          h.audio.callLog.whereType<PlayLogEntry>().map((e) => e.ref),
          contains(_phonemeAudioRefs['S']),
        );

        final events = await h.analyticsEvents(tester);
        expect(
          events.where(
            (e) => e['event'] == AnalyticsEventName.soundCardPlayed.wireName,
          ),
          hasLength(1),
        );
      },
    );
  });

  // =========================================================================
  group('reading, end to end through the real pipeline (accept 2)', () {
    testWidgets(
      'POSITIVE: tapping an awake story opens the reading screen on that story',
      (tester) async {
        h = _Harness();
        await h.setUp(script: _story1Words);
        await h.boot(tester);
        await h.selectProfile(tester, 'profile.ada');
        await h.openStory(tester, 'story.1');

        expect(h.location, '/reading/story.1');
        expect(find.byType(ReadingScreen), findsOneWidget);
        for (var i = 0; i < _story1Words.length; i++) {
          expect(find.byKey(ValueKey('word-text-$i')), findsOneWidget);
        }
      },
    );

    testWidgets(
      'POSITIVE: the injected engine is started with the sentence as its '
      'biasing context -- expected-text hybridization, never open-ended',
      (tester) async {
        h = _Harness();
        await h.setUp(script: _story1Words);
        await h.boot(tester);
        await h.selectProfile(tester, 'profile.ada');
        await h.openStory(tester, 'story.1');

        expect(h.engine.recordedBiasingContext, _story1Words);
      },
    );

    testWidgets(
      'POSITIVE: scripted hypotheses turn every word green through the REAL '
      'matcher + tracker + word state machine (only the engine is faked)',
      (tester) async {
        h = _Harness();
        await h.setUp(script: _story1Words);
        await h.boot(tester);
        await h.selectProfile(tester, 'profile.ada');
        await h.openStory(tester, 'story.1');

        expect(_colorOfWord(tester, 0), isNot(DesignTokens.wordReadGreen));

        for (var i = 0; i < _story1Words.length; i++) {
          await tester.pump(_kHypothesisGap + const Duration(milliseconds: 20));
          await tester.pump();
          expect(
            _colorOfWord(tester, i),
            DesignTokens.wordReadGreen,
            reason: 'word $i should be green after its hypothesis lands',
          );
        }
      },
    );

    testWidgets(
      'POSITIVE: one word_read(correct) per resolved word, with the A-14 '
      'hashed word text and never the plaintext word',
      (tester) async {
        h = _Harness();
        await h.setUp(script: _story1Words);
        await h.boot(tester);
        await h.selectProfile(tester, 'profile.ada');
        await h.openStory(tester, 'story.1');
        await _pumpFrames(tester, frames: 30, step: _kHypothesisGap);

        final events = await h.analyticsEvents(tester);
        final wordReads = events
            .where((e) => e['event'] == AnalyticsEventName.wordRead.wireName)
            .toList();
        expect(wordReads, hasLength(_story1Words.length));
        expect(
          wordReads.map((e) => e['result']).toSet(),
          <String>{WordReadResult.correct.wireValue},
        );
        expect(
          wordReads.map((e) => e['wordHash']),
          _story1Words.map(hashWord),
        );
        for (final word in _story1Words) {
          expect(jsonEncode(wordReads), isNot(contains('"$word"')));
        }
      },
    );

    testWidgets(
      'NEGATIVE: consent gating -- with micConsent off the engine is NEVER '
      'started and the OS microphone permission is never even requested; '
      'the story is still fully readable by tap',
      (tester) async {
        h = _Harness();
        await h.setUp(
          script: _story1Words,
          profiles: <Profile>[
            _profile('profile.ada', 'Ada', micConsent: false),
          ],
        );
        await h.boot(tester);
        await h.selectProfile(tester, 'profile.ada');
        await h.openStory(tester, 'story.1');

        expect(h.engine.recordedBiasingContext, isNull);
        expect(h.micPermission.wasRequested, isFalse);

        await tester.tap(find.byKey(const ValueKey('word-tap-0')));
        await _pumpFrames(tester, frames: 4);
        expect(_colorOfWord(tester, 0), DesignTokens.wordReadGreen);
      },
    );

    testWidgets(
      'EDGE: a story left mid-read reports story_abandoned with the §4.4 '
      'help marker (the reading-screen exit hook -> SessionTracker)',
      (tester) async {
        h = _Harness();
        await h.setUp(script: <String>['the']);
        await h.boot(tester);
        await h.selectProfile(tester, 'profile.ada');
        await h.openStory(tester, 'story.1');
        await _pumpFrames(tester, frames: 3, step: _kHypothesisGap);

        h.router.go(kRoutePathMap);
        await _pumpFrames(tester);

        final events = await h.analyticsEvents(tester);
        final abandoned = events
            .where(
              (e) => e['event'] == AnalyticsEventName.storyAbandoned.wireName,
            )
            .toList();
        expect(abandoned, hasLength(1));
        expect(abandoned.single['storyId'], 'story.1');
        expect(abandoned.single['helpInLast30s'], isA<bool>());
      },
    );
  });

  // =========================================================================
  group('stuck-word scaffold wiring (accept 2)', () {
    testWidgets(
      'POSITIVE: scripted silence past T1 fires Tier 1 -- the word is shown '
      'grapheme-by-grapheme and the phonemes play on the help channel',
      (tester) async {
        h = _Harness();
        // Empty script: the child says nothing at all.
        await h.setUp();
        await h.boot(tester);
        await h.selectProfile(tester, 'profile.ada');
        await h.openStory(tester, 'story.1');

        expect(find.byKey(const ValueKey('grapheme-0-0')), findsNothing);

        await tester.pump(kStruggleT1 + const Duration(milliseconds: 200));
        await _pumpFrames(tester, frames: 4);

        expect(
          find.byKey(const ValueKey('grapheme-0-0')),
          findsOneWidget,
          reason: 'Tier 1 sound-out must render on the reading screen',
        );
        final helpPlays = h.audio.callLog
            .whereType<PlayLogEntry>()
            .where((e) => e.channel == AudioChannel.help)
            .toList();
        expect(helpPlays, isNotEmpty);
        expect(helpPlays.first.ref, _phonemeAudioRefs['T']);
      },
    );

    testWidgets(
      'EDGE: Tier 1 starts exactly once even though BOTH triggers are live -- '
      'the tracker\'s StruggleDetected and the scaffold\'s own T1 timer',
      (tester) async {
        h = _Harness();
        await h.setUp();
        await h.boot(tester);
        await h.selectProfile(tester, 'profile.ada');
        await h.openStory(tester, 'story.1');

        await tester.pump(kStruggleT1 + const Duration(milliseconds: 200));
        await _pumpFrames(tester, frames: 4);

        final firstPhonemePlays = h.audio.callLog
            .whereType<PlayLogEntry>()
            .where(
              (e) =>
                  e.channel == AudioChannel.help &&
                  e.ref == _phonemeAudioRefs['T'],
            )
            .toList();
        expect(
          firstPhonemePlays,
          hasLength(1),
          reason: 'a double-trigger would sound the word out twice',
        );
      },
    );

    testWidgets(
      'POSITIVE: the full ladder resolves the word -- it turns green like any '
      'other, a WordHelpRecord row is written, and help_given is reported',
      (tester) async {
        h = _Harness();
        await h.setUp();
        await h.boot(tester);
        await h.selectProfile(tester, 'profile.ada');
        await h.openStory(tester, 'story.1');

        // T1 -> Tier 1 sound-out; drain each phoneme clip so the sequence
        // reaches its end, then let both T2 windows elapse into the pinned
        // auto-accept (docs/stuck-word-scaffold.md's bounded worst case).
        await tester.pump(kStruggleT1 + const Duration(milliseconds: 200));
        for (var i = 0; i < 8; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          final pending = h.audio.callLog
              .whereType<PlayLogEntry>()
              .where((e) => e.channel == AudioChannel.help)
              .toList();
          for (final entry in pending) {
            h.audio.completePlayback(entry.handle);
          }
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump(kTier2WaitT2 + const Duration(milliseconds: 100));
        await _pumpFrames(tester, frames: 4);
        await tester.pump(kTier2WaitT2 + const Duration(milliseconds: 100));
        await _pumpFrames(tester, frames: 6);

        expect(
          _colorOfWord(tester, 0),
          DesignTokens.wordReadGreen,
          reason: 'a helped word is pixel-identical to an unaided one',
        );

        final record = await h.db.wordHelpDao.rowCountForProfile('profile.ada');
        expect(record, greaterThan(0));

        final events = await h.analyticsEvents(tester);
        final helps = events
            .where((e) => e['event'] == AnalyticsEventName.helpGiven.wireName)
            .toList();
        expect(helps, isNotEmpty);
        expect(
          helps.map((e) => e['tier']).toSet(),
          everyElement(
            anyOf(HelpTier.soundOut.wireValue, HelpTier.modeled.wireValue),
          ),
        );
      },
    );
  });

  // =========================================================================
  group('vocab card injection into the reading screen (accept 2)', () {
    testWidgets(
      'POSITIVE: the reading route is hosted inside the real VocabCardHost, '
      'and tapping a blue word opens the real card',
      (tester) async {
        h = _Harness();
        await h.setUp(
          profiles: <Profile>[
            _profile('profile.ada', 'Ada', levelId: 'level.2'),
          ],
        );
        await h.boot(tester);
        await h.selectProfile(tester, 'profile.ada');
        h.router.go('/reading/story.5');
        await _pumpFrames(tester);

        expect(find.byType(VocabCardHost), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('word-tap-1')));
        await _pumpFrames(tester);

        expect(find.byKey(const ValueKey('vocab-card-popover')), findsOneWidget);
        expect(find.text('otter'), findsWidgets);
      },
    );

    testWidgets(
      'POSITIVE: closing the card restores the reading cursor exactly -- no '
      'word was resolved by opening it',
      (tester) async {
        h = _Harness();
        await h.setUp(
          profiles: <Profile>[
            _profile('profile.ada', 'Ada', levelId: 'level.2'),
          ],
        );
        await h.boot(tester);
        await h.selectProfile(tester, 'profile.ada');
        h.router.go('/reading/story.5');
        await _pumpFrames(tester);

        await tester.tap(find.byKey(const ValueKey('word-tap-1')));
        await _pumpFrames(tester);
        await tester.tap(find.byKey(const ValueKey('vocab-card-barrier')));
        await _pumpFrames(tester);

        expect(find.byKey(const ValueKey('vocab-card-popover')), findsNothing);
        expect(
          find.byKey(const ValueKey('word-current-marker-0')),
          findsOneWidget,
          reason: 'the cursor must still be on word 0',
        );
        expect(_colorOfWord(tester, 1), isNot(DesignTokens.wordReadGreen));
      },
    );

    testWidgets('POSITIVE: opening a card reports vocab_card_opened once', (
      tester,
    ) async {
      h = _Harness();
      await h.setUp(
        profiles: <Profile>[_profile('profile.ada', 'Ada', levelId: 'level.2')],
      );
      await h.boot(tester);
      await h.selectProfile(tester, 'profile.ada');
      h.router.go('/reading/story.5');
      await _pumpFrames(tester);
      await tester.tap(find.byKey(const ValueKey('word-tap-1')));
      await _pumpFrames(tester);

      final events = await h.analyticsEvents(tester);
      expect(
        events.where(
          (e) => e['event'] == AnalyticsEventName.vocabCardOpened.wireName,
        ),
        hasLength(1),
      );
    });
  });

  // =========================================================================
  group('completion -> celebration -> return to map (accept 2)', () {
    testWidgets(
      'POSITIVE: finishing the story runs the real celebration controller: '
      'the stage celebrates then collects, and the view is on screen for it',
      (tester) async {
        h = _Harness();
        await h.setUp(script: _story1Words);
        await h.boot(tester);
        await h.selectProfile(tester, 'profile.ada');
        await h.openStory(tester, 'story.1');

        await _pumpFrames(tester, frames: 6, step: _kHypothesisGap);
        await tester.pump(kCelebrationBeat + const Duration(milliseconds: 50));
        await _pumpFrames(tester, frames: 4);

        expect(find.byKey(const ValueKey('celebration-view')), findsOneWidget);

        final celebrationPlays = h.audio.callLog
            .whereType<PlayLogEntry>()
            .where((e) => e.channel == AudioChannel.celebration)
            .toList();
        expect(
          celebrationPlays.map((e) => e.ref),
          contains('audio/celebration/story.1.wav'),
        );
      },
    );

    testWidgets(
      'POSITIVE: the completion is persisted and the collectible granted '
      'BEFORE the animation hold -- skipping can never lose it',
      (tester) async {
        h = _Harness();
        await h.setUp(script: _story1Words);
        await h.boot(tester);
        await h.selectProfile(tester, 'profile.ada');
        await h.openStory(tester, 'story.1');

        await _pumpFrames(tester, frames: 6, step: _kHypothesisGap);
        await tester.pump(kCelebrationBeat + const Duration(milliseconds: 50));
        await _pumpFrames(tester, frames: 4);

        late CollectionState collection;
        late List<StoryProgress> progress;
        await tester.runAsync(() async {
          collection = await h.db.collectionDao.getCollectionState('profile.ada');
          progress = await h.db.storyProgressDao.allForProfile('profile.ada');
        });

        expect(collection.earnedCollectibles, contains('collectible.story.1'));
        final row = progress.firstWhere((p) => p.storyId == 'story.1');
        expect(row.status, StoryStatus.completed);
        expect(row.timesRead, 1);
      },
    );

    testWidgets(
      'POSITIVE: the sequence returns to the map with the NEXT story '
      'highlighted (PRD §8 Unit 8 return-navigation payload)',
      (tester) async {
        h = _Harness();
        await h.setUp(script: _story1Words);
        await h.boot(tester);
        await h.selectProfile(tester, 'profile.ada');
        await h.openStory(tester, 'story.1');

        await _pumpFrames(tester, frames: 6, step: _kHypothesisGap);
        await tester.pump(kCelebrationBeat + const Duration(milliseconds: 50));
        await tester.pump(kCelebrationDefaultAnimationDuration);
        await tester.pump(DesignTokens.collectibleFlightDuration);
        await _pumpFrames(tester, frames: 8);

        expect(h.location, startsWith(kRoutePathMap));
        expect(find.byKey(const ValueKey('celebration-view')), findsNothing);
        expect(
          find.byKey(const ValueKey('map-node-highlight-story.2')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('map-node-highlight-story.1')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('map-node-thumbnail-story.1')),
          findsOneWidget,
          reason: 'story.1 now renders in its completed treatment',
        );
      },
    );

    testWidgets(
      'POSITIVE: the celebration view carries a skip affordance that ends the '
      'hold early once the skip-unlock delay has passed',
      (tester) async {
        h = _Harness();
        await h.setUp(script: _story1Words);
        await h.boot(tester);
        await h.selectProfile(tester, 'profile.ada');
        await h.openStory(tester, 'story.1');

        await _pumpFrames(tester, frames: 6, step: _kHypothesisGap);
        await tester.pump(kCelebrationBeat + const Duration(milliseconds: 50));
        await tester.pump(
          kCelebrationSkipUnlockDelay + const Duration(milliseconds: 100),
        );
        await _pumpFrames(tester, frames: 2);

        expect(find.byKey(const ValueKey('celebration-view')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('celebration-skip-button')));
        await tester.pump(DesignTokens.collectibleFlightDuration);
        await _pumpFrames(tester, frames: 8);

        expect(
          find.byKey(const ValueKey('celebration-view')),
          findsNothing,
          reason: 'skipping must end the hold well before the full 4 s',
        );
        expect(h.location, startsWith(kRoutePathMap));
      },
    );

    testWidgets(
      'EDGE: re-reading a completed story celebrates again but grants no '
      'second collectible and preserves the original completedAt',
      (tester) async {
        h = _Harness();
        await h.setUp(script: _story1Words);
        await h.boot(tester);
        await h.selectProfile(tester, 'profile.ada');

        Future<void> readStory1() async {
          await h.openStory(tester, 'story.1');
          await _pumpFrames(tester, frames: 6, step: _kHypothesisGap);
          await tester.pump(kCelebrationBeat + const Duration(milliseconds: 50));
          await tester.pump(kCelebrationDefaultAnimationDuration);
          await tester.pump(DesignTokens.collectibleFlightDuration);
          await _pumpFrames(tester, frames: 8);
        }

        await readStory1();
        late StoryProgress first;
        await tester.runAsync(() async {
          final rows =
              await h.db.storyProgressDao.allForProfile('profile.ada');
          first = rows.firstWhere((p) => p.storyId == 'story.1');
        });

        // A completed node routes to the re-read path; the scripted engine has
        // already been drained, so the second read is finished by tapping.
        await tester.tap(find.byKey(const ValueKey('map-node-story-story.1')));
        await _pumpFrames(tester);
        for (var i = 0; i < _story1Words.length; i++) {
          await tester.tap(find.byKey(ValueKey('word-tap-$i')));
          await _pumpFrames(tester, frames: 3);
        }
        await tester.pump(kCelebrationBeat + const Duration(milliseconds: 50));
        await tester.pump(kCelebrationDefaultAnimationDuration);
        await tester.pump(DesignTokens.collectibleFlightDuration);
        await _pumpFrames(tester, frames: 8);

        late CollectionState collection;
        late StoryProgress second;
        await tester.runAsync(() async {
          collection = await h.db.collectionDao.getCollectionState('profile.ada');
          final rows =
              await h.db.storyProgressDao.allForProfile('profile.ada');
          second = rows.firstWhere((p) => p.storyId == 'story.1');
        });

        expect(
          collection.earnedCollectibles
              .where((id) => id == 'collectible.story.1'),
          hasLength(1),
        );
        expect(second.timesRead, 2);
        expect(second.completedAt, first.completedAt);

        final events = await h.analyticsEvents(tester);
        expect(
          events.where(
            (e) => e['event'] == AnalyticsEventName.collectibleEarned.wireName,
          ),
          hasLength(1),
          reason: 'collectible_earned fires on first completion only',
        );
        expect(
          events.where(
            (e) => e['event'] == AnalyticsEventName.storyCompleted.wireName,
          ),
          hasLength(2),
          reason: 'story_completed fires on every read, replays included',
        );
      },
    );
  });

  // =========================================================================
  group('parent corner behind the real gate (accept 1)', () {
    testWidgets(
      'NEGATIVE: routing to the parent corner shows the gate and none of the '
      'corner sections -- the shell adds no bypass',
      (tester) async {
        tester.view.physicalSize = _kGateScreenSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        h = _Harness();
        await h.setUp();
        await h.boot(tester);
        await h.selectProfile(tester, 'profile.ada');

        h.router.go(kRoutePathParentCorner);
        await tester.pumpAndSettle();

        expect(find.byType(ParentalGate), findsOneWidget);
        for (final key in const <String>[
          'parent-corner-section-profiles',
          'parent-corner-section-progress',
          'parent-corner-section-consent',
          'parent-corner-section-links',
        ]) {
          expect(find.byKey(Key(key)), findsNothing);
        }
      },
    );

    testWidgets(
      'POSITIVE: passing the REAL gate reveals the corner sections',
      (tester) async {
        tester.view.physicalSize = _kGateScreenSize;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        h = _Harness();
        await h.setUp();
        await h.boot(tester);
        await h.selectProfile(tester, 'profile.ada');

        h.router.go(kRoutePathParentCorner);
        await tester.pumpAndSettle();
        await _passRealGate(tester);

        for (final key in const <String>[
          'parent-corner-section-profiles',
          'parent-corner-section-progress',
          'parent-corner-section-consent',
          'parent-corner-section-links',
        ]) {
          expect(find.byKey(Key(key)), findsOneWidget);
        }
      },
    );
  });

  // =========================================================================
  group('profile switch and lifecycle (accept 3)', () {
    testWidgets(
      'POSITIVE: switching profiles isolates state -- B\'s map shows none of '
      'A\'s completions',
      (tester) async {
        h = _Harness();
        await h.setUp(
          profiles: <Profile>[
            _profile('profile.ada', 'Ada'),
            _profile('profile.bo', 'Bo'),
          ],
        );
        await h.db.storyProgressDao.upsertProgress(
          StoryProgress(
            profileId: 'profile.ada',
            storyId: 'story.1',
            status: StoryStatus.completed,
            completedAt: DateTime.utc(2026, 1, 1),
            timesRead: 1,
          ),
        );

        await h.boot(tester);
        await h.selectProfile(tester, 'profile.ada');
        expect(
          find.byKey(const ValueKey('map-node-thumbnail-story.1')),
          findsOneWidget,
        );

        h.container.read(activeProfileProvider.notifier).clear();
        await _pumpFrames(tester);
        await h.selectProfile(tester, 'profile.bo');

        expect(
          find.byKey(const ValueKey('map-node-thumbnail-story.1')),
          findsNothing,
          reason: 'Bo has read nothing; Ada\'s completion must not leak',
        );
        expect(
          find.byKey(const ValueKey('map-node-awake-animation-story.1')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'POSITIVE: a profile switch ends the old session and starts a new one, '
      'each carrying its own ordinal',
      (tester) async {
        h = _Harness();
        await h.setUp(
          profiles: <Profile>[
            _profile('profile.ada', 'Ada'),
            _profile('profile.bo', 'Bo'),
          ],
        );
        await h.boot(tester);
        await h.selectProfile(tester, 'profile.ada');
        h.container.read(activeProfileProvider.notifier).clear();
        await _pumpFrames(tester);
        await h.selectProfile(tester, 'profile.bo');

        final events = await h.analyticsEvents(tester);
        final sessions = events
            .where((e) => e['event'] == AnalyticsEventName.sessionStart.wireName)
            .toList();
        expect(sessions, hasLength(2));
        expect(sessions.map((e) => e['profileOrdinal']), <int>[1, 2]);
      },
    );

    testWidgets(
      'POSITIVE: backgrounding for more than 120 s mid-story ends the session '
      'and attributes the abandonment to the moment of backgrounding',
      (tester) async {
        h = _Harness();
        await h.setUp(script: <String>['the']);
        await h.boot(tester);
        await h.selectProfile(tester, 'profile.ada');
        await h.openStory(tester, 'story.1');
        await _pumpFrames(tester, frames: 3, step: _kHypothesisGap);

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await _pumpFrames(tester, frames: 2);
        h.clock.advance(kSessionBackgroundTimeout + const Duration(seconds: 5));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await _pumpFrames(tester, frames: 2);

        final events = await h.analyticsEvents(tester);
        expect(
          events.where(
            (e) => e['event'] == AnalyticsEventName.storyAbandoned.wireName,
          ),
          hasLength(1),
        );
      },
    );

    testWidgets(
      'NEGATIVE: a short background (under 120 s) does NOT end the session',
      (tester) async {
        h = _Harness();
        await h.setUp(script: <String>['the']);
        await h.boot(tester);
        await h.selectProfile(tester, 'profile.ada');
        await h.openStory(tester, 'story.1');
        await _pumpFrames(tester, frames: 3, step: _kHypothesisGap);

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await _pumpFrames(tester, frames: 2);
        h.clock.advance(const Duration(seconds: 10));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await _pumpFrames(tester, frames: 2);

        final events = await h.analyticsEvents(tester);
        expect(
          events.where(
            (e) => e['event'] == AnalyticsEventName.storyAbandoned.wireName,
          ),
          isEmpty,
        );
      },
    );
  });

  // =========================================================================
  group('the full loop, one story start to finish (accept 2)', () {
    testWidgets(
      'POSITIVE: select profile -> pick story -> words turn green -> complete '
      '-> celebrate -> collectible -> map, with only the ASR engine faked; '
      'asserted on the database rows and the analytics stream at the end',
      (tester) async {
        h = _Harness();
        await h.setUp(script: _story1Words);

        await h.boot(tester);
        expect(find.byType(ProfilePickerScreen), findsOneWidget);

        await h.selectProfile(tester, 'profile.ada');
        expect(h.location, kRoutePathMap);

        await h.openStory(tester, 'story.1');
        expect(h.location, '/reading/story.1');

        await _pumpFrames(tester, frames: 6, step: _kHypothesisGap);
        for (var i = 0; i < _story1Words.length; i++) {
          expect(_colorOfWord(tester, i), DesignTokens.wordReadGreen);
        }

        await tester.pump(kCelebrationBeat + const Duration(milliseconds: 50));
        await tester.pump(kCelebrationDefaultAnimationDuration);
        await tester.pump(DesignTokens.collectibleFlightDuration);
        await _pumpFrames(tester, frames: 8);

        expect(h.location, startsWith(kRoutePathMap));

        // --- persisted state ------------------------------------------------
        late CollectionState collection;
        late List<StoryProgress> progress;
        late int helpRows;
        await tester.runAsync(() async {
          collection = await h.db.collectionDao.getCollectionState('profile.ada');
          progress = await h.db.storyProgressDao.allForProfile('profile.ada');
          helpRows = await h.db.wordHelpDao.rowCountForProfile('profile.ada');
        });

        final completed = progress.firstWhere((p) => p.storyId == 'story.1');
        expect(completed.status, StoryStatus.completed);
        expect(completed.timesRead, 1);
        expect(completed.completedAt, isNotNull);
        expect(collection.earnedCollectibles, <String>['collectible.story.1']);
        expect(
          helpRows,
          0,
          reason: 'nothing needed help on a clean read (the §4.3 denominator '
              'is written by the scaffold, which never engaged here)',
        );

        // --- analytics ------------------------------------------------------
        final events = await h.analyticsEvents(tester);
        final names = events.map((e) => e['event']).toList();
        expect(names.first, AnalyticsEventName.sessionStart.wireName);
        expect(names, contains(AnalyticsEventName.storyStarted.wireName));
        expect(
          names
              .where((n) => n == AnalyticsEventName.wordRead.wireName)
              .length,
          _story1Words.length,
        );
        expect(names, contains(AnalyticsEventName.storyCompleted.wireName));
        expect(names, contains(AnalyticsEventName.collectibleEarned.wireName));
        expect(
          names,
          isNot(contains(AnalyticsEventName.storyAbandoned.wireName)),
          reason: 'a completed story is never also abandoned',
        );
        expect(
          names.indexOf(AnalyticsEventName.storyCompleted.wireName),
          greaterThan(names.indexOf(AnalyticsEventName.storyStarted.wireName)),
        );

        // Every payload is schema-valid: the §5 privacy tripwire holds for
        // everything the shell caused, end to end.
        for (final payload in events) {
          expect(() => validateEventPayload(payload), returnsNormally);
        }
      },
    );
  });
}

/// The app's navigation table and the route hosts that compose each merged
/// screen (PRD §8 Unit 1 shell half, §8 Unit 15's fourth destination, §9 A-2;
/// ticket `app-shell`, single-owner rule: **all** router wiring lives here).
///
/// ## The route table
///
/// Seven top-level routes: the four pinned child-facing screens (Home/progress
/// map, Reading, Collection, Sound Garden), the tongue-twister booster, the
/// profile picker, and the gated parent corner. Nothing is nested behind a
/// shell route — the child-facing nav chrome is applied per route by
/// [ChildShell], because the reading and twister routes deliberately carry
/// none (a child mid-story must not be one stray tap from leaving it).
///
/// ## The redirect
///
/// Every route except the picker and the parent corner requires an active
/// profile; without one it redirects to the picker. The parent corner is the
/// single exemption: on a fresh install it is the only way to create the
/// first profile.
///
/// ## Icon + voice-prompt navigation (no reading required)
///
/// Each nav affordance is an icon and nothing else — [ChildShell] renders no
/// `Text` at all — and tapping one plays that destination's voice prompt from
/// [kNavVoicePromptRefs] before navigating. The recordings themselves are
/// owner content; what lives here is the ref and the hook.
library;

import 'dart:async';

import 'package:flutter/material.dart' hide Page;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:learn_to_read/app/providers.dart';
import 'package:learn_to_read/design/confetti.dart';
import 'package:learn_to_read/design/motion.dart';
import 'package:learn_to_read/design/rive_stage.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/domain/phonics/phonics_engine.dart';
import 'package:learn_to_read/domain/phonics/scope_sequence_loader.dart';
import 'package:learn_to_read/features/analytics/analytics_client.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/analytics/events.dart';
import 'package:learn_to_read/features/analytics/session_tracker.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/celebration/celebration_controller.dart';
import 'package:learn_to_read/features/collection/collection_screen.dart';
import 'package:learn_to_read/features/help/help_recorder.dart';
import 'package:learn_to_read/features/listening/contracts/help_state.dart';
import 'package:learn_to_read/features/listening/matcher/sound_mode_scorer.dart';
import 'package:learn_to_read/features/map/progress_map_screen.dart';
import 'package:learn_to_read/features/parent/consent_controller.dart';
import 'package:learn_to_read/features/parent/parent_corner_screen.dart';
import 'package:learn_to_read/features/profiles/profile_picker_screen.dart';
import 'package:learn_to_read/features/reading/reading_screen.dart';
import 'package:learn_to_read/features/sound_garden/sound_garden_screen.dart';
import 'package:learn_to_read/features/twister/twister_controller.dart';
import 'package:learn_to_read/features/twister/twister_screen.dart';
import 'package:learn_to_read/features/vocab/vocab_card_opener.dart';

// ===========================================================================
// The pinned route table
// ===========================================================================

/// The profile picker — launch, and the only route reachable without a
/// profile besides the parent corner.
const String kRoutePathProfilePicker = '/';

/// Home: the illustrated progress map.
const String kRoutePathMap = '/map';

/// One story, read aloud.
const String kRoutePathReading = '/reading/:storyId';

/// The collection scene.
const String kRoutePathCollection = '/collection';

/// The Sound Garden (Unit 15).
const String kRoutePathSoundGarden = '/garden';

/// One tongue-twister booster (Unit 14).
const String kRoutePathTwister = '/twister/:twisterId';

/// The parent corner, behind the real parental gate.
const String kRoutePathParentCorner = '/parent';

/// Route name of [kRoutePathProfilePicker].
const String kRouteNameProfilePicker = 'profiles';

/// Route name of [kRoutePathMap].
const String kRouteNameMap = 'map';

/// Route name of [kRoutePathReading].
const String kRouteNameReading = 'reading';

/// Route name of [kRoutePathCollection].
const String kRouteNameCollection = 'collection';

/// Route name of [kRoutePathSoundGarden].
const String kRouteNameSoundGarden = 'soundGarden';

/// Route name of [kRoutePathTwister].
const String kRouteNameTwister = 'twister';

/// Route name of [kRoutePathParentCorner].
const String kRouteNameParentCorner = 'parentCorner';

/// The child-facing destinations reachable from the shell's own nav chrome,
/// in render order.
///
/// Reading is deliberately absent: a story is entered by tapping its map
/// node, never by a nav tab.
const List<String> kChildNavDestinationRouteNames = <String>[
  kRouteNameMap,
  kRouteNameCollection,
  kRouteNameSoundGarden,
];

/// Owner-recorded voice-prompt refs, keyed by route name.
///
/// The recordings are owner content (PRD: "Voice-prompt recordings are owner
/// content — refs only"); what this shell owns is the guarantee that every
/// navigable destination *has* one, so a non-reading child hears where they
/// are going as they tap.
const Map<String, AudioRef> kNavVoicePromptRefs = <String, AudioRef>{
  kRouteNameMap: 'audio/nav/map.wav',
  kRouteNameCollection: 'audio/nav/collection.wav',
  kRouteNameSoundGarden: 'audio/nav/garden.wav',
  kRouteNameParentCorner: 'audio/nav/parent-corner.wav',
};

/// The concrete path a nav destination navigates to.
const Map<String, String> _navDestinationPaths = <String, String>{
  kRouteNameMap: kRoutePathMap,
  kRouteNameCollection: kRoutePathCollection,
  kRouteNameSoundGarden: kRoutePathSoundGarden,
  kRouteNameParentCorner: kRoutePathParentCorner,
};

/// The icon each nav destination renders. Icons only — nothing about
/// navigating this app requires reading.
const Map<String, IconData> _navDestinationIcons = <String, IconData>{
  kRouteNameMap: Icons.home_rounded,
  kRouteNameCollection: Icons.pets_rounded,
  kRouteNameSoundGarden: Icons.spa_rounded,
  kRouteNameParentCorner: Icons.lock_rounded,
};

/// The query parameter the celebration sequence returns the next story to
/// highlight in (PRD §8 Unit 8's return-navigation payload).
const String kMapHighlightQueryParameter = 'highlight';

// ===========================================================================
// The router
// ===========================================================================

/// Re-runs the router's redirect whenever the active profile changes, so
/// clearing it (profile switch, session end) pulls the app back to the picker
/// from wherever it was.
class _ActiveProfileRefresh extends ChangeNotifier {
  void bump() => notifyListeners();
}

/// Wraps a route's screen in a page with **no** transition, over a plain
/// [Material] surface.
///
/// Two decisions live here:
///
///  * **No transition.** The stock platform page transition is exactly the
///    "assembled from stock components" feel PRD §8 Unit 1 rules out of
///    child-facing screens, and the storybook motion that replaces it is
///    owner-designed (OQ-8). Until then a destination simply *is* there when
///    its icon is tapped — which is also what keeps two screens from being
///    briefly on top of each other.
///  * **A [Material] ancestor.** Screens that build their own `Scaffold` get
///    one for free; the picker and the parental gate do not, and the gate's
///    text field needs one. Supplying it once here means no screen has to
///    grow stock chrome just to be mountable.
NoTransitionPage<void> _page(GoRouterState state, Widget child) =>
    NoTransitionPage<void>(
      key: state.pageKey,
      child: Material(color: DesignTokens.screenBackground, child: child),
    );

/// The composed router.
final Provider<GoRouter> appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _ActiveProfileRefresh();
  ref.listen<ActiveProfile?>(
    activeProfileProvider,
    (previous, next) => refresh.bump(),
  );

  return GoRouter(
    initialLocation: kRoutePathProfilePicker,
    refreshListenable: refresh,
    redirect: (BuildContext context, GoRouterState state) {
      final path = state.uri.path;
      if (path == kRoutePathProfilePicker || path == kRoutePathParentCorner) {
        return null;
      }
      // No profile, no child-facing route: a deep link into a story must
      // never open a microphone session for nobody.
      return ref.read(activeProfileProvider) == null
          ? kRoutePathProfilePicker
          : null;
    },
    // An unknown path is never a crash: it lands back where launch does.
    onException: (BuildContext context, GoRouterState state, GoRouter router) =>
        router.go(kRoutePathProfilePicker),
    routes: <RouteBase>[
      GoRoute(
        path: kRoutePathProfilePicker,
        name: kRouteNameProfilePicker,
        pageBuilder: (context, state) =>
            _page(state, const ProfilePickerRoute()),
      ),
      GoRoute(
        path: kRoutePathMap,
        name: kRouteNameMap,
        pageBuilder: (context, state) => _page(
          state,
          ChildShell(
            child: MapRoute(
              highlightedStoryId:
                  state.uri.queryParameters[kMapHighlightQueryParameter],
            ),
          ),
        ),
      ),
      GoRoute(
        path: kRoutePathReading,
        name: kRouteNameReading,
        pageBuilder: (context, state) => _page(
          state,
          ReadingRoute(storyId: state.pathParameters['storyId'] ?? ''),
        ),
      ),
      GoRoute(
        path: kRoutePathCollection,
        name: kRouteNameCollection,
        pageBuilder: (context, state) =>
            _page(state, const ChildShell(child: CollectionRoute())),
      ),
      GoRoute(
        path: kRoutePathSoundGarden,
        name: kRouteNameSoundGarden,
        pageBuilder: (context, state) =>
            _page(state, const ChildShell(child: SoundGardenRoute())),
      ),
      GoRoute(
        path: kRoutePathTwister,
        name: kRouteNameTwister,
        pageBuilder: (context, state) => _page(
          state,
          TwisterRoute(twisterId: state.pathParameters['twisterId'] ?? ''),
        ),
      ),
      GoRoute(
        path: kRoutePathParentCorner,
        name: kRouteNameParentCorner,
        pageBuilder: (context, state) => _page(state, const ParentCornerRoute()),
      ),
    ],
  );
});

// ===========================================================================
// Child-facing nav chrome
// ===========================================================================

/// Wraps a child-facing screen with the icon + voice-prompt nav rail.
///
/// Deliberately hand-built from a [Row] of icons rather than any stock
/// navigation component: PRD §8 Unit 1 pins that no stock component styling
/// is visible in child-facing screens, and `layout_smoke_test.dart` scans
/// these routes for exactly that.
class ChildShell extends ConsumerWidget {
  const ChildShell({super.key, required this.child});

  /// The screen this chrome wraps.
  final Widget child;

  Future<void> _onDestinationTap(
    BuildContext context,
    WidgetRef ref,
    String routeName,
  ) async {
    final prompt = kNavVoicePromptRefs[routeName];
    if (prompt != null) {
      // The prompt is fired, not awaited: the screen changes with the voice,
      // not after it.
      unawaited(
        _playQuietly(
          ref.read(audioServiceProvider),
          prompt,
          AudioChannel.narration,
        ),
      );
    }
    final path = _navDestinationPaths[routeName];
    if (path != null && context.mounted) context.go(path);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ColoredBox(
      color: DesignTokens.screenBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(child: child),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: DesignTokens.spacingXs,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: <Widget>[
                  for (final name in <String>[
                    ...kChildNavDestinationRouteNames,
                    kRouteNameParentCorner,
                  ])
                    GestureDetector(
                      key: ValueKey<String>('nav-destination-$name'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _onDestinationTap(context, ref, name),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: DesignTokens.spacingMd,
                          vertical: DesignTokens.spacingSm,
                        ),
                        child: Icon(
                          _navDestinationIcons[name] ?? Icons.circle_outlined,
                          size: 28,
                          color: DesignTokens.wordUnreadInk,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Plays [ref] and swallows a missing-clip error.
///
/// Voice prompts are owner content that may not have shipped yet; a missing
/// navigation clip must never stop a child from navigating.
Future<void> _playQuietly(
  AudioService audioService,
  AudioRef audioRef,
  AudioChannel channel,
) async {
  try {
    await audioService.play(audioRef, channel: channel);
  } on Object {
    // Content gap, not a runtime failure.
  }
}

/// The quiet placeholder shown while a route resolves its content.
///
/// Deliberately empty and token-coloured: content resolves within a frame or
/// two from local files, so anything more would be a flash.
class _RouteLoading extends StatelessWidget {
  const _RouteLoading();

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: DesignTokens.screenBackground, child: SizedBox.expand());
}

// ===========================================================================
// Profile picker
// ===========================================================================

/// Hosts [ProfilePickerScreen] over the device-local profile list.
class ProfilePickerRoute extends ConsumerStatefulWidget {
  const ProfilePickerRoute({super.key});

  @override
  ConsumerState<ProfilePickerRoute> createState() => _ProfilePickerRouteState();
}

class _ProfilePickerRouteState extends ConsumerState<ProfilePickerRoute> {
  List<Profile>? _profiles;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final profiles =
        await ref.read(appDatabaseProvider).profilesDao.allProfiles();
    if (!mounted) return;
    setState(() => _profiles = profiles);
  }

  @override
  Widget build(BuildContext context) {
    final profiles = _profiles;
    if (profiles == null) return const _RouteLoading();
    return ProfilePickerScreen(
      profiles: profiles,
      onProfileSelected: (profile, ordinal) {
        ref.read(activeProfileProvider.notifier).select(profile, ordinal);
        context.go(kRoutePathMap);
      },
    );
  }
}

// ===========================================================================
// Home: the progress map
// ===========================================================================

/// Everything [ProgressMapScreen] renders for one profile.
class _MapData {
  const _MapData({
    required this.stories,
    required this.storyProgress,
    required this.twisters,
    required this.unlockedTwisterLevelIds,
  });

  final List<StoryRef> stories;
  final Map<String, StoryProgress> storyProgress;
  final List<TongueTwister> twisters;
  final Set<String> unlockedTwisterLevelIds;
}

/// Hosts [ProgressMapScreen]: content repository -> phonics engine -> map.
class MapRoute extends ConsumerStatefulWidget {
  const MapRoute({super.key, this.highlightedStoryId});

  /// The story to render highlighted — the celebration sequence's
  /// return-navigation payload (PRD §8 Unit 8).
  final String? highlightedStoryId;

  @override
  ConsumerState<MapRoute> createState() => _MapRouteState();
}

class _MapRouteState extends ConsumerState<MapRoute> {
  _MapData? _data;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final active = ref.read(activeProfileProvider);
    if (active == null) return;
    final content = ref.read(phonicsContentProvider);
    final snapshot = await ref.read(contentSnapshotProvider.future);
    final rows = await ref
        .read(appDatabaseProvider)
        .storyProgressDao
        .allForProfile(active.profile.localId);
    if (!mounted) return;

    final completedIds = <String>{
      for (final row in rows)
        if (row.status == StoryStatus.completed) row.storyId,
    };
    // The rolling window is the phonics engine's decision, never this
    // screen's: `storiesFor` returns every completed story plus the next
    // three uncompleted ones, and everything else stays asleep.
    final offered = storiesFor(active.profile, content, completedIds);
    final rowsById = <String, StoryProgress>{
      for (final row in rows) row.storyId: row,
    };
    final progress = <String, StoryProgress>{
      for (final story in offered)
        story.id: completedIds.contains(story.id)
            ? rowsById[story.id]!
            : StoryProgress(
                profileId: active.profile.localId,
                storyId: story.id,
                status: StoryStatus.available,
                timesRead: rowsById[story.id]?.timesRead ?? 0,
              ),
    };

    setState(() {
      _data = _MapData(
        stories: content.stories,
        storyProgress: progress,
        twisters: snapshot.twisters,
        unlockedTwisterLevelIds:
            unlockedTwisterLevelIds(content, active.profile),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final active = ref.watch(activeProfileProvider);
    if (data == null || active == null) return const _RouteLoading();
    return ProgressMapScreen(
      profile: active.profile,
      stories: data.stories,
      storyProgress: data.storyProgress,
      twisters: data.twisters,
      unlockedTwisterLevelIds: data.unlockedTwisterLevelIds,
      highlightedStoryId: widget.highlightedStoryId,
      onStartStory: (storyId) => context.go('/reading/$storyId'),
      onReReadStory: (storyId) => context.go('/reading/$storyId'),
      onOpenTwister: (twisterId) => context.go('/twister/$twisterId'),
    );
  }
}

// ===========================================================================
// Reading
// ===========================================================================

/// Flattens `Story.pages -> Page.sentences -> words` into one token list per
/// page — the shape both `WordStateMachine` and [ReadingSession] work in.
List<List<WordToken>> flattenStoryPages(Story story) {
  if (story.pages.isEmpty) return <List<WordToken>>[<WordToken>[]];
  return <List<WordToken>>[
    for (final page in story.pages)
      <WordToken>[
        for (final sentence in page.sentences) ...sentence.words,
      ],
  ];
}

/// Hosts [ReadingScreen] with everything the read needs composed around it:
/// the paragraph-scoped listening session, the Unit 6 help scaffold, the real
/// vocabulary-card host, and the Unit 8 celebration sequence.
class ReadingRoute extends ConsumerStatefulWidget {
  const ReadingRoute({super.key, required this.storyId});

  final String storyId;

  @override
  ConsumerState<ReadingRoute> createState() => _ReadingRouteState();
}

class _ReadingRouteState extends ConsumerState<ReadingRoute> {
  final GlobalKey<VocabCardHostState> _vocabHostKey =
      GlobalKey<VocabCardHostState>();

  ReadingSession? _session;
  Story? _story;
  Level? _level;
  StoryStage? _stage;
  Map<String, VocabCard> _cardsById = const <String, VocabCard>{};
  Map<String, String> _pronunciationsById = const <String, String>{};
  String? _nextStoryId;
  CelebrationController? _celebration;
  bool _celebrating = false;

  /// Every timer the running celebration sequence has scheduled.
  ///
  /// `CelebrationController` owns its own hold/skip-unlock/flight timers and
  /// exposes no way to abandon a run, so the shell runs the sequence inside a
  /// forked zone that records the timers it creates. Leaving the reading route
  /// cancels them: no beat of a celebration may outlive the screen that
  /// started it.
  final Set<Timer> _celebrationTimers = <Timer>{};

  // Captured once so teardown never touches `ref` after this State is gone.
  SessionTracker? _sessionTracker;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  /// Resolves content and consent, then opens the listening session **before**
  /// the reading screen is built (the pinned lifecycle in
  /// docs/reading-screen.md: `start()` is the shell's call; the screen only
  /// ever resumes the session it was handed).
  Future<void> _prepare() async {
    final active = ref.read(activeProfileProvider);
    if (active == null) return;
    final content = ref.read(phonicsContentProvider);
    final snapshot = await ref.read(contentSnapshotProvider.future);
    if (!mounted) return;

    final story = snapshot.storyById(widget.storyId);
    if (story == null) return;
    final level = levelById(content, story.levelId) ??
        Level(
          id: story.levelId,
          ordinal: 1,
          newSkills: const <PhonicsSkill>[],
          format: LevelFormat.multiSentence,
          vocabEnabled: false,
        );

    final profile = active.profile;
    final micEnabled = await _resolveMicrophone(profile);
    if (!mounted) return;

    final db = ref.read(appDatabaseProvider);
    final analytics = ref.read(analyticsClientProvider);
    final sessionTracker = ref.read(sessionTrackerProvider);
    final installId = ref.read(installIdProvider);
    final levelOrdinal = levelOrdinalOf(content, profile.currentLevelId);

    final session = ReadingSession(
      pages: flattenStoryPages(story),
      engine: ref.read(sharedAsrEngineProvider),
      micConsent: micEnabled,
      audioService: ref.read(audioServiceProvider),
      phonemeAudioRefs: ref.read(phonemeAudioRefsProvider),
      helpRecorder: HelpRecorder(
          wordHelpDao: db.wordHelpDao,
          profileId: profile.localId,
      ),
      yourTurnPromptAudioRef: ref.read(yourTurnPromptAudioRefProvider),
      nearMissPromptAudioRef: ref.read(nearMissPromptAudioRefProvider),
      onHelpGiven: (index, tier) {
        sessionTracker.onHelpGiven();
        final wireTier = _helpTierOf(tier);
        if (wireTier == null) return;
        _record(
          analytics,
          AnalyticsEvent(
            name: AnalyticsEventName.helpGiven,
            timestamp: ref.read(clockProvider)(),
            installId: installId,
            profileOrdinal: active.ordinal,
            levelOrdinal: levelOrdinal,
            storyId: story.id,
            fields: <String, Object?>{'tier': wireTier.wireValue},
          ),
        );
      },
    );
    session.start();
    sessionTracker.onStoryStarted(storyId: story.id);

    final completedRows =
        await db.storyProgressDao.allForProfile(profile.localId);
    if (!mounted) {
      session.dispose();
      return;
    }
    final completedIds = <String>{
      for (final row in completedRows)
        if (row.status == StoryStatus.completed) row.storyId,
      story.id,
    };

    setState(() {
      _story = story;
      _level = level;
      _session = session;
      _sessionTracker = sessionTracker;
      _stage = ref.read(storyStageFactoryProvider)();
      _cardsById = <String, VocabCard>{
        for (final card in snapshot.vocabCards) card.id: card,
      };
      _pronunciationsById = <String, String>{
        for (final page in story.pages)
          for (final sentence in page.sentences)
            for (final word in sentence.words)
              if (word.vocabCardId != null)
                word.vocabCardId!: word.pronunciationAudioRef,
      };
      _nextStoryId = _firstUncompleted(content, completedIds);
    });
  }

  /// Whether this read may open the microphone at all.
  ///
  /// Consent gating sits above the engine seam: with `micConsent == false`
  /// the OS permission is never even requested, and `ReadingTracker` is
  /// handed `micConsent: false` so it never calls `engine.start`.
  Future<bool> _resolveMicrophone(Profile profile) async {
    if (!profile.micConsent) return false;
    final status =
        await ref.read(micPermissionServiceProvider).requestPermission();
    if (!mounted) return false;
    final mode = resolveReadingMode(
      micConsent: true,
      permissionStatus: status,
      cloudEngineInUse: ref.read(cloudEngineInUseProvider),
      cloudAsrConsent: profile.cloudAsrConsent,
    );
    return mode != ReadingMode.tapOnly;
  }

  static String? _firstUncompleted(
    PhonicsContent content,
    Set<String> completedIds,
  ) {
    for (final story in content.stories) {
      if (!completedIds.contains(story.id)) return story.id;
    }
    return null;
  }

  static HelpTier? _helpTierOf(HelpLevel level) => switch (level) {
        HelpLevel.soundOut => HelpTier.soundOut,
        HelpLevel.modeled => HelpTier.modeled,
        HelpLevel.none => null,
      };

  void _onStoryComplete() {
    if (!mounted || _celebrating) return;
    final active = ref.read(activeProfileProvider);
    final story = _story;
    final stage = _stage;
    if (active == null || story == null || stage == null) return;

    // The story can no longer be abandoned (§8 Unit 12) — said before the
    // celebration starts, so nothing that follows can be read as a walk-away.
    _sessionTracker?.onStoryCompleted();

    final db = ref.read(appDatabaseProvider);
    final analytics = ref.read(analyticsClientProvider);
    final controller = CelebrationController(
      stage: stage,
      audioService: ref.read(audioServiceProvider),
      collectionDao: db.collectionDao,
      storyProgressDao: db.storyProgressDao,
      lineRotator: ref.read(celebrationLineRotatorProvider),
      installId: ref.read(installIdProvider),
      onAnalyticsEvent: (event) => _record(analytics, event),
      onFinished: _onCelebrationFinished,
    );
    _celebration = controller;
    setState(() => _celebrating = true);
    final levelOrdinal = levelOrdinalOf(
      ref.read(phonicsContentProvider),
      active.profile.currentLevelId,
    );
    _celebrationZone().run(
      () => unawaited(
        controller.run(
          story: story,
          profileId: active.profile.localId,
          profileOrdinal: active.ordinal,
          levelOrdinal: levelOrdinal,
          nextStoryId: _nextStoryId,
        ),
      ),
    );
  }

  /// A zone that records every timer the celebration sequence schedules, so
  /// [dispose] can cancel them all.
  Zone _celebrationZone() => Zone.current.fork(
        specification: ZoneSpecification(
          createTimer: (self, parent, zone, duration, callback) {
            late Timer timer;
            timer = parent.createTimer(zone, duration, () {
              _celebrationTimers.remove(timer);
              callback();
            });
            _celebrationTimers.add(timer);
            return timer;
          },
        ),
      );

  void _onCelebrationFinished(CelebrationResult result) {
    if (!mounted) return;
    unawaited(_advanceLevelIfCompleted(result.completedStoryId));
    final next = result.nextStoryId;
    context.go(
      next == null
          ? kRoutePathMap
          : '$kRoutePathMap?$kMapHighlightQueryParameter=$next',
    );
  }

  /// Persists level advancement (PRD §8 Unit 2: `currentLevelId` advances
  /// only when a level's full story set is completed).
  ///
  /// Everything it needs is read up front, because the route is navigating
  /// away as this runs.
  Future<void> _advanceLevelIfCompleted(String completedStoryId) async {
    final active = ref.read(activeProfileProvider);
    if (active == null) return;
    final content = ref.read(phonicsContentProvider);
    final db = ref.read(appDatabaseProvider);
    final profiles = ref.read(activeProfileProvider.notifier);

    StoryRef? storyRef;
    for (final candidate in content.stories) {
      if (candidate.id == completedStoryId) storyRef = candidate;
    }
    if (storyRef == null) return;

    final rows = await db.storyProgressDao.allForProfile(active.profile.localId);
    final completedIds = <String>{
      for (final row in rows)
        if (row.status == StoryStatus.completed) row.storyId,
    };
    try {
      final advanced =
          advance(active.profile, storyRef, content, completedIds..remove(completedStoryId));
      if (advanced.profile.currentLevelId == active.profile.currentLevelId) {
        return;
      }
      await db.profilesDao.updateProfile(advanced.profile);
      profiles.replaceProfile(advanced.profile);
    } on ArgumentError {
      // A story outside this profile's window cannot advance a level; the
      // completion itself is already persisted either way.
    }
  }

  void _onReadingExited() => _sessionTracker?.onReadingScreenExited();

  @override
  void dispose() {
    for (final timer in _celebrationTimers) {
      timer.cancel();
    }
    _celebrationTimers.clear();
    _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final story = _story;
    final level = _level;
    final stage = _stage;
    final active = ref.watch(activeProfileProvider);
    if (session == null ||
        story == null ||
        level == null ||
        stage == null ||
        active == null) {
      return const _RouteLoading();
    }
    final installId = ref.watch(installIdProvider);
    final levelOrdinal = levelOrdinalOf(
      ref.watch(phonicsContentProvider),
      active.profile.currentLevelId,
    );
    final audioService = ref.watch(audioServiceProvider);
    final analytics = ref.watch(analyticsClientProvider);

    return Stack(
      children: <Widget>[
        VocabCardHost(
          key: _vocabHostKey,
          cardsById: _cardsById,
          pronunciationAudioRefsById: _pronunciationsById,
          audioService: audioService,
          analytics: analytics,
          installId: installId,
          profileOrdinal: active.ordinal,
          levelOrdinal: levelOrdinal,
          storyId: story.id,
          child: ValueListenableBuilder<HelpState>(
            valueListenable: session.helpState,
            builder: (context, helpState, _) => ReadingScreen(
              story: story,
              level: level,
              tracker: session,
              audioService: audioService,
              analytics: analytics,
              installId: installId,
              profileOrdinal: active.ordinal,
              levelOrdinal: levelOrdinal,
              stage: stage,
              vocabCardOpener: _openVocabCard,
              onStoryComplete: _onStoryComplete,
              // Page-turn hold (PRD §8 Unit 5): the child's curl gesture is
              // what moves the listening session onto the next page.
              onPageTurned: session.advancePage,
              onReadingExited: _onReadingExited,
              helpState: helpState,
            ),
          ),
        ),
        if (_celebrating)
          CelebrationView(
            onSkip: () => _celebration?.skip(),
            // Deterministic confetti per story: the seed is derived from the
            // story id the route already holds (stable across replays), per
            // the mockup-spec §6 restyle. No new data is plumbed.
            confettiSeed: _story?.id.hashCode ?? 0,
          ),
      ],
    );
  }

  Future<void> _openVocabCard(String vocabCardId) {
    final host = _vocabHostKey.currentState;
    if (host == null) return Future<void>.value();
    return host.open(vocabCardId);
  }
}

/// Records [event] fire-and-forget, on the root zone (see
/// `providers.dart`'s note on why analytics never runs in the caller's zone).
void _record(AnalyticsClient analytics, AnalyticsEvent event) =>
    Zone.root.run(
    () => unawaited(
      // Analytics must never crash a child's reading session.
      analytics.track(event).catchError((Object _, StackTrace __) {}),
    ),
  );

// ===========================================================================
// The celebration view
// ===========================================================================

/// The thin, token-styled view the merged [CelebrationController] runs
/// behind, restyled to the owner mockup's done state (docs/design/
/// mockup-spec.md §5-§6).
///
/// The controller owns every beat of the sequence (stage triggers, audio,
/// persistence, the hold phase, the collectible flight); this view owns
/// exactly three things: it is on screen for the duration, it carries the
/// skip affordance, and it plays the pure-code confetti celebration. It
/// deliberately renders no text — skipping is one tap on an icon, and
/// nothing here asks a five-year-old to read; the mockup's stats numbers
/// and hurray copy need words-read/streak data no one plumbs to this view,
/// so the success panel is a quiet token-styled emblem instead (see the
/// restyle report).
///
/// It sits *over* the reading screen rather than replacing it, because the
/// celebration transforms the story stage that is already on screen (PRD §8
/// Unit 8) — which is why the whole overlay (not a new stage) gets the
/// spec's `sceneReveal` entrance, and the success panel fades up over it.
///
/// All three animations here are finite (sceneReveal 620 ms, fadeUp 420 ms,
/// confetti a bounded one-shot), so settle-based tests can never hang on
/// this view.
class CelebrationView extends StatelessWidget {
  const CelebrationView({super.key, required this.onSkip, this.confettiSeed = 0});

  /// Wired to `CelebrationController.skip()`, which is a harmless no-op
  /// until the skip-unlock delay has elapsed.
  final VoidCallback onSkip;

  /// Seed for the deterministic confetti overlay; the reading route passes
  /// the story id's hashCode so a story always replays its own celebration.
  final int confettiSeed;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      key: const ValueKey<String>('celebration-view'),
      child: Stack(
        children: <Widget>[
          // Spec §6: full-screen, non-interactive confetti. Intensity is
          // min(3, stories-in-a-row); no streak data reaches this view, so
          // it plays at the single-story intensity.
          Positioned.fill(
            child: ConfettiOverlay(intensity: 1, seed: confettiSeed),
          ),
          SceneReveal(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: FadeUp(
                  duration: const Duration(milliseconds: 420),
                  child: Container(
                    margin: const EdgeInsets.all(DesignTokens.spacingLg),
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.spacingLg,
                      vertical: DesignTokens.spacingMd,
                    ),
                    decoration: BoxDecoration(
                      color: DesignTokens.successPanelBackground,
                      border: Border.all(
                        color: DesignTokens.successPanelBorder,
                        width: 1.5,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: 28,
                          color: DesignTokens.successDeepGreen,
                        ),
                        SizedBox(width: DesignTokens.spacingSm),
                        Icon(
                          Icons.menu_book_rounded,
                          size: 28,
                          color: DesignTokens.successDeepGreen,
                        ),
                        SizedBox(width: DesignTokens.spacingSm),
                        Icon(
                          Icons.auto_awesome_rounded,
                          size: 28,
                          color: DesignTokens.successDeepGreen,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.topRight,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(DesignTokens.spacingMd),
                child: GestureDetector(
                  key: const ValueKey<String>('celebration-skip-button'),
                  behavior: HitTestBehavior.opaque,
                  onTap: onSkip,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: DesignTokens.readingBackground,
                      shape: BoxShape.circle,
                      border: Border.all(color: DesignTokens.cardBorder),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: DesignTokens.wordUnreadInk
                              .withValues(alpha: 0.18),
                          offset: const Offset(0, 6),
                          blurRadius: 14,
                          spreadRadius: -8,
                        ),
                      ],
                    ),
                    child: const Padding(
                      padding: EdgeInsets.all(DesignTokens.spacingSm),
                      child: Icon(
                        Icons.skip_next_rounded,
                        size: 28,
                        color: DesignTokens.wordUnreadInk,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// Collection
// ===========================================================================

/// Hosts [CollectionScreen] over this profile's earned collectibles.
class CollectionRoute extends ConsumerStatefulWidget {
  const CollectionRoute({super.key});

  @override
  ConsumerState<CollectionRoute> createState() => _CollectionRouteState();
}

class _CollectionRouteState extends ConsumerState<CollectionRoute> {
  List<Collectible>? _collectibles;
  CollectionState? _state;
  final Map<String, StoryStage> _stages = <String, StoryStage>{};

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final active = ref.read(activeProfileProvider);
    if (active == null) return;
    final snapshot = await ref.read(contentSnapshotProvider.future);
    final state = await ref
        .read(appDatabaseProvider)
        .collectionDao
        .getCollectionState(active.profile.localId);
    if (!mounted) return;
    setState(() {
      _collectibles = snapshot.collectibles;
      _state = state;
    });
  }

  StoryStage _stageFor(String collectibleId) => _stages.putIfAbsent(
        collectibleId,
        ref.read(storyStageFactoryProvider),
      );

  @override
  Widget build(BuildContext context) {
    final collectibles = _collectibles;
    final state = _state;
    final active = ref.watch(activeProfileProvider);
    if (collectibles == null || state == null || active == null) {
      return const _RouteLoading();
    }
    return CollectionScreen(
      profile: active.profile,
      collectibles: collectibles,
      collectionState: state,
      stageFor: _stageFor,
    );
  }
}

// ===========================================================================
// Sound Garden (Unit 15)
// ===========================================================================

/// Hosts [SoundGardenScreen] over the content repository's grapheme
/// inventory and the profile's phonics level state.
class SoundGardenRoute extends ConsumerStatefulWidget {
  const SoundGardenRoute({super.key});

  @override
  ConsumerState<SoundGardenRoute> createState() => _SoundGardenRouteState();
}

class _SoundGardenRouteState extends ConsumerState<SoundGardenRoute> {
  ContentSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final snapshot = await ref.read(contentSnapshotProvider.future);
    if (!mounted) return;
    setState(() => _snapshot = snapshot);
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final active = ref.watch(activeProfileProvider);
    if (snapshot == null || active == null) return const _RouteLoading();
    final content = ref.watch(phonicsContentProvider);
    final analytics = ref.watch(analyticsClientProvider);
    return SoundGardenScreen(
      profile: active.profile,
      profileOrdinal: active.ordinal,
      levelOrdinal: levelOrdinalOf(content, active.profile.currentLevelId),
      installId: ref.watch(installIdProvider),
      inventory: snapshot.graphemeInventory,
      levels: content.levels,
      audioService: ref.watch(audioServiceProvider),
      phonemeAudioRefs: ref.watch(phonemeAudioRefsProvider),
      downloadedExampleWordAudioRefs: snapshot.downloadedExampleWordAudioRefs,
      echoEngine: ref.watch(sharedAsrEngineProvider),
      buildScorer: _buildScorer,
      onAnalyticsEvent: (event) => _record(analytics, event),
    );
  }

  /// One card's echo scorer: the card's own phoneme sequence, with its first
  /// phoneme as the drilled target (a grapheme card has no authored
  /// `targetPhonemeId`, so the shell supplies the obvious one).
  SoundModeScorer _buildScorer(GraphemeSound card) => SoundModeScorer(
        targetPhonemeSequence: card.phonemeIds,
        targetPhonemeId: card.phonemeIds.isEmpty ? '' : card.phonemeIds.first,
      );
}

// ===========================================================================
// Tongue-twister booster (Unit 14)
// ===========================================================================

/// Hosts [TwisterScreen] over one [TwisterController] attempt.
class TwisterRoute extends ConsumerStatefulWidget {
  const TwisterRoute({super.key, required this.twisterId});

  final String twisterId;

  @override
  ConsumerState<TwisterRoute> createState() => _TwisterRouteState();
}

class _TwisterRouteState extends ConsumerState<TwisterRoute> {
  TwisterController? _controller;
  TongueTwister? _twister;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final active = ref.read(activeProfileProvider);
    if (active == null) return;
    final snapshot = await ref.read(contentSnapshotProvider.future);
    if (!mounted) return;
    final twister = snapshot.twisterById(widget.twisterId);
    if (twister == null) return;
    setState(() {
      _twister = twister;
      _controller = _buildController(twister, active);
    });
  }

  TwisterController _buildController(
    TongueTwister twister,
    ActiveProfile active,
  ) {
    final analytics = ref.read(analyticsClientProvider);
    return TwisterController(
      twister: twister,
      engine: ref.read(sharedAsrEngineProvider),
      audioService: ref.read(audioServiceProvider),
      twisterProgressDao: ref.read(appDatabaseProvider).twisterProgressDao,
      profileId: active.profile.localId,
      micConsent: active.profile.micConsent,
      installId: ref.read(installIdProvider),
      profileOrdinal: active.ordinal,
      levelOrdinal: levelOrdinalOf(
        ref.read(phonicsContentProvider),
        active.profile.currentLevelId,
      ),
      onAnalyticsEvent: (event) => _record(analytics, event),
      clock: ref.read(clockProvider),
    );
  }

  /// One optional "faster" replay round: a fresh controller for the same
  /// twister, since a controller models exactly one attempt (Unit 14).
  Future<void> _runFasterPass() async {
    final active = ref.read(activeProfileProvider);
    final twister = _twister;
    if (active == null || twister == null) return;
    await _buildController(twister, active).start();
  }

  @override
  void dispose() {
    _controller?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const _RouteLoading();
    return TwisterScreen(
      controller: controller,
      runFasterPass: _runFasterPass,
      onExit: () => context.go(kRoutePathMap),
    );
  }
}

// ===========================================================================
// Parent corner (gated)
// ===========================================================================

/// Hosts [ParentCornerScreen] — which *is* the gate: it renders the real
/// parental gate (hold two opposite corners, then a multiplication challenge,
/// A-4) and swaps in the corner's contents only after an unlock. The shell
/// adds no bypass of any kind.
class ParentCornerRoute extends ConsumerWidget {
  const ParentCornerRoute({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ParentCornerScreen(
      db: ref.watch(appDatabaseProvider),
      phonicsContent: ref.watch(phonicsContentProvider),
      cloudEngineInUse: ref.watch(cloudEngineInUseProvider),
    );
  }
}

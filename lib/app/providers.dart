/// The app shell's composition seams (PRD §8 Unit 1 shell half, §9 A-2;
/// ticket `app-shell`).
///
/// This file performs **no feature logic of its own**. Every provider here
/// either (a) names an environment seam the app is built over — storage,
/// content, audio, speech recognition, the clock, analytics transport — or
/// (b) composes two already-merged units together. Swapping any one of them
/// is a one-line `overrideWithValue`, which is what makes the whole app
/// drivable headlessly by `test/app/`.
///
/// ## The seams an owner / skinning / platform pass touches
///
/// | seam | production value | why it is a seam |
/// | --- | --- | --- |
/// | [databaseExecutorProvider] | file-backed `NativeDatabase` under the app documents directory | tests substitute `NativeDatabase.memory()` |
/// | [starterPackProvider] | the bundled starter pack (A-9), loaded from disk | owner content; tests build one in a temp directory |
/// | [packInstallerProvider] | the installed-packs directory | tests point it at an empty temp directory ("fresh install") |
/// | [phonicsContentProvider] | the authored scope & sequence JSON | authored content (OQ-5) |
/// | [audioServiceProvider] | **not yet implemented** — see the provider's doc | the just_audio adapter is an owner/[DEVICE] task |
/// | [asrEngineProvider] | **not yet implemented** — see the provider's doc | THE engine-selection seam (A-10 / cloud / fake) |
/// | [micPermissionServiceProvider] | **not yet implemented** — platform permission plugin | consent gating sits above it |
/// | [phonemeAudioRefsProvider] | the shipped phoneme clip map | owner-recorded content |
/// | [installIdProvider] | a per-install UUID persisted next to the database | never a device identifier (§5) |
/// | [clockProvider] | [systemClock] | drives the 120 s session timeout and the 30-day queue expiry |
/// | [analyticsTransportProvider] | `NullAnalyticsTransport` until the endpoint exists (OQ-6) | A-5 self-hosted endpoint |
/// | [analyticsStorageDirectoryProvider] | the app support directory | file ownership stays disjoint from user data |
/// | [catalogFetcherProvider] | `null` until the CDN base URL exists (OQ-6) | the launch catalog check degrades silently |
/// | [storyStageFactoryProvider] | [FakeStoryStage] | no licensed Rive asset exists in this container; swap in `RiveStoryStage` |
/// | [celebrationVoiceLineRefsProvider] / [yourTurnPromptAudioRefProvider] / [nearMissPromptAudioRefProvider] / [kNavVoicePromptRefs] | placeholder refs | owner-recorded voice content — refs only |
///
/// ## Paragraph scoping (ORCHESTRATOR-PINNED)
///
/// A reading session runs **one [ReadingTracker] per page**: the tracker's
/// `sentence` is that page's word tokens, its biasing context is those same
/// words, and every index on the pinned tracker event stream is therefore
/// *page-relative* — exactly the indexing `WordStateMachine` already applies
/// events with. When the child TURNS a completed page (the ratified
/// page-turn hold, PRD §8 Unit 5 / mockup-spec §8) the finished page's
/// tracker is stopped and a fresh one is built for the next page —
/// [ReadingSession.advancePage], wired to the reading screen's turn path.
/// [ReadingSession] owns that rebuild behind one stable
/// [ReadingTrackerHandle], so the reading screen (which subscribes to the
/// handle once, on open) never sees the swap.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' show LazyDatabase, QueryExecutor;
import 'package:drift/native.dart' show NativeDatabase;
import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:learn_to_read/data/content/catalog_client.dart';
import 'package:learn_to_read/data/content/content_repository.dart';
import 'package:learn_to_read/data/content/pack_installer.dart';
import 'package:learn_to_read/data/content/pack_loader.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/design/fake_rive_stage.dart';
import 'package:learn_to_read/design/rive_stage.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/domain/phonics/scope_sequence_loader.dart';
import 'package:learn_to_read/features/analytics/analytics_client.dart';
import 'package:learn_to_read/features/analytics/event_queue.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/analytics/session_tracker.dart';
import 'package:learn_to_read/features/analytics/transport.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/audio/phoneme_sequencer.dart';
import 'package:learn_to_read/features/celebration/celebration_controller.dart';
import 'package:learn_to_read/features/help/help_recorder.dart';
import 'package:learn_to_read/features/help/near_miss_prompt.dart';
import 'package:learn_to_read/features/help/sound_out_sequence.dart';
import 'package:learn_to_read/features/help/stuck_word_controller.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/contracts/fake_asr_engine.dart';
import 'package:learn_to_read/features/listening/contracts/help_state.dart';
import 'package:learn_to_read/features/listening/contracts/tracker_events.dart';
import 'package:learn_to_read/features/listening/tracker/reading_tracker.dart';
import 'package:learn_to_read/features/parent/consent_controller.dart';
import 'package:learn_to_read/features/reading/reading_controller.dart';
import 'package:learn_to_read/features/reading/reading_screen.dart' show kNoHelp;

// ===========================================================================
// Storage
// ===========================================================================

/// File name of the device-local Drift database.
const String kAppDatabaseFileName = 'learn_to_read.sqlite';

/// The Drift executor [appDatabaseProvider] is composed over.
///
/// Production is a lazily-opened, file-backed SQLite database in the app
/// documents directory; every suite in `test/app/` overrides this with
/// `NativeDatabase.memory()` and nothing else changes.
final Provider<QueryExecutor> databaseExecutorProvider =
    Provider<QueryExecutor>((ref) {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    return NativeDatabase.createInBackground(
      _fileIn(directory.path, kAppDatabaseFileName),
    );
  });
});

/// The app's single Drift database, composed over
/// [databaseExecutorProvider].
final Provider<AppDatabase> appDatabaseProvider = Provider<AppDatabase>(
  (ref) => AppDatabase(ref.watch(databaseExecutorProvider)),
);

// ===========================================================================
// Content (PRD §8 Unit 11, §6 Offline, A-9)
// ===========================================================================

/// The starter pack that ships inside the binary (A-9) — never downloaded,
/// always present. Supplied by `main()`; owner content.
final Provider<LoadedPack> starterPackProvider = Provider<LoadedPack>((ref) {
  throw StateError(
    'starterPackProvider has no default: the bundled starter pack is owner '
    'content and is supplied by main() (or by a test override).',
  );
});

/// Where downloaded CDN packs are installed. Supplied by `main()`.
final Provider<PackInstaller> packInstallerProvider =
    Provider<PackInstaller>((ref) {
  throw StateError(
    'packInstallerProvider has no default: the installed-packs directory is '
    'resolved at boot by main() (or by a test override).',
  );
});

/// The app's single read surface over starter + installed content.
final Provider<ContentRepository> contentRepositoryProvider =
    Provider<ContentRepository>(
  (ref) => ContentRepository(
    starterPack: ref.watch(starterPackProvider),
    installer: ref.watch(packInstallerProvider),
  ),
);

/// The authored scope & sequence (PRD §8 Unit 2: "stored as data, not
/// code"). Supplied by `main()`; authored content (OQ-5).
final Provider<PhonicsContent> phonicsContentProvider =
    Provider<PhonicsContent>((ref) {
  throw StateError(
    'phonicsContentProvider has no default: the scope & sequence is authored '
    'content loaded at boot by main() (or by a test override).',
  );
});

/// Everything the child-facing screens read out of content, loaded once.
///
/// Merging installed packs is a handful of small file reads, so this is a
/// launch-time snapshot rather than a per-screen query; invalidate the
/// provider after installing a pack to pick it up without a restart.
class ContentSnapshot {
  const ContentSnapshot({
    required this.stories,
    required this.twisters,
    required this.vocabCards,
    required this.collectibles,
    required this.graphemeInventory,
  });

  final List<Story> stories;
  final List<TongueTwister> twisters;
  final List<VocabCard> vocabCards;
  final List<Collectible> collectibles;
  final List<GraphemeSound> graphemeInventory;

  /// The story with [id], or null when no installed pack carries it.
  Story? storyById(String id) {
    for (final story in stories) {
      if (story.id == id) return story;
    }
    return null;
  }

  /// The twister with [id], or null.
  TongueTwister? twisterById(String id) {
    for (final twister in twisters) {
      if (twister.id == id) return twister;
    }
    return null;
  }

  /// Every example-word pronunciation ref that actually resolved on disk.
  ///
  /// [ContentRepository.graphemeInventory] has already dropped the words it
  /// has no audio for, so the surviving refs *are* the downloaded set the
  /// Sound Garden filters against (Unit 15: "shows only words it has audio
  /// for").
  Set<AudioRef> get downloadedExampleWordAudioRefs => <AudioRef>{
        for (final card in graphemeInventory)
          for (final word in card.exampleWords) word.pronunciationAudioRef,
      };
}

/// The launch-time content snapshot every child-facing route renders from.
final FutureProvider<ContentSnapshot> contentSnapshotProvider =
    FutureProvider<ContentSnapshot>((ref) async {
  final repository = ref.watch(contentRepositoryProvider);
  return ContentSnapshot(
    stories: await repository.stories(),
    twisters: await repository.twisters(),
    vocabCards: await repository.vocabCards(),
    collectibles: await repository.collectibles(),
    graphemeInventory: await repository.graphemeInventory(),
  );
});

// ===========================================================================
// Audio (PRD §8 Unit 13)
// ===========================================================================

/// Where every clip in the app is played.
///
/// **Owner/[DEVICE] seam.** No platform playback adapter exists in this
/// container (the `just_audio` adapter is a device-verified task), so the
/// default is the headless [FakeAudioService] — the app boots and every
/// audio call is recorded rather than heard. Replace with the real adapter
/// through this one override.
final Provider<AudioService> audioServiceProvider =
    Provider<AudioService>((ref) => FakeAudioService());

/// Phoneme id -> shipped clip ref, for sound-out help and Sound Garden
/// cards. Owner-recorded content; empty until the recordings ship.
final Provider<Map<String, AudioRef>> phonemeAudioRefsProvider =
    Provider<Map<String, AudioRef>>((ref) => const <String, AudioRef>{});

/// The recorded celebration voice lines, rotated per story (Unit 8).
/// Owner-recorded content — refs only.
final Provider<List<AudioRef>> celebrationVoiceLineRefsProvider =
    Provider<List<AudioRef>>(
  (ref) => const <AudioRef>[
    'audio/celebration/line-1.wav',
    'audio/celebration/line-2.wav',
    'audio/celebration/line-3.wav',
  ],
);

/// The authored "your turn" line Tier 2 plays after modelling a word
/// (Unit 6). Owner-recorded content — ref only.
final Provider<AudioRef> yourTurnPromptAudioRefProvider =
    Provider<AudioRef>((ref) => 'audio/help/your-turn.wav');

/// The authored warm near-miss prompt line (Unit 6). Owner-recorded content
/// — ref only.
final Provider<AudioRef> nearMissPromptAudioRefProvider =
    Provider<AudioRef>((ref) => 'audio/help/near-miss.wav');

/// Builds the [StoryStage] a story/collectible animates on.
///
/// **Owner/[DEVICE] seam.** No licensed Rive artboard exists in this
/// container, so the default is [FakeStoryStage]; a device build overrides
/// this with a factory returning `RiveStoryStage` over the loaded artboard.
/// Nothing in the app branches on which one it got — `StoryStage` is the
/// whole contract (PRD §8 Unit 8).
final Provider<StoryStage Function()> storyStageFactoryProvider =
    Provider<StoryStage Function()>((ref) => FakeStoryStage.new);

// ===========================================================================
// Listening (PRD §8 Unit 4, §9 A-10; ticket validator note)
// ===========================================================================

/// **THE ASR ENGINE SELECTION SEAM.**
///
/// Swapping the recognizer — platform on-device (A-10), a metered cloud
/// engine, or a scripted fake — is a one-line override of this provider and
/// nothing else. Consent gating sits *above* it: with `micConsent == false`
/// the shell hands `micConsent: false` to `ReadingTracker`, which never
/// calls `engine.start` at all and never asks the OS for the microphone.
///
/// **Owner seam.** `PlatformAsrEngine` does not exist yet (its ticket is
/// blocked on the Unit 0 spike verdict), so the default is an engine that
/// produces no hypotheses — i.e. the app ships tap-only until that one-line
/// override lands.
final Provider<AsrEngine> asrEngineProvider =
    Provider<AsrEngine>((ref) => FakeAsrEngine(script: const <Hypothesis>[]));

/// The engine every listening session actually runs on: [asrEngineProvider]
/// normalized so its hypothesis stream is subscribed **once**.
///
/// `ReadingTracker` reads `engine.hypothesesStream` on every start, resume
/// and A-7 downgrade. A real platform engine hands back the same long-lived
/// stream each time; an engine that *generates* a stream per access would
/// replay its whole history on every vocabulary card and every narration
/// replay. This adapter makes the seam behave the way the tracker's contract
/// assumes, so engine substitution stays a one-line override.
final Provider<AsrEngine> sharedAsrEngineProvider = Provider<AsrEngine>((ref) {
  final engine = SharedHypothesisAsrEngine(ref.watch(asrEngineProvider));
  ref.onDispose(engine.dispose);
  return engine;
});

/// The OS microphone-permission prompt.
///
/// **Owner seam.** No permission plugin is wired yet, so the default answers
/// [MicPermissionStatus.notDetermined] — which [resolveReadingMode] turns
/// into tap-only, the safe direction.
final Provider<MicPermissionService> micPermissionServiceProvider =
    Provider<MicPermissionService>(
  (ref) => FakeMicPermissionService(MicPermissionStatus.notDetermined),
);

/// Whether a cloud speech engine is in use at all (PRD §8 Unit 10: the
/// cloud-processing toggle only appears when one is).
final Provider<bool> cloudEngineInUseProvider = Provider<bool>((ref) => false);

/// Wraps an [AsrEngine] so its [hypothesesStream] is subscribed exactly once
/// and re-broadcast to every consumer. See [sharedAsrEngineProvider].
class SharedHypothesisAsrEngine implements AsrEngine {
  SharedHypothesisAsrEngine(this._delegate);

  final AsrEngine _delegate;
  StreamController<Hypothesis>? _controller;
  StreamSubscription<Hypothesis>? _subscription;

  @override
  void start(List<String> biasingContext) => _delegate.start(biasingContext);

  @override
  void stop() => _delegate.stop();

  @override
  Stream<Hypothesis> get hypothesesStream {
    final existing = _controller;
    if (existing != null) return existing.stream;
    // Reading the delegate's stream can throw — that is the "microphone
    // unavailable" shape `ReadingTracker`'s fallback chain is built around,
    // so it propagates untouched and the tracker degrades to tap.
    final source = _delegate.hypothesesStream;
    final controller = StreamController<Hypothesis>.broadcast();
    _controller = controller;
    _subscription = source.listen(
      controller.add,
      onError: controller.addError,
      onDone: () => unawaited(controller.close()),
    );
    return controller.stream;
  }

  /// Releases the single upstream subscription.
  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    final controller = _controller;
    _controller = null;
    if (controller != null && !controller.isClosed) {
      unawaited(controller.close());
    }
  }
}

// ===========================================================================
// Analytics (PRD §5, §8 Unit 12)
// ===========================================================================

/// The random per-install UUID stamped on every §5 event. Never a device
/// identifier. Supplied by `main()` from durable storage.
final Provider<String> installIdProvider = Provider<String>((ref) {
  throw StateError(
    'installIdProvider has no default: the per-install UUID is read from (or '
    'created in) durable storage at boot by main() (or by a test override).',
  );
});

/// The app's clock. Drives the 120 s session timeout, the 30-day analytics
/// queue expiry, and the §4.4 help-recency window.
final Provider<Clock> clockProvider = Provider<Clock>((ref) => systemClock);

/// Where analytics batches go (A-5: a self-controlled HTTPS endpoint).
///
/// The endpoint URL is OQ-6 and blocks pilot distribution, not build, so the
/// default drops batches rather than accumulating them forever.
final Provider<AnalyticsTransport> analyticsTransportProvider =
    Provider<AnalyticsTransport>((ref) => const NullAnalyticsTransport());

/// Where the offline analytics queue file lives — deliberately disjoint from
/// the Drift user database. Supplied by `main()`.
final Provider<Directory> analyticsStorageDirectoryProvider =
    Provider<Directory>((ref) {
  throw StateError(
    'analyticsStorageDirectoryProvider has no default: the queue directory is '
    'resolved at boot by main() (or by a test override).',
  );
});

/// The durable, offline-first analytics queue.
final Provider<EventQueue> eventQueueProvider = Provider<EventQueue>(
  (ref) => EventQueue(
    transport: ref.watch(analyticsTransportProvider),
    clock: ref.watch(clockProvider),
    storageDirectory: ref.watch(analyticsStorageDirectoryProvider),
  ),
);

/// The single entry point every screen records analytics through — and the
/// single place the `DISABLE_ANALYTICS` kill switch takes effect.
final Provider<AnalyticsClient> analyticsClientProvider =
    Provider<AnalyticsClient>(
  (ref) => AnalyticsClient(
    enabled: kAnalyticsEnabled,
    queue: ref.watch(eventQueueProvider),
  ),
);

/// Records one event, fire-and-forget.
///
/// Handed to [Zone.root] exactly as `ReadingController._track` and
/// `VocabCardHostState.open` do: analytics is background I/O and a queued
/// write must always drain on the real event loop rather than being stranded
/// by whatever zone the caller happens to be running in.
void _record(AnalyticsClient analytics, AnalyticsEvent event) {
  Zone.root.run(
    () => unawaited(
      // Analytics must never crash a child's reading session.
      analytics.track(event).catchError((Object _, StackTrace __) {}),
    ),
  );
}

/// Session boundaries and story-abandonment detection (PRD §8 Unit 12).
///
/// The shell drives it: [ActiveProfileController.select] starts a session,
/// [ActiveProfileController.clear] ends one, and `LearnToReadApp`'s lifecycle
/// observer reports background/foreground/close.
final Provider<SessionTracker> sessionTrackerProvider =
    Provider<SessionTracker>((ref) {
  final analytics = ref.watch(analyticsClientProvider);
  return SessionTracker(
    clock: ref.watch(clockProvider),
    installId: ref.watch(installIdProvider),
    onEvent: (event) => _record(analytics, event),
  );
});

/// Dispenses the recorded celebration voice lines in shuffle-cycle order, so
/// no two consecutive stories end with the same line (PRD §8 Unit 8).
final Provider<CelebrationLineRotator> celebrationLineRotatorProvider =
    Provider<CelebrationLineRotator>(
  (ref) => CelebrationLineRotator(
    lines: ref.watch(celebrationVoiceLineRefsProvider),
    nextInt: Random().nextInt,
  ),
);

// ===========================================================================
// Launch catalog check (PRD §8 Unit 11, §6 Offline)
// ===========================================================================

/// Fetches `catalog.json` over the network.
///
/// Null until the CDN base URL exists (OQ-6) — with no fetcher the launch
/// check resolves to a failure result rather than throwing or hanging.
final Provider<CatalogFetcher?> catalogFetcherProvider =
    Provider<CatalogFetcher?>((ref) => null);

/// This build's version, compared against each catalog entry's
/// `minAppVersion`.
final Provider<String> appVersionProvider =
    Provider<String>((ref) => kAppVersion);

/// The app version this build reports to the catalog.
const String kAppVersion = '0.1.0';

/// The launch-time catalog check (PRD §8 Unit 11 "online: catalog checked in
/// the background").
///
/// Fire-and-forget by construction: `LearnToReadApp` kicks it off at boot and
/// nothing the child can see depends on it. Failure — airplane mode, a
/// captive portal, a half-understood catalog — is silent, because
/// `ContentRepository` never consults the network at all (§6 Offline).
final FutureProvider<CatalogFetchResult> launchCatalogCheckProvider =
    FutureProvider<CatalogFetchResult>((ref) async {
  final fetcher = ref.watch(catalogFetcherProvider);
  if (fetcher == null) return const CatalogFetchResult.failure();
  return CatalogClient(fetcher: fetcher)
      .checkCatalog(currentAppVersion: ref.watch(appVersionProvider));
});

// ===========================================================================
// The active profile — the thing every child-facing route hangs off
// ===========================================================================

/// The profile currently reading, plus its **1-based** ordinal within the
/// picker (§5: "profile ordinal (1-4)"; never a profile id or name).
class ActiveProfile {
  const ActiveProfile({required this.profile, required this.ordinal});

  final Profile profile;
  final int ordinal;
}

/// Selecting a profile is what starts an analytics session (PRD §8 Unit 12)
/// and what unlocks every child-facing route (see `router.dart`'s redirect).
class ActiveProfileController extends Notifier<ActiveProfile?> {
  @override
  ActiveProfile? build() => null;

  /// Enters [profile]'s home and opens their session.
  ///
  /// The session is started *before* the state change so `session_start` is
  /// the first event queued for this child, ahead of anything the map or the
  /// reading screen goes on to record.
  void select(Profile profile, int ordinal) {
    final levelOrdinal = levelOrdinalOf(
      ref.read(phonicsContentProvider),
      profile.currentLevelId,
    );
    ref.read(sessionTrackerProvider).startSession(
          profileOrdinal: ordinal,
          levelOrdinal: levelOrdinal,
        );
    state = ActiveProfile(profile: profile, ordinal: ordinal);
  }

  /// Leaves the child's home and ends their session (profile switch, or the
  /// app closing).
  void clear() {
    ref.read(sessionTrackerProvider).onClose();
    state = null;
  }

  /// Replaces the active profile's row in place — used when level
  /// advancement or a consent change rewrites it. Never starts or ends a
  /// session.
  void replaceProfile(Profile profile) {
    final current = state;
    if (current == null || current.profile.localId != profile.localId) return;
    state = ActiveProfile(profile: profile, ordinal: current.ordinal);
  }
}

/// The active profile, or null on the picker.
final NotifierProvider<ActiveProfileController, ActiveProfile?>
    activeProfileProvider =
    NotifierProvider<ActiveProfileController, ActiveProfile?>(
  ActiveProfileController.new,
);

// ===========================================================================
// Small shared derivations
// ===========================================================================

/// The [Level] with [levelId], or null when the scope & sequence has none.
Level? levelById(PhonicsContent content, String levelId) {
  for (final level in content.levels) {
    if (level.id == levelId) return level;
  }
  return null;
}

/// The §5 `levelOrdinal` for [levelId]; 1 when the level is unknown (the
/// schema requires a positive int, and a missing level is a content bug that
/// must not take analytics down with it).
int levelOrdinalOf(PhonicsContent content, String levelId) =>
    levelById(content, levelId)?.ordinal ?? 1;

/// Levels whose tongue-twister booster this profile has reached: every level
/// at or below their current one (Unit 14 — boosters are level-tagged).
Set<String> unlockedTwisterLevelIds(PhonicsContent content, Profile profile) {
  final currentOrdinal = levelOrdinalOf(content, profile.currentLevelId);
  return <String>{
    for (final level in content.levels)
      if (level.ordinal <= currentOrdinal) level.id,
  };
}

// ===========================================================================
// One reading session: the paragraph-scoped tracker + the help scaffold
// ===========================================================================

/// One story read, composed: the paragraph-scoped [ReadingTracker]s, the
/// Unit 6 [StuckWordController] over them, and the one stable
/// [ReadingTrackerHandle] the reading screen subscribes to.
///
/// ## Why the tracker is per page
///
/// `WordStateMachine` applies every tracker index against the *current
/// page*, so a tracker scoped to the whole story would mis-address words the
/// moment a story turned a page. One tracker per page keeps indices
/// page-relative and keeps the engine's biasing context (PRD §6: "never
/// open-ended transcription") to exactly the words on screen.
///
/// ## Why both T1 triggers stay live
///
/// `ReadingTracker` owns T1 detection (A-12b) and emits `Silence(T1)` then
/// `StruggleDetected`; `StuckWordController` carries its own T1 timer, armed
/// from every `watchWord`. Both are wired, and Tier 1 is idempotent across
/// them — it starts once, from whichever signal lands first (see
/// docs/stuck-word-scaffold.md).
class ReadingSession implements ReadingTrackerHandle {
  ReadingSession({
    required this.pages,
    required AsrEngine engine,
    required bool micConsent,
    required AudioService audioService,
    required Map<String, AudioRef> phonemeAudioRefs,
    required HelpRecorderApi helpRecorder,
    required AudioRef yourTurnPromptAudioRef,
    required AudioRef nearMissPromptAudioRef,
    required void Function(int index, HelpLevel tier) onHelpGiven,
  })  : _engine = engine,
        _micConsent = micConsent {
    _scaffold = StuckWordController(
      events: _events.stream,
      soundOutSequence: SoundOutSequence(
        phonemeSequencer: PhonemeSequencer(
          audioService: audioService,
          phonemeAudioRefs: phonemeAudioRefs,
        ),
      ),
      audioService: audioService,
      nearMissPrompt: NearMissPrompt(
        audioService: audioService,
        promptLineAudioRef: nearMissPromptAudioRef,
      ),
      helpRecorder: helpRecorder,
      yourTurnPromptAudioRef: yourTurnPromptAudioRef,
      onHelpGiven: onHelpGiven,
      // Help audio plays over the same open microphone the child reads
      // into, so every help pass (Tier 1 sound-out, Tier 2's model +
      // "your turn", the near-miss prompt) brackets recognition with the
      // session's own pause/resume — the same tracker verbs the narration
      // replay and the on-demand sound-out already use. Without this the
      // recognizer can hear Tier 2 model the target word and self-accept
      // it, and Tier 1's phoneme bursts feed the tracker's A-12
      // non-matching-burst counter. Escalation timing is untouched: T1->T2
      // runs on the scaffold's own timers, and the tracker's silence
      // detector (disarmed while paused, restarted fresh on resume) only
      // ever *enters* Tier 1, which has already fired by the time any help
      // audio plays.
      pauseListening: pause,
      resumeListening: resume,
    );
    _helpStateSub = _scaffold.helpState.listen((state) {
      if (!_disposed) helpState.value = state;
    });
    _wordHelpedSub = _scaffold.wordHelpedStream.listen((event) {
      if (!_disposed) _tracker?.helpCompleted(event.tier);
    });
  }

  /// Every page of the story, flattened to word tokens — the same shape
  /// `ReadingController` derives for the state machine.
  final List<List<WordToken>> pages;

  final AsrEngine _engine;
  final bool _micConsent;

  /// The one stable event stream the reading screen subscribes to. Sync
  /// delivery, so a tap resolves in the same turn as the gesture and the
  /// help scaffold sees an event before the cursor advances past it.
  final StreamController<TrackerEvent> _events =
      StreamController<TrackerEvent>.broadcast(sync: true);

  late final StuckWordController _scaffold;
  StreamSubscription<HelpState>? _helpStateSub;
  StreamSubscription<WordHelped>? _wordHelpedSub;
  StreamSubscription<TrackerEvent>? _trackerSub;

  /// The Unit 6 help tier and grapheme highlight the reading screen renders.
  final ValueNotifier<HelpState> helpState = ValueNotifier<HelpState>(kNoHelp);

  ReadingTracker? _tracker;
  int _pageIndex = 0;
  bool _started = false;
  bool _stopped = false;
  bool _disposed = false;

  /// True while a tracker event is being delivered synchronously.
  ///
  /// `ReadingTracker` publishes on a *sync* broadcast controller and
  /// `ReadingController` calls `tracker.stop()` on the very event that
  /// resolves the last word — which would close that controller from inside
  /// its own emission and throw. Both behaviours are pinned by their own
  /// units, so composing them is this shell's problem: the stop is deferred
  /// by exactly one microtask, and nothing observable moves.
  bool _forwarding = false;

  /// Opens the session on the story's first page.
  ///
  /// Called by the shell *before* the reading screen is pushed (the pinned
  /// lifecycle in docs/reading-screen.md): the screen only ever `resume()`s
  /// the session it was handed, which is what makes listen-first possible.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _openPage(0);
  }

  void _openPage(int pageIndex) {
    _pageIndex = pageIndex;
    final words = _wordsOf(pageIndex);
    final tracker = ReadingTracker(
      engine: _engine,
      sentence: words,
      micConsent: _micConsent,
    );
    _tracker = tracker;
    _trackerSub = tracker.eventsStream.listen(_forward);
    tracker.start();
    if (words.isNotEmpty) {
      _scaffold.watchWord(index: 0, word: words.first);
    }
  }

  List<WordToken> _wordsOf(int pageIndex) =>
      pageIndex >= 0 && pageIndex < pages.length
          ? pages[pageIndex]
          : const <WordToken>[];

  /// Republishes one tracker event on the stable stream, then advances the
  /// help scaffold's watched word.
  ///
  /// Order is load-bearing: `_events.add` is synchronous, so the scaffold
  /// (and the reading screen) have fully processed the event — including
  /// resolving the word it accepted — before the cursor moves on.
  void _forward(TrackerEvent event) {
    if (_disposed) return;
    _forwarding = true;
    try {
      if (!_events.isClosed) _events.add(event);
    } finally {
      _forwarding = false;
    }
    final resolvedIndex = _resolvedIndexOf(event);
    if (resolvedIndex == null) return;
    final words = _wordsOf(_pageIndex);
    final next = resolvedIndex + 1;
    if (next < words.length) {
      _scaffold.watchWord(index: next, word: words[next]);
      return;
    }
    // The page is finished. The word state machine HOLDS here (page-turn
    // hold, PRD §8 Unit 5 / mockup-spec §8, owner-confirmed 2026-07-28;
    // amended 2026-07-29: every page holds, the final one included), so
    // nothing advances at resolution time. On a NON-final page the finished
    // page's tracker stays open (listening is uninterrupted, and a
    // completed tracker is quiescent — its matcher is complete, so
    // silence/struggle timers are disarmed) until the child's turn gesture
    // reaches [advancePage]. On the FINAL page the reading controller calls
    // [stop] on this very event — the mic closes at resolution time, and
    // the dog-ear waits visually for the story-closing turn.
  }

  int? _resolvedIndexOf(TrackerEvent event) => switch (event) {
        WordAccepted(:final index) => index,
        WordAcceptedNearMiss(:final index) => index,
        WordHelped(:final index) => index,
        _ => null,
      };

  /// Moves the listening session onto the next page: stops the finished
  /// page's tracker and opens a fresh one scoped to the new page's words.
  ///
  /// Called at TURN time — the shell wires it to the reading screen's
  /// `onPageTurned`, which fires when the child completes the page-curl
  /// gesture (PRD §8 Unit 5 page-turn hold) — never at resolution time, so
  /// the session and the word state machine advance together and exactly
  /// once. No-op after [stop]/[dispose] or when there is no next page.
  void advancePage() {
    if (_disposed || _stopped) return;
    if (_pageIndex + 1 >= pages.length) return;
    _closeTracker();
    _openPage(_pageIndex + 1);
  }

  void _closeTracker() {
    unawaited(_trackerSub?.cancel());
    _trackerSub = null;
    final tracker = _tracker;
    _tracker = null;
    if (tracker == null) return;
    if (_forwarding) {
      scheduleMicrotask(tracker.stop);
    } else {
      tracker.stop();
    }
  }

  // --- ReadingTrackerHandle -------------------------------------------------

  @override
  Stream<TrackerEvent> get eventsStream => _events.stream;

  @override
  bool get isListening => _tracker?.isListening ?? false;

  @override
  void pause() => _tracker?.pause();

  @override
  void resume() => _tracker?.resume();

  @override
  void stop() {
    _stopped = true;
    _closeTracker();
  }

  @override
  void tapCurrentWord() => _tracker?.tapCurrentWord();

  /// Ends the session for good: no microphone session, help timer, or
  /// stream outlives the screen that opened it.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _closeTracker();
    _scaffold.dispose();
    unawaited(_helpStateSub?.cancel());
    unawaited(_wordHelpedSub?.cancel());
    helpState.dispose();
    if (!_events.isClosed) unawaited(_events.close());
  }
}

// ===========================================================================
// Boot helpers used by main()
// ===========================================================================

/// A v4 UUID in the §5 `installId` shape, drawn from [random].
String generateInstallId(Random random) {
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int start, int end) => bytes
      .sublist(start, end)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}

File _fileIn(String directoryPath, String name) =>
    File(p.join(directoryPath, name));

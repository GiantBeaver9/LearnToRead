/// The celebration sequence controller (PRD §8 Unit 8 "Celebration: story
/// animation & audio"; ticket celebration-sequence).
///
/// Drives the post-completion payoff (RECALIBRATED 2026-07-29, PRD §8
/// Unit 8): fires `celebrate` on the story's [StoryStage], then -- when the
/// story has narration -- plays the narrated read-back of EVERY sentence of
/// the story, in order, sequentially (each clip starts when the previous
/// completes) over the celebrate animation. The celebration payoff (the
/// fixed sting + one rotated recorded voice line + the `collect` trigger)
/// waits for the read-back to finish instead of running concurrently;
/// stories without narration keep the immediate payoff. Completion +
/// collectible are persisted durably before the skip window even opens,
/// and -- after the animation-hold phase ends (read-back finished, natural
/// duration elapsed, or an accepted skip) -- the controller fires `collect`
/// and hands back to the caller via [CelebrationController.run]'s
/// `onFinished` callback once the collectible-flight token has elapsed.
///
/// [CelebrationController] depends on nothing but the [StoryStage]
/// interface -- any implementation works, and the controller never branches
/// on which story it is celebrating (PRD §8 Unit 8's Rive contract: every
/// artboard exposes the same `idle`/`celebrate`/`collect` inputs; this
/// ticket assumes that contract holds -- validating it is Unit 3's
/// pack-build linter, not a runtime concern here).
library;

import 'dart:async';

import 'package:learn_to_read/data/db/daos/collection_dao.dart';
import 'package:learn_to_read/data/db/daos/story_progress_dao.dart';
import 'package:learn_to_read/design/rive_stage.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/analytics/events.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';

/// How long into the sequence a tap first becomes able to skip the
/// animation-hold phase (PRD §8 Unit 8: "skippable by tap after the first
/// 2 s"). A tap before this elapses is silently ignored.
const Duration kCelebrationSkipUnlockDelay = Duration(seconds: 2);

/// The hard ceiling on the total post-completion sequence (PRD §8 Unit 8:
/// "total post-completion sequence <= 10 s"), enforced structurally by the
/// [CelebrationController] constructor -- see its doc comment.
const Duration kCelebrationSequenceBudget = Duration(seconds: 10);

/// The default animation-hold duration when a run is not skipped.
const Duration kCelebrationDefaultAnimationDuration = Duration(seconds: 4);

/// Dispenses [AudioRef]s from a fixed recorded set in shuffle-cycle order
/// (PRD §8 Unit 8: "one recorded celebration voice line ... rotated
/// randomly so it doesn't repeat verbatim every story").
///
/// The set is shuffled exactly once, at construction, via a Fisher-Yates
/// shuffle driven by the injected [nextInt] (so the shuffle itself is
/// deterministic and testable); afterwards [next] simply cycles through
/// that fixed order forever. Every full cycle therefore replays the same
/// permutation -- which is what guarantees two consecutive dispenses never
/// repeat (for a set of two or more lines) -- without ever re-consulting
/// the RNG after construction.
class CelebrationLineRotator {
  CelebrationLineRotator({
    required List<AudioRef> lines,
    required int Function(int exclusiveMax) nextInt,
  }) : _lines = List.of(lines) {
    if (_lines.isEmpty) {
      throw ArgumentError.value(lines, 'lines', 'must not be empty');
    }
    // Fisher-Yates: for a single-line set the loop never runs, so nextInt
    // is never consulted -- a single line has nothing to shuffle.
    for (var i = _lines.length - 1; i > 0; i--) {
      final j = nextInt(i + 1);
      final swap = _lines[i];
      _lines[i] = _lines[j];
      _lines[j] = swap;
    }
  }

  final List<AudioRef> _lines;
  int _index = 0;

  /// Returns the next line in the shuffled rotation, wrapping back to the
  /// start (replaying the same order) once every line has been dispensed.
  AudioRef next() {
    final ref = _lines[_index];
    _index = (_index + 1) % _lines.length;
    return ref;
  }
}

/// The outcome of one [CelebrationController.run], handed to the
/// controller's `onFinished` callback once the full post-completion
/// sequence (animation hold + collectible flight) has ended.
class CelebrationResult {
  const CelebrationResult({
    required this.completedStoryId,
    required this.nextStoryId,
    required this.skipped,
    required this.isFirstCompletion,
  });

  /// The story that was just celebrated.
  final String completedStoryId;

  /// The next story to highlight on the map, or null when there is none
  /// (e.g. the last story in the library) -- carried through to the
  /// return-navigation payload.
  final String? nextStoryId;

  /// Whether the animation-hold phase ended early via an accepted
  /// [CelebrationController.skip] rather than running its natural
  /// duration.
  final bool skipped;

  /// Whether this run was the story's first-ever completion -- and
  /// therefore the run that granted the collectible and emitted
  /// `collectible_earned`. False on a replay of an already-completed
  /// story.
  final bool isFirstCompletion;
}

/// Drives one story's celebration sequence end to end (PRD §8 Unit 8;
/// RECALIBRATED 2026-07-29).
///
/// See the file-level doc comment for the overall contract. `run`'s
/// synchronous prefix -- `stage.trigger(celebrate)` plus either the FIRST
/// read-back clip's play (story with narration) or the sting + rotated
/// line (story without narration) -- executes in the same event-loop turn
/// as the call, before `run`'s first `await` suspends it. That is the
/// headless proxy for "the stage never does synchronous work over a frame
/// budget during the transition" (PRD §8 Unit 8 acceptance, [DEVICE] A-6's
/// real 60 fps measurement is owner/device-verified separately).
class CelebrationController {
  CelebrationController({
    required StoryStage stage,
    required AudioService audioService,
    required CollectionDao collectionDao,
    required StoryProgressDao storyProgressDao,
    required CelebrationLineRotator lineRotator,
    required String installId,
    required void Function(AnalyticsEvent event) onAnalyticsEvent,
    required void Function(CelebrationResult result) onFinished,
    Duration celebrationDuration = kCelebrationDefaultAnimationDuration,
    Duration skipUnlockDelay = kCelebrationSkipUnlockDelay,
    Duration sequenceBudget = kCelebrationSequenceBudget,
  })  : _stage = stage,
        _audioService = audioService,
        _collectionDao = collectionDao,
        _storyProgressDao = storyProgressDao,
        _lineRotator = lineRotator,
        _installId = installId,
        _onAnalyticsEvent = onAnalyticsEvent,
        _onFinished = onFinished,
        _celebrationDuration = celebrationDuration,
        _skipUnlockDelay = skipUnlockDelay,
        _sequenceBudget = sequenceBudget {
    if (_celebrationDuration + DesignTokens.collectibleFlightDuration > _sequenceBudget) {
      throw ArgumentError(
        'celebrationDuration ($_celebrationDuration) + '
        'DesignTokens.collectibleFlightDuration '
        '(${DesignTokens.collectibleFlightDuration}) exceeds sequenceBudget '
        '($_sequenceBudget) -- PRD §8 Unit 8 caps the total post-completion '
        'sequence at 10 s',
      );
    }
  }

  final StoryStage _stage;
  final AudioService _audioService;
  final CollectionDao _collectionDao;
  final StoryProgressDao _storyProgressDao;
  final CelebrationLineRotator _lineRotator;
  final String _installId;
  final void Function(AnalyticsEvent event) _onAnalyticsEvent;
  final void Function(CelebrationResult result) _onFinished;
  final Duration _celebrationDuration;
  final Duration _skipUnlockDelay;
  final Duration _sequenceBudget;

  bool _isRunning = false;

  /// The current run's animation-hold-phase completion signal, or null
  /// before a run has reached that phase / after it has already ended.
  /// Guards [skip] against acting before the hold phase starts or after it
  /// has already ended (naturally or via an earlier accepted skip).
  Completer<void>? _holdCompleter;

  /// True once [_skipUnlockDelay] has elapsed for the current run --
  /// [skip] can only end the hold phase early once this is true.
  bool _skipUnlocked = false;

  /// Whether the current run's hold phase ended via an accepted [skip]
  /// (surfaced on the eventual [CelebrationResult.skipped]).
  bool _skippedThisRun = false;

  /// True once the current run's narrated read-back has played every clip
  /// to natural completion. Consulted by [_runHoldPhase] so a read-back
  /// that finishes before the hold phase even starts (e.g. while
  /// persistence is still being awaited) still ends the hold immediately.
  bool _readbackDone = false;

  /// Set when the current run's hold phase has ended (naturally, via
  /// [skip], or via the sequence-budget ceiling) so the read-back chain
  /// stops starting new clips.
  bool _readbackCancelled = false;

  /// The read-back clip currently playing, if any -- stopped when the hold
  /// phase ends before the read-back does (skip or ceiling).
  PlaybackHandle? _activeNarrationHandle;

  /// Whether a run is currently in progress.
  bool get isRunning => _isRunning;

  /// Runs the full celebration sequence for [story]'s completion by the
  /// profile identified by [profileId] (used for persistence only --
  /// analytics never carries a raw profile id, only [profileOrdinal]).
  ///
  /// Order of operations (RECALIBRATED 2026-07-29; see the class doc
  /// comment for the synchronous prefix):
  ///  1. `stage.trigger(celebrate)`.
  ///  2. Narrated read-back, if [story] has any sentence carrying a
  ///     `narrationAudioRef`: EVERY such sentence's clip, in page/sentence
  ///     order, played sequentially (each clip starts when the previous
  ///     one completes, per `AudioService.completionOf`) over the
  ///     celebrate animation. The first clip's play is issued in the same
  ///     synchronous turn as the celebrate trigger. A clip that fails to
  ///     play is swallowed and the chain continues -- playback failures
  ///     never wedge the sequence.
  ///     For a story with NO narration, the payoff audio (sting + rotated
  ///     line, step 5) plays immediately instead -- unchanged behavior.
  ///  3. Story-progress + collectible persistence, and `story_completed` /
  ///     `collectible_earned` analytics, fully awaited *before* the
  ///     animation-hold phase begins (and therefore before [skip] can even
  ///     be actionable) -- so the collectible can never be lost to a skip.
  ///     The collectible is granted only the first time [story] is
  ///     completed by [profileId]; a replay still records the read
  ///     (incrementing `timesRead`, preserving the original
  ///     `completedAt`) and still plays the full sequence, but grants no
  ///     second collectible and emits no second `collectible_earned`.
  ///  4. The animation-hold phase, which ends at the earliest of: the
  ///     read-back playing its last clip to completion, an accepted
  ///     [skip], or [_celebrationDuration] elapsing (the ≤10 s
  ///     sequence-budget ceiling stays authoritative: the constructor
  ///     guarantees `_celebrationDuration + collectibleFlightDuration <=
  ///     _sequenceBudget`, so a read-back can never push the sequence past
  ///     the budget).
  ///  5. The payoff, for a story WITH narration (deferred until here so it
  ///     lands at the end of the narrated animation): any still-playing
  ///     read-back clip is stopped (a skip or the ceiling cut it short),
  ///     then the celebration sting (`story.celebrationAudioRef`) and one
  ///     rotated recorded voice line (`lineRotator.next()`) play.
  ///  6. `stage.trigger(collect)`, then
  ///     `DesignTokens.collectibleFlightDuration` elapses.
  ///  7. `onFinished` fires exactly once with the run's [CelebrationResult]
  ///     (carrying [nextStoryId] through for the return-navigation
  ///     payload).
  Future<void> run({
    required Story story,
    required String profileId,
    required int profileOrdinal,
    required int levelOrdinal,
    String? nextStoryId,
  }) async {
    _isRunning = true;
    _readbackDone = false;
    _readbackCancelled = false;
    _activeNarrationHandle = null;

    _stage.trigger(StoryStageInput.celebrate);

    final narrationRefs = _narrationRefs(story);
    final hasReadback = narrationRefs.isNotEmpty;
    if (hasReadback) {
      // Sequential read-back of every narrated sentence; the first clip's
      // play() is issued synchronously (before _runReadback's first await),
      // in the same turn as the celebrate trigger. The payoff audio is
      // deferred until the read-back finishes (or the hold ends it).
      unawaited(_runReadback(narrationRefs));
    } else {
      // No narration: immediate payoff, unchanged behavior.
      _playPayoffAudio(story);
    }

    final existing = await _storyProgressDao.getProgress(
      profileId: profileId,
      storyId: story.id,
    );
    final isFirstCompletion = existing == null || existing.status != StoryStatus.completed;

    await _storyProgressDao.recordCompletion(profileId: profileId, storyId: story.id);
    if (isFirstCompletion) {
      await _collectionDao.grantCollectible(
        profileId: profileId,
        collectibleId: story.collectibleRef,
      );
    }

    final timestamp = systemClock();
    _onAnalyticsEvent(AnalyticsEvent(
      name: AnalyticsEventName.storyCompleted,
      timestamp: timestamp,
      installId: _installId,
      profileOrdinal: profileOrdinal,
      levelOrdinal: levelOrdinal,
      storyId: story.id,
    ));
    if (isFirstCompletion) {
      _onAnalyticsEvent(AnalyticsEvent(
        name: AnalyticsEventName.collectibleEarned,
        timestamp: timestamp,
        installId: _installId,
        profileOrdinal: profileOrdinal,
        levelOrdinal: levelOrdinal,
        storyId: story.id,
      ));
    }

    await _runHoldPhase();

    if (hasReadback) {
      // The hold ended -- by the read-back finishing, an accepted skip, or
      // the sequence-budget ceiling. Stop any still-playing read-back clip
      // and land the deferred payoff.
      _readbackCancelled = true;
      final active = _activeNarrationHandle;
      _activeNarrationHandle = null;
      if (active != null) {
        unawaited(_audioService.stop(active));
      }
      _playPayoffAudio(story);
    }

    _stage.trigger(StoryStageInput.collect);
    await Future<void>.delayed(DesignTokens.collectibleFlightDuration);

    _isRunning = false;
    _onFinished(CelebrationResult(
      completedStoryId: story.id,
      nextStoryId: nextStoryId,
      skipped: _skippedThisRun,
      isFirstCompletion: isFirstCompletion,
    ));
  }

  /// Ends the animation-hold phase early -- but only if [_skipUnlockDelay]
  /// has already elapsed for the current run and that phase hasn't already
  /// ended. A harmless no-op before the unlock delay, before the hold
  /// phase has even started, or after it has already ended (naturally or
  /// via an earlier accepted skip): calling it repeatedly, or after the
  /// sequence has already finished, never errors and never double-fires
  /// `onFinished`.
  void skip() {
    final completer = _holdCompleter;
    if (completer == null || completer.isCompleted || !_skipUnlocked) {
      return;
    }
    _skippedThisRun = true;
    completer.complete();
  }

  /// Waits for the animation-hold phase to end: the narrated read-back
  /// plays its last clip to completion, [_celebrationDuration] elapses
  /// naturally (the sequence-budget ceiling's enforcement arm -- the
  /// constructor guarantees it fits inside [_sequenceBudget] with the
  /// collectible flight), or [skip] completes it early once unlocked.
  Future<void> _runHoldPhase() {
    final completer = Completer<void>();
    _holdCompleter = completer;
    _skipUnlocked = false;
    _skippedThisRun = false;

    // A read-back that already finished (while persistence was being
    // awaited) ends the hold immediately -- the payoff is already due.
    if (_readbackDone) {
      completer.complete();
    }

    final naturalTimer = Timer(_celebrationDuration, () {
      if (!completer.isCompleted) completer.complete();
    });
    final unlockTimer = Timer(_skipUnlockDelay, () {
      _skipUnlocked = true;
    });

    return completer.future.whenComplete(() {
      naturalTimer.cancel();
      unlockTimer.cancel();
    });
  }

  /// Plays the celebration payoff audio: the story's sting, then one
  /// rotated recorded voice line. Fire-and-forget on both, mirroring the
  /// sequence's swallow-and-continue posture -- a failed payoff clip never
  /// wedges the run.
  void _playPayoffAudio(Story story) {
    unawaited(_audioService.play(story.celebrationAudioRef, channel: AudioChannel.celebration));
    unawaited(_audioService.play(_lineRotator.next(), channel: AudioChannel.celebration));
  }

  /// Plays [refs] sequentially on the narration channel: each clip starts
  /// when the previous one completes (`AudioService.completionOf`). The
  /// first clip's play() is issued synchronously (before this method's
  /// first suspension). A clip that fails to play is swallowed and the
  /// chain moves straight to the next clip. When the last clip completes
  /// naturally (the run wasn't cancelled by a skip or the ceiling first),
  /// the hold phase is ended so the payoff can land.
  Future<void> _runReadback(List<AudioRef> refs) async {
    for (final ref in refs) {
      if (_readbackCancelled) break;
      try {
        final handle = await _audioService.play(ref, channel: AudioChannel.narration);
        if (_readbackCancelled) {
          unawaited(_audioService.stop(handle));
          break;
        }
        _activeNarrationHandle = handle;
        await _audioService.completionOf(handle);
      } catch (_) {
        // Swallow-and-continue: a clip that fails to play (or to report
        // completion) never wedges the celebration -- move on.
      } finally {
        _activeNarrationHandle = null;
      }
    }
    if (!_readbackCancelled) {
      _readbackDone = true;
      final completer = _holdCompleter;
      if (completer != null && !completer.isCompleted) {
        completer.complete();
      }
    }
  }

  /// The story's narrated read-back playlist: every sentence's
  /// `narrationAudioRef`, across all pages, in page/sentence order,
  /// skipping sentences without one (RECALIBRATED 2026-07-29: previously
  /// only the first page's first sentence). A story "has narration" iff
  /// this list is non-empty. Narration presence is read straight off
  /// [story] -- this controller is never given a `Level` and never
  /// inspects `Level.format` / `Level.narrationEnabled` directly.
  List<AudioRef> _narrationRefs(Story story) => <AudioRef>[
        for (final page in story.pages)
          for (final sentence in page.sentences)
            if (sentence.narrationAudioRef != null) sentence.narrationAudioRef!,
      ];
}

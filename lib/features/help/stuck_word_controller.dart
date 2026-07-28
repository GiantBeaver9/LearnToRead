/// The tiered stuck-word help scaffold (PRD §8 Unit 6; §5 `WordHelpRecord`;
/// §7 R7; ticket stuck-word-scaffold accept entries 1, 3, 4, 5, 7, 8, 9, 10).
library;

import 'dart:async';

import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/domain/tuning.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/help/help_recorder.dart';
import 'package:learn_to_read/features/help/near_miss_prompt.dart';
import 'package:learn_to_read/features/help/sound_out_sequence.dart';
import 'package:learn_to_read/features/listening/contracts/help_state.dart';
import 'package:learn_to_read/features/listening/contracts/tracker_events.dart';

/// Drives the ratified Unit 6 help ladder for the word currently being read.
///
/// ```text
///  watchWord ──T1 silence (or struggleDetected)──▶ Tier 1: sound it out
///                                                        │
///                                       sound-out stream closes
///                                                        │
///                                                     wait T2
///                                                        │
///                                        Tier 2: whole word + "your turn"
///                                                        │
///                                                     wait T2
///                                                        │
///                                            auto-accept, helped(modeled)
/// ```
///
/// Every path out of that ladder resolves the word — the child is **never
/// hard-blocked**. The worst case is bounded by
/// `T1 + Tier1 audio + T2 + Tier2 audio + T2` (pinned by
/// `test/features/help/never_blocked_test.dart`), and an accepting event at
/// any point short-circuits straight to a resolution.
///
/// ## Resolution semantics
///
/// | when the child's word lands | recorded tier | `WordHelped` emitted |
/// |---|---|---|
/// | before Tier 1 starts | [HelpLevel.none] | no |
/// | during Tier 1 audio or the T2 wait after it | [HelpLevel.soundOut] | yes |
/// | once Tier 2 has started (repeat, or auto-accept after the final T2) | [HelpLevel.modeled] | yes |
/// | near-miss acceptance (no tier had started) | [HelpLevel.none] | no |
///
/// A resolution *always* calls [HelpRecorderApi.recordResolution], including
/// the unaided `none` case — that is the §4.3 help-rate denominator. Helped
/// words are marked internally only: nothing here produces a visible marker
/// (Unit 1 ratified).
///
/// ## The T1 timer stand-in (wiring note for the app shell)
///
/// The pinned trigger is "`struggleDetected` **or** sustained silence on the
/// current word for T1". Unit 4's listening tracker is the component that
/// will eventually own sustained-silence detection and emit
/// [StruggleDetected] itself; it is not a merged dependency of this unit, so
/// this controller carries its own T1 [Timer], started from each
/// [watchWord] call, as the "sustained silence" half of the trigger. Both
/// halves are live simultaneously and whichever comes first wins:
///
///  - the internal T1 timer firing;
///  - an incoming [StruggleDetected] for the watched index (fires Tier 1
///    immediately, short-circuiting the timer);
///  - an incoming [Silence] whose `duration` is already `>= t1` (same
///    short-circuit; a shorter [Silence] is informational only and leaves the
///    timer governing).
///
/// **App-shell wiring:** when the real tracker lands, keep calling
/// [watchWord] on every word advance and simply let the tracker's
/// `struggleDetected` arrive on [events]. The internal timer is idempotent
/// with it — Tier 1 starts once, from whichever signal is first — so no
/// double-trigger is possible and no code change is needed here. If a tracker
/// build ever wants to own the trigger outright, pass a very large `t1` to
/// park the stand-in timer rather than editing this controller.
///
/// ## Timing overrides (PRD §7 R7)
///
/// `t1`/`t2` default to [kStruggleT1]/[kTier2WaitT2] from the single tuning
/// file and are constructor overrides so per-level timing profiles (longer
/// patience at higher levels) and pilot adjustments never touch this file.
class StuckWordController {
  /// Wires the scaffold to its collaborators.
  ///
  /// [events] is the single tracker event stream (Unit 4 contract).
  /// [yourTurnPromptAudioRef] is the authored recorded "your turn" line
  /// played at Tier 2. [onHelpGiven] is the `help_given(tier)` analytics
  /// emission hook — the actual client wiring lives in the reading screen /
  /// app shell.
  StuckWordController({
    required Stream<TrackerEvent> events,
    required this.soundOutSequence,
    required this.audioService,
    required this.nearMissPrompt,
    required this.helpRecorder,
    required this.yourTurnPromptAudioRef,
    this.t1 = kStruggleT1,
    this.t2 = kTier2WaitT2,
    this.onHelpGiven,
  }) {
    _eventsSub = events.listen(_onEvent);
  }

  /// Tier 1: phoneme sound-out plus the grapheme-highlight state.
  final SoundOutSequence soundOutSequence;

  /// The audio seam Tier 2's two clips are played through.
  final AudioService audioService;

  /// The lighter near-miss path (never a tier, never escalates).
  final NearMissPrompt nearMissPrompt;

  /// Where every resolution — helped or unaided — is recorded.
  final HelpRecorderApi helpRecorder;

  /// The authored recorded "your turn" line played after Tier 2's model.
  final AudioRef yourTurnPromptAudioRef;

  /// Sustained-silence threshold before Tier 1 (default [kStruggleT1]).
  final Duration t1;

  /// Wait for the child's production after Tier 1, and again after Tier 2
  /// (default [kTier2WaitT2]).
  final Duration t2;

  /// `help_given(tier)` analytics hook. Fires synchronously alongside every
  /// [WordHelped] emission and never for a [HelpLevel.none] resolution.
  final void Function(int index, HelpLevel tier)? onHelpGiven;

  final StreamController<HelpState> _helpStateController =
      StreamController<HelpState>.broadcast();
  final StreamController<WordHelped> _wordHelpedController =
      StreamController<WordHelped>.broadcast();

  StreamSubscription<TrackerEvent>? _eventsSub;
  _WatchedWord? _current;
  bool _disposed = false;

  /// The help state the reading screen renders: one event per highlighted
  /// grapheme cluster through Tier 1, a single tier-`modeled` event with no
  /// highlight (`-1`) when Tier 2 begins, and a cleared
  /// `HelpState(none, -1)` on every resolution.
  Stream<HelpState> get helpState => _helpStateController.stream;

  /// Emits once per *helped* resolution. Unaided and near-miss resolutions
  /// are recorded but never emitted here.
  Stream<WordHelped> get wordHelpedStream => _wordHelpedController.stream;

  /// Marks `(index, word)` as the word currently being read and (re)starts
  /// its T1 silence timer from this call.
  ///
  /// Any still-pending timer, sound-out playback, or Tier 2 continuation for
  /// a previously-watched word is cancelled, so no stale tier can fire for a
  /// word the child has already moved past. Superseding a word this way does
  /// not resolve or record it — only an accepting event or the Tier 2
  /// auto-accept does that.
  void watchWord({required int index, required WordToken word}) {
    if (_disposed) {
      return;
    }
    _current?.cancel();
    final watched = _WatchedWord(index: index, word: word);
    _current = watched;
    watched.timer = Timer(t1, () => _startTier1(watched));
  }

  /// Cancels the event subscription and every pending timer/playback, and
  /// closes both output streams.
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _current?.cancel();
    _current = null;
    unawaited(_eventsSub?.cancel());
    _eventsSub = null;
    unawaited(_helpStateController.close());
    unawaited(_wordHelpedController.close());
  }

  // -------------------------------------------------------------------------
  // Event handling.
  // -------------------------------------------------------------------------

  void _onEvent(TrackerEvent event) {
    final watched = _current;
    if (watched == null || watched.resolved || _disposed) {
      return; // Nothing watched, or already resolved: ignore entirely.
    }

    switch (event) {
      case WordAccepted(:final index):
        if (index == watched.index) {
          _resolve(watched, watched.tier);
        }
      case WordAcceptedNearMiss(:final index):
        if (index == watched.index) {
          // Lighter path: the word is already green. Play the warm model and
          // resolve at whatever tier had been reached (none, in the ordinary
          // case) -- this never starts, and never escalates to, a tier.
          unawaited(_playNearMiss(watched));
          _resolve(watched, watched.tier);
        }
      case StruggleDetected(:final index):
        if (index == watched.index) {
          _startTier1(watched);
        }
      case Silence(:final duration):
        // `Silence` carries no index -- it describes the current word by
        // construction. Only a silence that has already reached T1 triggers;
        // anything shorter is informational and leaves the timer governing.
        if (duration >= t1) {
          _startTier1(watched);
        }
      case WordHelped():
        break; // Emitted by this controller; never consumed by it.
      default:
        break;
    }
  }

  Future<void> _playNearMiss(_WatchedWord watched) async {
    try {
      await nearMissPrompt.play(watched.word);
    } catch (_) {
      // A missing authored clip must never block reading: the word is
      // already accepted and green, so there is nothing to recover.
    }
  }

  // -------------------------------------------------------------------------
  // Tier 1 -- sound it out.
  // -------------------------------------------------------------------------

  void _startTier1(_WatchedWord watched) {
    if (!_isActive(watched) || watched.tier != HelpLevel.none) {
      return; // Superseded, resolved, or Tier 1 already running/passed.
    }
    watched.cancelTimer();
    watched.tier = HelpLevel.soundOut;
    watched.soundOutSub = soundOutSequence
        .play(watched.word)
        .listen(
          (state) {
            if (_isActive(watched)) {
              _publish(state);
            }
          },
          onError: (Object _) {
            // A content/pack error (missing phoneme audio) stops the
            // sound-out, but the stream still closes -- `onDone` below keeps
            // the ladder moving so the child is never left stranded.
          },
          onDone: () => _onSoundOutDone(watched),
        );
  }

  void _onSoundOutDone(_WatchedWord watched) {
    watched.soundOutSub = null;
    if (!_isActive(watched)) {
      return;
    }
    // Tier 1's audio is over: the child now gets T2 to say the word.
    watched.timer = Timer(t2, () => _startTier2(watched));
  }

  // -------------------------------------------------------------------------
  // Tier 2 -- model it.
  // -------------------------------------------------------------------------

  void _startTier2(_WatchedWord watched) {
    watched.timer = null;
    if (!_isActive(watched)) {
      return;
    }
    watched.tier = HelpLevel.modeled;
    _publish(
      const HelpState(
        currentHelpTier: HelpLevel.modeled,
        highlightedGraphemeIndex: -1,
      ),
    );
    unawaited(_playTier2(watched));
  }

  Future<void> _playTier2(_WatchedWord watched) async {
    try {
      final wordHandle = await audioService.play(
        watched.word.pronunciationAudioRef,
        channel: AudioChannel.help,
      );
      await audioService.completionOf(wordHandle);
      if (!_isActive(watched)) {
        return;
      }
      final promptHandle = await audioService.play(
        yourTurnPromptAudioRef,
        channel: AudioChannel.help,
      );
      await audioService.completionOf(promptHandle);
    } catch (_) {
      // A missing clip is a content bug, not a reason to strand the child:
      // fall through to the final T2 wait and the auto-accept below.
    }
    if (!_isActive(watched)) {
      return;
    }
    // One more T2 for the repeat; if it never comes, accept anyway.
    watched.timer = Timer(t2, () => _resolve(watched, HelpLevel.modeled));
  }

  // -------------------------------------------------------------------------
  // Resolution.
  // -------------------------------------------------------------------------

  void _resolve(_WatchedWord watched, HelpLevel tier) {
    if (!_isActive(watched)) {
      return; // Already resolved, superseded, or disposed: never double-record.
    }
    watched.resolved = true;
    watched.cancel();

    _publish(
      const HelpState(
        currentHelpTier: HelpLevel.none,
        highlightedGraphemeIndex: -1,
      ),
    );

    unawaited(helpRecorder.recordResolution(word: watched.word, tier: tier));

    if (tier == HelpLevel.none) {
      return; // Unaided (or near-miss): an encounter, but not help.
    }
    if (!_wordHelpedController.isClosed) {
      _wordHelpedController.add(WordHelped(index: watched.index, tier: tier));
    }
    onHelpGiven?.call(watched.index, tier);
  }

  bool _isActive(_WatchedWord watched) =>
      !_disposed && identical(_current, watched) && !watched.resolved;

  void _publish(HelpState state) {
    if (!_helpStateController.isClosed) {
      _helpStateController.add(state);
    }
  }
}

/// The mutable per-word state the ladder walks: which word, how far up the
/// tiers it got, and the one pending timer / sound-out subscription it owns.
///
/// One instance per [StuckWordController.watchWord] call. Async continuations
/// capture their instance and re-check `identical(_current, watched)` before
/// acting, which is what makes a superseded or resolved word inert without
/// needing to unwind in-flight futures.
class _WatchedWord {
  _WatchedWord({required this.index, required this.word});

  /// The word's position in the sentence (0-based).
  final int index;

  /// The word being read.
  final WordToken word;

  /// The highest tier reached so far — also the tier a resolution records.
  HelpLevel tier = HelpLevel.none;

  /// Set once the word has resolved; makes every later event a no-op.
  bool resolved = false;

  /// The single pending timer (T1, the post-Tier-1 T2, or the final T2).
  Timer? timer;

  /// The live Tier 1 sound-out subscription, if any.
  StreamSubscription<HelpState>? soundOutSub;

  void cancelTimer() {
    timer?.cancel();
    timer = null;
  }

  /// Stops everything still pending for this word. Cancelling the sound-out
  /// subscription is what guarantees no further phoneme is force-played once
  /// the child has produced the word.
  void cancel() {
    cancelTimer();
    final sub = soundOutSub;
    soundOutSub = null;
    unawaited(sub?.cancel());
  }
}

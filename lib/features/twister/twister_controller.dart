/// Runtime orchestration for one tongue-twister booster attempt
/// (PRD §8 Unit 14 "Tongue-twister boosters"; §5 TongueTwister /
/// TwisterProgress; §9 A-13; ticket twister-flow).
///
/// A tongue twister is an *enunciation* booster, not a decoding exercise:
/// the goal is clear, confident speech. [TwisterController] therefore owns a
/// deliberately different runtime from the story reading screen:
///
/// - **Narration models the twister first.** `start()`'s synchronous prefix
///   emits `twister_started` and plays the owner-supplied
///   `narrationAudioRef` on [AudioChannel.narration]. Listening (or, absent
///   consent or a healthy engine, listen-then-tap) begins only once that
///   clip's `completionOf` resolves. The child hears it before they try it.
/// - **Tracking is sound-level, not word-level** (PRD ratified). One
///   [SoundModeScorer] grades the whole twister's concatenated phoneme
///   sequence, with the drilled `targetPhonemeId`'s instances weighted
///   (A-13). Producing the right SOUNDS advances the attempt even when word
///   recognition would fail outright. The thresholds are the twister set
///   (`kSoundMode*` in lib/domain/tuning.dart), never the story/word-mode
///   near-miss set, and they are injected so a pilot pass can move them in
///   one file.
/// - **The controller owns the engine loop itself.** It takes an
///   [AsrEngine] directly and runs engine → [SoundModeScorer] with no
///   `ReadingTracker` in between: the story tracker's word state machine,
///   help tiers, cloud-minute cap and struggle detection are all
///   story-shaped concerns a twister does not have.
/// - **Never hard-blocked** (PRD §6). With microphone consent off the engine
///   is never touched at all; with consent but a failing engine an attempt
///   is made and then abandoned. Both degrade to listen-then-tap, where
///   [tapWord] walks the twister's words and completion fires exactly the
///   same effects as the mic path.
/// - **No collectible.** There is deliberately no `CollectionDao` in this
///   constructor — collectibles stay story-tied (PRD §8 Unit 14). Completion
///   writes [TwisterProgress] and emits `twister_completed`, nothing more.
/// - **Always replayable.** A controller models ONE attempt; re-entry means
///   a fresh controller, which starts un-done and increments
///   `timesCompleted` again.
library;

import 'dart:async';

import 'package:learn_to_read/data/db/daos/twister_progress_dao.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/tuning.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/analytics/events.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/matcher/sound_mode_scorer.dart';

/// Orchestrates one tongue-twister attempt end to end: narration →
/// listening (or listen-then-tap) → completion effects.
///
/// One instance models one attempt. It is not restartable: replay is a new
/// instance (PRD §8 Unit 14 "always replayable").
class TwisterController {
  /// Creates a controller for [twister].
  ///
  /// [engine] is the ASR engine this controller drives directly (the real
  /// on-device/cloud engine is injected by the app shell; tests inject
  /// `FakeAsrEngine`). [micConsent] is the profile's current Unit 10
  /// consent: when false the engine is never started at all.
  ///
  /// [installId] / [profileOrdinal] / [levelOrdinal] are the §5 analytics
  /// base fields; twister events never carry a `storyId`.
  ///
  /// The three threshold parameters default to the A-13 constants in
  /// lib/domain/tuning.dart and are forwarded verbatim to the internal
  /// [SoundModeScorer]; override them only for tests or a pilot tuning
  /// experiment.
  TwisterController({
    required this.twister,
    required AsrEngine engine,
    required AudioService audioService,
    required TwisterProgressDao twisterProgressDao,
    required this.profileId,
    required this.micConsent,
    required this.installId,
    required this.profileOrdinal,
    required this.levelOrdinal,
    required void Function(AnalyticsEvent event) onAnalyticsEvent,
    void Function()? onCelebrate,
    double matchThreshold = kSoundModeMatchThreshold,
    int perPhonemeMaxDistance = kSoundModePerPhonemeMaxDistance,
    int targetPhonemeWeight = kSoundModeTargetPhonemeWeight,
    Clock clock = systemClock,
  })  : _engine = engine,
        _audioService = audioService,
        _twisterProgressDao = twisterProgressDao,
        _onAnalyticsEvent = onAnalyticsEvent,
        _onCelebrate = onCelebrate,
        _clock = clock,
        _scorer = SoundModeScorer(
          targetPhonemeSequence: phonemeSequenceOf(twister),
          targetPhonemeId: twister.targetPhonemeId,
          matchThreshold: matchThreshold,
          perPhonemeMaxDistance: perPhonemeMaxDistance,
          targetPhonemeWeight: targetPhonemeWeight,
        );

  /// The twister being practised.
  final TongueTwister twister;

  /// The profile this attempt belongs to (never sent to analytics).
  final String profileId;

  /// Whether microphone consent is granted right now (Unit 10). False means
  /// the engine is never started — the attempt runs as listen-then-tap.
  final bool micConsent;

  /// The random per-install UUID carried by every analytics event.
  final String installId;

  /// The §5 profile ordinal (1-4) carried by every analytics event.
  final int profileOrdinal;

  /// The §5 level ordinal carried by every analytics event.
  final int levelOrdinal;

  final AsrEngine _engine;
  final AudioService _audioService;
  final TwisterProgressDao _twisterProgressDao;
  final void Function(AnalyticsEvent event) _onAnalyticsEvent;
  final void Function()? _onCelebrate;
  final Clock _clock;
  final SoundModeScorer _scorer;

  StreamSubscription<Hypothesis>? _engineSub;
  bool _isListening = false;
  bool _isTapMode = false;
  bool _isComplete = false;
  bool _completing = false;
  int _tappedWordCount = 0;

  /// The whole twister's phoneme sequence: every word's AUTHORED
  /// `graphemePhonemeMap` phonemes, concatenated in word order.
  ///
  /// This is the target the sound-mode scorer grades against — the PRD's
  /// "the twister's phoneme sequence … is the target". Authored phonemes,
  /// never a G2P guess: the comparison G2P exists only for hypothesis words
  /// the engine hands back as text.
  static List<String> phonemeSequenceOf(TongueTwister twister) => [
        for (final word in twister.words)
          for (final entry in word.graphemePhonemeMap) entry.phonemeId,
      ];

  // ---------------------------------------------------------------------
  // Sound-mode progress.
  // ---------------------------------------------------------------------

  /// Weighted fraction of the twister's phoneme sequence produced so far
  /// (A-13; drilled-phoneme positions weigh [targetPhonemeWeight]).
  double get matchedFraction => _scorer.matchedFraction;

  /// Whether [matchedFraction] has reached [matchThreshold] (inclusive).
  bool get accepted => _scorer.accepted;

  // ---------------------------------------------------------------------
  // Session state.
  // ---------------------------------------------------------------------

  /// Whether the microphone/engine session is open right now. This is the
  /// flag the screen's small "listening" indicator renders: false while the
  /// narration models the twister, true while the child is being listened
  /// to, false again the moment the attempt ends.
  bool get isListening => _isListening;

  /// Whether this attempt degraded to listen-then-tap (no consent, or the
  /// engine failed). Tapping is always *available*; this flag says it is
  /// the only path forward.
  bool get isTapMode => _isTapMode;

  /// Whether the node is done, by either path.
  bool get isComplete => _isComplete;

  // ---------------------------------------------------------------------
  // Tap-fallback progress.
  // ---------------------------------------------------------------------

  /// How many of the twister's words have been tapped through so far.
  int get tappedWordCount => _tappedWordCount;

  /// How many words the twister has in total.
  int get totalWordCount => twister.words.length;

  // ---------------------------------------------------------------------
  // Tunables actually in effect (proves config injection, not hardcoding).
  // ---------------------------------------------------------------------

  /// The acceptance floor in effect (A-13 default 0.60).
  double get matchThreshold => _scorer.matchThreshold;

  /// The per-phoneme distance ceiling in effect (A-13 default 1).
  int get perPhonemeMaxDistance => _scorer.perPhonemeMaxDistance;

  /// The drilled phoneme's weight in effect (A-13 default 2).
  int get targetPhonemeWeight => _scorer.targetPhonemeWeight;

  // ---------------------------------------------------------------------
  // Lifecycle.
  // ---------------------------------------------------------------------

  /// Runs the attempt: `twister_started` + narration synchronously, then —
  /// once the narration clip ends — listening, or listen-then-tap when
  /// consent is off or the engine cannot be opened.
  ///
  /// The returned future resolves once the session has been established (or
  /// degraded); completion itself is driven by hypotheses or [tapWord].
  Future<void> start() async {
    _emit(AnalyticsEventName.twisterStarted);
    // Synchronous prefix ends here: `play` logs its call before returning,
    // so the narration is unambiguously requested before the first await.
    final playing = _audioService.play(
      twister.narrationAudioRef,
      channel: AudioChannel.narration,
    );

    final handle = await playing;
    await _audioService.completionOf(handle);
    if (_isComplete) return;

    _beginListening();
  }

  /// Opens the engine session, or degrades to listen-then-tap.
  void _beginListening() {
    if (!micConsent) {
      // Unit 10: without consent the microphone is never opened at all —
      // the engine is not even asked to start.
      _enterTapMode();
      return;
    }
    try {
      _engine.start([for (final word in twister.words) word.text]);
      final stream = _engine.hypothesesStream;
      _engineSub = stream.listen(
        _onHypothesis,
        onError: (Object _) => _enterTapMode(),
        onDone: _releaseSubscription,
      );
      _isListening = true;
    } catch (_) {
      // An engine that cannot open is never a hard block (PRD §6): the
      // attempt continues as listen-then-tap.
      _enterTapMode();
    }
  }

  void _enterTapMode() {
    _isListening = false;
    _isTapMode = true;
  }

  /// Feeds one finalized hypothesis burst to the sound-mode scorer.
  ///
  /// Bursts the engine had already emitted when the attempt was accepted are
  /// still scored: the mic is closed on acceptance, but whatever the child
  /// actually produced keeps counting toward the reported [matchedFraction].
  /// The scorer is monotone, so this can only ever raise it, and [_complete]
  /// is guarded so it runs exactly once.
  void _onHypothesis(Hypothesis hypothesis) {
    _scorer.onHypothesis(hypothesis);
    if (_scorer.accepted) unawaited(_complete());
  }

  /// Listen-then-tap manual advance. Available in every mode (a child who
  /// prefers tapping is never forced through the microphone). A no-op past
  /// the last word or once the node is done; the final tap completes the
  /// node through exactly the same path as an accepted mic attempt.
  void tapWord() {
    if (_isComplete || _completing) return;
    if (_tappedWordCount >= totalWordCount) return;
    _tappedWordCount += 1;
    if (_tappedWordCount >= totalWordCount) unawaited(_complete());
  }

  /// Ends the attempt early (screen dismissed, app backgrounded). Closes the
  /// engine session; never records a completion.
  void stop() {
    _endSession();
    _releaseSubscription();
  }

  /// Closes the microphone/engine session: the indicator goes dark and the
  /// engine is told to stop capturing. The hypothesis subscription is NOT
  /// torn down here — see [_onHypothesis] — it is released when the engine's
  /// stream drains, or by [stop].
  void _endSession() {
    if (!_isListening) return;
    _isListening = false;
    _engine.stop();
  }

  /// Releases the hypothesis subscription. Called when the engine's stream
  /// drains of its own accord and by [stop].
  void _releaseSubscription() {
    final sub = _engineSub;
    _engineSub = null;
    if (sub != null) unawaited(sub.cancel());
  }

  /// The single completion path, shared by the mic and tap routes: close the
  /// session, write [TwisterProgress], emit `twister_completed`, celebrate.
  /// No collectible is granted — there is nowhere here for one to come from.
  Future<void> _complete() async {
    if (_isComplete || _completing) return;
    _completing = true;
    _endSession();
    await _twisterProgressDao.recordCompletion(
      profileId: profileId,
      twisterId: twister.id,
    );
    _isComplete = true;
    _emit(AnalyticsEventName.twisterCompleted);
    _onCelebrate?.call();
  }

  void _emit(AnalyticsEventName name) {
    _onAnalyticsEvent(AnalyticsEvent(
      name: name,
      timestamp: _clock(),
      installId: installId,
      profileOrdinal: profileOrdinal,
      levelOrdinal: levelOrdinal,
    ));
  }
}

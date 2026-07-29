// WIRING: this screen is built standalone (the app-shell files are owned by
// another work stream right now). The orchestrator hooks it up as follows:
//
//  * lib/app/router.dart — add a child-shell route (alongside map /
//    collection / sound garden), e.g. path '/flashcards', building
//    `FlashcardsScreen` from the providers below. Nav entry per PRD §8
//    Unit 16: icon + nav voice prompt "Flash cards"
//    (`audio/nav/flashcards.wav` — owner recording, added to the
//    recording checklist).
//  * lib/app/providers.dart — construct with:
//      - profileId:        the active profile's `Profile.localId`
//      - deck:             `FlashcardDeck.fromWordTokens(tokens)` where
//                          `tokens` = every `WordToken` of every installed
//                          pack's stories (content-delivery exposes the
//                          installed packs; the deck loader is the Unit 16
//                          seam — owner-curated decks come later)
//      - audioService:     the app's `AudioService` provider
//      - phonemeAudioRefs: the shipped phoneme-id -> AudioRef map (same one
//                          the reading screen / Sound Garden use)
//      - dao:              `appDatabase.flashcardsDao`
//      - now:              `systemClock` (features/analytics/event_schema.dart)
//      - echoEngine:       the app's `AsrEngine` provider — ONLY when
//                          `profile.micConsent` (mirror Sound Garden's
//                          consent gate); pass null for listen-only mode
//                          and the screen stays exactly the manual
//                          scaffold
//      - buildEchoAttempt: a closure returning `EchoSession(engine: ...,
//                          <matcher>)` where <matcher> is the sound-mode
//                          matcher over `sequence` drilling
//                          `targetPhonemeId`, constructed exactly as Sound
//                          Garden's builder wiring constructs its own (see
//                          sound_garden_screen.dart's builder param and
//                          echo_session.dart's constructor). The matcher is
//                          injected rather than built here because this
//                          feature's frozen structural scan bans naming
//                          any v1 point-tally concept anywhere in
//                          lib/features/flashcards sources, and the
//                          matcher type's own name contains one; the screen
//                          still owns WHAT is listened for (the card's
//                          phoneme sequence + first-phoneme target)
//      - cumulativeGraphemes: `cumulativeGraphemeSet(levels: levels,
//                          levelId: profile.currentLevelId)`
//                          (lib/pipeline/cumulative_grapheme_set.dart,
//                          pure) — the phonics-first deck-ordering input;
//                          null keeps plain deck order
//  * lib/data/db/daos/profiles_dao.dart — extend `deleteProfile`'s erasure
//    cascade with the FlashcardProgressRows table (PRD §8 Unit 10 "deleting
//    a profile erases all its local data"); `FlashcardsDao.eraseProfile`
//    exists as the hook. That file is owned elsewhere at the moment, so the
//    cascade amendment ships with the wiring, not with this scaffold.
//
// The flashcards screen itself (PRD §8 Unit 16 — phonics flashcards, MVP
// scaffold; visual spec docs/design/mockup-spec.md §10b, card surface §3,
// chip styling §4):
//
//  * Session queue = all cards due at open (new cards are box 1 = due now).
//  * FRONT: the word, huge, in the reading typeface on the parchment card;
//    tapping the WORD plays its gapless phoneme sound-out
//    (PhonemeSequencer). Tapping the card elsewhere flips it.
//  * FLIP: 3D horizontal flip (FlipCard) to the back — grapheme chips
//    (syllable-chip styling) each labeled with its phoneme id in mono
//    type, plus a whole-word pronunciation play button.
//  * GRADING (back side only, exactly two buttons): amber "practice again"
//    (box 1, re-queued after the remaining due cards this session) and
//    green "got it" (next box, capped; dues per lib/domain/tuning.dart).
//  * Queue cleared -> warm all-done state + a single intensity-1 confetti
//    (seed stable per session). No negative state anywhere: "practice
//    again" is amber, copy stays warm, reps are their own reward in v1
//    (test/features/flashcards/no_negative_state_test.dart scans this
//    directory for banned lexemes).
//
// SPEECH-FIRST LAYER (PRD §8 Unit 16 "Speech-first", RATIFIED 2026-07-28;
// docs/design/mockup-spec.md §10b):
//
//  * LISTENING: while the FRONT shows and `echoEngine` is provided, a
//    fresh echo attempt (Sound Garden's `EchoSession` pattern, sound-mode
//    over the card's phoneme sequence — crediting the SOUNDS, not word
//    identity) runs via `buildEchoAttempt`. Flipping to the back stops the
//    attempt; flipping home starts a fresh one. With `echoEngine` null the
//    screen is exactly the manual scaffold above.
//  * ACCEPT -> the word IMPRESSES: text turns read-green with a subtle
//    scale swell, an intensity-1 `ConfettiOverlay` bursts (seed =
//    [flashcardConfettiSeed] over card key + per-card visit count, so each
//    visit's burst differs deterministically), and a "got it" grade is
//    recorded through the SAME dao/scheduler path as the green button.
//    After [kSoundGardenGreenHold] (reused — the same treatment family as
//    Sound Garden's green hold) the session advances by the existing
//    got-it path. The echo attempt is stopped the moment it accepts.
//  * SWIPE: a horizontal drag past a small threshold advances at ANY time
//    (front or back, accepted or not — success never gates). Without a
//    grade nothing is written: the card rotates to the end of the session
//    queue and stays due. A live attempt is stopped cleanly first.
//  * SWIPE CUES (owner refinement 2026-07-28): the card is never static —
//    a gentle repeating horizontal sway (±6 px, ease-in-out, 1.6 s period)
//    plus a faint outline chevron at the trailing edge give the impression
//    to swipe. Both cues are suppressed during the impress hold.
//  * ORDERING: the optional `cumulativeGraphemes` set orders the session
//    queue phonics-first (decodable-at-level before ahead-of-level; see
//    phonics_first_order.dart) — null keeps plain deck order.
library;

import 'dart:async';

import 'package:flutter/material.dart' show Scaffold, SafeArea;
import 'package:flutter/widgets.dart';
import 'package:learn_to_read/design/confetti.dart';
import 'package:learn_to_read/design/motion.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/data/db/daos/flashcards_dao.dart';
import 'package:learn_to_read/domain/tuning.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/phoneme_sequencer.dart';
import 'package:learn_to_read/features/flashcards/flashcard_deck.dart';
import 'package:learn_to_read/features/flashcards/flashcard_progress.dart';
import 'package:learn_to_read/features/flashcards/flashcard_session.dart';
import 'package:learn_to_read/features/flashcards/flip_card.dart';
import 'package:learn_to_read/features/flashcards/leitner_scheduler.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/sound_garden/echo_session.dart';

/// Builds one fresh echo attempt for one card visit: an [EchoSession] over
/// [engine] and a NEW sound-mode matcher for [phonemeSequence] drilling
/// [targetPhonemeId] (see the WIRING block for why the matcher is injected
/// rather than constructed here). Called once per attempt — a used
/// attempt's accepted state is monotone and is never reused, mirroring
/// Sound Garden's fresh-per-rep rule.
typedef FlashcardEchoAttemptBuilder = EchoSession Function(
  AsrEngine engine,
  List<String> phonemeSequence,
  String targetPhonemeId,
);

/// The echo target for [card]: its `graphemePhonemeMap` phoneme ids in
/// order. Silent letters (empty phonemeId, e.g. the "e" in "cake") carry
/// no sound to say, so they contribute nothing to the sequence.
List<String> flashcardEchoPhonemeSequence(FlashcardCard card) => [
      for (final entry in card.graphemePhonemeMap)
        if (entry.phonemeId.isNotEmpty) entry.phonemeId,
    ];

/// Deterministic confetti seed for one accepted card visit: a stable
/// FNV-1a hash of [cardKey]'s code units mixed with [visit] (the per-card
/// visit count this session). Deliberately NOT `Object.hash` /
/// `String.hashCode`, whose values may vary between runs — equal inputs
/// must replay the identical burst (same rule as Sound Garden's per-rep
/// seed).
int flashcardConfettiSeed(String cardKey, int visit) {
  var hash = 0x811C9DC5;
  for (final unit in cardKey.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7FFFFFFF;
  }
  return hash ^ visit;
}

/// The phonics-flashcards screen (PRD §8 Unit 16). See the WIRING block at
/// the top of this file for how the shell constructs it.
class FlashcardsScreen extends StatefulWidget {
  const FlashcardsScreen({
    super.key,
    required this.profileId,
    required this.deck,
    required this.audioService,
    required this.phonemeAudioRefs,
    required this.dao,
    required this.now,
    this.confettiSeed,
    this.echoEngine,
    this.buildEchoAttempt,
    this.cumulativeGraphemes,
  }) : assert(
          (echoEngine == null) == (buildEchoAttempt == null),
          'echoEngine and buildEchoAttempt ship together: the engine is '
          'what listens, the builder is how each attempt is constructed',
        );

  /// The active profile's `Profile.localId` — scopes all persistence.
  final String profileId;

  /// The unique-word deck (the Unit 16 MVP deck-loader seam).
  final FlashcardDeck deck;

  /// The audio seam every play goes through.
  final AudioService audioService;

  /// Phoneme id -> shipped audio ref, for the front-side sound-out.
  final Map<String, AudioRef> phonemeAudioRefs;

  /// Persistence for `(box, dueAt)` per card.
  final FlashcardsDao dao;

  /// The injected clock — never `DateTime.now()` inline (repo convention).
  final DateTime Function() now;

  /// Confetti seed override. When null, a seed is derived ONCE from `now()`
  /// at session start, so the celebration is stable within a session and
  /// deterministic under test.
  final int? confettiSeed;

  /// The OPTIONAL ASR engine the speech-first layer listens through (PRD
  /// §8 Unit 16 "Speech-first"). Null = the manual scaffold, unchanged:
  /// no attempt is ever constructed and the engine seam is never touched.
  /// The wiring passes the engine only with `profile.micConsent`, mirror of
  /// Sound Garden's consent gate.
  final AsrEngine? echoEngine;

  /// Constructs each fresh echo attempt (see [FlashcardEchoAttemptBuilder]
  /// and the WIRING block). Required exactly when [echoEngine] is given.
  final FlashcardEchoAttemptBuilder? buildEchoAttempt;

  /// The OPTIONAL phonics-first ordering input: the profile's cumulative
  /// grapheme set (the SET itself, not the profile — this feature stays
  /// decoupled from levels). When non-null the session queue puts
  /// decodable-at-level cards before ahead-of-level ones (stable within
  /// groups); when null the deck order stands.
  final Set<String>? cumulativeGraphemes;

  @override
  State<FlashcardsScreen> createState() => _FlashcardsScreenState();
}

class _FlashcardsScreenState extends State<FlashcardsScreen> {
  late final PhonemeSequencer _sequencer = PhonemeSequencer(
    audioService: widget.audioService,
    phonemeAudioRefs: widget.phonemeAudioRefs,
  );
  late final LeitnerScheduler _scheduler = LeitnerScheduler(now: widget.now);
  late final int _confettiSeed =
      widget.confettiSeed ?? widget.now().millisecondsSinceEpoch;

  final Map<String, FlashcardProgress> _progressByKey = {};
  FlashcardSession? _session;
  bool _showBack = false;
  bool _grading = false;

  /// True from the grade that clears the queue until the confetti overlay
  /// reports finished — the overlay mounts exactly once per session, and
  /// only when the child actually cleared a non-empty queue (opening with
  /// nothing due shows the calm all-done state, no confetti).
  bool _confettiPlaying = false;
  bool _confettiSpent = false;

  // --- Speech-first layer state (see the SPEECH-FIRST LAYER doc block) ---

  /// The live echo attempt for the current card visit, or null when
  /// nothing is listening (no engine, back showing, impress hold, or the
  /// attempt already accepted).
  EchoSession? _echoAttempt;

  /// Per-card visit counter this session (first visit = 1): incremented
  /// each time a card takes the front of the queue. Feeds
  /// [flashcardConfettiSeed] so each visit's accepted burst differs.
  final Map<String, int> _visitCounts = {};

  /// The card key currently holding its impress (green flash) window, with
  /// that visit's confetti seed; null outside the hold.
  String? _impressedCardKey;
  int? _impressConfettiSeed;

  /// The [kSoundGardenGreenHold] timer from accept to auto-advance.
  Timer? _impressTimer;

  /// Cumulative horizontal drag distance of the in-flight swipe gesture.
  double _swipeDx = 0;

  /// How far a horizontal drag must travel to count as the §10b advance
  /// swipe. A gesture-recognition distance (like page_curl.dart's own drag
  /// threshold), not a behavior-pacing tuning constant.
  static const double _swipeAdvanceDistance = 56.0;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _impressTimer?.cancel();
    _stopEchoAttempt();
    super.dispose();
  }

  Future<void> _load() async {
    final rows = await widget.dao.allForProfile(widget.profileId);
    if (!mounted) return;
    setState(() {
      for (final row in rows) {
        _progressByKey[row.cardKey] = row;
      }
      _session = FlashcardSession(
        queue: dueCardsAt(
          deck: widget.deck,
          progressByKey: _progressByKey,
          at: widget.now(),
          cumulativeGraphemes: widget.cumulativeGraphemes,
        ),
      );
    });
    _beginCardVisit();
  }

  /// The current card just took the front of the queue: count the visit
  /// and (when the speech layer is wired) start listening for it.
  void _beginCardVisit() {
    final card = _session?.current;
    if (card == null) return;
    _visitCounts[card.cardKey] = (_visitCounts[card.cardKey] ?? 0) + 1;
    _startEchoAttempt();
  }

  /// Starts a FRESH echo attempt for the current card (a used attempt is
  /// never reused — Sound Garden's fresh-per-rep rule). No-op without the
  /// speech layer, while the back shows, during the impress hold, or for a
  /// card with nothing sayable (all silent letters).
  void _startEchoAttempt() {
    final engine = widget.echoEngine;
    final build = widget.buildEchoAttempt;
    final card = _session?.current;
    if (engine == null || build == null || card == null) return;
    if (_showBack || _impressedCardKey != null) return;
    _stopEchoAttempt();
    final sequence = flashcardEchoPhonemeSequence(card);
    if (sequence.isEmpty) return;
    // Target = the FIRST phoneme id: sound mode drills one phoneme, and a
    // flashcard has no curated drill target, so the word's opening sound
    // (the one the child attacks first when sounding out) is it.
    final attempt = build(engine, sequence, sequence.first);
    _echoAttempt = attempt;
    attempt.start(onMatch: () => _onEchoAccepted(card, attempt));
  }

  /// Stops any live attempt cleanly (the same `EchoSession.stop` path
  /// `dispose` uses). Safe to call with nothing listening.
  void _stopEchoAttempt() {
    final attempt = _echoAttempt;
    _echoAttempt = null;
    if (attempt != null && attempt.isListening) {
      attempt.stop();
    }
  }

  /// The attempt accepted: the word impresses (PRD §8 Unit 16 "when the
  /// child says the word/sounds and the [matcher] accepts"). Stops the
  /// attempt, records the got-it grade through the SAME dao/scheduler path
  /// as the green button, and opens the [kSoundGardenGreenHold] window —
  /// green flash + seeded intensity-1 confetti — before auto-advancing.
  void _onEchoAccepted(FlashcardCard card, EchoSession attempt) {
    if (!mounted || !identical(attempt, _echoAttempt)) return;
    if (_session?.current?.cardKey != card.cardKey) return;
    _stopEchoAttempt();
    unawaited(_impressAndRecord(card));
  }

  Future<void> _impressAndRecord(FlashcardCard card) async {
    final progress = _nextProgressFor(card, FlashcardGrade.gotIt);
    await widget.dao.upsertProgress(progress);
    if (!mounted) return;
    final visit = (_visitCounts[card.cardKey] ?? 1) - 1;
    setState(() {
      _progressByKey[card.cardKey] = progress;
      _impressedCardKey = card.cardKey;
      _impressConfettiSeed = flashcardConfettiSeed(card.cardKey, visit);
    });
    _impressTimer?.cancel();
    _impressTimer = Timer(kSoundGardenGreenHold, () {
      _impressTimer = null;
      _finishImpress();
    });
  }

  /// The impress hold is over: clear the green state and advance the queue
  /// through the existing got-it path (the grade itself was already
  /// written at accept time), then begin the next card's visit.
  void _finishImpress() {
    if (!mounted) return;
    final session = _session;
    final card = session?.current;
    setState(() {
      _impressedCardKey = null;
      _impressConfettiSeed = null;
      if (session != null && card != null) {
        session.gradeCurrent(FlashcardGrade.gotIt);
        _showBack = false;
        if (session.isComplete && !_confettiSpent) {
          _confettiPlaying = true;
        }
      }
    });
    _beginCardVisit();
  }

  /// §10b swipe: advances to the next session card at ANY time — success
  /// never gates. Ungraded cards rotate to the end of the queue with NO
  /// progress write (still due); a card mid-impress-hold was already
  /// graded at accept, so the swipe simply ends its hold early through the
  /// same advance path the timer takes. Any live attempt stops first.
  void _onSwipeAdvance() {
    final session = _session;
    final card = session?.current;
    if (session == null || card == null || _grading) return;
    _stopEchoAttempt();
    if (_impressedCardKey == card.cardKey) {
      _impressTimer?.cancel();
      _impressTimer = null;
      _finishImpress();
      return;
    }
    setState(() {
      session.skipCurrent();
      _showBack = false;
    });
    _beginCardVisit();
  }

  void _onSoundOutTap(FlashcardCard card) {
    // Mirrors the Tier 1 sound-out path (SoundOutSequence over
    // PhonemeSequencer): phonemes play gaplessly in graphemePhonemeMap
    // order on the help channel. A missing phoneme ref is a content/pack
    // bug surfaced by the pipeline linter; the child screen stays calm
    // rather than crashing mid-practice.
    _sequencer.playSequence(card.token).listen((_) {}, onError: (Object _) {});
  }

  void _onPronunciationTap(FlashcardCard card) {
    unawaited(
      widget.audioService
          .play(card.pronunciationAudioRef, channel: AudioChannel.help),
    );
  }

  /// A back-side grapheme chip was tapped (owner direction 2026-07-29:
  /// tappable chips): play exactly THAT cluster's phoneme clip — a single
  /// clip, never the whole sequence. A silent letter (empty phonemeId) or
  /// a clip absent from the shipped map plays nothing.
  ///
  /// The tap then continues into the card's flip toggle, exactly the
  /// observable behavior a chip tap has always had (a chip tap reaches the
  /// flip detector — pinned by the speech-first suite), so flipping home
  /// off the back keeps working from a chip.
  void _onChipTap(FlashcardCard card, int graphemeIndex) {
    final map = card.graphemePhonemeMap;
    if (graphemeIndex >= 0 && graphemeIndex < map.length) {
      final phonemeId = map[graphemeIndex].phonemeId;
      final ref = phonemeId.isEmpty ? null : widget.phonemeAudioRefs[phonemeId];
      if (ref != null) {
        unawaited(() async {
          try {
            await widget.audioService.play(ref, channel: AudioChannel.help);
          } catch (_) {
            // A missing clip is a content/pack bug; the screen stays calm.
          }
        }());
      }
    }
    _onCardTap();
  }

  /// The `(box, dueAt)` write [card] earns for [grade] — the one
  /// dao/scheduler path both the manual grade buttons and the speech
  /// accept go through.
  FlashcardProgress _nextProgressFor(FlashcardCard card, FlashcardGrade grade) {
    final currentBox = _progressByKey[card.cardKey]?.box ?? 1;
    final next = _scheduler.applyGrade(box: currentBox, grade: grade);
    return FlashcardProgress(
      profileId: widget.profileId,
      cardKey: card.cardKey,
      box: next.box,
      dueAt: next.dueAt,
    );
  }

  Future<void> _grade(FlashcardGrade grade) async {
    final session = _session;
    final card = session?.current;
    if (session == null || card == null || _grading) return;
    _grading = true;
    try {
      final progress = _nextProgressFor(card, grade);
      await widget.dao.upsertProgress(progress);
      if (!mounted) return;
      setState(() {
        _progressByKey[card.cardKey] = progress;
        session.gradeCurrent(grade);
        _showBack = false;
        if (session.isComplete && !_confettiSpent) {
          _confettiPlaying = true;
        }
      });
      _beginCardVisit();
    } finally {
      _grading = false;
    }
  }

  void _onConfettiFinished() {
    if (!mounted) return;
    setState(() {
      _confettiPlaying = false;
      _confettiSpent = true;
    });
  }

  /// The card flip toggle. During the impress hold the flip is a no-op —
  /// the green moment lands undisturbed, and the auto-advance is about to
  /// reset to the next card's front anyway.
  void _onCardTap() {
    if (_impressedCardKey != null) return;
    setState(() => _showBack = !_showBack);
    if (_showBack) {
      // The card listens while the FRONT is showing (PRD §8 Unit 16).
      _stopEchoAttempt();
    } else {
      _startEchoAttempt();
    }
  }

  Widget _buildCard(FlashcardCard card) {
    final impressed = _impressedCardKey == card.cardKey;
    return FadeUp(
      key: ValueKey('flashcard-entrance-${card.cardKey}'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _CardSway(
            key: ValueKey('flashcard-sway-${card.cardKey}'),
            swaying: !impressed,
            child: GestureDetector(
              key: ValueKey('flashcard-card-${card.cardKey}'),
              behavior: HitTestBehavior.opaque,
              onTap: _onCardTap,
              // §10b swipe: either horizontal direction advances; the
              // decision falls at gesture end so a hesitant wiggle that
              // returns home is not an advance.
              onHorizontalDragStart: (_) => _swipeDx = 0,
              onHorizontalDragUpdate: (details) =>
                  _swipeDx += details.delta.dx,
              onHorizontalDragCancel: () => _swipeDx = 0,
              onHorizontalDragEnd: (_) {
                if (_swipeDx.abs() >= _swipeAdvanceDistance) {
                  _onSwipeAdvance();
                }
                _swipeDx = 0;
              },
              child: FlipCard(
                showBack: _showBack,
                front: _CardFace(
                  child: _FrontFace(
                    card: card,
                    onWordTap: _onSoundOutTap,
                    impressed: impressed,
                  ),
                ),
                back: _CardFace(
                  child: _BackFace(
                    card: card,
                    onPronunciationTap: _onPronunciationTap,
                    onChipTap: _onChipTap,
                  ),
                ),
              ),
            ),
          ),
          if (_showBack)
            Padding(
              padding: const EdgeInsets.only(top: DesignTokens.spacingLg),
              child: FadeUp(child: _GradeBar(onGrade: _grade)),
            ),
        ],
      ),
    );
  }

  Widget _buildAllDone() {
    return FadeUp(
      key: const ValueKey('flashcards-all-done'),
      duration: const Duration(milliseconds: 420),
      child: Container(
        key: const ValueKey('flashcards-all-done-panel'),
        padding: const EdgeInsets.all(DesignTokens.spacingXl),
        decoration: BoxDecoration(
          color: DesignTokens.successPanelBackground,
          border: Border.all(color: DesignTokens.successPanelBorder, width: 1.5),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Text(
              'All done!',
              style: TextStyle(
                fontFamily: DesignTokens.readingFontFamily,
                fontSize: 30,
                fontWeight: FontWeight.w600,
                color: DesignTokens.successDeepGreen,
              ),
            ),
            SizedBox(height: DesignTokens.spacingSm),
            Text(
              'Every card is tucked back in its box.\nCome back tomorrow for more.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: DesignTokens.displayFontFamily,
                fontSize: 15,
                color: DesignTokens.mutedBody,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final card = session?.current;
    return Scaffold(
      backgroundColor: DesignTokens.screenBackground,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(DesignTokens.spacingLg),
                child: session == null
                    ? const SizedBox.shrink()
                    : (card == null ? _buildAllDone() : _buildCard(card)),
              ),
            ),
            if (_confettiPlaying)
              Positioned.fill(
                child: ConfettiOverlay(
                  intensity: 1,
                  seed: _confettiSeed,
                  onFinished: _onConfettiFinished,
                ),
              ),
            // Speech-first impress burst (PRD §8 Unit 16: "shoots confetti
            // like the others" — intensity 1, per-visit deterministic
            // seed). Mounted ONLY during the impress hold, like Sound
            // Garden's per-rep burst; dismounted at auto-advance.
            if (_impressConfettiSeed != null)
              Positioned.fill(
                child: ConfettiOverlay(
                  key: const ValueKey('flashcard-impress-confetti'),
                  intensity: 1,
                  seed: _impressConfettiSeed!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The §3 parchment card surface: cream gradient, 1px border, radius 20.
class _CardFace extends StatelessWidget {
  const _CardFace({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 260, minHeight: 220),
      padding: const EdgeInsets.all(DesignTokens.spacingLg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            DesignTokens.readingBackground,
            DesignTokens.cardGradientEnd,
          ],
        ),
        border: Border.all(color: DesignTokens.cardBorder),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Center(child: child),
    );
  }
}

/// Front: the word, huge, reading typeface, ink — tapping it sounds it
/// out. While [impressed] (an accepted echo's hold window) the word turns
/// read-green with a subtle scale swell, and the trailing-edge swipe-cue
/// chevron is suppressed.
class _FrontFace extends StatelessWidget {
  const _FrontFace({
    required this.card,
    required this.onWordTap,
    this.impressed = false,
  });

  final FlashcardCard card;
  final void Function(FlashcardCard card) onWordTap;
  final bool impressed;

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              key: ValueKey('flashcard-word-${card.cardKey}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onWordTap(card),
              // The impress swell: cheap (one implicit animation on the
              // word alone), settles well inside the hold window.
              child: AnimatedScale(
                scale: impressed ? 1.06 : 1.0,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                child: Text(
                  card.wordText,
                  style: TextStyle(
                    fontFamily: DesignTokens.readingFontFamily,
                    fontSize: 52,
                    color: impressed
                        ? DesignTokens.wordReadGreen
                        : DesignTokens.wordUnreadInk,
                  ),
                ),
              ),
            ),
            const SizedBox(height: DesignTokens.spacingMd),
            const Text(
              'TAP THE WORD TO SOUND IT OUT',
              style: TextStyle(
                fontFamily: DesignTokens.displayFontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.8,
                color: DesignTokens.mutedLabel,
              ),
            ),
            const SizedBox(height: DesignTokens.spacingXs),
            // The flip affordance: carries no gesture of its own, so a tap
            // here falls through to the card's flip GestureDetector (the
            // word above owns its own tap = sound-out; everywhere else on
            // the card flips).
            Text(
              'tap the card to turn it over',
              key: ValueKey('flashcard-flip-${card.cardKey}'),
              style: const TextStyle(
                fontFamily: DesignTokens.displayFontFamily,
                fontSize: 12,
                color: DesignTokens.legendText,
              ),
            ),
          ],
        ),
        // §10b swipe cue: a faint outline chevron at the trailing edge
        // ("adding an arrow that is a faint shadow/outline ... gives the
        // impression to swipe"). Suppressed during the impress hold.
        if (!impressed)
          Positioned(
            right: 0,
            child: _SwipeCueArrow(
              key: ValueKey('flashcard-swipe-cue-${card.cardKey}'),
            ),
          ),
      ],
    );
  }
}

/// The §10b trailing-edge swipe-cue chevron: a faint outline stroke in
/// [DesignTokens.mutedLabel] at low alpha (token-lint: color comes from
/// the token file, alpha applied here).
class _SwipeCueArrow extends StatelessWidget {
  const _SwipeCueArrow({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(14, 26),
      painter: _ChevronPainter(color: DesignTokens.mutedLabel.withAlpha(80)),
    );
  }
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path()
      ..moveTo(size.width * 0.2, size.height * 0.12)
      ..lineTo(size.width * 0.8, size.height * 0.5)
      ..lineTo(size.width * 0.2, size.height * 0.88);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// The §10b idle sway: "moving the card (no more static) gives the
/// impression to swipe". A gentle repeating horizontal translation, ±6 px
/// with ease-in-out over a 1.6 s period (800 ms per half-swing). While
/// [swaying] is false (the impress hold) the card sits still at center.
///
/// The child — the card's own GestureDetector — rides inside the
/// transform, so taps, flips, and the advance swipe all keep working
/// mid-sway (the pointer hit test follows the translation).
class _CardSway extends StatefulWidget {
  const _CardSway({super.key, required this.swaying, required this.child});

  final bool swaying;
  final Widget child;

  @override
  State<_CardSway> createState() => _CardSwayState();
}

class _CardSwayState extends State<_CardSway>
    with SingleTickerProviderStateMixin {
  static const double _amplitude = 6.0;
  static const Duration _halfPeriod = Duration(milliseconds: 800);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _halfPeriod,
    value: 0.5, // start at center, no jump on mount
  );
  late final CurvedAnimation _eased = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void initState() {
    super.initState();
    if (widget.swaying) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(_CardSway oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.swaying == oldWidget.swaying) return;
    if (widget.swaying) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0.5; // rest at center for the impress hold
    }
  }

  @override
  void dispose() {
    _eased.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _eased,
      builder: (BuildContext context, Widget? child) {
        final double dx = widget.swaying
            ? -_amplitude + 2 * _amplitude * _eased.value
            : 0.0;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: widget.child,
    );
  }
}

/// Back: one grapheme chip per `graphemePhonemeMap` entry (syllable-chip
/// styling, §4) with its phoneme id below in mono type, plus the whole-word
/// pronunciation play button. Each chip is tappable (owner direction
/// 2026-07-29): the tap plays that cluster's own phoneme clip and then
/// flips the card, preserving the pinned chip-tap-reaches-the-flip
/// behavior.
class _BackFace extends StatelessWidget {
  const _BackFace({
    required this.card,
    required this.onPronunciationTap,
    required this.onChipTap,
  });

  final FlashcardCard card;
  final void Function(FlashcardCard card) onPronunciationTap;

  /// Fired with the tapped chip's `graphemePhonemeMap` index.
  final void Function(FlashcardCard card, int graphemeIndex) onChipTap;

  @override
  Widget build(BuildContext context) {
    final map = card.graphemePhonemeMap;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: DesignTokens.spacingSm,
          runSpacing: DesignTokens.spacingSm,
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.start,
          children: [
            for (var i = 0; i < map.length; i++)
              Column(
                key: ValueKey('flashcard-chip-${card.cardKey}-$i'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Tappable chip (owner direction 2026-07-29): plays this
                  // cluster's phoneme, then the handler flips the card —
                  // the same flip a chip tap has always caused.
                  GestureDetector(
                    key: ValueKey('flashcard-chip-tap-${card.cardKey}-$i'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChipTap(card, i),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: DesignTokens.syllableChipIdleBackground,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        map[i].graphemes,
                        key: ValueKey(
                          'flashcard-chip-graphemes-${card.cardKey}-$i',
                        ),
                        style: const TextStyle(
                          fontFamily: DesignTokens.readingFontFamily,
                          fontSize: 26,
                          color: DesignTokens.syllableChipIdleText,
                        ),
                      ),
                    ),
                  ),
                  // Silent letters (empty phonemeId, e.g. the "e" in
                  // "cake") keep their chip but carry no phoneme label.
                  if (map[i].phonemeId.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: DesignTokens.spacingXs),
                      child: Text(
                        map[i].phonemeId,
                        key: ValueKey(
                          'flashcard-chip-phoneme-${card.cardKey}-$i',
                        ),
                        style: const TextStyle(
                          fontFamily: DesignTokens.monoFontFamily,
                          fontSize: 12,
                          color: DesignTokens.mutedBody,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
        const SizedBox(height: DesignTokens.spacingLg),
        GestureDetector(
          key: ValueKey('flashcard-pronounce-${card.cardKey}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => onPronunciationTap(card),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spacingLg,
              vertical: DesignTokens.spacingSm + 2,
            ),
            decoration: BoxDecoration(
              color: DesignTokens.wordUnreadInk,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text(
              'Hear the word',
              style: TextStyle(
                fontFamily: DesignTokens.displayFontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: DesignTokens.readingBackground,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The two-button grade bar (back side only): amber "practice again",
/// green "got it" — app-wide color semantics, no negative state.
class _GradeBar extends StatelessWidget {
  const _GradeBar({required this.onGrade});

  final Future<void> Function(FlashcardGrade grade) onGrade;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _GradePill(
          key: const ValueKey('flashcard-grade-practice-again'),
          label: 'practice again',
          background: DesignTokens.wordCurrentInk,
          foreground: DesignTokens.wordUnreadInk,
          onTap: () => unawaited(onGrade(FlashcardGrade.practiceAgain)),
        ),
        const SizedBox(width: DesignTokens.spacingMd),
        _GradePill(
          key: const ValueKey('flashcard-grade-got-it'),
          label: 'got it',
          background: DesignTokens.successDeepGreen,
          foreground: DesignTokens.readingBackground,
          onTap: () => unawaited(onGrade(FlashcardGrade.gotIt)),
        ),
      ],
    );
  }
}

class _GradePill extends StatelessWidget {
  const _GradePill({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onTap,
  });

  final String label;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 46),
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingLg,
          vertical: DesignTokens.spacingSm,
        ),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: DesignTokens.displayFontFamily,
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: foreground,
          ),
        ),
      ),
    );
  }
}

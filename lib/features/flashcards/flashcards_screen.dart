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
library;

import 'dart:async';

import 'package:flutter/material.dart' show Scaffold, SafeArea;
import 'package:flutter/widgets.dart';
import 'package:learn_to_read/design/confetti.dart';
import 'package:learn_to_read/design/motion.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/data/db/daos/flashcards_dao.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/phoneme_sequencer.dart';
import 'package:learn_to_read/features/flashcards/flashcard_deck.dart';
import 'package:learn_to_read/features/flashcards/flashcard_progress.dart';
import 'package:learn_to_read/features/flashcards/flashcard_session.dart';
import 'package:learn_to_read/features/flashcards/flip_card.dart';
import 'package:learn_to_read/features/flashcards/leitner_scheduler.dart';

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
  });

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

  @override
  void initState() {
    super.initState();
    unawaited(_load());
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
        ),
      );
    });
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

  Future<void> _grade(FlashcardGrade grade) async {
    final session = _session;
    final card = session?.current;
    if (session == null || card == null || _grading) return;
    _grading = true;
    try {
      final currentBox = _progressByKey[card.cardKey]?.box ?? 1;
      final next = _scheduler.applyGrade(box: currentBox, grade: grade);
      final progress = FlashcardProgress(
        profileId: widget.profileId,
        cardKey: card.cardKey,
        box: next.box,
        dueAt: next.dueAt,
      );
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

  Widget _buildCard(FlashcardCard card) {
    return FadeUp(
      key: ValueKey('flashcard-entrance-${card.cardKey}'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            key: ValueKey('flashcard-card-${card.cardKey}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _showBack = !_showBack),
            child: FlipCard(
              showBack: _showBack,
              front: _CardFace(
                child: _FrontFace(card: card, onWordTap: _onSoundOutTap),
              ),
              back: _CardFace(
                child: _BackFace(
                  card: card,
                  onPronunciationTap: _onPronunciationTap,
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

/// Front: the word, huge, reading typeface, ink — tapping it sounds it out.
class _FrontFace extends StatelessWidget {
  const _FrontFace({required this.card, required this.onWordTap});

  final FlashcardCard card;
  final void Function(FlashcardCard card) onWordTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          key: ValueKey('flashcard-word-${card.cardKey}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => onWordTap(card),
          child: Text(
            card.wordText,
            style: const TextStyle(
              fontFamily: DesignTokens.readingFontFamily,
              fontSize: 52,
              color: DesignTokens.wordUnreadInk,
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
        // The flip affordance: carries no gesture of its own, so a tap here
        // falls through to the card's flip GestureDetector (the word above
        // owns its own tap = sound-out; everywhere else on the card flips).
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
    );
  }
}

/// Back: one grapheme chip per `graphemePhonemeMap` entry (syllable-chip
/// styling, §4) with its phoneme id below in mono type, plus the whole-word
/// pronunciation play button.
class _BackFace extends StatelessWidget {
  const _BackFace({required this.card, required this.onPronunciationTap});

  final FlashcardCard card;
  final void Function(FlashcardCard card) onPronunciationTap;

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
                  Container(
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

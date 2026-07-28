/// The Sound Garden: an illustrated, browsable space of grapheme-sound
/// cards covering the full scope-&-sequence grapheme inventory (PRD §8
/// Unit 15; ticket sound-garden accept entries 1, 3, 4, 10, 11).
///
/// A third child-facing area alongside the progress map (Unit 9) and the
/// collected-things shelf -- free practice, observed only via
/// `sound_card_played` / `sound_card_echo` analytics. There is no "done"
/// state anywhere in this feature (see `no_failure_state_test.dart`'s
/// structural scan).
///
/// Renders the FULL `inventory` (PRD: "all cards visible from day one") as
/// `SoundCardWidget`s. Tapping a card:
///  1. fires `sound_card_played` (no event-specific fields) via
///     `onAnalyticsEvent`,
///  2. calls `playSoundCard(...)` and awaits it,
///  3. once playback ends, IF `profile.micConsent`: sets that card's echo
///     state to listening (amber grapheme) and starts a fresh echo attempt.
///     IF `!profile.micConsent`: the echo state stays hidden and
///     `echoEngine` is never touched (`start` is never called) --
///     listen-only mode.
///
/// PRACTICE LOOP (docs/design/mockup-spec.md §10a; PRD §8 Unit 15
/// "Practice loop", RATIFIED 2026-07-28 -- supersedes the one-shot "warm
/// sparkle" semantics): when the sound-mode scorer accepts, the grapheme
/// turns read-green and a small `ConfettiOverlay` burst plays (intensity 1,
/// seed = [confettiSeedFor] over the card id + rep count, so each rep's
/// confetti differs deterministically). After [kSoundGardenGreenHold]
/// (pinned 1000 ms) the card resets to amber with a FRESH `EchoSession` --
/// a used session is never reused -- and the rep counter increments.
/// Unlimited reps; wrong/no sound simply keeps listening (unchanged
/// no-failure invariant). Each accepted rep fires its own
/// `sound_card_echo` (fields: `{'matched': true}`).
///
/// NEXT CARD (spec §10a + §8): the current practice card carries the
/// bottom-right `PageCurlCorner` dog-ear, ALWAYS enabled -- turning (drag
/// past threshold or tap) advances to the next card in the inventory's
/// existing order, wrapping past the end. Turning never requires an
/// accepted rep and works mid-attempt: the live session is stopped cleanly
/// (the same `EchoSession.stop` path `dispose` uses) before the practice
/// pointer moves. The curl's `nextPage` is a plain themed preview of the
/// next card's face (NOT a real `SoundCardWidget`: the real face carries
/// the pinned `sound-card-*` structural keys, which must stay unique in
/// the tree).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:learn_to_read/design/confetti.dart';
import 'package:learn_to_read/design/page_curl.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/domain/tuning.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/analytics/events.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/matcher/sound_mode_scorer.dart';
import 'package:learn_to_read/features/sound_garden/echo_session.dart';
import 'package:learn_to_read/features/sound_garden/example_words.dart';
import 'package:learn_to_read/features/sound_garden/sound_card.dart';
import 'package:learn_to_read/features/sound_garden/sound_card_controller.dart';

/// Deterministic confetti seed for one practice rep (spec §10a: "seeded
/// from card id + rep count so each rep's confetti differs
/// deterministically").
///
/// A stable FNV-1a hash of [cardId]'s code units, mixed with [rep] --
/// deliberately NOT `Object.hash`/`String.hashCode`, whose values may vary
/// between runs; equal inputs must replay the identical burst.
int confettiSeedFor(String cardId, int rep) {
  var hash = 0x811C9DC5;
  for (final unit in cardId.codeUnits) {
    hash = ((hash ^ unit) * 0x01000193) & 0x7FFFFFFF;
  }
  return hash ^ rep;
}

/// The Sound Garden screen. See the file-level doc comment for the tap
/// sequence, the consent gate, and the §10a practice loop.
class SoundGardenScreen extends StatefulWidget {
  const SoundGardenScreen({
    super.key,
    required this.profile,
    required this.profileOrdinal,
    required this.levelOrdinal,
    required this.installId,
    required this.inventory,
    required this.levels,
    required this.audioService,
    required this.phonemeAudioRefs,
    required this.downloadedExampleWordAudioRefs,
    required this.echoEngine,
    required this.buildScorer,
    required this.onAnalyticsEvent,
  });

  /// The profile browsing this screen -- drives wake state, consent, and
  /// example-word visibility.
  final Profile profile;

  /// The profile's ordinal (1-4), carried straight into every analytics
  /// event.
  final int profileOrdinal;

  /// The profile's current level ordinal, carried straight into every
  /// analytics event.
  final int levelOrdinal;

  /// The per-install UUID, carried straight into every analytics event.
  final String installId;

  /// The FULL grapheme-sound inventory -- every card renders, awake or
  /// muted (PRD: "all cards visible from day one"). Loading the real
  /// inventory from starter content/packs is content-delivery's concern,
  /// not this screen's. Its order is also the §10a page-curl practice
  /// order (wrapping).
  final List<GraphemeSound> inventory;

  /// The level ladder, used to resolve ordinals for wake state and
  /// example-word visibility.
  final List<Level> levels;

  /// The audio seam every card and example-word chip plays through.
  final AudioService audioService;

  /// Phoneme id -> shipped audio ref, for card taps.
  final Map<String, AudioRef> phonemeAudioRefs;

  /// The set of example-word pronunciation refs that have actually been
  /// downloaded (packs arrive separately from the base inventory) -- a card
  /// with no downloaded example-word audio shows only the words it has
  /// audio for.
  final Set<AudioRef> downloadedExampleWordAudioRefs;

  /// The ASR engine an echo attempt is driven over. Never started when
  /// `profile.micConsent` is false.
  final AsrEngine echoEngine;

  /// Builds the sound-mode scorer for one card's echo attempt. Which
  /// phoneme (if any) is double-weighted is a per-card scoring choice this
  /// screen never makes itself -- `GraphemeSound` carries no
  /// `targetPhonemeId` field, so the caller supplies the scorer. Called
  /// once per rep: every fresh attempt gets a fresh scorer (a used
  /// scorer's `accepted` is monotone and can never revert).
  final SoundModeScorer Function(GraphemeSound card) buildScorer;

  /// Receives every `sound_card_played` / `sound_card_echo` event this
  /// screen fires.
  final void Function(AnalyticsEvent event) onAnalyticsEvent;

  @override
  State<SoundGardenScreen> createState() => _SoundGardenScreenState();
}

class _SoundGardenScreenState extends State<SoundGardenScreen> {
  /// Fixed extent of the practice card's page-curl surface. Tall/wide
  /// enough that the curl's bottom-right hit region never covers the card
  /// face's own tap center, and bounded so the curl's internal
  /// `LayoutBuilder` works inside the scrollable `Wrap`.
  static const double _practiceCurlExtent = 160.0;

  final Map<String, CardEchoState> _echoStates = {};
  final Map<String, EchoSession> _sessions = {};

  /// Per-card practice-rep counter (spec §10a): 0 for the first attempt,
  /// incremented at each green-hold reset. Feeds [confettiSeedFor].
  final Map<String, int> _repCounts = {};

  /// Per-card green-hold timers ([kSoundGardenGreenHold]); canceled on
  /// page turn and in [dispose].
  final Map<String, Timer> _holdTimers = {};

  /// Cards currently in their green hold -> that rep's confetti seed. A
  /// `ConfettiOverlay` is mounted ONLY while an entry exists here, so the
  /// tree settles again as soon as every hold ends.
  final Map<String, int> _confettiSeeds = {};

  /// Index (into `widget.inventory`) of the card carrying the §10a
  /// page-curl dog-ear; advances (wrapping) on every finished turn.
  int _practiceIndex = 0;

  @override
  void dispose() {
    for (final timer in _holdTimers.values) {
      timer.cancel();
    }
    for (final session in _sessions.values) {
      if (session.isListening) {
        session.stop();
      }
    }
    super.dispose();
  }

  Future<void> _onCardTap(GraphemeSound card) async {
    widget.onAnalyticsEvent(AnalyticsEvent(
      name: AnalyticsEventName.soundCardPlayed,
      timestamp: systemClock(),
      installId: widget.installId,
      profileOrdinal: widget.profileOrdinal,
      levelOrdinal: widget.levelOrdinal,
    ));

    await playSoundCard(
      card,
      audioService: widget.audioService,
      phonemeAudioRefs: widget.phonemeAudioRefs,
    );

    if (!widget.profile.micConsent || !mounted) {
      return;
    }

    setState(() {
      _echoStates[card.id] = CardEchoState.listening;
    });
    _startEchoAttempt(card);
  }

  /// Starts a FRESH echo attempt for [card]: new scorer, new
  /// [EchoSession] (spec §10a: a used session is never reused). Any prior
  /// live session for this card is stopped first.
  void _startEchoAttempt(GraphemeSound card) {
    final previous = _sessions[card.id];
    if (previous != null && previous.isListening) {
      previous.stop();
    }
    final scorer = widget.buildScorer(card);
    final session = EchoSession(engine: widget.echoEngine, scorer: scorer);
    _sessions[card.id] = session;
    session.start(onMatch: () => _onEchoMatch(card));
  }

  void _onEchoMatch(GraphemeSound card) {
    if (!mounted) return;
    // The attempt is accepted: end this session now -- the next rep gets a
    // brand-new one (§10a).
    final session = _sessions[card.id];
    if (session != null && session.isListening) {
      session.stop();
    }
    final rep = _repCounts[card.id] ?? 0;
    setState(() {
      _echoStates[card.id] = CardEchoState.matched;
      _confettiSeeds[card.id] = confettiSeedFor(card.id, rep);
    });
    widget.onAnalyticsEvent(AnalyticsEvent(
      name: AnalyticsEventName.soundCardEcho,
      timestamp: systemClock(),
      installId: widget.installId,
      profileOrdinal: widget.profileOrdinal,
      levelOrdinal: widget.levelOrdinal,
      fields: const {'matched': true},
    ));
    _holdTimers[card.id]?.cancel();
    _holdTimers[card.id] =
        Timer(kSoundGardenGreenHold, () => _startNextRep(card));
  }

  /// Green hold over (§10a "Reset"): back to amber/listening with a fresh
  /// attempt, rep counter incremented. Unlimited reps.
  void _startNextRep(GraphemeSound card) {
    if (!mounted) return;
    _holdTimers.remove(card.id);
    _repCounts[card.id] = (_repCounts[card.id] ?? 0) + 1;
    setState(() {
      _echoStates[card.id] = CardEchoState.listening;
      _confettiSeeds.remove(card.id);
    });
    _startEchoAttempt(card);
  }

  /// §10a "Next card": the finished page turn. Stops the practice card's
  /// live session cleanly (turning works mid-attempt and never requires an
  /// accepted rep), clears its loop state, and advances the practice
  /// pointer through the inventory's existing order, wrapping.
  void _onPageTurn() {
    if (widget.inventory.isEmpty) return;
    final card = widget.inventory[_practiceIndex % widget.inventory.length];
    final session = _sessions.remove(card.id);
    if (session != null && session.isListening) {
      session.stop();
    }
    _holdTimers.remove(card.id)?.cancel();
    setState(() {
      _echoStates.remove(card.id);
      _confettiSeeds.remove(card.id);
      _practiceIndex = (_practiceIndex + 1) % widget.inventory.length;
    });
  }

  Widget _buildCardTile(GraphemeSound card, {required bool isPractice}) {
    final wakeState = wakeStateFor(card: card, profile: widget.profile, levels: widget.levels);
    final echoState = _echoStates[card.id] ?? CardEchoState.hidden;
    final visibleWords = visibleExampleWords(
      card: card,
      profile: widget.profile,
      levels: widget.levels,
      downloadedAudioRefs: widget.downloadedExampleWordAudioRefs,
    );

    Widget face = SoundCardWidget(
      card: card,
      wakeState: wakeState,
      echoState: echoState,
      onTap: () => _onCardTap(card),
    );

    if (isPractice && widget.inventory.isNotEmpty) {
      final next = widget
          .inventory[(_practiceIndex + 1) % widget.inventory.length];
      face = SizedBox(
        width: _practiceCurlExtent,
        height: _practiceCurlExtent,
        child: PageCurlCorner(
          // §10a: ALWAYS enabled -- never gated on an accepted rep.
          enabled: true,
          onTurned: _onPageTurn,
          page: Align(alignment: Alignment.topCenter, child: face),
          nextPage: Align(
            alignment: Alignment.topCenter,
            child: _NextCardPreview(grapheme: next.grapheme),
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 160),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          face,
          if (visibleWords.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: DesignTokens.spacingXs),
              child: Wrap(
                spacing: DesignTokens.spacingXs,
                runSpacing: DesignTokens.spacingXs,
                alignment: WrapAlignment.center,
                children: [
                  for (final word in visibleWords)
                    ExampleWordChip(
                      wordText: word.wordText,
                      grapheme: card.grapheme,
                      pronunciationAudioRef: word.pronunciationAudioRef,
                      audioService: widget.audioService,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DesignTokens.screenBackground,
      body: Stack(
        children: [
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(DesignTokens.spacingMd),
              child: Wrap(
                spacing: DesignTokens.spacingMd,
                runSpacing: DesignTokens.spacingMd,
                alignment: WrapAlignment.center,
                children: [
                  for (var i = 0; i < widget.inventory.length; i++)
                    _buildCardTile(
                      widget.inventory[i],
                      isPractice: i == _practiceIndex,
                    ),
                ],
              ),
            ),
          ),
          // §10a confetti: one burst per card currently in its green hold
          // (intensity 1, per-rep deterministic seed). Mounted ONLY during
          // the hold window, so no animation outlives it.
          for (final entry in _confettiSeeds.entries)
            Positioned.fill(
              child: ConfettiOverlay(
                key: ValueKey('sound-garden-confetti-${entry.key}'),
                intensity: 1,
                seed: entry.value,
              ),
            ),
        ],
      ),
    );
  }
}

/// The page-curl's underleaf: a plain themed preview of the next card's
/// face (parchment surface, reading typeface). Deliberately NOT a real
/// `SoundCardWidget` -- the real face carries the pinned `sound-card-*`
/// structural `ValueKey`s, which must appear exactly once in the tree.
class _NextCardPreview extends StatelessWidget {
  const _NextCardPreview({required this.grapheme});

  final String grapheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('sound-garden-next-card-preview'),
      width: 96,
      height: 96,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: DesignTokens.surfaceBackground,
        borderRadius: BorderRadius.circular(DesignTokens.spacingMd),
        border: Border.all(
          color: DesignTokens.wordUnreadInk.withAlpha(60),
          width: 2,
        ),
      ),
      child: Text(
        grapheme,
        style: const TextStyle(
          fontFamily: DesignTokens.readingFontFamily,
          fontSize: 40,
          fontWeight: FontWeight.bold,
          color: DesignTokens.wordUnreadInk,
        ),
      ),
    );
  }
}

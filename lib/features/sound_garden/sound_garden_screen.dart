/// The Sound Garden: an illustrated, browsable space of grapheme-sound
/// cards covering the full scope-&-sequence grapheme inventory (PRD §8
/// Unit 15; ticket sound-garden accept entries 1, 3, 4, 10, 11).
///
/// A third child-facing area alongside the progress map (Unit 9) and
/// collection -- free practice, observed only via `sound_card_played` /
/// `sound_card_echo` analytics. There is no "done" state anywhere in this
/// feature (see `no_failure_state_test.dart`'s structural scan).
///
/// Renders the FULL `inventory` (PRD: "all cards visible from day one") as
/// `SoundCardWidget`s. Tapping a card:
///  1. fires `sound_card_played` (no event-specific fields) via
///     `onAnalyticsEvent`,
///  2. calls `playSoundCard(...)` and awaits it,
///  3. once playback ends, IF `profile.micConsent`: sets that card's echo
///     state to listening, builds a scorer via `buildScorer(card)`,
///     constructs an `EchoSession` over `echoEngine` and that scorer, and
///     starts it; the first match sets the echo state to matched and fires
///     `sound_card_echo` (fields: `{'matched': true}`) exactly once. IF
///     `!profile.micConsent`: the echo state stays hidden and `echoEngine`
///     is never touched (`start` is never called) -- listen-only mode.
///
/// Each card also lists its visible example words (`visibleExampleWords`,
/// filtered against `downloadedExampleWordAudioRefs`) as `ExampleWordChip`s
/// beneath it.
library;

import 'package:flutter/material.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/features/analytics/event_schema.dart';
import 'package:learn_to_read/features/analytics/events.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';
import 'package:learn_to_read/features/listening/matcher/sound_mode_scorer.dart';
import 'package:learn_to_read/features/sound_garden/echo_session.dart';
import 'package:learn_to_read/features/sound_garden/example_words.dart';
import 'package:learn_to_read/features/sound_garden/sound_card.dart';
import 'package:learn_to_read/features/sound_garden/sound_card_controller.dart';

/// The Sound Garden screen. See the file-level doc comment for the tap
/// sequence and the consent gate.
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
  /// not this screen's.
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
  /// `targetPhonemeId` field, so the caller supplies the scorer.
  final SoundModeScorer Function(GraphemeSound card) buildScorer;

  /// Receives every `sound_card_played` / `sound_card_echo` event this
  /// screen fires.
  final void Function(AnalyticsEvent event) onAnalyticsEvent;

  @override
  State<SoundGardenScreen> createState() => _SoundGardenScreenState();
}

class _SoundGardenScreenState extends State<SoundGardenScreen> {
  final Map<String, CardEchoState> _echoStates = {};
  final Map<String, EchoSession> _sessions = {};

  @override
  void dispose() {
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

    final scorer = widget.buildScorer(card);
    final session = EchoSession(engine: widget.echoEngine, scorer: scorer);
    _sessions[card.id] = session;
    session.start(onMatch: () => _onEchoMatch(card));
  }

  void _onEchoMatch(GraphemeSound card) {
    if (!mounted) return;
    setState(() {
      _echoStates[card.id] = CardEchoState.matched;
    });
    widget.onAnalyticsEvent(AnalyticsEvent(
      name: AnalyticsEventName.soundCardEcho,
      timestamp: systemClock(),
      installId: widget.installId,
      profileOrdinal: widget.profileOrdinal,
      levelOrdinal: widget.levelOrdinal,
      fields: const {'matched': true},
    ));
  }

  Widget _buildCardTile(GraphemeSound card) {
    final wakeState = wakeStateFor(card: card, profile: widget.profile, levels: widget.levels);
    final echoState = _echoStates[card.id] ?? CardEchoState.hidden;
    final visibleWords = visibleExampleWords(
      card: card,
      profile: widget.profile,
      levels: widget.levels,
      downloadedAudioRefs: widget.downloadedExampleWordAudioRefs,
    );

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 160),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SoundCardWidget(
            card: card,
            wakeState: wakeState,
            echoState: echoState,
            onTap: () => _onCardTap(card),
          ),
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(DesignTokens.spacingMd),
          child: Wrap(
            spacing: DesignTokens.spacingMd,
            runSpacing: DesignTokens.spacingMd,
            alignment: WrapAlignment.center,
            children: [for (final card in widget.inventory) _buildCardTile(card)],
          ),
        ),
      ),
    );
  }
}

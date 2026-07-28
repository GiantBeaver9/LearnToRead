/// One Sound Garden card's face (PRD §8 Unit 15; ticket sound-garden accept
/// entries 1, 2, 4).
///
/// [SoundCardWidget] is presentational and fully controlled by its props --
/// it mirrors `MapNode`'s marker-widget convention (see
/// `test/features/map/map_states_test.dart`): every marker below is a
/// zero-size `KeyedSubtree` sibling, findable by [Key] without depending on
/// paint/pixel output.
///
/// PINNED CONTRAST vs `MapNode`: `MapNode`'s asleep nodes swallow taps
/// (`onTap: isTappable ? onTap : null`). [SoundCardWidget] deliberately does
/// NOT gate on [CardWakeState] -- PRD §8 Unit 15: "Muted cards are still
/// fully tappable and echoable." `onTap` is wired unconditionally, no
/// matter the wake state.
library;

import 'package:flutter/material.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/features/sound_garden/sound_card_controller.dart';

/// A Sound Garden card's echo-attempt state, driven entirely by the caller
/// (`SoundGardenScreen`) -- this widget never starts, scores, or ends an
/// echo attempt itself.
///
/// Practice-loop ruling (docs/design/mockup-spec.md §10a, ratified
/// 2026-07-28): the grapheme's ink follows this state -- amber
/// (`DesignTokens.wordCurrentInk`, "saying now" semantics) while
/// [listening], read-green (`DesignTokens.wordReadGreen`) while [matched],
/// plain ink while [hidden]. `matched` is no longer terminal: the caller
/// holds it for ~1 s and then loops back to [listening] with a fresh echo
/// attempt.
enum CardEchoState { hidden, listening, matched }

/// One grapheme-sound card. See the file-level doc comment for the pinned
/// tap-gating contrast against `MapNode`.
///
/// Structural markers (id == `card.id`):
///   - `ValueKey('sound-card-<id>')`              the tap target
///     (`GestureDetector`), `onTap` ALWAYS wired.
///   - `ValueKey('sound-card-text-<id>')`         the grapheme face `Text`;
///     `.data == card.grapheme`, `style.fontFamily ==
///     DesignTokens.readingFontFamily`.
///   - `ValueKey('sound-card-muted-<id>')`        present iff `wakeState ==
///     CardWakeState.muted`.
///   - `ValueKey('sound-card-echo-prompt-<id>')`  present iff `echoState ==
///     CardEchoState.listening`.
///   - `ValueKey('sound-card-sparkle-<id>')`      present iff `echoState ==
///     CardEchoState.matched`.
class SoundCardWidget extends StatelessWidget {
  const SoundCardWidget({
    super.key,
    required this.card,
    required this.wakeState,
    this.echoState = CardEchoState.hidden,
    required this.onTap,
  });

  /// The card being rendered.
  final GraphemeSound card;

  /// Awake iff `card.introducedAtLevelId` is at or below the profile's
  /// current level -- see `sound_card_controller.dart`'s `wakeStateFor`.
  /// Purely cosmetic here: it dims the card and shows the muted marker, but
  /// never gates `onTap`.
  final CardWakeState wakeState;

  /// The in-flight echo attempt's state, fully controlled by the caller.
  final CardEchoState echoState;

  /// Fired on tap. Wired unconditionally regardless of [wakeState] -- see
  /// the file-level doc comment.
  final VoidCallback onTap;

  static const double _faceSize = 96.0;

  @override
  Widget build(BuildContext context) {
    final muted = wakeState == CardWakeState.muted;
    final matched = echoState == CardEchoState.matched;

    // Practice-loop grapheme ink (docs/design/mockup-spec.md §10a): amber
    // while listening ("saying now"), read-green during the matched hold,
    // plain ink otherwise.
    final graphemeInk = switch (echoState) {
      CardEchoState.hidden => DesignTokens.wordUnreadInk,
      CardEchoState.listening => DesignTokens.wordCurrentInk,
      CardEchoState.matched => DesignTokens.wordReadGreen,
    };

    return GestureDetector(
      key: ValueKey('sound-card-${card.id}'),
      onTap: onTap,
      child: Opacity(
        opacity: muted ? 0.55 : 1.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: _faceSize,
              height: _faceSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: DesignTokens.surfaceBackground,
                borderRadius: BorderRadius.circular(DesignTokens.spacingMd),
                border: Border.all(
                  color: matched ? DesignTokens.wordReadGreen : DesignTokens.wordUnreadInk.withAlpha(60),
                  width: matched ? 4 : 2,
                ),
              ),
              child: Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  Text(
                    card.grapheme,
                    key: ValueKey('sound-card-text-${card.id}'),
                    style: TextStyle(
                      fontFamily: DesignTokens.readingFontFamily,
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: graphemeInk,
                    ),
                  ),
                  if (matched)
                    Positioned(
                      top: -DesignTokens.spacingSm,
                      right: -DesignTokens.spacingSm,
                      child: KeyedSubtree(
                        key: ValueKey('sound-card-sparkle-${card.id}'),
                        child: const Icon(
                          Icons.auto_awesome,
                          color: DesignTokens.wordReadGreen,
                          size: 24,
                        ),
                      ),
                    ),
                  if (muted)
                    Positioned(
                      bottom: -DesignTokens.spacingSm,
                      child: KeyedSubtree(
                        key: ValueKey('sound-card-muted-${card.id}'),
                        child: const Icon(
                          Icons.nightlight_round,
                          color: DesignTokens.wordUnreadInk,
                          size: 16,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (echoState == CardEchoState.listening)
              Padding(
                padding: const EdgeInsets.only(top: DesignTokens.spacingXs),
                child: KeyedSubtree(
                  key: ValueKey('sound-card-echo-prompt-${card.id}'),
                  child: const Icon(
                    Icons.mic_none,
                    color: DesignTokens.wordVocabBlue,
                    size: 20,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

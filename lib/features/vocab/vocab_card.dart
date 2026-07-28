/// The vocabulary definition card itself (PRD §8 Unit 7; ticket vocab-cards
/// accept entries 1, 2, 3, 6).
///
/// [VocabCardPopover] is a self-contained, full-bleed overlay: it owns its
/// own tap-outside barrier rather than relying on a host `showDialog`/
/// `Navigator` barrier, and it owns its own `SafeArea` rather than depending
/// on the reading screen's. That is deliberate — "this ticket owns the card
/// itself" — because the card can be requested while the reading screen is
/// in any layout class, and it must never let its close affordance land
/// under a notch/home-indicator/status bar.
///
/// The seam that wires this popover into a real [ReadingScreen]
/// (`lib/features/reading/reading_screen.dart`) — including logging
/// `vocab_card_opened` and resolving `VocabCardOpener`'s future on close —
/// lives in `vocab_card_opener.dart`, not here. This file only renders the
/// card and plays its audio.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:learn_to_read/design/motion.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart' show VocabCard;
import 'package:learn_to_read/features/audio/audio_service.dart';

/// The audio channel every vocab-card play (definition autoplay, replay, and
/// word pronunciation) is tagged with: recorded-narrator read-aloud content,
/// the same channel sentence/story narration uses — not the Unit 6 help
/// scaffold and not celebration/ambient audio.
const AudioChannel kVocabCardAudioChannel = AudioChannel.narration;

/// Illustration slot size (mockup §4: a 150x110 supporting-image slot,
/// never the star of the card — the word and definition are).
const double kVocabCardIllustrationWidth = 150.0;

/// See [kVocabCardIllustrationWidth].
const double kVocabCardIllustrationHeight = 110.0;

/// Diameter of the round close affordance (mockup §4: 40x40).
const double kVocabCardCloseButtonSize = 40.0;

/// A playful popover card showing one vocabulary word's authored,
/// kid-friendly definition (PRD §8 Unit 7).
///
/// The definition plays automatically, once, as soon as this widget first
/// builds; the replay affordance repeats it on demand, and tapping the
/// word itself plays [pronunciationAudioRef] (a no-op when absent). Dismiss
/// fires [onClosed] exactly once, whether triggered by the tap-outside
/// barrier, the close affordance, or (defensively) both before the caller
/// removes this widget from the tree.
class VocabCardPopover extends StatefulWidget {
  /// Creates a popover for [card].
  ///
  /// [pronunciationAudioRef] is the originating word's own pronunciation
  /// clip — plumbed in separately because [VocabCard] itself carries no
  /// pronunciation ref, only [VocabCard.definitionAudioRef].
  const VocabCardPopover({
    super.key,
    required this.card,
    required this.audioService,
    this.pronunciationAudioRef,
    required this.onClosed,
  });

  /// The card being shown.
  final VocabCard card;

  /// Where every play call on this card goes.
  final AudioService audioService;

  /// The word's own pronunciation clip, or null when unknown -- tapping the
  /// word is then a graceful no-op.
  final String? pronunciationAudioRef;

  /// Fired exactly once when the card is dismissed, by any path.
  final VoidCallback onClosed;

  @override
  State<VocabCardPopover> createState() => _VocabCardPopoverState();
}

class _VocabCardPopoverState extends State<VocabCardPopover> {
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    // Fires exactly once per card open: `initState` runs once per State,
    // never again on a same-key rebuild of the same widget.
    _playDefinition();
  }

  void _playDefinition() {
    unawaited(
      widget.audioService.play(
        widget.card.definitionAudioRef,
        channel: kVocabCardAudioChannel,
      ),
    );
  }

  void _playPronunciation() {
    final ref = widget.pronunciationAudioRef;
    if (ref == null) return;
    unawaited(widget.audioService.play(ref, channel: kVocabCardAudioChannel));
  }

  void _dismiss() {
    if (_closed) return;
    _closed = true;
    widget.onClosed();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        // The tap-outside barrier: full-bleed and BEHIND the card in this
        // Stack, so it only ever catches a tap that the card content did
        // not already claim.
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey<String>('vocab-card-barrier'),
            behavior: HitTestBehavior.opaque,
            onTap: _dismiss,
            child: ColoredBox(
              color: DesignTokens.wordUnreadInk.withValues(alpha: 0.35),
            ),
          ),
        ),
        Center(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(DesignTokens.spacingMd),
              // Mockup §4: the popup enters with a 320 ms fadeUp.
              child: FadeUp(
                duration: const Duration(milliseconds: 320),
                // Absorbs any tap that lands on the card's own surface (away
                // from the three interactive affordances below) so it can
                // never fall through to the barrier behind it.
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    // Layered surface: the outer box keeps the pinned
                    // parchment surface paint (frozen contract:
                    // test/features/vocab/vocab_card_test.dart asserts some
                    // box paints exactly DesignTokens.surfaceBackground);
                    // the inner box applies the mockup §4 vocab-popup
                    // blue-tinted background and border over it.
                    child: DecoratedBox(
                      key: const ValueKey<String>('vocab-card-popover'),
                      decoration: BoxDecoration(
                        color: DesignTokens.surfaceBackground,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: DesignTokens.vocabPopupBackground,
                          border: Border.all(
                            color: DesignTokens.vocabPopupBorder,
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: DesignTokens.wordUnreadInk
                                  .withValues(alpha: 0.35),
                              offset: const Offset(0, 14),
                              blurRadius: 36,
                              spreadRadius: -24,
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.all(DesignTokens.spacingLg),
                        // Scrolls internally rather than ever overflowing: a
                        // long, paragraph-level definition on a short
                        // landscape phone can exceed the safe area's height,
                        // and this is the graceful fallback.
                        child: SingleChildScrollView(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: <Widget>[
                              Align(
                                alignment: Alignment.topRight,
                                // Mockup §4: round 40x40 close affordance in
                                // the popup's own blue family.
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Color.lerp(
                                      DesignTokens.vocabPopupBackground,
                                      DesignTokens.vocabPopupBorder,
                                      0.55,
                                    ),
                                  ),
                                  child: IconButton(
                                    key: const ValueKey<String>(
                                      'vocab-card-close-button',
                                    ),
                                    onPressed: _dismiss,
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints.tightFor(
                                      width: kVocabCardCloseButtonSize,
                                      height: kVocabCardCloseButtonSize,
                                    ),
                                    iconSize: 22,
                                    icon: const Icon(
                                      Icons.close,
                                      color: DesignTokens.vocabPopupHeading,
                                    ),
                                  ),
                                ),
                              ),
                              GestureDetector(
                                key: const ValueKey<String>(
                                  'vocab-card-word-tap',
                                ),
                                onTap: _playPronunciation,
                                child: Text(
                                  widget.card.word,
                                  key: const ValueKey<String>('vocab-card-word'),
                                  textAlign: TextAlign.center,
                                  // Serif word, mockup §4 (26-34, weight
                                  // 600). Color stays the pinned
                                  // wordVocabBlue -- the frozen suite ties
                                  // the popup back to the blue word that
                                  // opened it.
                                  style: const TextStyle(
                                    fontFamily: DesignTokens.readingFontFamily,
                                    fontSize: 34,
                                    fontWeight: FontWeight.w600,
                                    color: DesignTokens.wordVocabBlue,
                                  ),
                                ),
                              ),
                              if (widget.card.illustrationRef !=
                                  null) ...<Widget>[
                                const SizedBox(height: DesignTokens.spacingMd),
                                _VocabCardIllustration(
                                  ref: widget.card.illustrationRef!,
                                ),
                              ],
                              const SizedBox(height: DesignTokens.spacingMd),
                              // Meaning text, mockup §4: 16.5px / 1.45,
                              // capped at a comfortable measure. Color stays
                              // the pinned wordUnreadInk.
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 380),
                                child: Text(
                                  widget.card.definitionText,
                                  key: const ValueKey<String>(
                                    'vocab-card-definition',
                                  ),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontFamily: DesignTokens.readingFontFamily,
                                    fontSize: 16.5,
                                    height: 1.45,
                                    color: DesignTokens.wordUnreadInk,
                                  ),
                                ),
                              ),
                              const SizedBox(height: DesignTokens.spacingMd),
                              IconButton(
                                key: const ValueKey<String>(
                                  'vocab-card-replay-button',
                                ),
                                onPressed: _playDefinition,
                                icon: const Icon(
                                  Icons.replay,
                                  color: DesignTokens.vocabPopupHeading,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The optional small illustration slot.
///
/// [ref] is an opaque pack-relative asset reference, exactly like
/// [AudioRef]: the real image pipeline is an owner-supplied asset (PRD §10
/// OQ-8), not something this container renders pixels for. This slot is a
/// token-styled placeholder so the layout it occupies is real and testable
/// without real art.
class _VocabCardIllustration extends StatelessWidget {
  const _VocabCardIllustration({required this.ref});

  final String ref;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: const ValueKey<String>('vocab-card-illustration'),
      decoration: BoxDecoration(
        color: DesignTokens.readingBackground,
        border: Border.all(color: DesignTokens.vocabPopupBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const SizedBox(
        width: kVocabCardIllustrationWidth,
        height: kVocabCardIllustrationHeight,
      ),
    );
  }
}

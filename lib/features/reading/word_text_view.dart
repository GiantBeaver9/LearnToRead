/// Story text rendering for the reading screen (PRD §8 Unit 5, word states
/// from PRD §8 Unit 1; restyled to the owner's "Sound It Out" mockup,
/// docs/design/mockup-spec.md §3-§4).
///
/// [WordTextView] is the only place story words become pixels. It renders
/// one page of already-computed [WordState]s: it holds no state machine, no
/// recognition logic, and no opinion about what a word means -- it is a
/// pure projection of `WordState.renderColor` plus the affordances the
/// design system pins on top of it (the current-word marker, the discreet
/// tap targets, the vocab dotted underline, and the stuck-word pulse).
///
/// Pinned rendering rules, all token-driven:
///  - unread ink, vocab blue while unread, current amber plus a marker, and
///    once done: read green for ordinary words, vocab-read purple for vocab
///    words (owner ruling 2026-07-28) -- straight from
///    [WordState.renderColor], so accepted, near-miss and helped words are
///    pixel-identical per word kind (there is no helped badge, by design).
///  - the green transition is an animated per-word sweep over
///    [DesignTokens.greenSweepDuration], never an instant recolor, and it
///    makes no sound: audio is reserved for help and celebration so the
///    child own voice stays the primary audio.
///  - during Tier-1 sound-out the current word renders one chip per
///    `WordToken.graphemePhonemeMap` entry inside the mockup's hint panel
///    ("take it slowly" styling, spec §4), so a digraph lights as one unit.
///    The active-chip timing is owned entirely by the Unit 6 sound-out
///    stream -- this file only styles whatever index it is handed.
///  - the stuck word pulses ([PulseWord], spec §3/§7) only while the screen
///    already reports a stuck/hint signal (`WordState.struggling` or an
///    active help tier); the pulse widget is always mounted but only ticks
///    while active, so settle-based tests never meet a live loop.
///  - the current word is always tappable (the Unit 4 fallback input) and a
///    vocab word is tappable at any point in its lifecycle; where both
///    apply, the vocab card wins.
///
/// Nothing here can express negative feedback: there is no failure state to
/// render, and every color comes from [DesignTokens].
library;

import 'package:flutter/material.dart';

import 'package:learn_to_read/design/motion.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart' show WordToken;
import 'package:learn_to_read/domain/models/user_models.dart' show HelpLevel;
import 'package:learn_to_read/features/listening/contracts/help_state.dart';
import 'package:learn_to_read/features/reading/word_state.dart';

/// Thickness of the current-word marker rule.
const double kCurrentWordMarkerThickness = 3.0;

/// Opacity of the current-word marker: a subtle underline/glow under the
/// amber "saying now" word, not a second color token.
const double kCurrentWordMarkerOpacity = 0.55;

/// Reading-text line height (mockup §2 band 1.5-1.7; the sentence end).
const double kReadingTextLineHeight = 1.5;

/// Reading-text letter spacing as a fraction of the font size
/// (mockup §2: -0.005em).
const double kReadingTextLetterSpacingEm = -0.005;

/// Dotted-underline thickness on an unread vocab word (mockup §3).
const double kVocabUnderlineThickness = 2.0;

/// Renders one page of story text.
class WordTextView extends StatelessWidget {
  /// Creates a view over [words] rendered per [wordStates].
  ///
  /// [words] and [wordStates] are index-aligned views of the same page;
  /// [helpState] applies to the current word only (Unit 6 owns producing
  /// it); [textSize] is the caller-resolved reading text token for this
  /// layout class and level format.
  const WordTextView({
    super.key,
    required this.words,
    required this.wordStates,
    required this.helpState,
    required this.textSize,
    required this.onCurrentWordTap,
    required this.onVocabWordTap,
  });

  /// The page word tokens, in reading order.
  final List<WordToken> words;

  /// The per-word state for the same page, index-aligned with [words].
  final List<WordState> wordStates;

  /// The active help tier and grapheme highlight (Unit 6).
  final HelpState helpState;

  /// The reading text size token for this layout class and level format.
  final double textSize;

  /// Fired with the word index when the current word is tapped: the
  /// always-available tap fallback (Unit 4 UI side).
  final void Function(int index) onCurrentWordTap;

  /// Fired with the word index when a vocab-tappable word is tapped.
  final void Function(int index) onVocabWordTap;

  @override
  Widget build(BuildContext context) {
    final count = words.length < wordStates.length ? words.length : wordStates.length;
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: DesignTokens.spacingMd,
      runSpacing: DesignTokens.spacingMd,
      children: <Widget>[
        for (var index = 0; index < count; index++) _buildWord(index),
      ],
    );
  }

  Widget _buildWord(int index) {
    final state = wordStates[index];
    final token = words[index];
    final isCurrent = state.lifecycle == WordLifecycle.current;
    final tapKind = _tapKindFor(state);
    final soundingOut = _isSoundingOut(isCurrent, token);
    // The mockup's stuck-word pulse (spec §3): active only while the screen
    // already reports a stuck/hint signal for the current word. During the
    // Tier-1 chip panel the word body IS the hint panel, so the pulse rests.
    final pulsing = isCurrent &&
        !soundingOut &&
        (state.struggling || helpState.currentHelpTier != HelpLevel.none);

    // Marker and tap layer are positioned siblings laid over the word, not
    // wrappers around it: that keeps the animated text element identical
    // across a lifecycle change, so the green sweep actually animates
    // instead of being rebuilt from scratch as an instant recolor. Both are
    // positioned, so the word body alone decides this stack size. The
    // [PulseWord] wrapper is likewise ALWAYS mounted (its `active` flag
    // toggles) so the word's element identity survives entering/leaving the
    // stuck state.
    return Stack(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: _markerLane),
          child: PulseWord(
            active: pulsing,
            child: _buildWordBody(index, token, state, soundingOut),
          ),
        ),
        if (isCurrent)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: DecoratedBox(
              key: ValueKey<String>('word-current-marker-$index'),
              decoration: BoxDecoration(
                color: DesignTokens.wordCurrentInk.withValues(alpha: kCurrentWordMarkerOpacity),
                borderRadius: BorderRadius.circular(kCurrentWordMarkerThickness),
              ),
              child: const SizedBox(height: kCurrentWordMarkerThickness),
            ),
          ),
        if (tapKind != null)
          Positioned.fill(
            child: GestureDetector(
              key: ValueKey<String>('word-tap-$index'),
              behavior: HitTestBehavior.opaque,
              onTap: tapKind == _TapKind.vocabCard
                  ? () => onVocabWordTap(index)
                  : () => onCurrentWordTap(index),
            ),
          ),
      ],
    );
  }

  /// Vocab wins over the tap fallback wherever both apply: a blue word is
  /// tappable at any point in its lifecycle, including while it is the
  /// current word and after it has turned green.
  _TapKind? _tapKindFor(WordState state) {
    if (state.vocabTappable) return _TapKind.vocabCard;
    if (state.lifecycle == WordLifecycle.current) return _TapKind.currentWord;
    return null;
  }

  bool _isSoundingOut(bool isCurrent, WordToken token) =>
      isCurrent &&
      helpState.currentHelpTier == HelpLevel.soundOut &&
      helpState.highlightedGraphemeIndex >= 0 &&
      token.graphemePhonemeMap.isNotEmpty;

  Widget _buildWordBody(int index, WordToken token, WordState state, bool soundingOut) {
    if (soundingOut) {
      return _SoundOutHintPanel(
        wordIndex: index,
        token: token,
        highlightedGraphemeIndex: helpState.highlightedGraphemeIndex,
        textSize: textSize,
      );
    }
    return _SweepingWordText(
      index: index,
      text: token.text,
      color: state.renderColor,
      textSize: textSize,
      // Mockup §3: a not-yet-read vocab word is weight 600 with a dotted
      // underline inviting the tap; once current/read it renders like any
      // other word (color still flows from renderColor).
      isVocabUnread:
          state.vocabTappable && state.lifecycle == WordLifecycle.unread,
    );
  }

}

/// Vertical room reserved under every word for the current-word marker, so
/// the marker appearing and disappearing never reflows the page.
const double _markerLane = kCurrentWordMarkerThickness + DesignTokens.spacingXs;

/// Which of the two tap paths a word offers.
enum _TapKind { vocabCard, currentWord }

/// One word, animating between word-state colors over the motion token.
///
/// The sweep is what makes a resolved word feel earned rather than simply
/// recolored; it is the only feedback a resolved word produces, since no
/// per-word sound is ever played.
class _SweepingWordText extends StatelessWidget {
  const _SweepingWordText({
    required this.index,
    required this.text,
    required this.color,
    required this.textSize,
    required this.isVocabUnread,
  });

  final int index;
  final String text;
  final Color color;
  final double textSize;
  final bool isVocabUnread;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: color),
      duration: DesignTokens.greenSweepDuration,
      curve: Curves.easeOut,
      builder: (context, sweptColor, _) {
        return Text(
          text,
          key: ValueKey<String>('word-text-$index'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: DesignTokens.readingFontFamily,
            fontSize: textSize,
            height: kReadingTextLineHeight,
            letterSpacing: textSize * kReadingTextLetterSpacingEm,
            fontWeight: isVocabUnread ? FontWeight.w600 : FontWeight.w400,
            decoration: isVocabUnread ? TextDecoration.underline : TextDecoration.none,
            decorationStyle: isVocabUnread ? TextDecorationStyle.dotted : null,
            decorationColor: isVocabUnread ? DesignTokens.wordVocabBlue : null,
            decorationThickness: isVocabUnread ? kVocabUnderlineThickness : null,
            color: sweptColor ?? color,
          ),
        );
      },
    );
  }
}

/// The Tier-1 "take it slowly" hint panel (mockup §4): the current word
/// rendered one grapheme-cluster chip per `graphemePhonemeMap` entry, the
/// chip whose phoneme is playing lit amber, inside the warm hint panel with
/// its small-caps label. Enters with the spec's 380 ms fadeUp.
///
/// Clusters come from the authored `graphemePhonemeMap`, so a digraph is
/// one chip and is never split letter by letter. Which chip is active is
/// decided entirely upstream (PhonemeSequencer -> SoundOutSequence ->
/// HelpState); this widget never re-times anything.
class _SoundOutHintPanel extends StatelessWidget {
  const _SoundOutHintPanel({
    required this.wordIndex,
    required this.token,
    required this.highlightedGraphemeIndex,
    required this.textSize,
  });

  final int wordIndex;
  final WordToken token;
  final int highlightedGraphemeIndex;
  final double textSize;

  @override
  Widget build(BuildContext context) {
    return FadeUp(
      duration: const Duration(milliseconds: 380),
      child: Container(
        key: ValueKey<String>('sound-out-hint-panel-$wordIndex'),
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingMd,
          vertical: DesignTokens.spacingSm,
        ),
        decoration: BoxDecoration(
          color: DesignTokens.hintPanelBackground,
          border: Border.all(color: DesignTokens.hintPanelBorder, width: 1.5),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              "LET'S TAKE IT SLOWLY",
              style: TextStyle(
                fontFamily: DesignTokens.displayFontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 12 * 0.14,
                color: DesignTokens.hintLabel,
              ),
            ),
            const SizedBox(height: DesignTokens.spacingSm),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                for (var g = 0; g < token.graphemePhonemeMap.length; g++) ...<Widget>[
                  if (g > 0) const SizedBox(width: DesignTokens.spacingXs),
                  _buildChip(g),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChip(int g) {
    final active = g == highlightedGraphemeIndex;
    return AnimatedContainer(
      duration: DesignTokens.greenSweepDuration,
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingSm + DesignTokens.spacingXs,
        vertical: DesignTokens.spacingXs,
      ),
      decoration: BoxDecoration(
        color: active
            ? DesignTokens.wordCurrentInk
            : DesignTokens.syllableChipIdleBackground,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        token.graphemePhonemeMap[g].graphemes,
        key: ValueKey<String>('grapheme-$wordIndex-$g'),
        style: TextStyle(
          fontFamily: DesignTokens.readingFontFamily,
          fontSize: textSize,
          height: 1.2,
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
          color: active
              ? DesignTokens.wordUnreadInk
              : DesignTokens.syllableChipIdleText,
        ),
      ),
    );
  }
}

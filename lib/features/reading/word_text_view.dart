/// Story text rendering for the reading screen (PRD §8 Unit 5, word states
/// from PRD §8 Unit 1).
///
/// [WordTextView] is the only place story words become pixels. It renders
/// one page of already-computed [WordState]s: it holds no state machine, no
/// recognition logic, and no opinion about what a word means -- it is a
/// pure projection of `WordState.renderColor` plus the two affordances the
/// design system pins on top of it (the current-word marker and the
/// discreet tap targets).
///
/// Pinned rendering rules, all token-driven:
///  - unread ink, vocab blue while unread, current ink plus a marker, and
///    read green once done -- straight from [WordState.renderColor], so
///    accepted, near-miss and helped words are pixel-identical (there is no
///    helped badge, by design).
///  - the green transition is an animated per-word sweep over
///    [DesignTokens.greenSweepDuration], never an instant recolor, and it
///    makes no sound: audio is reserved for help and celebration so the
///    child own voice stays the primary audio.
///  - during Tier-1 sound-out the current word renders one span per
///    `WordToken.graphemePhonemeMap` entry, so a digraph lights as one unit.
///  - the current word is always tappable (the Unit 4 fallback input) and a
///    vocab word is tappable at any point in its lifecycle; where both
///    apply, the vocab card wins.
///
/// Nothing here can express negative feedback: there is no failure state to
/// render, and every color comes from [DesignTokens].
library;

import 'package:flutter/material.dart';

import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart' show WordToken;
import 'package:learn_to_read/domain/models/user_models.dart' show HelpLevel;
import 'package:learn_to_read/features/listening/contracts/help_state.dart';
import 'package:learn_to_read/features/reading/word_state.dart';

/// Thickness of the current-word marker rule.
const double kCurrentWordMarkerThickness = 3.0;

/// Opacity of the current-word marker: a subtle underline/glow in ink, not
/// a second color token.
const double kCurrentWordMarkerOpacity = 0.55;

/// Opacity applied to the non-highlighted grapheme clusters of a word being
/// sounded out, so the cluster currently playing reads as the active one.
const double kUnhighlightedGraphemeOpacity = 0.45;

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

    // Marker and tap layer are positioned siblings laid over the word, not
    // wrappers around it: that keeps the animated text element identical
    // across a lifecycle change, so the green sweep actually animates
    // instead of being rebuilt from scratch as an instant recolor. Both are
    // positioned, so the word body alone decides this stack size.
    return Stack(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(bottom: _markerLane),
          child: _buildWordBody(index, token, state, isCurrent),
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

  Widget _buildWordBody(int index, WordToken token, WordState state, bool isCurrent) {
    final soundingOut = isCurrent &&
        helpState.currentHelpTier == HelpLevel.soundOut &&
        helpState.highlightedGraphemeIndex >= 0 &&
        token.graphemePhonemeMap.isNotEmpty;
    if (soundingOut) {
      return _GraphemeSpans(
        wordIndex: index,
        token: token,
        highlightedGraphemeIndex: helpState.highlightedGraphemeIndex,
        color: state.renderColor,
        textSize: textSize,
      );
    }
    return _SweepingWordText(
      index: index,
      text: token.text,
      color: state.renderColor,
      textSize: textSize,
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
  });

  final int index;
  final String text;
  final Color color;
  final double textSize;

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
            height: 1.2,
            color: sweptColor ?? color,
          ),
        );
      },
    );
  }
}

/// The current word rendered one grapheme cluster per span during Tier-1
/// sound-out, with the cluster whose phoneme is playing brought forward.
///
/// Clusters come from the authored `graphemePhonemeMap`, so a digraph is
/// one span and is never split letter by letter.
class _GraphemeSpans extends StatelessWidget {
  const _GraphemeSpans({
    required this.wordIndex,
    required this.token,
    required this.highlightedGraphemeIndex,
    required this.color,
    required this.textSize,
  });

  final int wordIndex;
  final WordToken token;
  final int highlightedGraphemeIndex;
  final Color color;
  final double textSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        for (var g = 0; g < token.graphemePhonemeMap.length; g++)
          Text(
            token.graphemePhonemeMap[g].graphemes,
            key: ValueKey<String>('grapheme-$wordIndex-$g'),
            style: TextStyle(
              fontFamily: DesignTokens.readingFontFamily,
              fontSize: textSize,
              height: 1.2,
              fontWeight: g == highlightedGraphemeIndex ? FontWeight.bold : FontWeight.normal,
              color: g == highlightedGraphemeIndex
                  ? color
                  : color.withValues(alpha: kUnhighlightedGraphemeOpacity),
            ),
          ),
      ],
    );
  }
}

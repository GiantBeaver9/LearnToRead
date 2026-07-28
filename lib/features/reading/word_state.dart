/// Per-word state model for the Unit 5 word state machine (PRD §8 Unit 5,
/// docs/tickets/word-state-machine.json).
///
/// Pure data: [WordLifecycle], [WordResolution], and the immutable
/// [WordState] snapshot for a single word, including the pinned
/// lifecycle -> [DesignTokens] color mapping. All mutation/transition logic
/// lives in word_state_machine.dart -- this file has none.
library;

import 'package:flutter/widgets.dart' show Color;

import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/user_models.dart' show HelpLevel;

/// A word's position in the `unread -> current -> done` lifecycle (PRD §8
/// Unit 5). Driven solely by the state machine in response to tracker
/// events -- never set directly by UI code.
enum WordLifecycle { unread, current, done }

/// How a `done` word was resolved.
///
/// Purely an observer-facing distinction (analytics `word_read`
/// correct/near_miss/helped, `WordHelpRecord` writers) -- it never changes
/// [WordState.renderColor]. `none` is the default for words that have not
/// yet resolved.
enum WordResolution { none, accepted, acceptedNearMiss, helped }

/// Immutable per-word state snapshot.
///
/// Produced and replaced (never mutated in place) by [WordStateMachine] as
/// tracker events are applied. Two [WordState]s are `==` iff every field is
/// equal.
class WordState {
  const WordState({
    required this.index,
    required this.lifecycle,
    this.resolution = WordResolution.none,
    this.helpTier,
    this.vocabTappable = false,
    this.struggling = false,
  });

  /// This word's 0-based position within its page.
  final int index;

  /// Where this word sits in the `unread -> current -> done` lifecycle.
  final WordLifecycle lifecycle;

  /// How a `done` word was resolved; [WordResolution.none] until then.
  final WordResolution resolution;

  /// The help tier reached, when [resolution] is [WordResolution.helped];
  /// `null` otherwise. Retained for `WordHelpRecord` writers even though it
  /// has no visual effect (helped words render identically to accepted).
  final HelpLevel? helpTier;

  /// Whether this word is tappable to open its vocab card (PRD §8 Unit 7):
  /// true iff the word's `WordToken.vocabCardId` is set AND the owning
  /// `Level.vocabEnabled` is true. Static for the word's lifetime -- it does
  /// NOT change with [lifecycle] (vocab words are tappable "at any time" per
  /// PRD Unit 5). It affects [renderColor] while `unread` (vocab blue) and
  /// once `done` (vocab-read purple, owner ruling 2026-07-28); the `current`
  /// amber is shared by every word kind.
  final bool vocabTappable;

  /// True while the current word is being struggled with (set by a
  /// `StruggleDetected` tracker event, cleared the moment the word
  /// resolves). Never true for a non-current word.
  final bool struggling;

  /// The color this word renders in, pinned to [DesignTokens] -- never a
  /// raw hex literal. Derived solely from [lifecycle] plus [vocabTappable]:
  /// a `done` ordinary word renders [DesignTokens.wordReadGreen] and a
  /// `done` vocab word renders [DesignTokens.wordVocabReadPurple] (owner
  /// ruling 2026-07-28, PRD §8 Unit 1) -- in BOTH cases regardless of which
  /// [resolution] produced it (accepted, near-miss, and helped are visually
  /// IDENTICAL per word kind -- the literal Unit 1/5/6 ratification; the
  /// invisible-help rule is per word kind, so helped-vocab == read-vocab).
  Color get renderColor {
    switch (lifecycle) {
      case WordLifecycle.unread:
        return vocabTappable ? DesignTokens.wordVocabBlue : DesignTokens.wordUnreadInk;
      case WordLifecycle.current:
        return DesignTokens.wordCurrentInk;
      case WordLifecycle.done:
        return vocabTappable ? DesignTokens.wordVocabReadPurple : DesignTokens.wordReadGreen;
    }
  }

  /// Returns a copy with the given fields replaced. Internal to this
  /// feature -- callers outside the state machine should treat [WordState]
  /// as read-only.
  WordState copyWith({
    WordLifecycle? lifecycle,
    WordResolution? resolution,
    HelpLevel? helpTier,
    bool? struggling,
  }) {
    return WordState(
      index: index,
      lifecycle: lifecycle ?? this.lifecycle,
      resolution: resolution ?? this.resolution,
      helpTier: helpTier ?? this.helpTier,
      vocabTappable: vocabTappable,
      struggling: struggling ?? this.struggling,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is WordState &&
          other.index == index &&
          other.lifecycle == lifecycle &&
          other.resolution == resolution &&
          other.helpTier == helpTier &&
          other.vocabTappable == vocabTappable &&
          other.struggling == struggling);

  @override
  int get hashCode => Object.hash(index, lifecycle, resolution, helpTier, vocabTappable, struggling);

  @override
  String toString() => 'WordState(index: $index, lifecycle: $lifecycle, resolution: $resolution, '
      'helpTier: $helpTier, vocabTappable: $vocabTappable, struggling: $struggling)';
}

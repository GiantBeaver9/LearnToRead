/// Help state contract: rendered by reading screen, produced by stuck-word scaffold.
///
/// Captures the current help tier and the grapheme cluster being highlighted
/// during Tier 1 sound-out (Unit 6).
library;

import 'package:learn_to_read/domain/models/user_models.dart';

/// Shared contract for help rendering and production.
///
/// The reading screen consumes [HelpState] to render help UI and highlight
/// grapheme clusters as they are sounded out. The stuck-word scaffold
/// produces [HelpState] updates as it guides the child through help tiers.
///
/// [currentHelpTier]: the active help level.
/// [highlightedGraphemeIndex]: during Tier 1 sound-out, the index into the
/// word's `graphemePhonemeMap` of the grapheme cluster currently highlighted.
/// -1 or out of range means no highlight.
class HelpState {
  /// Constructs help state with tier and grapheme highlight index.
  ///
  /// [currentHelpTier]: the active help level ([HelpLevel.none],
  /// [HelpLevel.soundOut], or [HelpLevel.modeled]).
  ///
  /// [highlightedGraphemeIndex]: the index into the word's
  /// `graphemePhonemeMap` of the grapheme cluster to highlight. Negative
  /// values indicate no highlight. Example: for "ship", the graphemePhonemeMap
  /// is [("sh", "SH"), ("i", "IH"), ("p", "P")]; index 0 highlights "sh" as
  /// one unit, never s-h separately.
  const HelpState({
    required this.currentHelpTier,
    required this.highlightedGraphemeIndex,
  });

  /// The current help tier.
  final HelpLevel currentHelpTier;

  /// Index into the word's graphemePhonemeMap of the highlighted cluster.
  /// Negative (e.g., -1) means no highlight.
  final int highlightedGraphemeIndex;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is HelpState &&
          other.currentHelpTier == currentHelpTier &&
          other.highlightedGraphemeIndex == highlightedGraphemeIndex);

  @override
  int get hashCode =>
      Object.hash(currentHelpTier, highlightedGraphemeIndex);

  @override
  String toString() => 'HelpState('
      'currentHelpTier: ${currentHelpTier.name}, '
      'highlightedGraphemeIndex: $highlightedGraphemeIndex)';
}

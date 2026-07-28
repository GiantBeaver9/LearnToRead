// Design tokens — the single source of truth for color, type, spacing, and
// motion across every child-facing screen (PRD §8 Unit 1).
//
// PLACEHOLDER STATUS (PRD §10 OQ-8): every concrete value in this file
// (hex colors, font-family names, exact spacing/duration numbers) is a
// builder-chosen placeholder pending product-owner sign-off. The *token
// interface* (these field names, their types, and the structural rules
// asserted in test/design/tokens_test.dart — e.g. helped-word ==
// read-correct-green, tablet sizes > phone sizes) is pinned and must not
// change without a new product-owner decision. [DesignTokens.tokensAreOwnerSignedOff]
// is the machine-readable marker of this status; flip it to `true` only once
// the product owner has recorded sign-off on the style guide + tokens in the
// repo (ticket accept #9).
//
// Token-lint rule (see test/design/token_lint_test.dart, CI-enforceable):
// no file under lib/features/ may reference `Color(0x...)`, `Colors.*`, or an
// inline `TextStyle(fontFamily: '...')` literal — every color and font must
// flow through [DesignTokens]. Within lib/design/ itself, only this file may
// contain raw color/font literals; layout.dart, rive_stage.dart, and
// fake_rive_stage.dart must reference [DesignTokens] rather than define their
// own.
import 'package:flutter/widgets.dart';

/// The single design-token file for LearnToRead (PRD §8 Unit 1).
///
/// All child-facing colors, type sizes, spacing, and motion durations are
/// declared here as `static const` members and referenced by name elsewhere
/// in the app — never as inline literals. See the file-level doc comment for
/// the OQ-8 placeholder-values / pinned-interface distinction and the
/// token-lint rule this file anchors.
abstract final class DesignTokens {
  // ---------------------------------------------------------------------
  // Word-state colors (single source of truth, used by Units 5-7).
  // ---------------------------------------------------------------------

  /// Unread word ink: a warm near-black (not pure `#000000`), matching the
  /// storybook-illustrated direction. Also used for body/title ink where a
  /// non-word-specific "ink" color is needed.
  static const Color wordUnreadInk = Color(0xFF3B2A1E);

  /// Current word ink. Per PRD: "current word: subtle underline/glow marker,
  /// ink color" — the ink itself is unchanged from [wordUnreadInk]; only a
  /// marker (drawn by the widget, not a separate token) is added.
  static const Color wordCurrentInk = wordUnreadInk;

  /// Read-correct word color: palette green, WCAG AA (>=4.5:1) against
  /// [readingBackground].
  static const Color wordReadGreen = Color(0xFF1F6B3D);

  /// Helped-word color. Ratified: a word the child needed help with is
  /// visually IDENTICAL to a word read correctly unaided — no distinct
  /// "helped" marker exists in the UI. Help is tracked invisibly elsewhere
  /// (WordHelpRecord), not via a color token. Deliberately aliased to
  /// [wordReadGreen] rather than given its own hex, so the two can never
  /// drift apart.
  static const Color wordHelpedGreen = wordReadGreen;

  /// Vocabulary (unread) word color: blue, chosen to be distinguishable from
  /// [wordReadGreen] both for color-typical viewers and, per the tritan-safe
  /// heuristic in test/design/tokens_test.dart, for protanopia/deuteranopia
  /// viewers (real simulation screenshots remain an owner/device task).
  static const Color wordVocabBlue = Color(0xFF1E88E5);

  // ---------------------------------------------------------------------
  // Backgrounds.
  // ---------------------------------------------------------------------

  /// Warm, near-white "storybook page" background behind reading text.
  /// [wordReadGreen] is contrast-checked against this value.
  static const Color readingBackground = Color(0xFFFFFBF3);

  /// General screen background, matching the same warm paper tone.
  static const Color screenBackground = readingBackground;

  /// Elevated/card surface background, a touch warmer than [screenBackground]
  /// so illustrated cards read as physical objects on the page.
  static const Color surfaceBackground = Color(0xFFFFF3DE);

  // ---------------------------------------------------------------------
  // Reading-text minimum sizes (pinned exact values, PRD §8 Unit 1).
  // ---------------------------------------------------------------------

  /// Minimum sentence-level reading text size on phone-class layouts.
  static const double sentenceTextSizePhone = 28.0;

  /// Minimum sentence-level reading text size on tablet-class layouts.
  static const double sentenceTextSizeTablet = 36.0;

  /// Minimum paragraph-level reading text size on phone-class layouts.
  static const double paragraphTextSizePhone = 20.0;

  /// Minimum paragraph-level reading text size on tablet-class layouts.
  static const double paragraphTextSizeTablet = 24.0;

  // ---------------------------------------------------------------------
  // Typography indirection (actual font files are owner-supplied, OQ-8).
  // ---------------------------------------------------------------------

  /// Font-family name for reading text (purpose-built early-reader face:
  /// unambiguous a/g forms, generous x-height). Placeholder name bound to a
  /// bundled system fallback until the owner supplies the licensed font
  /// file; every reading-text widget references this token so swapping the
  /// real typeface in is a one-line change.
  static const String readingFontFamily = 'LTRReadingFace';

  /// Font-family name for titles/display text (friendly display face).
  /// Placeholder name, see [readingFontFamily].
  static const String displayFontFamily = 'LTRDisplayFace';

  // ---------------------------------------------------------------------
  // Spacing scale.
  // ---------------------------------------------------------------------

  static const double spacingXs = 4.0;
  static const double spacingSm = 8.0;
  static const double spacingMd = 16.0;
  static const double spacingLg = 24.0;
  static const double spacingXl = 32.0;

  // ---------------------------------------------------------------------
  // Motion durations.
  // ---------------------------------------------------------------------

  /// Duration of the "green sweep" transition when a word resolves to
  /// read-correct (PRD §8 Unit 5): ~250 ms.
  static const Duration greenSweepDuration = Duration(milliseconds: 250);

  /// Duration of the collectible-flight motion — the earned collectible's
  /// flight from the celebration stage to the collection icon after a story
  /// completes (PRD §8 Unit 8).
  static const Duration collectibleFlightDuration = Duration(milliseconds: 600);

  // ---------------------------------------------------------------------
  // OQ-8 placeholder marker.
  // ---------------------------------------------------------------------

  /// `true` once the product owner has signed off the style guide + these
  /// token values (PRD §8 Unit 1 acceptance, PRD §10 OQ-8). Every value in
  /// this file is a builder-chosen placeholder until then — this flag is the
  /// machine-readable record of that status; downstream code and tests must
  /// not treat exact hex/typeface values as final while it is `false`.
  static const bool tokensAreOwnerSignedOff = false;
}

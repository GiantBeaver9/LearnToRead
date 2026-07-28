// Design tokens — the single source of truth for color, type, spacing, and
// motion across every child-facing screen (PRD §8 Unit 1).
//
// VALUE STATUS (PRD §10 OQ-8 + docs/design/mockup-spec.md): the concrete
// values in this file now come from the product owner's 2026-07-28 mockup
// ("warm paper storybook" — see docs/design/mockup-spec.md §1-§3), replacing
// the original builder-chosen placeholders. The *token interface* (these
// field names, their types, and the structural rules asserted in
// test/design/tokens_test.dart — e.g. helped-word == read-correct-green,
// tablet sizes > phone sizes) is pinned and must not change without a new
// product-owner decision. [DesignTokens.tokensAreOwnerSignedOff] remains
// `false` until the owner has seen the restyle on device and recorded
// sign-off in the repo (ticket accept #9).
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
/// the OQ-8 value-provenance / pinned-interface distinction and the
/// token-lint rule this file anchors.
abstract final class DesignTokens {
  // ---------------------------------------------------------------------
  // Word-state colors (single source of truth, used by Units 5-7).
  // ---------------------------------------------------------------------

  /// Unread word ink: the mockup's warm near-black (`#33302B` — not pure
  /// `#000000`), used for unread words, titles, and dark buttons. Also used
  /// for body/title ink where a non-word-specific "ink" color is needed.
  static const Color wordUnreadInk = Color(0xFF33302B);

  /// Current word ink: the mockup's "saying now" amber (`#D79A3C`).
  ///
  /// AMENDED 2026-07-28 (docs/design/mockup-spec.md §9.1): the PRD's
  /// "current word: subtle underline/glow marker, ink color" line is
  /// superseded by the owner's mockup legend — the word being said NOW reads
  /// amber, distinct from [wordUnreadInk]. The token name is unchanged.
  static const Color wordCurrentInk = Color(0xFFD79A3C);

  /// Read-correct word color: the mockup's read green, WCAG AA (>=4.5:1)
  /// against [readingBackground].
  ///
  /// The mockup's raw `#4E8B5C` measures ~3.9:1 on `#FDFAF3`; per
  /// docs/design/mockup-spec.md §9.2 it is darkened minimally along the same
  /// hue/saturation to the lightest passing shade, `#477F54` (~4.55:1). The
  /// mockup family look wins, the accessibility floor stays.
  static const Color wordReadGreen = Color(0xFF477F54);

  /// Helped-word color. Ratified: a word the child needed help with is
  /// visually IDENTICAL to a word read correctly unaided — no distinct
  /// "helped" marker exists in the UI. Help is tracked invisibly elsewhere
  /// (WordHelpRecord), not via a color token. Deliberately aliased to
  /// [wordReadGreen] rather than given its own hex, so the two can never
  /// drift apart.
  static const Color wordHelpedGreen = wordReadGreen;

  /// Vocabulary (unread) word color: the mockup's vocab blue (`#5A79B8` —
  /// dotted underline, weight 600, tappable), chosen to be distinguishable
  /// from [wordReadGreen] both for color-typical viewers and, per the
  /// tritan-safe heuristic in test/design/tokens_test.dart, for
  /// protanopia/deuteranopia viewers (real simulation screenshots remain an
  /// owner/device task).
  static const Color wordVocabBlue = Color(0xFF5A79B8);

  /// Vocabulary (read/helped) word color: the owner's vocab-read purple
  /// (violet family `#7A5AA0`, PRD §8 Unit 1 / mockup-spec §3, owner ruling
  /// 2026-07-28). A vocab word that resolves (read OR helped — the
  /// invisible-help rule is per word kind) renders this instead of
  /// [wordReadGreen]: the purple says both "you read it" and "this was a
  /// new word", keeping the tap-for-definition affordance discoverable.
  ///
  /// The ruling's starting value `#7A5AA0` already measures ~5.30:1 against
  /// [readingBackground] (WCAG AA floor is 4.5:1), so no darkening was
  /// needed — the hex is used as ratified.
  static const Color wordVocabReadPurple = Color(0xFF7A5AA0);

  // ---------------------------------------------------------------------
  // Backgrounds & card chrome.
  // ---------------------------------------------------------------------

  /// Warm cream "storybook page" background behind reading text — the
  /// mockup's reading-card color (`#FDFAF3`, gradient start).
  /// [wordReadGreen] is contrast-checked against this value.
  static const Color readingBackground = Color(0xFFFDFAF3);

  /// General screen (page body) background: the mockup's parchment
  /// (`#F3EADA`), on which cream cards read as physical paper.
  static const Color screenBackground = Color(0xFFF3EADA);

  /// Elevated/card surface background. The mockup's page/surface parchment
  /// (`#F3EADA`) — cards themselves sit on this in the mockup's cream
  /// ([readingBackground]-toned) card color.
  static const Color surfaceBackground = Color(0xFFF3EADA);

  /// 1px card border used on every card/pill in the mockup (`#E2D6BF`).
  static const Color cardBorder = Color(0xFFE2D6BF);

  /// End color of the reading/object-card gradient
  /// (`#FDFAF3` → `#FBF6EB`, mockup §3).
  static const Color cardGradientEnd = Color(0xFFFBF6EB);

  /// Dashed divider above the legend row under the reading text (`#E4D9C3`).
  static const Color dashedDivider = Color(0xFFE4D9C3);

  // ---------------------------------------------------------------------
  // Listening indicator (mockup §4, waveform pill).
  // ---------------------------------------------------------------------

  /// Waveform bar red (`#C6412F`), alternating with [listeningRedAlt].
  static const Color listeningRed = Color(0xFFC6412F);

  /// Alternate waveform bar red (`#D0684F`).
  static const Color listeningRedAlt = Color(0xFFD0684F);

  // ---------------------------------------------------------------------
  // Hint panel ("let's take it slowly", mockup §4).
  // ---------------------------------------------------------------------

  /// Hint panel background (`#FDF3DF`).
  static const Color hintPanelBackground = Color(0xFFFDF3DF);

  /// Hint panel border (`#EFD9A6`).
  static const Color hintPanelBorder = Color(0xFFEFD9A6);

  /// Hint small-caps label (`#B48A3A`).
  static const Color hintLabel = Color(0xFFB48A3A);

  /// Idle syllable chip background (`#F6E7C5`); the active chip uses
  /// [wordCurrentInk] amber with [wordUnreadInk] text (mockup §1).
  static const Color syllableChipIdleBackground = Color(0xFFF6E7C5);

  /// Idle syllable chip text (`#8A6A24`).
  static const Color syllableChipIdleText = Color(0xFF8A6A24);

  // ---------------------------------------------------------------------
  // Done-state success panel (mockup §5).
  // ---------------------------------------------------------------------

  /// Success/stats panel background (`#E9F2EA`).
  static const Color successPanelBackground = Color(0xFFE9F2EA);

  /// Success/stats panel border (`#BFDCC6`).
  static const Color successPanelBorder = Color(0xFFBFDCC6);

  /// Deep stat green (`#3C7A4B`): big stat numbers and the
  /// "Read another →" button.
  static const Color successDeepGreen = Color(0xFF3C7A4B);

  /// Success small-caps stat label (`#6E9478`).
  static const Color successLabel = Color(0xFF6E9478);

  // ---------------------------------------------------------------------
  // Vocab popup (mockup §4).
  // ---------------------------------------------------------------------

  /// Vocab popup background (`#EEF2FA`).
  static const Color vocabPopupBackground = Color(0xFFEEF2FA);

  /// Vocab popup border (`#C8D5EC`).
  static const Color vocabPopupBorder = Color(0xFFC8D5EC);

  /// Vocab popup heading/word color (`#3E5C93`).
  static const Color vocabPopupHeading = Color(0xFF3E5C93);

  // ---------------------------------------------------------------------
  // Muted text roles (mockup §1).
  // ---------------------------------------------------------------------

  /// Uppercase small-caps label color ("READ THIS OUT LOUD", `#A0937D`).
  static const Color mutedLabel = Color(0xFFA0937D);

  /// Secondary/body muted text (`#6E6455`).
  static const Color mutedBody = Color(0xFF6E6455);

  /// Legend-row text under the reading card (`#8C816C`).
  static const Color legendText = Color(0xFF8C816C);

  // ---------------------------------------------------------------------
  // Celebration confetti set (mockup §1/§6, pure-code overlay).
  // ---------------------------------------------------------------------

  /// Ribbon/spark colors for the completion confetti, exactly the mockup's
  /// confetti set (red, amber, green, blue, pink).
  static const List<Color> confettiColors = <Color>[
    Color(0xFFC6412F),
    Color(0xFFD79A3C),
    Color(0xFF4E8B5C),
    Color(0xFF5A79B8),
    Color(0xFFB85C8A),
  ];

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
  // Typography (owner-chosen faces, mockup §2; families declared in
  // pubspec.yaml from assets/fonts/).
  // ---------------------------------------------------------------------

  /// Font-family name for reading text: Literata (serif, variable weight),
  /// the mockup's storybook reading face. Every reading-text widget
  /// references this token, so a face swap stays a one-line change.
  static const String readingFontFamily = 'Literata';

  /// Font-family name for UI/titles/display text: Nunito (rounded humanist
  /// sans, variable weight). See [readingFontFamily].
  static const String displayFontFamily = 'Nunito';

  /// Font-family name for meta/mono text: IBM Plex Mono (small-caps-ish
  /// labels, vocab-popup syllable dot-notation "prin · cess").
  static const String monoFontFamily = 'IBMPlexMono';

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
  // OQ-8 sign-off marker.
  // ---------------------------------------------------------------------

  /// `true` once the product owner has signed off the style guide + these
  /// token values (PRD §8 Unit 1 acceptance, PRD §10 OQ-8). The values now
  /// follow the owner's 2026-07-28 mockup (docs/design/mockup-spec.md), but
  /// this stays `false` until the owner has seen the restyle on device and
  /// recorded sign-off — downstream code and tests must not treat exact
  /// hex/typeface values as final while it is `false`.
  static const bool tokensAreOwnerSignedOff = false;
}

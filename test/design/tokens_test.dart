// Pins the token INTERFACE and structural rules from PRD §8 Unit 1 /
// docs/tickets/design-tokens.json. Per §9 OQ-8, concrete hex/typeface
// values are placeholder-pending-owner-sign-off — these tests do NOT pin
// exact colors, only the pinned structural rules (word-state identity
// rules, pinned reading-text minimum sizes, the ~250ms green-sweep motion
// token, WCAG AA contrast, and the tritan-safe headless color-vision proxy).
//
// lib/design/tokens.dart does not exist yet: this whole file fails to
// compile/analyze until it is created, which is the expected red state.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/design/tokens.dart';

/// WCAG 2.x relative luminance of an sRGB color, per
/// https://www.w3.org/TR/WCAG21/#dfn-relative-luminance
/// [Color.r]/[Color.g]/[Color.b] are already 0.0..1.0 sRGB components.
double _relativeLuminance(Color c) {
  double linearize(double channel) {
    return channel <= 0.03928
        ? channel / 12.92
        : math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
  }

  final r = linearize(c.r);
  final g = linearize(c.g);
  final b = linearize(c.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

/// WCAG contrast ratio between two colors; always >= 1.0.
double _contrastRatio(Color a, Color b) {
  final la = _relativeLuminance(a) + 0.05;
  final lb = _relativeLuminance(b) + 0.05;
  return la > lb ? la / lb : lb / la;
}

/// Headless proxy for the [DEVICE] protanopia/deuteranopia simulation
/// (ticket accept #4): protan/deutan color-vision deficiencies distort
/// the red-green axis but leave blue-yellow perception largely intact, so
/// a green/blue pair that differs *substantially on the blue-yellow axis*
/// stays distinguishable to those viewers even though the two colors
/// might look closer under a naive red-green-sensitive hue comparison.
/// This is a documented heuristic, not a full simulation — real
/// protanopia/deuteranopia screenshots remain an owner/[DEVICE] task.
///
/// Axis defined on the 0.0..1.0 sRGB channel range as blue minus the
/// average of red and green: a simple opponent-color approximation of
/// the blue-yellow axis.
double _blueYellowAxis(Color c) => c.b - ((c.r + c.g) / 2);

void main() {
  group('word-state colors — single source of truth (accept #1)', () {
    test(
      'POSITIVE: wordUnreadInk is a warm near-black, not pure black',
      () {
        expect(DesignTokens.wordUnreadInk, isNot(equals(const Color(0xFF000000))));
        // "Warm" ink: red channel is not less than blue (a cool/blue-leaning
        // near-black would have blue >= red). This also rules out a neutral
        // gray (r == g == b), which would not read as "warm".
        final ink = DesignTokens.wordUnreadInk;
        expect(ink.r, greaterThanOrEqualTo(ink.b));
        expect(
          ink.r == ink.g && ink.g == ink.b,
          isFalse,
          reason: 'unread ink must be a tinted warm near-black, not neutral gray',
        );
      },
    );

    // AMENDED 2026-07-28: owner mockup ruling (docs/design/mockup-spec.md §9.1) — current word reads amber ("saying now"), superseding the ink+marker PRD line.
    test(
      'POSITIVE: current-word ink is the mockup\'s "saying now" amber '
      '(#D79A3C family), distinct from unread ink',
      () {
        expect(DesignTokens.wordCurrentInk, equals(const Color(0xFFD79A3C)));
        expect(
          DesignTokens.wordCurrentInk,
          isNot(equals(DesignTokens.wordUnreadInk)),
        );
      },
    );

    test(
      'POSITIVE: helped word resolves to the exact same color value as '
      'read-correct green — no distinct "helped" token exists (ratified)',
      () {
        expect(DesignTokens.wordHelpedGreen, equals(DesignTokens.wordReadGreen));
      },
    );

    test(
      'NEGATIVE: distinct word states use distinct colors '
      '(read-green, vocab-blue, unread-ink are pairwise different)',
      () {
        expect(DesignTokens.wordReadGreen, isNot(equals(DesignTokens.wordVocabBlue)));
        expect(DesignTokens.wordReadGreen, isNot(equals(DesignTokens.wordUnreadInk)));
        expect(DesignTokens.wordVocabBlue, isNot(equals(DesignTokens.wordUnreadInk)));
      },
    );

    test(
      'EDGE: all word-state colors are fully opaque (alpha == 1.0), '
      'so no accidental partial transparency in the shared token file',
      () {
        for (final c in <Color>[
          DesignTokens.wordUnreadInk,
          DesignTokens.wordCurrentInk,
          DesignTokens.wordReadGreen,
          DesignTokens.wordHelpedGreen,
          DesignTokens.wordVocabBlue,
        ]) {
          expect(c.a, equals(1.0));
        }
      },
    );
  });

  group('reading-text minimum sizes (accept #3, pinned exact values)', () {
    test(
      'POSITIVE: sentence-level minimum sizes are 28pt phone / 36pt tablet',
      () {
        expect(DesignTokens.sentenceTextSizePhone, equals(28.0));
        expect(DesignTokens.sentenceTextSizeTablet, equals(36.0));
      },
    );

    test(
      'POSITIVE: paragraph-level minimum sizes are 20pt phone / 24pt tablet',
      () {
        expect(DesignTokens.paragraphTextSizePhone, equals(20.0));
        expect(DesignTokens.paragraphTextSizeTablet, equals(24.0));
      },
    );

    test(
      'NEGATIVE: paragraph minimum sizes are smaller than sentence minimum '
      'sizes at the same device class (paragraph pages carry more text)',
      () {
        expect(DesignTokens.paragraphTextSizePhone, lessThan(DesignTokens.sentenceTextSizePhone));
        expect(DesignTokens.paragraphTextSizeTablet, lessThan(DesignTokens.sentenceTextSizeTablet));
      },
    );

    test(
      'EDGE: tablet minimum size is strictly larger than phone minimum '
      'size, at both sentence and paragraph levels',
      () {
        expect(DesignTokens.sentenceTextSizeTablet, greaterThan(DesignTokens.sentenceTextSizePhone));
        expect(DesignTokens.paragraphTextSizeTablet, greaterThan(DesignTokens.paragraphTextSizePhone));
      },
    );
  });

  group('font-family indirection (pinned_design: "one-line swap")', () {
    test(
      'POSITIVE: reading and display font families are non-empty, distinct '
      'named indirections (actual font files are owner-supplied, OQ-8)',
      () {
        expect(DesignTokens.readingFontFamily, isNotEmpty);
        expect(DesignTokens.displayFontFamily, isNotEmpty);
        expect(DesignTokens.readingFontFamily, isNot(equals(DesignTokens.displayFontFamily)));
      },
    );
  });

  group('spacing scale (accept #1: spacing lives in the token file)', () {
    test(
      'POSITIVE: spacing scale is strictly increasing and all-positive '
      '(exact placeholder values are OQ-8; the scale-ordering rule is pinned)',
      () {
        final scale = <double>[
          DesignTokens.spacingXs,
          DesignTokens.spacingSm,
          DesignTokens.spacingMd,
          DesignTokens.spacingLg,
          DesignTokens.spacingXl,
        ];
        for (final v in scale) {
          expect(v, greaterThan(0));
        }
        for (var i = 1; i < scale.length; i++) {
          expect(
            scale[i],
            greaterThan(scale[i - 1]),
            reason: 'spacing scale must be strictly increasing',
          );
        }
      },
    );
  });

  group('motion durations (accept #1: green sweep + collectible flight)', () {
    test(
      'POSITIVE: green-sweep transition duration is exactly ~250ms '
      '(pinned in PRD §8 Unit 5, sourced from this token file)',
      () {
        expect(DesignTokens.greenSweepDuration, equals(const Duration(milliseconds: 250)));
      },
    );

    test(
      'POSITIVE: collectible-flight motion token exists as a positive '
      'duration (exact value is a design placeholder; existence + type are '
      'pinned by Unit 8\'s reference to "Unit 1 tokens")',
      () {
        expect(DesignTokens.collectibleFlightDuration, greaterThan(Duration.zero));
      },
    );

    test(
      'EDGE: green-sweep and collectible-flight are distinct motion tokens '
      '(not accidentally aliased to the same Duration constant)',
      () {
        expect(
          DesignTokens.greenSweepDuration,
          isNot(equals(DesignTokens.collectibleFlightDuration)),
        );
      },
    );

    test(
      'NEGATIVE: motion durations are never zero or negative',
      () {
        expect(DesignTokens.greenSweepDuration, greaterThan(Duration.zero));
        expect(DesignTokens.collectibleFlightDuration, greaterThan(Duration.zero));
      },
    );
  });

  group('green vs blue contrast + tritan-safe proxy (accept #4)', () {
    test(
      'POSITIVE: read-correct green meets WCAG AA (>= 4.5:1) against the '
      'reading background',
      () {
        final ratio = _contrastRatio(DesignTokens.wordReadGreen, DesignTokens.readingBackground);
        expect(ratio, greaterThanOrEqualTo(4.5));
      },
    );

    test(
      'NEGATIVE: contrast helper distinguishes a genuinely low-contrast pair '
      '(sanity check on the WCAG formula itself: identical colors == 1.0)',
      () {
        final ratio = _contrastRatio(DesignTokens.readingBackground, DesignTokens.readingBackground);
        expect(ratio, closeTo(1.0, 1e-9));
      },
    );

    test(
      'POSITIVE: read-green vs vocab-blue differ sufficiently on the '
      'blue-yellow (tritan-safe) axis — headless proxy for the [DEVICE] '
      'protanopia/deuteranopia simulation screenshots',
      () {
        final axisDelta = (
          _blueYellowAxis(DesignTokens.wordReadGreen) -
          _blueYellowAxis(DesignTokens.wordVocabBlue)
        ).abs();
        // Threshold chosen well above sRGB rounding/anti-alias noise
        // (~0.02) but well below the maximum possible delta of 1.5;
        // documented rationale: this is a coarse headless proxy, not a
        // substitute for the real simulation screenshots.
        expect(axisDelta, greaterThanOrEqualTo(0.15));
      },
    );

    test(
      'EDGE: the tritan-safe axis heuristic itself reports zero delta for '
      'two identical colors (sanity check on the heuristic, not the tokens)',
      () {
        final delta = (
          _blueYellowAxis(DesignTokens.wordReadGreen) -
          _blueYellowAxis(DesignTokens.wordReadGreen)
        ).abs();
        expect(delta, equals(0.0));
      },
    );
  });

  group('vocab-read purple (owner ruling 2026-07-28, PRD §8 Unit 1)', () {
    test(
      'POSITIVE: vocab-read purple meets WCAG AA (>= 4.5:1) against the '
      'reading background',
      () {
        final ratio = _contrastRatio(
          DesignTokens.wordVocabReadPurple,
          DesignTokens.readingBackground,
        );
        expect(ratio, greaterThanOrEqualTo(4.5));
      },
    );

    test(
      'NEGATIVE: vocab-read purple is distinct from vocab-blue, read-green, '
      'and unread ink (no state pair shares a color)',
      () {
        expect(
          DesignTokens.wordVocabReadPurple,
          isNot(equals(DesignTokens.wordVocabBlue)),
        );
        expect(
          DesignTokens.wordVocabReadPurple,
          isNot(equals(DesignTokens.wordReadGreen)),
        );
        expect(
          DesignTokens.wordVocabReadPurple,
          isNot(equals(DesignTokens.wordUnreadInk)),
        );
      },
    );

    test(
      'EDGE: vocab-read purple is fully opaque (alpha == 1.0), like every '
      'other word-state color',
      () {
        expect(DesignTokens.wordVocabReadPurple.a, equals(1.0));
      },
    );

    test(
      'POSITIVE: read-green vs vocab-read purple differ sufficiently on the '
      'blue-yellow (tritan-safe) axis — same heuristic and floor as the '
      'green/blue pair (a done ordinary word next to a done vocab word)',
      () {
        final axisDelta = (
          _blueYellowAxis(DesignTokens.wordReadGreen) -
          _blueYellowAxis(DesignTokens.wordVocabReadPurple)
        ).abs();
        expect(axisDelta, greaterThanOrEqualTo(0.15));
      },
    );

    // NOTE (measured 2026-07-28, not asserted): the blue<->purple pair
    // (unread vocab vs read vocab) measures only ~0.096 on the same
    // blue-yellow axis — below the 0.15 floor the suite uses for
    // green<->blue. Per the ruling handoff the floor is NOT weakened here;
    // whether the dotted-underline + weight-600 affordance (present only
    // while unread) plus reading position sufficiently differentiate that
    // pair for protan/deutan viewers is an orchestrator/owner call.
  });

  group('single-token-file marking for OQ-8 (accept #9, partial proxy)', () {
    // The actual product-owner sign-off (accept #9) is an owner/[DEVICE]
    // task and cannot be tested here. This only pins that the token file
    // documents itself as placeholder-pending-review, which is the part of
    // accept #9 the ticket assigns to the build ("ticket leaves tokens
    // clearly marked as proposed-pending-owner-review").
    test(
      'POSITIVE: DesignTokens exposes a marker that values are placeholder '
      'pending product-owner sign-off (OQ-8)',
      () {
        expect(DesignTokens.tokensAreOwnerSignedOff, isFalse);
      },
    );
  });
}

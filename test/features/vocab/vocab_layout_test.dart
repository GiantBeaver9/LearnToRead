/// Headless layout-class coverage for `VocabCardPopover`
/// (lib/features/vocab/vocab_card.dart; PRD §8 Unit 7 accept "Cards render
/// within safe areas in all four layout classes (golden tests)"; ticket
/// vocab-cards accept entry 6).
///
/// Mirrors test/features/reading/layout_classes_test.dart's established
/// pattern exactly: pump the popover at each of the four `LayoutClass`
/// sizes (lib/design/layout.dart, merged) and assert no overflow and that
/// its content stays within the safe-area-adjusted viewport, then route the
/// actual pixel-level goldens to the owner as `[DEVICE]`-skipped stubs. This
/// file imports lib/features/vocab/vocab_card.dart, which does not exist
/// yet: it fails to compile/analyze until it is created -- the expected red
/// state.
///
/// Pinned contract this suite locks in: `VocabCardPopover` wraps its
/// visible card content in a `SafeArea` internally -- "this ticket owns the
/// card itself" per the ticket notes, so the card is responsible for its
/// own safe-area rendering rather than depending on `ReadingScreen`'s
/// `SafeArea` (the card is a full-bleed overlay that can be requested while
/// the reading screen is in any layout class, and must never let its close
/// affordance land under a notch/home-indicator/status bar).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart' show VocabCard;
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/vocab/vocab_card.dart';

/// Resizes the actual test viewport (not just an ambient MediaQuery) so the
/// popover lays out exactly as it would at a real device size of [size] --
/// mirrors test/features/reading/layout_classes_test.dart's `_pumpAt`
/// helper (private there, so redefined locally per-file, same behavior,
/// per this repo's established convention).
Future<void> _pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(child);
}

const _phonePortrait = Size(375, 812);
const _phoneLandscape = Size(812, 375);
const _tabletPortrait = Size(768, 1024);
const _tabletLandscape = Size(1024, 768);

const _layoutSizes = <String, Size>{
  'phonePortrait': _phonePortrait,
  'phoneLandscape': _phoneLandscape,
  'tabletPortrait': _tabletPortrait,
  'tabletLandscape': _tabletLandscape,
};

/// A simulated notch/home-indicator inset, so the safe-area assertion below
/// is meaningful (a device with zero insets would pass trivially).
const _unsafeInsets = EdgeInsets.only(top: 44, bottom: 34, left: 12, right: 12);

VocabCard _shortCard() => VocabCard(
      id: 'vocab.brave',
      word: 'brave',
      definitionText: 'Ready to do something that feels a little scary.',
      definitionAudioRef: 'audio/vocab/brave_def.mp3',
      illustrationRef: 'art/brave.png',
    );

/// A realistically long authored definition (paragraph-level story vocab),
/// to stress-test wrapping at the smallest layout class.
VocabCard _longCard() => VocabCard(
      id: 'vocab.magnificent',
      word: 'magnificent',
      definitionText: 'So wonderful and grand that everyone who sees it '
          'cannot help but stop, stare, and feel a little bit amazed -- '
          'the way you might feel looking up at a huge, sparkling castle '
          'for the very first time.',
      definitionAudioRef: 'audio/vocab/magnificent_def.mp3',
      illustrationRef: 'art/magnificent.png',
    );

Widget _buildPopover(VocabCard card, {EdgeInsets padding = EdgeInsets.zero}) {
  return MaterialApp(
    home: Builder(
      // Inherits the real ambient size/devicePixelRatio set by `_pumpAt`'s
      // `tester.view.physicalSize` and only overrides `padding`, so the
      // simulated notch/home-indicator insets are layered on top of the
      // actual pumped viewport rather than a hand-guessed zero size.
      builder: (context) {
        final base = MediaQuery.of(context);
        return MediaQuery(
          data: base.copyWith(padding: padding),
          child: Scaffold(
            body: VocabCardPopover(
              card: card,
              audioService: FakeAudioService(),
              pronunciationAudioRef: 'audio/words/${card.word}.mp3',
              onClosed: () {},
            ),
          ),
        );
      },
    ),
  );
}

void main() {
  group('VocabCardPopover — short card, all four layout classes (POSITIVE)', () {
    for (final entry in _layoutSizes.entries) {
      testWidgets('${entry.key} (${entry.value}) renders without overflow', (tester) async {
        await _pumpAt(tester, entry.value, _buildPopover(_shortCard(), padding: _unsafeInsets));
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('vocab-card-popover')), findsOneWidget);
        expect(find.byKey(const ValueKey('vocab-card-word')), findsOneWidget);
        expect(find.byKey(const ValueKey('vocab-card-definition')), findsOneWidget);
        expect(find.byKey(const ValueKey('vocab-card-illustration')), findsOneWidget);
        expect(find.byKey(const ValueKey('vocab-card-close-button')), findsOneWidget);
      });
    }
  });

  group('VocabCardPopover — long (paragraph-level) definition, all four '
      'layout classes (POSITIVE)', () {
    for (final entry in _layoutSizes.entries) {
      testWidgets('${entry.key} (${entry.value}) renders without overflow', (tester) async {
        await _pumpAt(tester, entry.value, _buildPopover(_longCard(), padding: _unsafeInsets));
        await tester.pump();

        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('vocab-card-definition')), findsOneWidget);
      });
    }
  });

  group('VocabCardPopover — safe-area containment (POSITIVE)', () {
    for (final entry in _layoutSizes.entries) {
      testWidgets('${entry.key}: the card wraps a SafeArea, and the close '
          'affordance never lands inside the simulated notch/home-indicator '
          'insets', (tester) async {
        await _pumpAt(tester, entry.value, _buildPopover(_shortCard(), padding: _unsafeInsets));
        await tester.pump();

        // The pinned contract (see this file's header) is that
        // `VocabCardPopover` wraps its visible card content in a
        // `SafeArea` -- i.e. `SafeArea` is an ANCESTOR of the
        // `vocab-card-popover` surface, not a descendant of it.
        expect(
          find.ancestor(
            of: find.byKey(const ValueKey('vocab-card-popover')),
            matching: find.byType(SafeArea),
          ),
          findsWidgets,
        );

        final screenRect = Offset.zero & entry.value;
        final safeTop = screenRect.top + _unsafeInsets.top;
        final safeBottom = screenRect.bottom - _unsafeInsets.bottom;
        final safeLeft = screenRect.left + _unsafeInsets.left;
        final safeRight = screenRect.right - _unsafeInsets.right;

        final closeRect = tester.getRect(find.byKey(const ValueKey('vocab-card-close-button')));
        expect(closeRect.top, greaterThanOrEqualTo(safeTop));
        expect(closeRect.bottom, lessThanOrEqualTo(safeBottom));
        expect(closeRect.left, greaterThanOrEqualTo(safeLeft));
        expect(closeRect.right, lessThanOrEqualTo(safeRight));
      });
    }
  });

  group('VocabCardPopover — resizing while open (EDGE)', () {
    testWidgets('rotating from portrait to landscape while the card is '
        'open keeps content intact with no overflow', (tester) async {
      final card = _shortCard();
      await _pumpAt(tester, _phonePortrait, _buildPopover(card));
      await tester.pump();
      expect(tester.takeException(), isNull);

      await _pumpAt(tester, _phoneLandscape, _buildPopover(card));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.text('brave'), findsOneWidget);
    });
  });

  group('[DEVICE] pixel goldens — not testable headlessly, skipped with reason', () {
    for (final layoutClassName in _layoutSizes.keys) {
      test(
        'VocabCardPopover golden at $layoutClassName matches the '
        'illustrated storybook style guide',
        () {},
        skip: '[DEVICE] Real illustration art and the licensed early-reader '
            'typeface are owner-commissioned/owner-supplied (PRD §10 OQ-8, '
            'OQ-4); DesignTokens.tokensAreOwnerSignedOff is still false. '
            'This container has only token-styled placeholder rendering, so '
            'a pixel golden here would pin placeholder art, not the shipped '
            'design. Routed to the owner once tokens are signed off. The '
            'headless proxy above (no-overflow + safe-area-containment '
            'assertion at this exact layout class, with real card content) '
            'is the compile-time stand-in.',
      );
    }
  });
}

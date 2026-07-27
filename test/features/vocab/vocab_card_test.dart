/// Widget tests for `VocabCardPopover` in isolation (PRD §8 Unit 7; ticket
/// vocab-cards accept entries 1, 2, 3 (card half)).
///
/// Exercises `VocabCardPopover` (lib/features/vocab/vocab_card.dart), which
/// does not exist yet: this suite fails to compile/analyze until it is
/// created -- the expected red state. `vocab_card.dart` is the file THIS
/// suite pins the contract for; `vocab_card_opener.dart` (the seam that
/// wires a real popover into `ReadingScreen`) is exercised end-to-end in
/// vocab_integration_test.dart instead.
///
/// Pinned contract this suite locks in (a builder decision this ticket owns,
/// since neither file exists yet -- see the ticket note "defined concrete
/// here"):
///
///  - `VocabCardPopover({required VocabCard card, required AudioService
///    audioService, String? pronunciationAudioRef, required VoidCallback
///    onClosed})`: a self-contained, full-bleed overlay (its own tap-outside
///    barrier, not relying on a host `showDialog`/`Navigator` barrier) --
///    "this ticket owns the card itself" per the ticket notes.
///  - Widget keys: `vocab-card-barrier` (full-bleed tap-outside target),
///    `vocab-card-popover` (the visible card surface), `vocab-card-word`,
///    `vocab-card-word-tap` (gesture target over the word),
///    `vocab-card-definition`, `vocab-card-illustration` (present iff
///    `card.illustrationRef != null`), `vocab-card-replay-button`,
///    `vocab-card-close-button`.
///  - On first build, the definition plays automatically exactly once via
///    `audioService.play(card.definitionAudioRef, channel:
///    kVocabCardAudioChannel)` -- `kVocabCardAudioChannel` (this file's
///    `AudioChannel.narration`: recorded-narrator read-aloud content, not
///    the Unit 6 help scaffold and not celebration/ambient) is exported by
///    lib/features/vocab/vocab_card.dart.
///  - The replay button (`vocab-card-replay-button`) re-plays the exact
///    same ref/channel on every tap.
///  - The word tap target (`vocab-card-word-tap`) plays
///    `pronunciationAudioRef` (when non-null) on the same channel -- a
///    DIFFERENT ref from the definition, never the definition replayed.
///  - Dismiss: tapping the barrier OR `vocab-card-close-button` calls
///    `onClosed` -- exactly once per dismissal, guarded against a
///    double-fire even if both paths are triggered before the caller
///    removes the widget from the tree.
///  - Tapping the visible card surface itself (away from any of the three
///    interactive affordances) does NOT dismiss -- the barrier sits BEHIND
///    the card, not in front of it.
///  - Tokens only: the word renders in `DesignTokens.wordVocabBlue` (ties
///    the popover back to the blue word that opened it) at a strictly
///    larger font size than the definition (word "large at top"); the
///    definition renders in `DesignTokens.wordUnreadInk`; the card surface
///    uses `DesignTokens.surfaceBackground`. The word sits above the
///    definition in the card's vertical layout.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart' show VocabCard;
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/fake_audio_service.dart';
import 'package:learn_to_read/features/vocab/vocab_card.dart';

// ---------------------------------------------------------------------------
// Fixtures.
// ---------------------------------------------------------------------------

VocabCard _card({String? illustrationRef}) => VocabCard(
      id: 'vocab.enormous',
      word: 'enormous',
      definitionText: 'Really, really big.',
      definitionAudioRef: 'audio/vocab/enormous_def.mp3',
      illustrationRef: illustrationRef,
    );

Widget _harness({
  required VocabCard card,
  required FakeAudioService audioService,
  String? pronunciationAudioRef,
  VoidCallback? onClosed,
}) {
  return MaterialApp(
    home: Scaffold(
      body: VocabCardPopover(
        card: card,
        audioService: audioService,
        pronunciationAudioRef: pronunciationAudioRef,
        onClosed: onClosed ?? () {},
      ),
    ),
  );
}

const _barrierKey = ValueKey<String>('vocab-card-barrier');
const _popoverKey = ValueKey<String>('vocab-card-popover');
const _wordKey = ValueKey<String>('vocab-card-word');
const _wordTapKey = ValueKey<String>('vocab-card-word-tap');
const _definitionKey = ValueKey<String>('vocab-card-definition');
const _illustrationKey = ValueKey<String>('vocab-card-illustration');
const _replayKey = ValueKey<String>('vocab-card-replay-button');
const _closeKey = ValueKey<String>('vocab-card-close-button');

void main() {
  group('POSITIVE: renders word, definition, and optional illustration', () {
    testWidgets('word and definition text are present', (tester) async {
      final card = _card();
      await tester.pumpWidget(_harness(card: card, audioService: FakeAudioService()));
      await tester.pump();

      expect(find.text('enormous'), findsOneWidget);
      expect(find.text('Really, really big.'), findsOneWidget);
      expect(find.byKey(_wordKey), findsOneWidget);
      expect(find.byKey(_definitionKey), findsOneWidget);
    });

    testWidgets('illustration slot is present when illustrationRef is set', (tester) async {
      final card = _card(illustrationRef: 'art/enormous.png');
      await tester.pumpWidget(_harness(card: card, audioService: FakeAudioService()));
      await tester.pump();

      expect(find.byKey(_illustrationKey), findsOneWidget);
    });

    testWidgets('NEGATIVE: illustration slot is absent when illustrationRef is null', (tester) async {
      final card = _card(); // illustrationRef: null
      await tester.pumpWidget(_harness(card: card, audioService: FakeAudioService()));
      await tester.pump();

      expect(find.byKey(_illustrationKey), findsNothing);
    });

    testWidgets('the word sits above the definition, and renders larger '
        '(word "large at top")', (tester) async {
      final card = _card();
      await tester.pumpWidget(_harness(card: card, audioService: FakeAudioService()));
      await tester.pump();

      final wordTop = tester.getTopLeft(find.byKey(_wordKey)).dy;
      final definitionTop = tester.getTopLeft(find.byKey(_definitionKey)).dy;
      expect(wordTop, lessThan(definitionTop));

      // Per this repo's established convention (word_text_view.dart:
      // `Text(text, key: ValueKey('word-text-$index'), ...)`), the pinned
      // key sits directly on the `Text` widget itself.
      final wordText = tester.widget<Text>(find.byKey(_wordKey));
      final definitionText = tester.widget<Text>(find.byKey(_definitionKey));
      expect(wordText.style?.fontSize, isNotNull);
      expect(definitionText.style?.fontSize, isNotNull);
      expect(wordText.style!.fontSize!, greaterThan(definitionText.style!.fontSize!));
    });
  });

  group('POSITIVE: tokens only, no raw literals', () {
    testWidgets('word renders DesignTokens.wordVocabBlue, definition renders '
        'DesignTokens.wordUnreadInk, card surface uses '
        'DesignTokens.surfaceBackground', (tester) async {
      final card = _card();
      await tester.pumpWidget(_harness(card: card, audioService: FakeAudioService()));
      await tester.pump();

      final wordText = tester.widget<Text>(find.byKey(_wordKey));
      final definitionText = tester.widget<Text>(find.byKey(_definitionKey));
      expect(wordText.style?.color, DesignTokens.wordVocabBlue);
      expect(definitionText.style?.color, DesignTokens.wordUnreadInk);

      // Implementation-agnostic: the card surface may be painted via
      // `Container.decoration` or a bare `DecoratedBox` -- either is
      // acceptable as long as SOME box behind `vocab-card-popover` paints
      // exactly `DesignTokens.surfaceBackground`.
      final usesSurfaceBackground = tester
              .widgetList<Container>(find.byType(Container))
              .any((c) => (c.decoration as BoxDecoration?)?.color == DesignTokens.surfaceBackground) ||
          tester
              .widgetList<DecoratedBox>(find.byType(DecoratedBox))
              .any((d) => (d.decoration as BoxDecoration?)?.color == DesignTokens.surfaceBackground);
      expect(usesSurfaceBackground, isTrue,
          reason: 'no Container/DecoratedBox paints DesignTokens.surfaceBackground');
    });

    testWidgets('word text uses DesignTokens.readingFontFamily', (tester) async {
      final card = _card();
      await tester.pumpWidget(_harness(card: card, audioService: FakeAudioService()));
      await tester.pump();

      final wordText = tester.widget<Text>(find.byKey(_wordKey));
      expect(wordText.style?.fontFamily, DesignTokens.readingFontFamily);
    });
  });

  group('POSITIVE: definition audio auto-plays on open', () {
    testWidgets('plays card.definitionAudioRef on kVocabCardAudioChannel '
        'exactly once as soon as the card appears', (tester) async {
      final audio = FakeAudioService();
      final card = _card();
      await tester.pumpWidget(_harness(card: card, audioService: audio));
      await tester.pump();

      final plays = audio.callLog.whereType<PlayLogEntry>().toList();
      expect(plays, hasLength(1));
      expect(plays.single.ref, card.definitionAudioRef);
      expect(plays.single.channel, kVocabCardAudioChannel);
    });

    testWidgets('EDGE: an unrelated rebuild (same card) does not '
        're-trigger autoplay', (tester) async {
      final audio = FakeAudioService();
      final card = _card();
      await tester.pumpWidget(_harness(card: card, audioService: audio));
      await tester.pump();
      expect(audio.callLog.whereType<PlayLogEntry>(), hasLength(1));

      // Rebuild the same widget tree (e.g. an ancestor repaints).
      await tester.pumpWidget(_harness(card: card, audioService: audio));
      await tester.pump();

      expect(audio.callLog.whereType<PlayLogEntry>(), hasLength(1));
    });
  });

  group('POSITIVE: replay button repeats the definition audio', () {
    testWidgets('tapping replay plays the exact same ref/channel again', (tester) async {
      final audio = FakeAudioService();
      final card = _card();
      await tester.pumpWidget(_harness(card: card, audioService: audio));
      await tester.pump();

      expect(find.byKey(_replayKey), findsOneWidget);
      await tester.tap(find.byKey(_replayKey));
      await tester.pump();

      final plays = audio.callLog.whereType<PlayLogEntry>().toList();
      expect(plays, hasLength(2));
      expect(plays[1].ref, card.definitionAudioRef);
      expect(plays[1].channel, kVocabCardAudioChannel);
    });

    testWidgets('EDGE: tapping replay twice plays it three times total '
        '(one autoplay + two replays)', (tester) async {
      final audio = FakeAudioService();
      final card = _card();
      await tester.pumpWidget(_harness(card: card, audioService: audio));
      await tester.pump();

      await tester.tap(find.byKey(_replayKey));
      await tester.pump();
      await tester.tap(find.byKey(_replayKey));
      await tester.pump();

      final plays = audio.callLog.whereType<PlayLogEntry>().where((e) => e.ref == card.definitionAudioRef);
      expect(plays, hasLength(3));
    });
  });

  group('POSITIVE / NEGATIVE / EDGE: tapping the word plays its pronunciation', () {
    testWidgets('POSITIVE: tapping the word plays pronunciationAudioRef, '
        'distinct from the definition ref', (tester) async {
      final audio = FakeAudioService();
      final card = _card();
      await tester.pumpWidget(_harness(
        card: card,
        audioService: audio,
        pronunciationAudioRef: 'audio/words/enormous.mp3',
      ));
      await tester.pump();

      expect(find.byKey(_wordTapKey), findsOneWidget);
      await tester.tap(find.byKey(_wordTapKey));
      await tester.pump();

      final plays = audio.callLog.whereType<PlayLogEntry>().toList();
      expect(plays, hasLength(2)); // autoplay + word tap
      final wordPlay = plays.last;
      expect(wordPlay.ref, 'audio/words/enormous.mp3');
      expect(wordPlay.channel, kVocabCardAudioChannel);
      expect(wordPlay.ref, isNot(card.definitionAudioRef));
    });

    testWidgets('EDGE: with no pronunciationAudioRef supplied, tapping the '
        'word is a graceful no-op (no crash, no new play call)', (tester) async {
      final audio = FakeAudioService();
      final card = _card();
      await tester.pumpWidget(_harness(card: card, audioService: audio)); // pronunciationAudioRef: null
      await tester.pump();
      final before = audio.callLog.whereType<PlayLogEntry>().length;

      expect(find.byKey(_wordTapKey), findsOneWidget);
      await tester.tap(find.byKey(_wordTapKey));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(audio.callLog.whereType<PlayLogEntry>(), hasLength(before));
    });
  });

  group('Dismiss (POSITIVE / NEGATIVE / EDGE)', () {
    testWidgets('POSITIVE: tapping the close affordance calls onClosed once', (tester) async {
      var closedCalls = 0;
      final card = _card();
      await tester.pumpWidget(_harness(
        card: card,
        audioService: FakeAudioService(),
        onClosed: () => closedCalls++,
      ));
      await tester.pump();

      expect(find.byKey(_closeKey), findsOneWidget);
      await tester.tap(find.byKey(_closeKey));
      await tester.pump();

      expect(closedCalls, 1);
    });

    testWidgets('POSITIVE: tapping outside the card (the barrier) calls '
        'onClosed once', (tester) async {
      var closedCalls = 0;
      final card = _card();
      await tester.pumpWidget(_harness(
        card: card,
        audioService: FakeAudioService(),
        onClosed: () => closedCalls++,
      ));
      await tester.pump();

      // The barrier spans the full screen and the card sits centered on top
      // of it, so `tester.tap(find.byKey(_barrierKey))` (which targets that
      // finder's geometric center) would actually hit the card. Tap a
      // corner instead -- definitely outside the centered card, definitely
      // still over the full-bleed barrier.
      expect(find.byKey(_barrierKey), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();

      expect(closedCalls, 1);
    });

    testWidgets('NEGATIVE: tapping the card surface itself (away from any '
        'affordance) does not dismiss', (tester) async {
      var closedCalls = 0;
      final card = _card();
      await tester.pumpWidget(_harness(
        card: card,
        audioService: FakeAudioService(),
        onClosed: () => closedCalls++,
      ));
      await tester.pump();

      await tester.tap(find.byKey(_definitionKey));
      await tester.pump();

      expect(closedCalls, 0);
    });

    testWidgets('EDGE: onClosed fires exactly once even when the close '
        'button and the barrier are both triggered before the caller '
        'removes the widget from the tree', (tester) async {
      var closedCalls = 0;
      final card = _card();
      await tester.pumpWidget(_harness(
        card: card,
        audioService: FakeAudioService(),
        onClosed: () => closedCalls++,
      ));
      await tester.pump();

      await tester.tap(find.byKey(_closeKey));
      await tester.pump();
      // The widget is still mounted (test double did not remove it from the
      // tree on close) -- a second dismissal path must not double-fire.
      // See the corner-tap note above for why this uses `tapAt` rather than
      // `tap(find.byKey(_barrierKey))`.
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();

      expect(closedCalls, 1);
    });
  });
}

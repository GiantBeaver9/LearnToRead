/// The reading screen (PRD §8 Unit 5), the centre of the whole app: the
/// child reads a story aloud and watches their own words turn green.
///
/// This widget is pure composition. It owns no recognition logic (Unit 4
/// owns that, and reaches this screen only as [ReadingTrackerHandle]
/// events), no help logic (Unit 6 owns that, and reaches this screen only
/// as a [HelpState]), and no celebration logic (Unit 8 owns that, and is
/// reached only through [onStoryComplete]). What it does own:
///
///  - the layout: reading text and the story stage side by side in
///    landscape, stacked in portrait, via the shared [ReadingLayout],
///  - listen-first narration (A-11) at [Level.narrationEnabled] levels, and
///    the ear-icon replay that suspends recognition while it plays,
///  - the page host, plus the ratified page-turn hold (PRD §8 Unit 5,
///    mockup-spec §8, owner-confirmed 2026-07-28): completing a non-final
///    page STOPS the machine, a dog-ear appears at the reading card's
///    bottom-right corner, and the child's curl gesture -- the reward beat
///    -- is what turns the page,
///  - the two always-available touch affordances: the discreet tap fallback
///    on the current word, and blue vocabulary words, which pause listening
///    and restore the cursor exactly when their card closes, and
///  - the quiet listening indicator, shown while the microphone session is
///    open.
///
/// There is no failure path anywhere in this screen: no word is ever
/// coloured for being imperfect, no sound is ever played at a word, and
/// nothing on screen can blame the reader. The only responses to imperfect
/// reading are patience and help, and both live in Unit 6.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import 'package:learn_to_read/design/layout.dart';
import 'package:learn_to_read/design/page_curl.dart';
import 'package:learn_to_read/design/rive_stage.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/content_models.dart'
    show Level, LevelFormat, Story;
import 'package:learn_to_read/domain/models/user_models.dart' show HelpLevel;
import 'package:learn_to_read/features/analytics/analytics_client.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/listening/contracts/help_state.dart';
import 'package:learn_to_read/features/reading/listening_indicator.dart';
import 'package:learn_to_read/features/reading/narration_controller.dart';
import 'package:learn_to_read/features/reading/page_turn.dart';
import 'package:learn_to_read/features/reading/reading_controller.dart';
import 'package:learn_to_read/features/reading/word_text_view.dart';

/// Opens the vocabulary card for [vocabCardId] and completes when the child
/// closes it again (PRD §8 Unit 7 owns the card itself).
///
/// The reading screen only needs the promise that the future completes on
/// close: that is what lets it restore the reading cursor exactly.
typedef VocabCardOpener = Future<void> Function(String vocabCardId);

/// The default, quiet help state: no tier, no grapheme highlighted.
const HelpState kNoHelp = HelpState(
  currentHelpTier: HelpLevel.none,
  highlightedGraphemeIndex: -1,
);

/// One story, read aloud.
class ReadingScreen extends StatefulWidget {
  /// Creates the reading screen for [story] at [level].
  ///
  /// Every collaborator is injected: [tracker] is the Unit 4 listening
  /// session, [audioService] plays narration, [analytics] records the two
  /// §5 events this screen causes, [stage] is the story animation stage
  /// (idle throughout reading; Unit 8 drives it afterwards), and
  /// [vocabCardOpener] opens vocabulary cards. [helpState] is fed by the
  /// Unit 6 scaffold once that is wired; it defaults to [kNoHelp].
  const ReadingScreen({
    super.key,
    required this.story,
    required this.level,
    required this.tracker,
    required this.audioService,
    required this.analytics,
    required this.installId,
    required this.profileOrdinal,
    required this.levelOrdinal,
    required this.stage,
    required this.vocabCardOpener,
    this.onStoryComplete,
    this.onPageTurned,
    this.onReadingExited,
    this.helpState = kNoHelp,
  });

  /// The story being read.
  final Story story;

  /// The level it is being read at.
  final Level level;

  /// The Unit 4 listening session for this read.
  final ReadingTrackerHandle tracker;

  /// Playback for the recorded sentence narration.
  final AudioService audioService;

  /// Where `story_started` and `word_read` are recorded.
  final AnalyticsClient analytics;

  /// The random per-install UUID (§5 base field).
  final String installId;

  /// Which on-device profile is reading (ordinal 1-4).
  final int profileOrdinal;

  /// The profile current level ordinal.
  final int levelOrdinal;

  /// The story animation stage. It shows the story idle scene for the whole
  /// read (PRD §8 Unit 8) so the celebration later transforms the scene
  /// already on screen; this screen therefore never triggers it.
  final StoryStage stage;

  /// Opens a vocabulary card and completes when it closes.
  final VocabCardOpener vocabCardOpener;

  /// Fired once, a beat after the last word turns green, to hand over to
  /// the celebration sequence.
  final VoidCallback? onStoryComplete;

  /// Fired once per completed page-curl turn, after the word state machine
  /// has advanced onto the new page. The app shell wires it to
  /// `ReadingSession.advancePage`, which is what moves the listening
  /// tracker to the new page's words at turn time (PRD §8 Unit 5 page-turn
  /// hold).
  final VoidCallback? onPageTurned;

  /// Fired once when this screen leaves the tree. The app shell wires it to
  /// `SessionTracker.onReadingScreenExited`, which is what turns leaving
  /// mid-story into `story_abandoned` (Unit 12 owns that judgement).
  final VoidCallback? onReadingExited;

  /// The current help tier and grapheme highlight (Unit 6).
  final HelpState helpState;

  @override
  State<ReadingScreen> createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen> {
  late final ReadingController _controller;
  late final NarrationController _narration;

  @override
  void initState() {
    super.initState();
    _controller = ReadingController(
      story: widget.story,
      level: widget.level,
      tracker: widget.tracker,
      analytics: widget.analytics,
      installId: widget.installId,
      profileOrdinal: widget.profileOrdinal,
      levelOrdinal: widget.levelOrdinal,
      onStoryComplete: widget.onStoryComplete,
      onPageTurned: widget.onPageTurned,
    );
    _narration = NarrationController(
      audioService: widget.audioService,
      pauseListening: _pauseListening,
      resumeListening: _resumeListening,
    );
    _startReading();
  }

  /// Listen-first (A-11): where the level has narration and the page has a
  /// recording, the recording plays through BEFORE anything is listening,
  /// so the child hears the sentence once, unhurried, with nothing to get
  /// right yet. Everywhere else, listening starts immediately.
  void _startReading() {
    final narrationRef = _narrationRefFor(_controller.snapshot.currentPageIndex);
    if (narrationRef == null) {
      _controller.beginListening();
      return;
    }
    unawaited(_playInitialNarration(narrationRef));
  }

  Future<void> _playInitialNarration(String narrationRef) async {
    await _narration.playInitial(narrationRef);
    if (!mounted) return;
    _controller.beginListening();
  }

  /// The recording for [pageIndex], or null when this level has narration
  /// switched off or the page has none authored.
  String? _narrationRefFor(int pageIndex) {
    if (!widget.level.narrationEnabled) return null;
    if (pageIndex < 0 || pageIndex >= widget.story.pages.length) return null;
    for (final sentence in widget.story.pages[pageIndex].sentences) {
      final ref = sentence.narrationAudioRef;
      if (ref != null) return ref;
    }
    return null;
  }

  void _pauseListening() {
    if (!mounted) return;
    _controller.pauseListening();
  }

  void _resumeListening() {
    if (!mounted) return;
    _controller.resumeListening();
  }

  Future<void> _onReplayNarration() async {
    final narrationRef = _narrationRefFor(_controller.snapshot.currentPageIndex);
    if (narrationRef == null || _narration.isPlaying) return;
    await _narration.replay(narrationRef);
  }

  /// A blue word was tapped, at any point in its life: listening pauses,
  /// the card opens, and when it closes listening resumes at the identical
  /// cursor. Opening a card never resolves a word, so the cursor cannot
  /// move underneath it.
  Future<void> _onVocabWordTap(int index) async {
    final tokens = _controller.currentPageTokens;
    if (index < 0 || index >= tokens.length) return;
    final vocabCardId = tokens[index].vocabCardId;
    if (vocabCardId == null) return;
    _controller.pauseListening();
    try {
      await widget.vocabCardOpener(vocabCardId);
    } finally {
      if (mounted) _controller.resumeListening();
    }
  }

  void _onCurrentWordTap(int index) => _controller.tapCurrentWord();

  double _readingTextSize(BuildContext context) {
    final layoutClass = LayoutResolver.resolve(context);
    final isTablet = layoutClass == LayoutClass.tabletPortrait ||
        layoutClass == LayoutClass.tabletLandscape;
    if (widget.level.format == LevelFormat.paragraph) {
      return isTablet
          ? DesignTokens.paragraphTextSizeTablet
          : DesignTokens.paragraphTextSizePhone;
    }
    return isTablet
        ? DesignTokens.sentenceTextSizeTablet
        : DesignTokens.sentenceTextSizePhone;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // Mockup §1: the page body is warm parchment; the reading card sits on
      // it as cream paper (see [_ReadingCard]).
      backgroundColor: DesignTokens.screenBackground,
      body: SafeArea(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => ReadingLayout(
            textRegion: _buildTextRegion(context),
            stageRegion: _StoryStageRegion(stage: widget.stage),
          ),
        ),
      ),
    );
  }

  Widget _buildTextRegion(BuildContext context) {
    final hasNarration = _narrationRefFor(_controller.snapshot.currentPageIndex) != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingMd,
            vertical: DesignTokens.spacingSm,
          ),
          child: Row(
            children: <Widget>[
              ListeningIndicator(isListening: _controller.isListening),
              const Spacer(),
              if (hasNarration)
                IconButton(
                  key: const ValueKey<String>('narration-replay-button'),
                  onPressed: _onReplayNarration,
                  icon: const Icon(
                    Icons.hearing,
                    color: DesignTokens.wordUnreadInk,
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: PageTurn(
            pageIndex: _controller.snapshot.currentPageIndex,
            pageBuilder: _buildPage,
          ),
        ),
      ],
    );
  }

  /// The child's page-curl completed: turn the held page. `turnPage()` is a
  /// no-op unless the machine is actually holding, so a stray second gesture
  /// can never advance twice.
  void _onPageTurned() => _controller.turnPage();

  Widget _buildPage(BuildContext context, int pageIndex) {
    final snapshot = _controller.snapshot;
    if (pageIndex < 0 || pageIndex >= snapshot.pages.length) {
      return const SizedBox.shrink();
    }
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        WordTextView(
          words: _controller.pages[pageIndex],
          wordStates: snapshot.pages[pageIndex],
          helpState: widget.helpState,
          textSize: _readingTextSize(context),
          onCurrentWordTap: _onCurrentWordTap,
          onVocabWordTap: _onVocabWordTap,
        ),
        const SizedBox(height: DesignTokens.spacingLg),
        const _WordStateLegend(),
      ],
    );

    // Page-turn hold (PRD §8 Unit 5, mockup-spec §8): while the machine is
    // holding at this completed non-final page, the reading card grows to
    // fill the page region (a book page) and carries the bottom-right
    // page-curl dog-ear. [PageCurlCorner] needs bounded constraints for its
    // corner geometry, which is why the held layout swaps the
    // centered/scrollable card for a stretched one.
    final held =
        snapshot.isPageComplete && pageIndex == snapshot.currentPageIndex;
    if (held) {
      return Padding(
        key: ValueKey<String>('page-$pageIndex'),
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingLg,
          vertical: DesignTokens.spacingMd,
        ),
        child: PageCurlCorner(
          enabled: true,
          page: _ReadingCard(child: SingleChildScrollView(child: content)),
          // The face revealed under the curl is a blank sheet of the same
          // cream paper, NOT the next page's live words: the next page has
          // not started yet (its words go current only on turnPage()), and
          // rendering it here would duplicate the per-word widget keys.
          nextPage: const _ReadingCard(child: SizedBox.expand()),
          onTurned: _onPageTurned,
        ),
      );
    }

    return Center(
      key: ValueKey<String>('page-$pageIndex'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingLg,
          vertical: DesignTokens.spacingMd,
        ),
        child: _ReadingCard(child: content),
      ),
    );
  }

  @override
  void dispose() {
    // Leaving mid-story closes the microphone session: the tracker itself
    // belongs to the app shell, which starts and stops it, but no session
    // may outlive the screen that opened it.
    if (!_controller.snapshot.isStoryComplete) {
      widget.tracker.pause();
    }
    _controller.dispose();
    widget.onReadingExited?.call();
    super.dispose();
  }
}

/// The mockup's reading card (docs/design/mockup-spec.md §3): a cream paper
/// card -- gradient [DesignTokens.readingBackground] ->
/// [DesignTokens.cardGradientEnd], 1px [DesignTokens.cardBorder], radius 20
/// -- floating on the parchment page with the spec's soft drop shadow
/// (`0 18px 40px -28px`, ink at 45%). The spec's 1px inset top highlight is
/// approximated by the gradient starting at the card's lightest paper tone
/// (no raw color literals may exist here, and Flutter has no inset shadow).
class _ReadingCard extends StatelessWidget {
  const _ReadingCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey<String>('reading-card'),
      padding: const EdgeInsets.all(DesignTokens.spacingLg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            DesignTokens.readingBackground,
            DesignTokens.cardGradientEnd,
          ],
        ),
        border: Border.all(color: DesignTokens.cardBorder),
        borderRadius: BorderRadius.circular(20),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: DesignTokens.wordUnreadInk.withValues(alpha: 0.45),
            offset: const Offset(0, 18),
            blurRadius: 40,
            spreadRadius: -28,
          ),
        ],
      ),
      child: child,
    );
  }
}

/// The legend row under the reading text (mockup §3): a dashed divider, then
/// three dots explaining the word states -- green "read it", amber "saying
/// now", blue "new word — tap it". Purely additive decoration; it renders no
/// tappable surface and collides with no pinned key.
class _WordStateLegend extends StatelessWidget {
  const _WordStateLegend();

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey<String>('reading-legend'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const CustomPaint(
          painter: _DashedDividerPainter(),
          child: SizedBox(height: 1, width: double.infinity),
        ),
        const SizedBox(height: DesignTokens.spacingSm + DesignTokens.spacingXs),
        Wrap(
          alignment: WrapAlignment.center,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: DesignTokens.spacingMd,
          runSpacing: DesignTokens.spacingXs,
          children: const <Widget>[
            _LegendItem(color: DesignTokens.wordReadGreen, label: 'read it'),
            _LegendItem(color: DesignTokens.wordCurrentInk, label: 'saying now'),
            _LegendItem(color: DesignTokens.wordVocabBlue, label: 'new word — tap it'),
          ],
        ),
      ],
    );
  }
}

/// One legend entry: a state-colored dot plus its label
/// (12px, weight 700, [DesignTokens.legendText], mockup §3).
class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        DecoratedBox(
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: const SizedBox(width: 10, height: 10),
        ),
        const SizedBox(width: DesignTokens.spacingXs + 2),
        Text(
          label,
          style: const TextStyle(
            fontFamily: DesignTokens.displayFontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: DesignTokens.legendText,
          ),
        ),
      ],
    );
  }
}

/// Paints the mockup's dashed rule above the legend
/// ([DesignTokens.dashedDivider], mockup §3).
class _DashedDividerPainter extends CustomPainter {
  const _DashedDividerPainter();

  static const double _dashLength = 6.0;
  static const double _gapLength = 5.0;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = DesignTokens.dashedDivider
      ..strokeWidth = 1.0;
    var x = 0.0;
    final y = size.height / 2;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(x + _dashLength, y), paint);
      x += _dashLength + _gapLength;
    }
  }

  @override
  bool shouldRepaint(_DashedDividerPainter oldDelegate) => false;
}

/// The animation-stage half of the reading layout.
///
/// During reading the stage shows the story idle scene and nothing else
/// (PRD §8 Unit 8), so this is a token-styled placeholder standing in for
/// the Rive artboard until Unit 8 lands the real view; [stage] is held here
/// because that view binds to it, and is deliberately never triggered from
/// the reading screen.
class _StoryStageRegion extends StatelessWidget {
  const _StoryStageRegion({required this.stage});

  /// The story stage this region will render, idle, for the whole read.
  final StoryStage stage;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: DesignTokens.surfaceBackground,
          borderRadius: BorderRadius.circular(DesignTokens.spacingMd),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

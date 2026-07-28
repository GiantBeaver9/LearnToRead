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
///  - the page host, turning pages full-bleed at the authored page
///    boundaries the merged word state machine reports,
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
      backgroundColor: DesignTokens.readingBackground,
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

  Widget _buildPage(BuildContext context, int pageIndex) {
    final snapshot = _controller.snapshot;
    if (pageIndex < 0 || pageIndex >= snapshot.pages.length) {
      return const SizedBox.shrink();
    }
    return Center(
      key: ValueKey<String>('page-$pageIndex'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingLg,
          vertical: DesignTokens.spacingMd,
        ),
        child: WordTextView(
          words: _controller.pages[pageIndex],
          wordStates: snapshot.pages[pageIndex],
          helpState: widget.helpState,
          textSize: _readingTextSize(context),
          onCurrentWordTap: _onCurrentWordTap,
          onVocabWordTap: _onVocabWordTap,
        ),
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

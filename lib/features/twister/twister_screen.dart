/// The tongue-twister booster node's screen (PRD §8 Unit 14; ticket
/// twister-flow).
///
/// A thin, token-styled composition over [TwisterController] — all the
/// runtime behavior (narration-before-listening, sound-mode scoring,
/// listen-then-tap fallback, completion effects) lives in the controller and
/// is contract-tested there. This widget only renders what the controller
/// exposes and forwards the two gestures the child has: tapping a word, and
/// answering the optional "faster" offer.
///
/// What it shows, in flow order:
/// 1. The twister's words, large, in the reading face. Words already covered
///    render [DesignTokens.wordReadGreen] via [WordState.renderColor] — the
///    same word-state → color mapping the reading screen uses, reused rather
///    than re-derived, so a twister's green never drifts from a story's.
/// 2. A small, non-alarming listening indicator, shown exactly while
///    `controller.isListening` (PRD §8 Unit 4: the indicator is visible
///    whenever the mic is open, and only then). It is deliberately absent
///    during the narration and after completion.
/// 3. A tap-to-advance affordance. Always available — it is the whole path
///    when consent is off or the engine failed (`controller.isTapMode`), and
///    a always-there escape hatch otherwise (PRD §6: never hard-blocked).
/// 4. On completion, [SparkleCelebration], then the optional
///    [FasterPassPrompt] — offered once, skippable, granting nothing.
///
/// **Placeholder art (PRD §10 OQ-8).** Illustration, the listening
/// indicator's real treatment, and the sparkle asset are owner-commissioned;
/// every color/size/duration here comes from [DesignTokens] so skinning is a
/// token change, not a rewrite of this file.
///
/// **Observing the controller.** [TwisterController] is deliberately not a
/// `ChangeNotifier` — its pinned contract is a plain object the app shell
/// owns, so nothing below it depends on a particular state-management
/// choice. This screen therefore samples the controller once per frame while
/// an attempt is live. When the app shell wraps the controller in a provider,
/// that sampling can be replaced with a real subscription without touching
/// anything else here.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/features/reading/word_state.dart';
import 'package:learn_to_read/features/twister/faster_pass.dart';
import 'package:learn_to_read/features/twister/sparkle_celebration.dart';
import 'package:learn_to_read/features/twister/twister_controller.dart';

/// The booster node screen for one tongue-twister attempt.
class TwisterScreen extends StatefulWidget {
  /// Creates the screen for [controller]'s attempt.
  ///
  /// [runFasterPass] performs one optional replay round (typically: build a
  /// fresh [TwisterController] for the same twister and run it). When null,
  /// no faster-pass offer is made. [onExit] is invoked when the child leaves
  /// the node; the node is already done by then either way — the faster pass
  /// never gates it.
  const TwisterScreen({
    super.key,
    required this.controller,
    this.runFasterPass,
    this.onExit,
  });

  /// The attempt this screen renders. The screen calls `start()` on it once,
  /// on first build, and `stop()` on dispose.
  final TwisterController controller;

  /// Runs one optional "faster" replay round, or null to make no offer.
  final Future<void> Function()? runFasterPass;

  /// Invoked when the child leaves the node.
  final VoidCallback? onExit;

  @override
  State<TwisterScreen> createState() => _TwisterScreenState();
}

class _TwisterScreenState extends State<TwisterScreen> {
  FasterPassPrompt? _fasterPass;
  bool _celebrationDone = false;
  bool _sampling = false;

  TwisterController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    unawaited(_controller.start());
    _scheduleSample();
  }

  @override
  void dispose() {
    _sampling = false;
    _controller.stop();
    super.dispose();
  }

  /// Re-reads the controller once per frame while the attempt is live. See
  /// the library doc for why this is a sample rather than a subscription.
  void _scheduleSample() {
    if (_sampling) return;
    _sampling = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _sampling = false;
      if (!mounted) return;
      setState(() {});
      if (!_controller.isComplete) _scheduleSample();
    });
  }

  void _onTapWord() {
    setState(_controller.tapWord);
  }

  void _onCelebrationFinished() {
    if (!mounted) return;
    setState(() {
      _celebrationDone = true;
      final runReplay = widget.runFasterPass;
      if (runReplay != null && _controller.isComplete) {
        _fasterPass = FasterPassPrompt(
          primaryController: _controller,
          runReplay: runReplay,
        );
      }
    });
  }

  /// How many leading words render as covered.
  ///
  /// Tap mode counts taps; the mic path maps the sound-mode
  /// [TwisterController.matchedFraction] across the twister's words, which is
  /// what "green-word tracking driven by sound-level matching" (PRD §8
  /// Unit 14) means when the unit of grading is the phoneme sequence rather
  /// than the word.
  int get _coveredWordCount {
    final total = _controller.totalWordCount;
    if (_controller.isComplete) return total;
    final fromSound = (_controller.matchedFraction * total).floor();
    final fromTaps = _controller.tappedWordCount;
    return fromSound > fromTaps ? fromSound : fromTaps;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final showCelebration = controller.isComplete && !_celebrationDone;

    return ColoredBox(
      color: DesignTokens.screenBackground,
      child: SafeArea(
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(DesignTokens.spacingLg),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(child: Center(child: _buildTwisterText())),
                  _ListeningIndicator(visible: controller.isListening),
                  const SizedBox(height: DesignTokens.spacingMd),
                  if (!controller.isComplete)
                    _TapAdvanceButton(
                      onTap: _onTapWord,
                      emphasized: controller.isTapMode,
                    ),
                  if (_fasterPass != null)
                    _FasterPassRow(
                      prompt: _fasterPass!,
                      onChanged: () => setState(() {}),
                      onDone: widget.onExit,
                    ),
                ],
              ),
            ),
            if (showCelebration)
              Positioned.fill(
                child: SparkleCelebration(onFinished: _onCelebrationFinished),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTwisterText() {
    final covered = _coveredWordCount;
    final words = _controller.twister.words;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: DesignTokens.spacingMd,
      runSpacing: DesignTokens.spacingSm,
      children: [
        for (var i = 0; i < words.length; i++)
          Text(
            words[i].text,
            style: TextStyle(
              fontFamily: DesignTokens.readingFontFamily,
              fontSize: DesignTokens.sentenceTextSizePhone,
              color: WordState(
                index: i,
                lifecycle:
                    i < covered ? WordLifecycle.done : WordLifecycle.unread,
              ).renderColor,
            ),
          ),
      ],
    );
  }
}

/// The small, non-alarming "we are listening" marker (PRD §8 Unit 4).
/// Rendered only while the mic is genuinely open.
class _ListeningIndicator extends StatelessWidget {
  const _ListeningIndicator({required this.visible});

  final bool visible;

  static const double _dotSize = 14.0;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox(height: _dotSize);
    return SizedBox(
      height: _dotSize,
      width: _dotSize,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: DesignTokens.wordReadGreen,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// Tap-to-advance. Always present: listen-then-tap is the fallback path when
/// there is no consent or no healthy engine, and an escape hatch otherwise.
class _TapAdvanceButton extends StatelessWidget {
  const _TapAdvanceButton({required this.onTap, required this.emphasized});

  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: emphasized
              ? DesignTokens.surfaceBackground
              : DesignTokens.screenBackground,
          borderRadius: BorderRadius.circular(DesignTokens.spacingMd),
        ),
        child: const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: DesignTokens.spacingLg,
            vertical: DesignTokens.spacingMd,
          ),
          child: Text(
            'Tap each word',
            style: TextStyle(
              fontFamily: DesignTokens.displayFontFamily,
              fontSize: DesignTokens.paragraphTextSizePhone,
              color: DesignTokens.wordUnreadInk,
            ),
          ),
        ),
      ),
    );
  }
}

/// The optional "say it again — a little faster!" offer. Purely optional and
/// skippable; the node is already done behind it either way.
class _FasterPassRow extends StatelessWidget {
  const _FasterPassRow({
    required this.prompt,
    required this.onChanged,
    required this.onDone,
  });

  final FasterPassPrompt prompt;
  final VoidCallback onChanged;
  final VoidCallback? onDone;

  @override
  Widget build(BuildContext context) {
    if (!prompt.isOffered) {
      return _label('Nice reading!');
    }
    return Column(
      children: [
        _label('Say it again — a little faster!'),
        const SizedBox(height: DesignTokens.spacingSm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () async {
                await prompt.accept();
                onChanged();
              },
              child: _label('Yes!'),
            ),
            const SizedBox(width: DesignTokens.spacingXl),
            GestureDetector(
              onTap: () {
                prompt.skip();
                onChanged();
                onDone?.call();
              },
              child: _label('No thanks'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontFamily: DesignTokens.displayFontFamily,
          fontSize: DesignTokens.paragraphTextSizePhone,
          color: DesignTokens.wordUnreadInk,
        ),
      );
}

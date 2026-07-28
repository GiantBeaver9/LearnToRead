/// A single node on the progress map's illustrated trail (PRD §8 Unit 9 +
/// Unit 14; ticket progress-map-collection accept entries 1-3).
///
/// A [MapNode] renders either an authored story or a tongue-twister booster
/// (Unit 14) at one point along the trail. Its visual treatment is driven
/// entirely by [visualState] -- this widget never computes progress itself;
/// callers (ProgressMapScreen) derive [visualState] from `StoryProgress` (or,
/// for boosters, from `unlockedTwisterLevelIds`) and hand it in.
///
/// Structural markers (findable by [Key], the headless proxy for the
/// pixel-level "distinct visual treatment" this container cannot golden-test
/// -- see map_states_test.dart / twister_nodes_test.dart for the pinned
/// contract):
///   - `map-node-thumbnail-<id>`       present iff [visualState] == completed
///   - `map-node-awake-animation-<id>` present iff [visualState] == awake
///   - `map-node-asleep-marker-<id>`   present iff [visualState] == asleep
///   - `map-node-twister-badge-<id>`   present iff [kind] == twisterBooster
///   - `map-node-highlight-<id>`       present iff [highlighted] == true
library;

import 'package:flutter/material.dart';
import 'package:learn_to_read/design/tokens.dart';

/// What a map node represents.
enum MapNodeKind { story, twisterBooster }

/// A node's derived visual state (PRD §8 Unit 9: "completed -> thumbnail;
/// the rolling window awake/gently animated; future stories asleep but
/// visible").
enum MapNodeVisualState { asleep, awake, completed }

/// One trail node: a story stepping-stone or a tongue-twister booster.
///
/// Real trail/booster illustrations are owner-commissioned (PRD §10 OQ-4);
/// this widget paints token-styled placeholder shapes behind that future
/// artwork, so the finished illustration can drop in without changing this
/// widget's API or structural markers.
class MapNode extends StatelessWidget {
  const MapNode({
    super.key,
    required this.id,
    required this.kind,
    required this.visualState,
    this.highlighted = false,
    this.onTap,
  });

  /// The story or twister id this node represents.
  final String id;

  final MapNodeKind kind;

  final MapNodeVisualState visualState;

  /// True for the single node highlighted after a return-navigation payload
  /// names it (PRD §8 Unit 9 accept "next story highlighted"). Never true
  /// for a [MapNodeKind.twisterBooster] node.
  final bool highlighted;

  /// Fired on tap, but only while [isTappable] -- an asleep node swallows
  /// the tap even when this is non-null (pinned tap-gating contract).
  final VoidCallback? onTap;

  /// True unless [visualState] is asleep. A future/unreached node is
  /// visible on the trail but not yet interactive.
  bool get isTappable => visualState != MapNodeVisualState.asleep;

  Color get _fillColor {
    switch (kind) {
      case MapNodeKind.twisterBooster:
        return DesignTokens.surfaceBackground;
      case MapNodeKind.story:
        return DesignTokens.readingBackground;
    }
  }

  IconData get _glyph {
    switch (kind) {
      case MapNodeKind.twisterBooster:
        return Icons.record_voice_over;
      case MapNodeKind.story:
        return visualState == MapNodeVisualState.completed ? Icons.auto_stories : Icons.menu_book;
    }
  }

  @override
  Widget build(BuildContext context) {
    final asleep = visualState == MapNodeVisualState.asleep;
    Widget core = Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _fillColor,
        border: Border.all(
          color: highlighted ? DesignTokens.wordVocabBlue : DesignTokens.wordUnreadInk.withAlpha(60),
          width: highlighted ? 4 : 2,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(_glyph, color: DesignTokens.wordUnreadInk),
    );

    if (visualState == MapNodeVisualState.awake) {
      core = _GentlePulse(child: core);
    }

    return GestureDetector(
      onTap: isTappable ? onTap : null,
      child: Opacity(
        opacity: asleep ? 0.5 : 1.0,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            core,
            if (visualState == MapNodeVisualState.completed)
              KeyedSubtree(
                key: ValueKey('map-node-thumbnail-$id'),
                child: const SizedBox.shrink(),
              ),
            if (visualState == MapNodeVisualState.awake)
              KeyedSubtree(
                key: ValueKey('map-node-awake-animation-$id'),
                child: const SizedBox.shrink(),
              ),
            if (asleep)
              KeyedSubtree(
                key: ValueKey('map-node-asleep-marker-$id'),
                child: const SizedBox.shrink(),
              ),
            if (kind == MapNodeKind.twisterBooster)
              Positioned(
                top: -4,
                right: -4,
                child: KeyedSubtree(
                  key: ValueKey('map-node-twister-badge-$id'),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: DesignTokens.wordVocabBlue,
                      border: Border.all(color: DesignTokens.screenBackground, width: 2),
                    ),
                  ),
                ),
              ),
            if (highlighted)
              Positioned.fill(
                child: KeyedSubtree(
                  key: ValueKey('map-node-highlight-$id'),
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: DesignTokens.wordVocabBlue, width: 3),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A slow, continuous scale pulse -- the placeholder stand-in for "gently
/// animated" (PRD §8 Unit 9) until the owner-commissioned trail animation
/// lands. Purely cosmetic: it never gates or reports tap behavior, which
/// [MapNode] handles itself via its outer [GestureDetector].
class _GentlePulse extends StatefulWidget {
  const _GentlePulse({required this.child});

  final Widget child;

  @override
  State<_GentlePulse> createState() => _GentlePulseState();
}

class _GentlePulseState extends State<_GentlePulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: Tween<double>(begin: 0.94, end: 1.06).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: widget.child,
    );
  }
}

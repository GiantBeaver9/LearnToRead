/// The full-bleed page-turn transition (PRD §8 Unit 5: "One sentence (early
/// levels) up to one paragraph (later levels) per page; multi-page stories
/// page with a full-bleed page-turn transition").
///
/// [PageTurn] is a pure presentation widget: it knows which page index is
/// showing and how to move between pages, and nothing about words, reading,
/// or when a page is finished. The reading screen feeds it
/// `WordStateSnapshot.currentPageIndex`, which the merged
/// `WordStateMachine` advances at authored page boundaries.
///
/// Full-bleed means exactly that: the built page is given the whole of the
/// parent, with no gutter or inset of its own, so a page reads as a page of
/// a book rather than a card floating on one.
library;

import 'package:flutter/material.dart';

/// How long a page takes to turn.
///
/// Local rather than a [DesignTokens] member because the token file
/// currently pins only the two motion durations the design system has
/// signed names for (the green sweep and the collectible flight); this
/// moves into the token file with the rest of the motion scale once the
/// owner signs the style guide off (PRD §10 OQ-8).
const Duration kPageTurnDuration = Duration(milliseconds: 350);

/// How far the incoming page slides in, as a fraction of its own width.
const double _pageTurnSlideFraction = 0.08;

/// Shows one page of a story and transitions between pages.
class PageTurn extends StatelessWidget {
  /// Creates a page host showing [pageIndex], built by [pageBuilder].
  const PageTurn({
    super.key,
    required this.pageIndex,
    required this.pageBuilder,
    this.duration = kPageTurnDuration,
  });

  /// The page currently being read.
  final int pageIndex;

  /// Builds the content of a given page. Called for the page being shown;
  /// the outgoing page keeps the widget it was already built with while it
  /// transitions away.
  final Widget Function(BuildContext context, int pageIndex) pageBuilder;

  /// How long the turn takes.
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        // Full-bleed: every page, incoming and outgoing, is stretched to
        // the whole of the available space rather than centered at its
        // intrinsic size (which is what the default layout builder does).
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(_pageTurnSlideFraction, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey<int>(pageIndex),
        child: SizedBox.expand(child: pageBuilder(context, pageIndex)),
      ),
    );
  }
}

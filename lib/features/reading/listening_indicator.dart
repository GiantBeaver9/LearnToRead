/// The listening indicator (PRD §8 Unit 4 UI side, pinned: "small
/// non-alarming listening indicator always visible while mic open").
///
/// It reports exactly one fact -- whether the microphone session is open --
/// and it reports it quietly: a small ink dot inside a soft ring, in
/// design-token ink, with no motion, no sound, and no state of its own. It
/// is deliberately incapable of expressing anything about how the reading
/// is going.
library;

import 'package:flutter/material.dart';

import 'package:learn_to_read/design/tokens.dart';

/// Diameter of the indicator dot.
const double kListeningDotDiameter = 10.0;

/// Diameter of the soft ring the dot sits in.
const double kListeningRingDiameter = 24.0;

/// Opacity of the dot: present, but never insistent.
const double kListeningDotOpacity = 0.6;

/// Opacity of the ring behind the dot.
const double kListeningRingOpacity = 0.08;

/// A small, quiet indicator of an open microphone session.
class ListeningIndicator extends StatelessWidget {
  /// Creates an indicator reflecting [isListening], which comes straight
  /// from the tracker session state.
  const ListeningIndicator({super.key, required this.isListening});

  /// Whether the microphone session is open right now.
  final bool isListening;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: kListeningRingDiameter,
      height: kListeningRingDiameter,
      child: isListening
          ? DecoratedBox(
              key: const ValueKey<String>('listening-indicator-active'),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: DesignTokens.wordUnreadInk.withValues(alpha: kListeningRingOpacity),
              ),
              child: Center(
                child: SizedBox(
                  width: kListeningDotDiameter,
                  height: kListeningDotDiameter,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: DesignTokens.wordUnreadInk.withValues(alpha: kListeningDotOpacity),
                    ),
                  ),
                ),
              ),
            )
          : null,
    );
  }
}

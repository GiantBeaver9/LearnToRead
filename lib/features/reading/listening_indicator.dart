/// The listening indicator (PRD §8 Unit 4 UI side, pinned: "small
/// non-alarming listening indicator always visible while mic open"),
/// restyled to the owner mockup's listening pill (docs/design/mockup-spec.md
/// §4): a cream card pill with the waveform bars and a quiet "Listening…"
/// label.
///
/// It reports exactly one fact -- whether the microphone session is open --
/// and it reports it quietly. It is deliberately incapable of expressing
/// anything about how the reading is going.
///
/// HARNESS NOTE (frozen-test compatibility): the mockup's `wave` animation
/// loops forever, but the frozen reading suites `pumpAndSettle` this screen
/// while listening is active (test/features/reading/page_turn_test.dart:259,
/// 282), and a perpetually-ticking animation would hang them. The waveform
/// is therefore rendered as a static [WaveBars] frame -- the same bars, the
/// same tokens, staggered at their natural phase offsets -- by mounting the
/// motion-library widget under `TickerMode(enabled: false)`, which mutes its
/// ticker so no frame is ever scheduled. The looping motion itself stays
/// parked until the frozen contract is relaxed (see the restyle report).
library;

import 'package:flutter/material.dart';

import 'package:learn_to_read/design/motion.dart';
import 'package:learn_to_read/design/tokens.dart';

/// Height of the waveform bars inside the pill.
const double kListeningWaveHeight = 18.0;

/// Label size (mockup §4: 14.5px weight 800).
const double kListeningLabelSize = 14.5;

/// A small, quiet indicator of an open microphone session.
class ListeningIndicator extends StatelessWidget {
  /// Creates an indicator reflecting [isListening], which comes straight
  /// from the tracker session state.
  const ListeningIndicator({super.key, required this.isListening});

  /// Whether the microphone session is open right now.
  final bool isListening;

  @override
  Widget build(BuildContext context) {
    if (!isListening) return const SizedBox.shrink();
    return Container(
      key: const ValueKey<String>('listening-indicator-active'),
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingMd,
        vertical: DesignTokens.spacingSm,
      ),
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
        borderRadius: BorderRadius.circular(999),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: DesignTokens.wordUnreadInk.withValues(alpha: 0.18),
            offset: const Offset(0, 6),
            blurRadius: 14,
            spreadRadius: -8,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Static frame of the motion library's waveform (see the harness
          // note in the file doc comment).
          const TickerMode(
            enabled: false,
            child: WaveBars(height: kListeningWaveHeight),
          ),
          const SizedBox(width: DesignTokens.spacingSm),
          Text(
            'Listening…',
            style: const TextStyle(
              fontFamily: DesignTokens.displayFontFamily,
              fontSize: kListeningLabelSize,
              fontWeight: FontWeight.w800,
              color: DesignTokens.mutedBody,
            ),
          ),
        ],
      ),
    );
  }
}

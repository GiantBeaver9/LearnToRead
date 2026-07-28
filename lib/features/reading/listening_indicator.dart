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
/// AMENDED 2026-07-28: page-turn-hold ruling (PRD §8 Unit 5). The waveform
/// was previously parked as a static frame under `TickerMode(enabled:
/// false)` because the then-frozen reading suites `pumpAndSettle`d this
/// screen while listening was active. Those two sites were re-expressed as
/// bounded stepped pumps in the same ruling's amendments, so [WaveBars] now
/// animates live (mockup-spec §7 `wave`: 900 ms loop, 120 ms stagger).
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
          // The motion library's live waveform (mockup-spec §4/§7).
          const WaveBars(height: kListeningWaveHeight),
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

// Unit 0 recognition spike — separate, disposable Flutter entrypoint.
//
// Run via `flutter run -t lib/spike/spike_main.dart` (see
// docs/spike/README.md for the full owner run-through, including how to
// register the native platform-channel handlers). This entrypoint is
// intentionally separate from the main app's lib/main.dart: PRD.md §8
// Unit 0 pins this as throwaway code, not wired into the main app's
// navigation, state management, or engine interface.

import 'package:flutter/material.dart';

import 'spike_screen.dart';

void main() {
  runApp(const SpikeApp());
}

/// Bare-bones `MaterialApp` shell hosting [SpikeScreen]. No routing, no
/// Riverpod, no design tokens — the spike is disposable (PRD §8 Unit 0).
class SpikeApp extends StatelessWidget {
  const SpikeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'ASR Spike (Unit 0 — disposable)',
      home: SpikeScreen(),
    );
  }
}

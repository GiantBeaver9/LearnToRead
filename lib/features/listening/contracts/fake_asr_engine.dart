/// FakeAsrEngine: scripted hypothesis playback for testing (Unit 4 fakes).
///
/// Emits a predefined sequence of hypotheses with configurable timing,
/// records the biasing context, and optionally simulates engine failure.
///
/// Works with or without fake_async for deterministic timing tests.
library;

import 'dart:async';
import 'asr_engine.dart';

/// Fake ASR engine for testing: emits scripted hypothesis sequences.
///
/// Use [FakeAsrEngine] to test the word matcher and listening tracker
/// without invoking a real speech recognizer. Configure the script,
/// delays, and failure mode; assert the recorded biasing context
/// to verify expected-text hybridization.
class FakeAsrEngine implements AsrEngine {
  /// Constructs a fake engine with a scripted hypothesis sequence.
  ///
  /// [script]: list of hypotheses to emit in order.
  /// [delayBetweenHypotheses]: delay before emitting each hypothesis.
  /// Defaults to [Duration.zero].
  /// [shouldFail]: if true, [hypothesesStream] throws an exception,
  /// simulating engine unavailability. Defaults to false.
  FakeAsrEngine({
    required this.script,
    this.delayBetweenHypotheses = const Duration(),
    this.shouldFail = false,
  });

  /// The scripted hypothesis sequence to emit.
  final List<Hypothesis> script;

  /// Delay before emitting each hypothesis.
  final Duration delayBetweenHypotheses;

  /// If true, [hypothesesStream] throws, simulating engine failure.
  final bool shouldFail;

  /// The biasing context recorded from the most recent [start] call.
  /// Mutable for test assertions; typically read-only after [start].
  late List<String> recordedBiasingContext;

  @override
  void start(List<String> biasingContext) {
    recordedBiasingContext = biasingContext;
  }

  @override
  void stop() {
    // No-op for fake; real engine would clean up resources.
  }

  @override
  Stream<Hypothesis> get hypothesesStream {
    if (shouldFail) {
      throw StateError('FakeAsrEngine: simulated engine failure');
    }
    return _emitHypotheses();
  }

  /// Internal stream factory.
  Stream<Hypothesis> _emitHypotheses() async* {
    for (final hyp in script) {
      if (delayBetweenHypotheses > Duration.zero) {
        await Future.delayed(delayBetweenHypotheses);
      }
      yield hyp;
    }
  }
}

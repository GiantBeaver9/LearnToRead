/// Tap-the-word fallback engine (PRD §8 Unit 4 pinned fallback chain).
///
/// "Fallback chain: engine failure or mic unavailable → tap-the-word (child
/// taps the current word to advance; always available, visually discreet)."
///
/// [TapEngine] is the *production* end of that chain, not a test stub: it is
/// an [AsrEngine] like any other, so a tap flows through exactly the same
/// matching pipeline as a spoken word. That is what makes the PRD's
/// "engine choice (on-device/cloud/tap) is invisible above this interface"
/// literally true — the tracker does not branch on the source of a
/// hypothesis, and a tapped word produces a `wordAccepted` event identical in
/// shape to an ASR acceptance.
///
/// The discreet tap affordance itself belongs to the reading screen (Unit 5);
/// this class is only the engine seam behind it.
library;

import 'dart:async';

import 'package:learn_to_read/features/listening/contracts/asr_engine.dart';

/// An [AsrEngine] whose "audio" is the child tapping the current word.
///
/// It never opens a microphone and never holds a buffer of anything: a call
/// to [tapWord] synthesises the one hypothesis a perfect recognizer would
/// have produced for that word and pushes it onto [hypothesesStream].
///
/// Delivery is synchronous (the stream is a `sync` broadcast stream) so a tap
/// resolves inside the same turn as the gesture — the child sees the word go
/// green with no frame of latency.
class TapEngine implements AsrEngine {
  /// Creates a tap engine. Cheap; the tracker owns one for a whole read
  /// whether or not it ever falls back.
  TapEngine();

  final StreamController<Hypothesis> _controller =
      StreamController<Hypothesis>.broadcast(sync: true);

  List<String>? _recordedBiasingContext;
  int _stopCallCount = 0;

  /// The biasing context handed to the most recent [start], or null if
  /// [start] has never been called.
  ///
  /// A tap engine has no language model to bias, but it records the context
  /// so it is observationally identical to a real engine at this seam.
  List<String>? get recordedBiasingContext => _recordedBiasingContext;

  /// How many times [stop] has been called.
  int get stopCallCount => _stopCallCount;

  @override
  void start(List<String> biasingContext) {
    _recordedBiasingContext = biasingContext;
  }

  @override
  void stop() {
    _stopCallCount += 1;
  }

  @override
  Stream<Hypothesis> get hypothesesStream => _controller.stream;

  /// Emits the exact-text [Hypothesis] a recognizer would produce for [word].
  ///
  /// Word-only, no phones: the matcher scores it textually against the target
  /// and grades it `exact`, which the tracker routes to `wordAccepted`.
  void tapWord(String word) {
    _controller.add(Hypothesis(wordHypotheses: [word], phoneHypotheses: null));
  }
}

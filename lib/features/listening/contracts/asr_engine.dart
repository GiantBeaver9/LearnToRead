/// Engine-agnostic ASR interface (Unit 4 pinned design).
///
/// The ASR engine is any recognizer exposing word/phone hypotheses with
/// contextual biasing. Engine choice (on-device / cloud / tap) is invisible
/// above this interface.
///
/// Hypothesis: the matcher always knows the target sentence; the engine is
/// fed the child's audio biased with the expected words (contextual strings).
/// Hypotheses are scored by the matching layer against the known next word —
/// never open-ended transcription (PRD §6).
library;

/// A single hypothesis from the ASR engine, carrying both word-level and
/// optional phone-level detail.
///
/// The ASR engine may return multiple word hypotheses (ranked by confidence)
/// and, where available, aligned phoneme sequences. Not all engines provide
/// phone-level detail; null [phoneHypotheses] means the engine did not
/// surface phones for this hypothesis (Unit 14 sound mode approximates
/// downstream by phonetic distance if only words are available).
class Hypothesis {
  /// Constructs a hypothesis with word alternatives and optional phones.
  ///
  /// [wordHypotheses]: list of candidate words (ordered by confidence),
  /// e.g. `['cat', 'can', 'car']`. Never null or empty.
  ///
  /// [phoneHypotheses]: optional list of phoneme IDs (e.g. `['K', 'AE', 'T']`).
  /// Null means the engine did not provide phone-level detail for this
  /// hypothesis. When present, length must align with the first word in
  /// [wordHypotheses] (the phonemes of the top candidate).
  const Hypothesis({
    required this.wordHypotheses,
    required this.phoneHypotheses,
  });

  /// Candidate words from the engine, ordered by confidence.
  /// Example: `['cat', 'can', 'car']` for input sounding like 'cat'.
  /// Never null; may be empty in malformed engines, but contract expects
  /// non-empty for meaningful hypotheses.
  final List<String> wordHypotheses;

  /// Aligned phoneme sequence for the top word hypothesis, if available.
  /// Null if the engine does not expose phone-level detail.
  /// When present, typically aligns with the first element of
  /// [wordHypotheses]. Example: `['K', 'AE', 'T']` for 'cat'.
  final List<String>? phoneHypotheses;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Hypothesis &&
          _listEquals(other.wordHypotheses, wordHypotheses) &&
          _listEquals(other.phoneHypotheses, phoneHypotheses));

  @override
  int get hashCode => Object.hash(
        Object.hashAll(wordHypotheses),
        phoneHypotheses == null ? null : Object.hashAll(phoneHypotheses!),
      );

  @override
  String toString() => 'Hypothesis('
      'wordHypotheses: $wordHypotheses, '
      'phoneHypotheses: $phoneHypotheses)';
}

/// Compares two lists for deep (element-by-element) equality.
bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return a == b;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Engine-agnostic ASR interface every ASR engine implements.
///
/// The engine abstracts over on-device (A-10), cloud, or tap fallback.
/// All engines expose word/phone hypotheses and accept contextual biasing
/// (expected words / phrase hints).
///
/// Lifecycle: [start] with biasing context (the expected sentence words) →
/// engine processes audio and emits [Hypothesis] objects through
/// [hypothesesStream] → [stop] when reading ends.
abstract class AsrEngine {
  /// Starts audio processing with contextual biasing.
  ///
  /// [biasingContext]: list of expected words and contextual strings.
  /// Example: for the sentence "the cat sat", pass `['the', 'cat', 'sat']`.
  /// The engine uses this to bias its language model (on-device or cloud),
  /// focusing hypotheses on expected words.
  ///
  /// Calling [start] multiple times without [stop] between them is undefined;
  /// implementations should handle gracefully (stop-then-restart or error).
  void start(List<String> biasingContext);

  /// Stops audio processing and closes the hypothesis stream.
  ///
  /// After [stop], [hypothesesStream] may be closed or produce no new events.
  void stop();

  /// Stream of hypotheses emitted during active listening.
  ///
  /// Emits [Hypothesis] objects as the engine processes audio.
  /// May be empty if [start] is never called or the engine produces
  /// no hypotheses for the audio.
  ///
  /// Closed when [stop] is called or the engine encounters a fatal error.
  Stream<Hypothesis> get hypothesesStream;
}

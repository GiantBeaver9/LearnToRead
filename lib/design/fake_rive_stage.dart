// FakeStoryStage — the [StoryStage] test double (PRD §8 Unit 1 accept #8).
//
// Records every triggered input in call order and reports whichever input
// was triggered most recently, so downstream unit/widget/integration tests
// (Units 5-9) can assert on stage behavior without any real Rive asset or
// runtime.
import 'package:learn_to_read/design/rive_stage.dart';

/// In-memory [StoryStage] double.
///
/// - Starts idle with no recorded triggers (matching the real stage's
///   pre-interaction state: the idle scene shown while reading).
/// - [trigger] appends to [triggeredInputs] (a full, order-preserving,
///   non-deduplicated history) and updates [activeState].
/// - Each instance owns independent state — two [FakeStoryStage]s (e.g. the
///   reading screen's stage vs. a celebration-sequence stage in the same
///   test) never cross-trigger each other.
class FakeStoryStage implements StoryStage {
  final List<StoryStageInput> _triggeredInputs = <StoryStageInput>[];

  StoryStageInput _activeState = StoryStageInput.idle;

  /// Every input triggered so far, in the order [trigger] was called.
  /// Repeated triggers of the same input each appear as their own entry.
  List<StoryStageInput> get triggeredInputs => List.unmodifiable(_triggeredInputs);

  @override
  StoryStageInput get activeState => _activeState;

  @override
  void trigger(StoryStageInput input) {
    _triggeredInputs.add(input);
    _activeState = input;
  }
}

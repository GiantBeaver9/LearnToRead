// The StoryStage contract (PRD §8 Unit 1 accept #8, verbatim from Unit 8's
// Rive integration contract, PRD §8 Unit 8): every story artboard exposes
// the same state-machine inputs, so app code (the reading screen, the
// celebration sequence) programs against [StoryStage] and never
// special-cases an individual story's Rive file.
//
// This file is the app-side statement of the animator's technical spec: a
// story pack fails validation (Unit 3's linter) if its Rive artboard is
// missing one of these inputs — that check happens at pack-build time, not
// here. This file only defines the Dart-side contract and a thin adapter
// over the `rive` runtime; no real Rive files exist in this container; the
// adapter's actual on-device rendering is an owner/device-verified concern.
// Tests exercise the contract through `FakeStoryStage`
// (lib/design/fake_rive_stage.dart), never through the real Rive runtime.
import 'package:rive/rive.dart' as rive;

/// The state-machine inputs every story artboard exposes (PRD §8 Unit 8,
/// pinned verbatim). Exactly these three exist — no story-specific inputs.
enum StoryStageInput {
  /// Idle scene, shown while the child is reading (same artboard, idle
  /// state machine) so the payoff transforms the scene already on screen.
  idle,

  /// Plays the story's completion animation depicting what the child just
  /// read, synchronized with celebration audio.
  celebrate,

  /// Fires the collectible-flight beat after the celebration animation.
  collect,
}

/// The app-facing contract for a story's animation stage.
///
/// Every story artboard — regardless of which illustrated scene it depicts —
/// is driven purely through [StoryStageInput]; nothing in app code branches
/// on which story is currently showing. Implementations report the input
/// that is currently active via [activeState] so UI (and tests) can assert
/// on stage state without depending on Rive internals.
abstract class StoryStage {
  /// The most recently triggered input; a freshly created stage reports
  /// [StoryStageInput.idle] before any trigger.
  StoryStageInput get activeState;

  /// Fires [input] on the underlying story-artboard state machine.
  void trigger(StoryStageInput input);
}

/// Thin adapter binding [StoryStage] to a real `rive` runtime
/// [rive.StateMachineController].
///
/// Every story's state machine must expose boolean/trigger inputs named
/// exactly `idle`, `celebrate`, and `collect` (matching [StoryStageInput.name]);
/// this adapter looks the input up by name and fires it, so it never needs
/// story-specific code. Constructed once a story's Rive artboard and state
/// machine are loaded; not exercised by unit tests in this container (no
/// licensed Rive assets are available here) — see [FakeStoryStage] for the
/// test double used throughout the rest of the test suite.
class RiveStoryStage implements StoryStage {
  RiveStoryStage(this._controller);

  final rive.StateMachineController _controller;
  StoryStageInput _activeState = StoryStageInput.idle;

  @override
  StoryStageInput get activeState => _activeState;

  @override
  void trigger(StoryStageInput input) {
    final smiInput = _controller.findInput<bool>(input.name);
    if (smiInput is rive.SMITrigger) {
      smiInput.fire();
    } else if (smiInput is rive.SMIBool) {
      smiInput.value = true;
    }
    _activeState = input;
  }
}

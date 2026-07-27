/// The optional "say it again — a little faster!" second pass (PRD §8
/// Unit 14: "after completion, a 'say it again — a little faster!' prompt
/// offers one replay round; purely optional, skippable, no extra reward";
/// ticket twister-flow).
///
/// Three properties are pinned, and this file is shaped so that two of them
/// hold *by construction* rather than by careful behavior:
///
/// - **Offered once.** [FasterPassPrompt] models one offer. Its status walks
///   `offered → skipped` or `offered → inProgress → completed` and then
///   never moves again; a resolved prompt cannot be re-offered, re-accepted,
///   or retroactively skipped. Offering another round means constructing
///   another prompt, which the flow deliberately never does.
/// - **After the primary attempt, never instead of it.** The constructor
///   throws a [StateError] unless `primaryController.isComplete` is already
///   true. The faster pass is a victory lap; it cannot become the way a node
///   gets finished.
/// - **No extra reward, structurally.** There is no `TwisterProgressDao`, no
///   `onAnalyticsEvent`, and no `CollectionDao` in this constructor. Whatever
///   `runReplay` does internally, the prompt itself has nowhere to record a
///   second completion, emit a second `twister_completed`, or grant anything.
///   It only sequences the replay and reports offer/skip/accept state.
/// - **Done-state independent.** [isNodeDone] mirrors the primary
///   controller's completion, which predates the prompt entirely. It is true
///   at offer time and stays true whether the prompt is accepted, skipped, or
///   simply left hanging.
library;

import 'package:learn_to_read/features/twister/twister_controller.dart';

/// Where a faster-pass offer currently stands.
enum FasterPassStatus {
  /// Offered and not yet answered. The state every prompt starts in.
  offered,

  /// [FasterPassPrompt.accept] was called and the replay is running.
  inProgress,

  /// The replay ran to the end.
  completed,

  /// The offer was declined. The replay never ran.
  skipped,
}

/// One optional "faster" replay offer, made after a twister node is already
/// done.
class FasterPassPrompt {
  /// Creates the offer over an already-completed [primaryController].
  ///
  /// Throws a [StateError] when `primaryController.isComplete` is false: the
  /// faster pass may only be offered *after* the primary attempt completes.
  ///
  /// [runReplay] performs one replay round and resolves when it is over.
  /// What it does is the caller's business — typically driving a fresh
  /// [TwisterController] for the same twister. The prompt neither inspects
  /// nor rewards its outcome.
  FasterPassPrompt({
    required TwisterController primaryController,
    required Future<void> Function() runReplay,
  })  : _primaryController = primaryController,
        _runReplay = runReplay {
    if (!primaryController.isComplete) {
      throw StateError(
        'FasterPassPrompt may only be offered after the primary twister '
        'attempt completes (PRD §8 Unit 14: the second pass is optional and '
        'follows completion; it can never substitute for it).',
      );
    }
  }

  final TwisterController _primaryController;
  final Future<void> Function() _runReplay;

  FasterPassStatus _status = FasterPassStatus.offered;

  /// Where this offer currently stands. Starts at [FasterPassStatus.offered].
  FasterPassStatus get status => _status;

  /// True while the offer is still open — i.e. immediately at construction,
  /// and until [skip] or [accept] resolves it.
  bool get isOffered => _status == FasterPassStatus.offered;

  /// Whether the twister node is done. Mirrors the primary controller for
  /// the prompt's whole lifetime, and is already true at offer time: the
  /// node's done state never depends on this pass being resolved at all.
  bool get isNodeDone => _primaryController.isComplete;

  /// Declines the offer. A no-op once the prompt has resolved (an accepted
  /// pass can never be re-labelled as skipped).
  void skip() {
    if (!isOffered) return;
    _status = FasterPassStatus.skipped;
  }

  /// Accepts the offer and runs exactly one replay round: the status moves
  /// to [FasterPassStatus.inProgress] synchronously, then to
  /// [FasterPassStatus.completed] when `runReplay` resolves.
  ///
  /// A no-op once the prompt has resolved — a second call never invokes
  /// `runReplay` again, which is what "offers ONE replay round" means.
  /// Nothing is granted or recorded either way.
  Future<void> accept() async {
    if (!isOffered) return;
    _status = FasterPassStatus.inProgress;
    await _runReplay();
    _status = FasterPassStatus.completed;
  }
}

/// Rive state-machine input validation (PRD §8 Unit 8 pinned: "every story
/// artboard exposes the same state machine inputs (idle, celebrate,
/// collect)"; §9 A-16; ticket pack-build-cli accept entry 7).
///
/// A-16 pins the mechanism: each `.riv` ships with a declared-inputs sidecar
/// JSON committed next to it, and **that sidecar is authoritative** for pack
/// validation. This file therefore validates JSON, never `.riv` binaries —
/// which is also what makes the check fully headless (no Rive runtime, no GPU,
/// no real art assets needed in CI). Runtime introspection of the actual
/// artboard may supplement this where available, but never replaces it: a
/// `.riv` whose sidecar is missing fails the build regardless of what the
/// file itself contains, because an undeclared contract is exactly the thing
/// A-16 exists to prevent.
///
/// Sidecar shape (pinned by the ticket's fixtures):
///
/// ```json
/// { "inputs": ["idle", "celebrate", "collect"] }
/// ```
///
/// The file name `rive_input_validator.dart` is retained per the ticket notes
/// even though the validation is sidecar-JSON-based.
library;

import 'package:learn_to_read/domain/models/content_models.dart';

/// The state-machine inputs every story artboard and every collectible
/// artboard must expose (PRD §8 Unit 8 pinned).
const List<String> kRequiredRiveStateMachineInputs = ['idle', 'celebrate', 'collect'];

/// One `.riv` whose declared inputs do not satisfy [kRequiredRiveStateMachineInputs]
/// (or which has no sidecar at all).
class RiveInputValidationError {
  const RiveInputValidationError({required this.riveRef, required this.message});

  /// The manifest ref of the offending `.riv`.
  final String riveRef;

  final String message;

  @override
  String toString() => 'RiveInputValidationError(riveRef: $riveRef, message: $message)';
}

/// The outcome of [validateRiveInputs] / [validateAllRiveInputs]: `isValid`
/// is true iff [errors] is empty.
class RiveInputValidationResult {
  const RiveInputValidationResult({required this.isValid, required this.errors});

  final bool isValid;
  final List<RiveInputValidationError> errors;

  static const RiveInputValidationResult _valid =
      RiveInputValidationResult(isValid: true, errors: []);
}

/// The sidecar path convention: `rive/foo.riv` declares its inputs in
/// `rive/foo.riv.inputs.json`, alongside the binary rather than in a parallel
/// tree, so art hand-offs move the pair together.
String riveSidecarRefFor(String riveRef) => '$riveRef.inputs.json';

/// Validates one `.riv`'s declared-inputs sidecar.
///
/// [sidecarJson] is the parsed sidecar; `null` means no sidecar file exists
/// for [riveRef] at all, which A-16 makes a failure in its own right.
///
/// The `inputs` list is checked as a *superset*: extra inputs (a bespoke
/// `sparkle` trigger, say) are fine, all three required inputs must be there.
/// A ref with several problems still yields one error, so error volume tracks
/// distinct broken assets rather than distinct broken fields.
RiveInputValidationResult validateRiveInputs({
  required String riveRef,
  required Map<String, dynamic>? sidecarJson,
}) {
  if (sidecarJson == null) {
    return RiveInputValidationResult(
      isValid: false,
      errors: List.unmodifiable([
        RiveInputValidationError(
          riveRef: riveRef,
          message: 'no declared-inputs sidecar found for "$riveRef" (expected '
              '"${riveSidecarRefFor(riveRef)}"); the sidecar is authoritative '
              'for pack validation (A-16)',
        ),
      ]),
    );
  }

  final rawInputs = sidecarJson['inputs'];
  if (rawInputs is! List) {
    return RiveInputValidationResult(
      isValid: false,
      errors: List.unmodifiable([
        RiveInputValidationError(
          riveRef: riveRef,
          message: 'declared-inputs sidecar for "$riveRef" has no "inputs" '
              'list (expected {"inputs": [...]})',
        ),
      ]),
    );
  }

  final declared = rawInputs.whereType<String>().toSet();
  final missing = [
    for (final required in kRequiredRiveStateMachineInputs)
      if (!declared.contains(required)) required,
  ];
  if (missing.isEmpty) return RiveInputValidationResult._valid;

  return RiveInputValidationResult(
    isValid: false,
    errors: List.unmodifiable([
      RiveInputValidationError(
        riveRef: riveRef,
        message: 'declared-inputs sidecar for "$riveRef" is missing required '
            'state-machine input(s) ${missing.join(', ')}; every artboard must '
            'expose ${kRequiredRiveStateMachineInputs.join('/')}',
      ),
    ]),
  );
}

/// Validates every *distinct* riveRef referenced by [stories]
/// (`Story.riveAnimationRef`) and [collectibles] (`Collectible.riveRef`)
/// against [sidecarJsonByRiveRef]; a riveRef absent from that map is treated
/// as missing-sidecar.
///
/// Validation is per distinct asset, not per reference: artwork shared by a
/// story and its collectible is checked once and, when broken, reports once.
RiveInputValidationResult validateAllRiveInputs({
  required List<Story> stories,
  required List<Collectible> collectibles,
  required Map<String, Map<String, dynamic>> sidecarJsonByRiveRef,
}) {
  final riveRefs = <String>{
    for (final story in stories) story.riveAnimationRef,
    for (final collectible in collectibles) collectible.riveRef,
  };

  final errors = <RiveInputValidationError>[];
  for (final riveRef in riveRefs) {
    errors.addAll(
      validateRiveInputs(riveRef: riveRef, sidecarJson: sidecarJsonByRiveRef[riveRef]).errors,
    );
  }

  return RiveInputValidationResult(isValid: errors.isEmpty, errors: List.unmodifiable(errors));
}

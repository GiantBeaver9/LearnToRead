// Pins the API of lib/pipeline/rive_input_validator.dart (PRD §8 Unit 8
// pinned design: "every story artboard exposes the same state machine
// inputs (idle, celebrate, collect)"; §9 A-16: "Pack-build Rive state-machine
// validation uses a declared-inputs sidecar JSON committed alongside each
// .riv (authoritative for validation); runtime introspection may supplement
// where available"; ticket pack-build-cli accept entry 7). This suite is
// authored before the implementation exists, so it is EXPECTED to fail to
// compile until rive_input_validator.dart is written with exactly the shapes
// exercised below. Filename retained as `rive_input_validator.dart` per the
// ticket notes even though A-16 validation is sidecar-JSON-based, not a
// runtime Rive introspection.
//
// Pinned API surface this suite requires:
//
//   const List<String> kRequiredRiveStateMachineInputs; // ['idle', 'celebrate', 'collect']
//
//   class RiveInputValidationError {
//     final String riveRef;
//     final String message;
//   }
//   class RiveInputValidationResult {
//     final bool isValid;
//     final List<RiveInputValidationError> errors;
//   }
//
//   /// Validates one .riv's declared-inputs sidecar. `sidecarJson` is the
//   /// parsed JSON of the sidecar file (shape: {"inputs": [String, ...]});
//   /// `null` means no sidecar file exists for `riveRef` at all (A-16:
//   /// missing sidecar fails validation, regardless of what runtime
//   /// introspection of the .riv might otherwise show -- sidecar is
//   /// authoritative).
//   RiveInputValidationResult validateRiveInputs({
//     required String riveRef,
//     required Map<String, dynamic>? sidecarJson,
//   });
//
//   /// Validates every distinct riveRef referenced by `stories`
//   /// (Story.riveAnimationRef) and `collectibles` (Collectible.riveRef)
//   /// against `sidecarJsonByRiveRef` (a riveRef -> parsed sidecar JSON map;
//   /// a riveRef absent from the map is treated as missing-sidecar).
//   RiveInputValidationResult validateAllRiveInputs({
//     required List<Story> stories,
//     required List<Collectible> collectibles,
//     required Map<String, Map<String, dynamic>> sidecarJsonByRiveRef,
//   });
//
// Contract this suite locks in (builder-mechanical):
//  - A sidecar's "inputs" list is a superset check: extra, non-required
//    inputs are allowed; only the three required inputs must all be present.
//  - Each missing required input on an otherwise-present sidecar contributes
//    to exactly one error for that riveRef (this suite does not require one
//    error per missing input -- it asserts on riveRef identity and message
//    content only, since exact one-vs-many-errors-per-ref granularity is a
//    builder-mechanical choice this suite leaves open... except: a distinct
//    riveRef used by MULTIPLE entities (e.g. a story and a collectible
//    sharing artwork) is validated once, producing exactly one error per
//    distinct invalid riveRef -- not one per referencing entity. This IS
//    pinned, to keep validateAllRiveInputs's error volume proportional to
//    distinct assets, not distinct references.

import 'package:flutter_test/flutter_test.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/pipeline/rive_input_validator.dart';

Story _storyWithRive(String id, String riveRef) => Story(
      id: id,
      levelId: 'level.1',
      title: 'Story $id',
      pages: const [],
      riveAnimationRef: riveRef,
      celebrationAudioRef: 'audio/celebration/$id.wav',
      collectibleRef: 'collectible.$id',
      skillsExercised: const [],
      packId: 'pack.fixture',
      contentVersion: '1',
    );

Collectible _collectibleWithRive(String id, String riveRef) => Collectible(
      id: id,
      storyId: 'story.$id',
      riveRef: riveRef,
      sceneSlot: 'shelf.1',
    );

void main() {
  group('kRequiredRiveStateMachineInputs (shape sanity)', () {
    test('is exactly idle/celebrate/collect', () {
      expect(kRequiredRiveStateMachineInputs.toSet(), {'idle', 'celebrate', 'collect'});
    });
  });

  group('validateRiveInputs (positive, accept 7: valid sidecar)', () {
    test('a sidecar declaring exactly idle/celebrate/collect passes', () {
      final result = validateRiveInputs(
        riveRef: 'rive/story.1.riv',
        sidecarJson: const {
          'inputs': ['idle', 'celebrate', 'collect'],
        },
      );
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('a sidecar declaring the required inputs plus extras still passes', () {
      final result = validateRiveInputs(
        riveRef: 'rive/story.1.riv',
        sidecarJson: const {
          'inputs': ['idle', 'celebrate', 'collect', 'sparkle', 'wiggle'],
        },
      );
      expect(result.isValid, isTrue);
    });
  });

  group('validateRiveInputs (negative, accept 7: missing input)', () {
    test('a sidecar missing "collect" fails, naming the riveRef', () {
      final result = validateRiveInputs(
        riveRef: 'rive/story.1.riv',
        sidecarJson: const {
          'inputs': ['idle', 'celebrate'],
        },
      );
      expect(result.isValid, isFalse);
      expect(result.errors, isNotEmpty);
      expect(result.errors.every((e) => e.riveRef == 'rive/story.1.riv'), isTrue);
      expect(result.errors.every((e) => e.message.isNotEmpty), isTrue);
    });

    test('a sidecar declaring zero inputs fails', () {
      final result = validateRiveInputs(
        riveRef: 'rive/story.1.riv',
        sidecarJson: const {'inputs': <String>[]},
      );
      expect(result.isValid, isFalse);
    });
  });

  group('validateRiveInputs (negative, accept 7: missing sidecar, A-16 authoritative)', () {
    test('a null sidecarJson (no sidecar file) fails, naming the riveRef', () {
      final result = validateRiveInputs(riveRef: 'rive/story.2.riv', sidecarJson: null);
      expect(result.isValid, isFalse);
      expect(result.errors.single.riveRef, 'rive/story.2.riv');
      expect(result.errors.single.message, isNotEmpty);
    });
  });

  group('validateAllRiveInputs (positive, accept 7)', () {
    test('every distinct riveRef across stories and collectibles has a valid sidecar', () {
      final stories = [_storyWithRive('s1', 'rive/s1.riv'), _storyWithRive('s2', 'rive/s2.riv')];
      final collectibles = [_collectibleWithRive('c1', 'rive/collectibles/c1.riv')];
      final sidecars = {
        'rive/s1.riv': const {
          'inputs': ['idle', 'celebrate', 'collect'],
        },
        'rive/s2.riv': const {
          'inputs': ['idle', 'celebrate', 'collect'],
        },
        'rive/collectibles/c1.riv': const {
          'inputs': ['idle', 'celebrate', 'collect'],
        },
      };

      final result = validateAllRiveInputs(stories: stories, collectibles: collectibles, sidecarJsonByRiveRef: sidecars);
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });
  });

  group('validateAllRiveInputs (negative, accept 7)', () {
    test('a story riveRef with no sidecar entry fails, naming that riveRef', () {
      final stories = [_storyWithRive('s1', 'rive/s1.riv')];
      final result = validateAllRiveInputs(
        stories: stories,
        collectibles: const [],
        sidecarJsonByRiveRef: const {},
      );
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.riveRef == 'rive/s1.riv'), isTrue);
    });

    test('a collectible riveRef whose sidecar lacks a required input fails, naming that riveRef', () {
      final collectibles = [_collectibleWithRive('c1', 'rive/collectibles/c1.riv')];
      final sidecars = {
        'rive/collectibles/c1.riv': const {
          'inputs': ['idle', 'celebrate'], // missing 'collect'
        },
      };
      final result = validateAllRiveInputs(stories: const [], collectibles: collectibles, sidecarJsonByRiveRef: sidecars);
      expect(result.isValid, isFalse);
      expect(result.errors.any((e) => e.riveRef == 'rive/collectibles/c1.riv'), isTrue);
    });
  });

  group('validateAllRiveInputs (edge: shared riveRef deduplicates, accept 7)', () {
    test('a riveRef shared by two stories, when invalid, produces exactly one error for that ref', () {
      final stories = [_storyWithRive('s1', 'rive/shared.riv'), _storyWithRive('s2', 'rive/shared.riv')];
      final result = validateAllRiveInputs(
        stories: stories,
        collectibles: const [],
        sidecarJsonByRiveRef: const {},
      );
      expect(result.errors.where((e) => e.riveRef == 'rive/shared.riv'), hasLength(1));
    });

    test('a riveRef shared by a story and a collectible, when valid, is validated once and passes', () {
      final stories = [_storyWithRive('s1', 'rive/shared.riv')];
      final collectibles = [_collectibleWithRive('c1', 'rive/shared.riv')];
      final sidecars = {
        'rive/shared.riv': const {
          'inputs': ['idle', 'celebrate', 'collect'],
        },
      };
      final result = validateAllRiveInputs(stories: stories, collectibles: collectibles, sidecarJsonByRiveRef: sidecars);
      expect(result.isValid, isTrue);
    });
  });

  group('validateAllRiveInputs (edge: empty input)', () {
    test('no stories and no collectibles produces a valid, empty result', () {
      final result = validateAllRiveInputs(stories: const [], collectibles: const [], sidecarJsonByRiveRef: const {});
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });
  });
}

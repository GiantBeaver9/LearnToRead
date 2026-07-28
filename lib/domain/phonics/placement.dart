/// Starting-level placement (PRD §8 Unit 2 pinned design: "Profile start
/// level from age band: 5-6 -> level 1; 7-8 -> first multiSentence level;
/// 9-10 -> first paragraph level. Parent can override in parent corner.
/// (Placement test is v2 -- Non-scope.)").
///
/// Pure Dart, no I/O: [placeStartingLevel] is a single pure function over a
/// [PhonicsContent] (already loaded by `scope_sequence_loader.dart`) and an
/// [AgeBand], with an optional parent-override input.
library;

import '../models/content_models.dart';
import '../models/user_models.dart';
import 'scope_sequence_loader.dart';

/// Picks the level id a newly created (or re-placed) [Profile] should start
/// at.
///
/// `parentOverrideLevelId`, when non-null, wins outright over `ageBand`: if
/// it matches some level's id in `content.levels`, that id is returned
/// verbatim; if it matches no level (including the empty string), this
/// throws [ArgumentError].
///
/// Otherwise, placement is by `ageBand`, over `content.levels` in ascending
/// ordinal order (as guaranteed by [loadPhonicsContent]):
///  - [AgeBand.fiveToSix] -> `content.levels.first.id` (lowest ordinal,
///    "level 1").
///  - [AgeBand.sevenToEight] -> the id of the first level with
///    `format == LevelFormat.multiSentence`; throws [StateError] if no such
///    level exists.
///  - [AgeBand.nineToTen] -> the id of the first level with
///    `format == LevelFormat.paragraph`; throws [StateError] if no such
///    level exists.
///
/// Throws [StateError] if `content.levels` is empty, regardless of
/// `ageBand`/override.
String placeStartingLevel({
  required AgeBand ageBand,
  required PhonicsContent content,
  String? parentOverrideLevelId,
}) {
  if (parentOverrideLevelId != null) {
    final matches = content.levels.where((l) => l.id == parentOverrideLevelId);
    if (matches.isEmpty) {
      throw ArgumentError.value(
        parentOverrideLevelId,
        'parentOverrideLevelId',
        'does not match any level id in content.levels',
      );
    }
    return parentOverrideLevelId;
  }

  if (content.levels.isEmpty) {
    throw StateError(
      'content.levels is empty; there is no level to place a profile at',
    );
  }

  switch (ageBand) {
    case AgeBand.fiveToSix:
      return content.levels.first.id;
    case AgeBand.sevenToEight:
      return content.levels
          .firstWhere(
            (l) => l.format == LevelFormat.multiSentence,
            orElse: () => throw StateError(
              'no multiSentence-format level exists in content.levels for '
              '7-8 placement',
            ),
          )
          .id;
    case AgeBand.nineToTen:
      return content.levels
          .firstWhere(
            (l) => l.format == LevelFormat.paragraph,
            orElse: () => throw StateError(
              'no paragraph-format level exists in content.levels for 9-10 '
              'placement',
            ),
          )
          .id;
  }
}

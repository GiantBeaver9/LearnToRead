/// Cumulative grapheme set (PRD §5 `PhonicsSkill.introducesGraphemes`: "the
/// decodability linter's cumulative grapheme set at level N is the union
/// over all skills of levels <= N -- one shared type, one schema"; §8 Unit 3
/// pinned design).
///
/// Pure Dart, no I/O: consumes only `Level`/`PhonicsSkill` from
/// `lib/domain/models/content_models.dart`, the one shared domain-models
/// schema.
library;

import 'package:learn_to_read/domain/models/content_models.dart';

/// Returns the cumulative grapheme set at the level identified by [levelId]:
/// the union, as a `Set<String>`, of `skill.introducesGraphemes` over every
/// skill (`level.newSkills`) of every level in [levels] whose `ordinal` is
/// less than or equal to the ordinal of the level resolved by [levelId]
/// (including that level itself).
///
/// Grapheme units are opaque strings -- a digraph (`"sh"`) or a silent-e
/// pattern (`"a_e"`) is one element of the set, never decomposed into its
/// component letters.
///
/// [levelId] is resolved against [levels] by `Level.id`; the comparison
/// bound is that resolved level's `ordinal` field, not its position in
/// [levels]. The result does not depend on the order [levels] are passed in.
///
/// Throws [ArgumentError] when no level in [levels] has `id == levelId`
/// (including when [levels] is empty).
Set<String> cumulativeGraphemeSet({
  required List<Level> levels,
  required String levelId,
}) {
  Level? target;
  for (final level in levels) {
    if (level.id == levelId) {
      target = level;
      break;
    }
  }
  if (target == null) {
    throw ArgumentError.value(
      levelId,
      'levelId',
      'does not match any Level.id in `levels`',
    );
  }

  final graphemes = <String>{};
  for (final level in levels) {
    if (level.ordinal > target.ordinal) continue;
    for (final skill in level.newSkills) {
      graphemes.addAll(skill.introducesGraphemes);
    }
  }
  return graphemes;
}

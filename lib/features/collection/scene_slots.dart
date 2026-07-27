/// Addressing scheme + layout math for the collection scene's `sceneSlot`
/// grid (PRD §5 Collectible.sceneSlot; §8 Unit 9; ticket
/// progress-map-collection accept entries 4, 7).
///
/// PRD §5 leaves the exact `sceneSlot` string format to content authoring;
/// this ticket pins it as `"row:col"`, both non-negative integers. The
/// canvas always grows in the row (vertical) direction to fit every authored
/// slot -- it is never a fixed cap, per PRD §8 Unit 9's "the scene design
/// must define how it extends for future packs" (pinned here as
/// scrollable/expanding, per the ticket's pinned_design).
library;

import 'package:flutter/widgets.dart';

/// Pure layout math for the `"row:col"` `sceneSlot` addressing scheme.
abstract final class SceneSlotLayout {
  /// Parses a `"row:col"` [sceneSlot] string. Throws [FormatException] for
  /// any other shape (missing separator, non-numeric, or a negative
  /// coordinate).
  static ({int row, int col}) parseSlot(String sceneSlot) {
    final parts = sceneSlot.split(':');
    if (parts.length != 2) {
      throw FormatException(
        'Malformed sceneSlot "$sceneSlot": expected "row:col"',
      );
    }
    final row = int.tryParse(parts[0]);
    final col = int.tryParse(parts[1]);
    if (row == null || col == null || row < 0 || col < 0) {
      throw FormatException(
        'Malformed sceneSlot "$sceneSlot": row and col must be non-negative integers',
      );
    }
    return (row: row, col: col);
  }

  /// The pixel offset of [sceneSlot] within the scene canvas, given a
  /// uniform cell size.
  static Offset offsetForSlot(
    String sceneSlot, {
    required double cellWidth,
    required double cellHeight,
  }) {
    final slot = parseSlot(sceneSlot);
    return Offset(slot.col * cellWidth, slot.row * cellHeight);
  }

  /// The canvas extent needed to fit every slot in [sceneSlots] without
  /// clipping. Grows with the highest row/col among the given slots -- an
  /// empty [sceneSlots] yields a zero-area canvas.
  static Size canvasSizeFor(
    Iterable<String> sceneSlots, {
    required double cellWidth,
    required double cellHeight,
  }) {
    var maxRow = -1;
    var maxCol = -1;
    for (final sceneSlot in sceneSlots) {
      final slot = parseSlot(sceneSlot);
      if (slot.row > maxRow) maxRow = slot.row;
      if (slot.col > maxCol) maxCol = slot.col;
    }
    if (maxRow < 0) return Size.zero;
    return Size((maxCol + 1) * cellWidth, (maxRow + 1) * cellHeight);
  }
}

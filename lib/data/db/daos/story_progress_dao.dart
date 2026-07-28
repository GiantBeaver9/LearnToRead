/// DAO for the device-local `StoryProgress` model (PRD §5 StoryProgress;
/// §8 Unit 2 status lifecycle; §8 Unit 9 "map reflects StoryProgress
/// exactly"; ticket local-storage accept entry 5).
library;

import 'package:drift/drift.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/data/db/tables.dart';
import 'package:learn_to_read/domain/models/user_models.dart';

part 'story_progress_dao.g.dart';

@DriftAccessor(tables: [StoryProgressEntries])
class StoryProgressDao extends DatabaseAccessor<AppDatabase>
    with _$StoryProgressDaoMixin {
  StoryProgressDao(super.db);

  /// Full write of [progress], keyed by `(profileId, storyId)`. Used to set
  /// up arbitrary fixture states, including status transitions
  /// (locked/available/completed), without duplicating the row.
  Future<void> upsertProgress(StoryProgress progress) async {
    await into(storyProgressEntries).insertOnConflictUpdate(
      StoryProgressEntriesCompanion.insert(
        profileId: progress.profileId,
        storyId: progress.storyId,
        status: progress.status,
        completedAt: Value(progress.completedAt),
        timesRead: progress.timesRead,
      ),
    );
  }

  /// Records a story read: sets `status = completed` and increments
  /// `timesRead`. `completedAt` is set only the first time the story is
  /// completed (a pre-existing non-null `completedAt` is preserved on
  /// re-reads); defaults to `DateTime.now()` when omitted.
  Future<void> recordCompletion({
    required String profileId,
    required String storyId,
    DateTime? completedAt,
  }) async {
    final effectiveCompletedAt = completedAt ?? DateTime.now();
    await transaction(() async {
      final existing = await _getRow(profileId, storyId);
      if (existing == null) {
        await into(storyProgressEntries).insert(
          StoryProgressEntriesCompanion.insert(
            profileId: profileId,
            storyId: storyId,
            status: StoryStatus.completed,
            completedAt: Value(effectiveCompletedAt),
            timesRead: 1,
          ),
        );
      } else {
        await (update(storyProgressEntries)..where(
          (t) => t.profileId.equals(profileId) & t.storyId.equals(storyId),
        )).write(
          StoryProgressEntriesCompanion(
            status: const Value(StoryStatus.completed),
            completedAt: Value(existing.completedAt ?? effectiveCompletedAt),
            timesRead: Value(existing.timesRead + 1),
          ),
        );
      }
    });
  }

  /// Returns the progress row for `(profileId, storyId)`, or null if the
  /// story has never been touched for this profile.
  Future<StoryProgress?> getProgress({
    required String profileId,
    required String storyId,
  }) async {
    final row = await _getRow(profileId, storyId);
    return row == null ? null : _toDomain(row);
  }

  /// Returns every story progress row for [profileId].
  Future<List<StoryProgress>> allForProfile(String profileId) async {
    final rows = await (select(
      storyProgressEntries,
    )..where((t) => t.profileId.equals(profileId))).get();
    return rows.map(_toDomain).toList();
  }

  /// Returns the number of story progress rows stored for [profileId].
  Future<int> rowCountForProfile(String profileId) async {
    final rows = await (select(
      storyProgressEntries,
    )..where((t) => t.profileId.equals(profileId))).get();
    return rows.length;
  }

  Future<StoryProgressRow?> _getRow(String profileId, String storyId) {
    return (select(storyProgressEntries)..where(
      (t) => t.profileId.equals(profileId) & t.storyId.equals(storyId),
    )).getSingleOrNull();
  }

  StoryProgress _toDomain(StoryProgressRow row) => StoryProgress(
    profileId: row.profileId,
    storyId: row.storyId,
    status: row.status,
    completedAt: row.completedAt,
    timesRead: row.timesRead,
  );
}

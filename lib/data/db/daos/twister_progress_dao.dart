/// DAO for the device-local `TwisterProgress` model (PRD §5 TwisterProgress;
/// §8 Unit 14 tongue-twister boosters; ticket local-storage accept entry
/// "TwisterProgress increments").
library;

import 'package:drift/drift.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/data/db/tables.dart';
import 'package:learn_to_read/domain/models/user_models.dart';

part 'twister_progress_dao.g.dart';

@DriftAccessor(tables: [TwisterProgressEntries])
class TwisterProgressDao extends DatabaseAccessor<AppDatabase>
    with _$TwisterProgressDaoMixin {
  TwisterProgressDao(super.db);

  /// Creates the row on first completion (`timesCompleted = 1`) or
  /// increments `timesCompleted` on an existing row; never duplicates rows
  /// for the same `(profileId, twisterId)`.
  Future<void> recordCompletion({
    required String profileId,
    required String twisterId,
  }) async {
    await transaction(() async {
      final existing = await _getRow(profileId, twisterId);
      if (existing == null) {
        await into(twisterProgressEntries).insert(
          TwisterProgressEntriesCompanion.insert(
            profileId: profileId,
            twisterId: twisterId,
            timesCompleted: 1,
          ),
        );
      } else {
        await (update(twisterProgressEntries)..where(
          (t) =>
              t.profileId.equals(profileId) & t.twisterId.equals(twisterId),
        )).write(
          TwisterProgressEntriesCompanion(
            timesCompleted: Value(existing.timesCompleted + 1),
          ),
        );
      }
    });
  }

  /// Returns the progress row for `(profileId, twisterId)`, or null if the
  /// twister has never been completed.
  Future<TwisterProgress?> getProgress({
    required String profileId,
    required String twisterId,
  }) async {
    final row = await _getRow(profileId, twisterId);
    return row == null ? null : _toDomain(row);
  }

  /// Returns every twister progress row for [profileId].
  Future<List<TwisterProgress>> allForProfile(String profileId) async {
    final rows = await (select(
      twisterProgressEntries,
    )..where((t) => t.profileId.equals(profileId))).get();
    return rows.map(_toDomain).toList();
  }

  /// Returns the number of twister progress rows stored for [profileId].
  Future<int> rowCountForProfile(String profileId) async {
    final rows = await (select(
      twisterProgressEntries,
    )..where((t) => t.profileId.equals(profileId))).get();
    return rows.length;
  }

  Future<TwisterProgressRow?> _getRow(String profileId, String twisterId) {
    return (select(twisterProgressEntries)..where(
      (t) => t.profileId.equals(profileId) & t.twisterId.equals(twisterId),
    )).getSingleOrNull();
  }

  TwisterProgress _toDomain(TwisterProgressRow row) => TwisterProgress(
    profileId: row.profileId,
    twisterId: row.twisterId,
    timesCompleted: row.timesCompleted,
  );
}

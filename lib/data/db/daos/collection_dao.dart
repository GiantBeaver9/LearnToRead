/// DAO for the device-local `CollectionState` model (PRD §5 CollectionState;
/// §8 Unit 8 "collectible granted only on first completion"; §8 Unit 9
/// collection scene; ticket local-storage accept entry "CollectionState
/// uniqueness").
library;

import 'package:drift/drift.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/data/db/tables.dart';
import 'package:learn_to_read/domain/models/user_models.dart';

part 'collection_dao.g.dart';

@DriftAccessor(tables: [CollectionEntries])
class CollectionDao extends DatabaseAccessor<AppDatabase>
    with _$CollectionDaoMixin {
  CollectionDao(super.db);

  /// Grants collectible [collectibleId] to [profileId]. Idempotent per
  /// `(profileId, collectibleId)` -- the table's primary key makes granting
  /// the same collectible twice store exactly one row, which is what makes
  /// Unit 8's "collectible granted only on first completion" rule safe even
  /// if the caller double-invokes this.
  Future<void> grantCollectible({
    required String profileId,
    required String collectibleId,
  }) async {
    await into(collectionEntries).insertOnConflictUpdate(
      CollectionEntriesCompanion.insert(
        profileId: profileId,
        collectibleId: collectibleId,
      ),
    );
  }

  /// Returns [profileId]'s collection state. Never null: a profile with
  /// nothing earned yet gets an empty `earnedCollectibles` list.
  Future<CollectionState> getCollectionState(String profileId) async {
    final rows = await (select(
      collectionEntries,
    )..where((t) => t.profileId.equals(profileId))).get();
    return CollectionState(
      profileId: profileId,
      earnedCollectibles: rows.map((r) => r.collectibleId).toList(),
    );
  }

  /// Returns the number of collectibles earned by [profileId].
  Future<int> rowCountForProfile(String profileId) async {
    final rows = await (select(
      collectionEntries,
    )..where((t) => t.profileId.equals(profileId))).get();
    return rows.length;
  }
}

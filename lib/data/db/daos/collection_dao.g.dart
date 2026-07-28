// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collection_dao.dart';

// ignore_for_file: type=lint
mixin _$CollectionDaoMixin on DatabaseAccessor<AppDatabase> {
  $CollectionEntriesTable get collectionEntries =>
      attachedDatabase.collectionEntries;
  CollectionDaoManager get managers => CollectionDaoManager(this);
}

class CollectionDaoManager {
  final _$CollectionDaoMixin _db;
  CollectionDaoManager(this._db);
  $$CollectionEntriesTableTableManager get collectionEntries =>
      $$CollectionEntriesTableTableManager(
        _db.attachedDatabase,
        _db.collectionEntries,
      );
}

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'twister_progress_dao.dart';

// ignore_for_file: type=lint
mixin _$TwisterProgressDaoMixin on DatabaseAccessor<AppDatabase> {
  $TwisterProgressEntriesTable get twisterProgressEntries =>
      attachedDatabase.twisterProgressEntries;
  TwisterProgressDaoManager get managers => TwisterProgressDaoManager(this);
}

class TwisterProgressDaoManager {
  final _$TwisterProgressDaoMixin _db;
  TwisterProgressDaoManager(this._db);
  $$TwisterProgressEntriesTableTableManager get twisterProgressEntries =>
      $$TwisterProgressEntriesTableTableManager(
        _db.attachedDatabase,
        _db.twisterProgressEntries,
      );
}

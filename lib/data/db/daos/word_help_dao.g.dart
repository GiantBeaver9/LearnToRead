// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'word_help_dao.dart';

// ignore_for_file: type=lint
mixin _$WordHelpDaoMixin on DatabaseAccessor<AppDatabase> {
  $WordHelpRecordsTable get wordHelpRecords => attachedDatabase.wordHelpRecords;
  WordHelpDaoManager get managers => WordHelpDaoManager(this);
}

class WordHelpDaoManager {
  final _$WordHelpDaoMixin _db;
  WordHelpDaoManager(this._db);
  $$WordHelpRecordsTableTableManager get wordHelpRecords =>
      $$WordHelpRecordsTableTableManager(
        _db.attachedDatabase,
        _db.wordHelpRecords,
      );
}

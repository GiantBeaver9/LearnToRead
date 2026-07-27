// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'profiles_dao.dart';

// ignore_for_file: type=lint
mixin _$ProfilesDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProfilesTable get profiles => attachedDatabase.profiles;
  $StoryProgressEntriesTable get storyProgressEntries =>
      attachedDatabase.storyProgressEntries;
  $WordHelpRecordsTable get wordHelpRecords => attachedDatabase.wordHelpRecords;
  $TwisterProgressEntriesTable get twisterProgressEntries =>
      attachedDatabase.twisterProgressEntries;
  $CollectionEntriesTable get collectionEntries =>
      attachedDatabase.collectionEntries;
  ProfilesDaoManager get managers => ProfilesDaoManager(this);
}

class ProfilesDaoManager {
  final _$ProfilesDaoMixin _db;
  ProfilesDaoManager(this._db);
  $$ProfilesTableTableManager get profiles =>
      $$ProfilesTableTableManager(_db.attachedDatabase, _db.profiles);
  $$StoryProgressEntriesTableTableManager get storyProgressEntries =>
      $$StoryProgressEntriesTableTableManager(
        _db.attachedDatabase,
        _db.storyProgressEntries,
      );
  $$WordHelpRecordsTableTableManager get wordHelpRecords =>
      $$WordHelpRecordsTableTableManager(
        _db.attachedDatabase,
        _db.wordHelpRecords,
      );
  $$TwisterProgressEntriesTableTableManager get twisterProgressEntries =>
      $$TwisterProgressEntriesTableTableManager(
        _db.attachedDatabase,
        _db.twisterProgressEntries,
      );
  $$CollectionEntriesTableTableManager get collectionEntries =>
      $$CollectionEntriesTableTableManager(
        _db.attachedDatabase,
        _db.collectionEntries,
      );
}

// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'story_progress_dao.dart';

// ignore_for_file: type=lint
mixin _$StoryProgressDaoMixin on DatabaseAccessor<AppDatabase> {
  $StoryProgressEntriesTable get storyProgressEntries =>
      attachedDatabase.storyProgressEntries;
  StoryProgressDaoManager get managers => StoryProgressDaoManager(this);
}

class StoryProgressDaoManager {
  final _$StoryProgressDaoMixin _db;
  StoryProgressDaoManager(this._db);
  $$StoryProgressEntriesTableTableManager get storyProgressEntries =>
      $$StoryProgressEntriesTableTableManager(
        _db.attachedDatabase,
        _db.storyProgressEntries,
      );
}

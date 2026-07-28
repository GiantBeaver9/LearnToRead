// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'flashcards_dao.dart';

// ignore_for_file: type=lint
mixin _$FlashcardsDaoMixin on DatabaseAccessor<AppDatabase> {
  $FlashcardProgressRowsTable get flashcardProgressRows =>
      attachedDatabase.flashcardProgressRows;
  FlashcardsDaoManager get managers => FlashcardsDaoManager(this);
}

class FlashcardsDaoManager {
  final _$FlashcardsDaoMixin _db;
  FlashcardsDaoManager(this._db);
  $$FlashcardProgressRowsTableTableManager get flashcardProgressRows =>
      $$FlashcardProgressRowsTableTableManager(
        _db.attachedDatabase,
        _db.flashcardProgressRows,
      );
}

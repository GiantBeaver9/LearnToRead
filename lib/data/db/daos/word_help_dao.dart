/// DAO for the device-local `WordHelpRecord` model (PRD §5 WordHelpRecord;
/// §4.3 learning signal; §8 Unit 6 tiered help; ticket local-storage accept
/// entry 3).
library;

import 'package:drift/drift.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/data/db/tables.dart';
import 'package:learn_to_read/domain/models/user_models.dart';

part 'word_help_dao.g.dart';

@DriftAccessor(tables: [WordHelpRecords])
class WordHelpDao extends DatabaseAccessor<AppDatabase>
    with _$WordHelpDaoMixin {
  WordHelpDao(super.db);

  /// Called for every word read, helped or unaided. Creates the row on
  /// first sight (`encounterCount = 1, helpCount = 0, lastHelpLevel =
  /// HelpLevel.none`) or increments `encounterCount` on an existing row.
  /// Never touches `helpCount` or `lastHelpLevel`.
  Future<void> recordEncounter({
    required String profileId,
    required String wordText,
  }) async {
    await transaction(() async {
      final existing = await _getRow(profileId, wordText);
      if (existing == null) {
        await into(wordHelpRecords).insert(
          WordHelpRecordsCompanion.insert(
            profileId: profileId,
            wordText: wordText,
            encounterCount: 1,
            helpCount: 0,
            lastHelpLevel: HelpLevel.none,
          ),
        );
      } else {
        await _writeRecord(
          profileId,
          wordText,
          WordHelpRecordsCompanion(
            encounterCount: Value(existing.encounterCount + 1),
          ),
        );
      }
    });
  }

  /// Called in addition to [recordEncounter] when a word needed help.
  /// Increments `helpCount` and sets `lastHelpLevel` to [tier]; never
  /// touches `encounterCount`. If called with no prior [recordEncounter]
  /// for this word, still stores a valid record (`encounterCount = 0`).
  Future<void> recordHelp({
    required String profileId,
    required String wordText,
    required HelpLevel tier,
  }) async {
    await transaction(() async {
      final existing = await _getRow(profileId, wordText);
      if (existing == null) {
        await into(wordHelpRecords).insert(
          WordHelpRecordsCompanion.insert(
            profileId: profileId,
            wordText: wordText,
            encounterCount: 0,
            helpCount: 1,
            lastHelpLevel: tier,
          ),
        );
      } else {
        await _writeRecord(
          profileId,
          wordText,
          WordHelpRecordsCompanion(
            helpCount: Value(existing.helpCount + 1),
            lastHelpLevel: Value(tier),
          ),
        );
      }
    });
  }

  /// Returns the help record for `(profileId, wordText)`, or null if the
  /// word has never been encountered.
  Future<WordHelpRecord?> getRecord({
    required String profileId,
    required String wordText,
  }) async {
    final row = await _getRow(profileId, wordText);
    return row == null ? null : _toDomain(row);
  }

  /// Returns every word-help record for [profileId].
  Future<List<WordHelpRecord>> allForProfile(String profileId) async {
    final rows = await (select(
      wordHelpRecords,
    )..where((t) => t.profileId.equals(profileId))).get();
    return rows.map(_toDomain).toList();
  }

  /// Returns the number of word-help rows stored for [profileId].
  Future<int> rowCountForProfile(String profileId) async {
    final rows = await (select(
      wordHelpRecords,
    )..where((t) => t.profileId.equals(profileId))).get();
    return rows.length;
  }

  Future<WordHelpRow?> _getRow(String profileId, String wordText) {
    return (select(wordHelpRecords)..where(
      (t) => t.profileId.equals(profileId) & t.wordText.equals(wordText),
    )).getSingleOrNull();
  }

  Future<void> _writeRecord(
    String profileId,
    String wordText,
    WordHelpRecordsCompanion companion,
  ) {
    return (update(wordHelpRecords)..where(
      (t) => t.profileId.equals(profileId) & t.wordText.equals(wordText),
    )).write(companion);
  }

  WordHelpRecord _toDomain(WordHelpRow row) => WordHelpRecord(
    profileId: row.profileId,
    wordText: row.wordText,
    encounterCount: row.encounterCount,
    helpCount: row.helpCount,
    lastHelpLevel: row.lastHelpLevel,
  );
}

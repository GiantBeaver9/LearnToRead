/// DAO for the device-local `Profile` model (PRD §5 Profile; §8 Unit 10 "up
/// to 4 local profiles" + irreversible per-profile erasure; ticket
/// local-storage accept entries 1, 2, 6).
///
/// `ProfilesDao` is deliberately given accessor access to every table this
/// unit owns (not just `Profiles`) so [deleteProfile] can perform the
/// cross-table erasure cascade in one transaction, without depending on
/// SQLite `PRAGMA foreign_keys` (off by default, and not something a
/// caller-supplied `QueryExecutor` is guaranteed to enable).
library;

import 'package:drift/drift.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/data/db/tables.dart';
import 'package:learn_to_read/domain/models/user_models.dart';

part 'profiles_dao.g.dart';

/// Thrown by [ProfilesDao.insertProfile] when the device already has
/// [kMaxProfilesPerDevice] profiles stored (PRD §5 "Max 4 per device").
class MaxProfilesExceededException implements Exception {
  const MaxProfilesExceededException(this.max);

  /// The max profile count that was hit (currently always
  /// [kMaxProfilesPerDevice]).
  final int max;

  @override
  String toString() =>
      'MaxProfilesExceededException: device already has the maximum of '
      '$max profiles';
}

@DriftAccessor(
  tables: [
    Profiles,
    StoryProgressEntries,
    WordHelpRecords,
    TwisterProgressEntries,
    CollectionEntries,
  ],
)
class ProfilesDao extends DatabaseAccessor<AppDatabase>
    with _$ProfilesDaoMixin {
  ProfilesDao(super.db);

  /// Inserts [profile]. Throws [MaxProfilesExceededException] (leaving
  /// existing profiles unchanged) if the device already has
  /// [kMaxProfilesPerDevice] profiles.
  Future<void> insertProfile(Profile profile) async {
    await transaction(() async {
      final existingCount = await select(profiles).get();
      if (existingCount.length >= kMaxProfilesPerDevice) {
        throw const MaxProfilesExceededException(kMaxProfilesPerDevice);
      }
      await into(profiles).insert(
        ProfilesCompanion.insert(
          localId: profile.localId,
          displayName: profile.displayName,
          ageBand: profile.ageBand,
          currentLevelId: profile.currentLevelId,
          micConsent: profile.micConsent,
          cloudAsrConsent: profile.cloudAsrConsent,
          createdAt: profile.createdAt,
        ),
      );
    });
  }

  /// Returns the profile with [localId], or null if none exists.
  Future<Profile?> getProfile(String localId) async {
    final row = await (select(
      profiles,
    )..where((t) => t.localId.equals(localId))).getSingleOrNull();
    return row == null ? null : _toDomain(row);
  }

  /// Returns every stored profile.
  Future<List<Profile>> allProfiles() async {
    final rows = await select(profiles).get();
    return rows.map(_toDomain).toList();
  }

  /// Streams the full profile list, for Riverpod providers to observe.
  Stream<List<Profile>> watchAllProfiles() {
    return select(
      profiles,
    ).watch().map((rows) => rows.map(_toDomain).toList());
  }

  /// Mutates [profile]'s mutable fields, matched by `localId`. `localId`
  /// and `createdAt` are identity/audit fields and are not changed by this
  /// call (the caller's `createdAt` is ignored; the stored value is kept).
  Future<void> updateProfile(Profile profile) async {
    await (update(
      profiles,
    )..where((t) => t.localId.equals(profile.localId))).write(
      ProfilesCompanion(
        displayName: Value(profile.displayName),
        ageBand: Value(profile.ageBand),
        currentLevelId: Value(profile.currentLevelId),
        micConsent: Value(profile.micConsent),
        cloudAsrConsent: Value(profile.cloudAsrConsent),
      ),
    );
  }

  /// Deletes the profile with [localId] and every row belonging to it in
  /// every other table this unit owns (StoryProgress, WordHelpRecord,
  /// TwisterProgress, CollectionState, and — since schema v2 —
  /// FlashcardProgress) -- irreversibly, per PRD §8 Unit 10.
  /// No-op (does not throw) if [localId] does not exist.
  Future<void> deleteProfile(String localId) async {
    await transaction(() async {
      await (delete(
        storyProgressEntries,
      )..where((t) => t.profileId.equals(localId))).go();
      await (delete(
        wordHelpRecords,
      )..where((t) => t.profileId.equals(localId))).go();
      await (delete(
        twisterProgressEntries,
      )..where((t) => t.profileId.equals(localId))).go();
      await (delete(
        collectionEntries,
      )..where((t) => t.profileId.equals(localId))).go();
      // Unit 16 (schema v2): flashcard progress is per-profile learning
      // data and erases with the profile like every other table above.
      await (attachedDatabase.delete(
        attachedDatabase.flashcardProgressRows,
      )..where((t) => t.profileId.equals(localId))).go();
      await (delete(profiles)..where((t) => t.localId.equals(localId))).go();
    });
  }

  Profile _toDomain(ProfileRow row) => Profile(
    localId: row.localId,
    displayName: row.displayName,
    ageBand: row.ageBand,
    currentLevelId: row.currentLevelId,
    micConsent: row.micConsent,
    cloudAsrConsent: row.cloudAsrConsent,
    createdAt: row.createdAt,
  );
}

# Local storage (Unit: local-storage)

The device-local Drift (SQLite) database for LearnToRead: one table per §5
device-local user model (`Profile`, `StoryProgress`, `WordHelpRecord`,
`TwisterProgress`, `CollectionState`) and one DAO per table. Headless-
testable against `NativeDatabase.memory()` — no `path_provider`, no device.

Source: `lib/data/db/app_database.dart`, `lib/data/db/tables.dart`,
`lib/data/db/daos/{profiles,story_progress,word_help,twister_progress,collection}_dao.dart`.
PRD refs: §5 (device-local user models), §8 Unit 10 (erasure, max 4
profiles), §9 A-2 (local storage is Drift/SQLite), §4.3 (learning signal).
Ticket: `docs/tickets/local-storage.json`. Pinned by `test/data/db/*.dart`
(6 files, 49 tests — see each test file's header comment for its exact
pinned API surface).

## Shape

`AppDatabase(QueryExecutor executor)` extends the Drift-generated
`_$AppDatabase`, `schemaVersion` pinned to `1`, and exposes five DAO
getters: `profilesDao`, `storyProgressDao`, `wordHelpDao`,
`twisterProgressDao`, `collectionDao`. Every DAO method takes and returns
the **domain** types from `package:learn_to_read/domain/models/user_models.dart`
(`Profile`, `StoryProgress`, `WordHelpRecord`, `TwisterProgress`,
`CollectionState`) — never a Drift-generated row class. This is what lets
Riverpod providers in UI tickets depend on the domain types only.

Drift table classes (`tables.dart`) are named in plural (`Profiles`,
`StoryProgressEntries`, `WordHelpRecords`, `TwisterProgressEntries`,
`CollectionEntries`) and each carries `@DataClassName(...)` to rename its
generated row class away from the domain type it would otherwise collide
with (e.g. `Profiles` → row class `ProfileRow`, not `Profile`, which is the
domain type). Enum-typed columns (`ageBand`, `status`, `lastHelpLevel`) use
hand-written `TypeConverter<DomainEnum, int>`s keyed to `enum.index`, so a
Drift row's field is already the domain enum — DAOs never hand-roll the
int↔enum mapping.

| Table | Primary key | Notes |
|---|---|---|
| `Profiles` | `localId` | Mirrors `Profile` exactly. |
| `StoryProgressEntries` | `(profileId, storyId)` | Mirrors `StoryProgress`. |
| `WordHelpRecords` | `(profileId, wordText)` | Mirrors `WordHelpRecord`. |
| `TwisterProgressEntries` | `(profileId, twisterId)` | Mirrors `TwisterProgress`. |
| `CollectionEntries` | `(profileId, collectibleId)` | One row per earned collectible; `CollectionState.earnedCollectibles` is the set of `collectibleId`s for a profile. |

Composite primary keys are load-bearing, not incidental: they are what make
`upsertProgress`, `recordEncounter`/`recordHelp`, `recordCompletion`, and
`grantCollectible` all non-duplicating by construction rather than by
careful caller discipline.

## DAO semantics

- **`ProfilesDao`** — `insertProfile` throws `MaxProfilesExceededException`
  (implements `Exception`, carries `max`) once the device already has
  `kMaxProfilesPerDevice` (4, from the domain-models ticket) profiles; the
  check-then-insert runs inside one `transaction()` so a rejected 5th insert
  leaves the existing 4 untouched. `getProfile`/`allProfiles`/
  `watchAllProfiles` read; `updateProfile` mutates every field except
  `localId`/`createdAt` (identity/audit fields, matched by `localId`).
  `deleteProfile` is a no-op (does not throw) for an unknown `localId`.
- **`StoryProgressDao`** — `upsertProgress` is a full keyed write (used to
  set up arbitrary fixture states, including status transitions, without
  duplicating the row). `recordCompletion` sets `status = completed`,
  increments `timesRead` on every call, and sets `completedAt` **only** if
  the existing row's `completedAt` was still null (first completion) —
  later calls preserve the original `completedAt` while still bumping
  `timesRead`, i.e. re-reads. Defaults `completedAt` to `DateTime.now()`
  when the caller omits it.
- **`WordHelpDao`** — `recordEncounter` is called for every word read
  (helped or not); it creates the row on first sight
  (`encounterCount: 1, helpCount: 0, lastHelpLevel: HelpLevel.none`) or
  increments `encounterCount` only. `recordHelp` is called in addition when
  a word needed help; it increments `helpCount` and sets `lastHelpLevel` to
  the tier reached, and never touches `encounterCount`. Calling `recordHelp`
  with no prior `recordEncounter` still stores a valid row
  (`encounterCount: 0`). `helpCount / encounterCount` is the §4.3 help-rate
  trajectory signal — declining as a word is learned — and is computed by
  the caller from the stored counts, not stored itself.
- **`TwisterProgressDao`** — `recordCompletion` creates the row on first
  completion (`timesCompleted: 1`) or increments `timesCompleted`; never
  duplicates a row for the same `(profileId, twisterId)`.
- **`CollectionDao`** — `grantCollectible` is `insertOnConflictUpdate`
  against the `(profileId, collectibleId)` primary key, so granting the
  same collectible twice always leaves exactly one row — this is the
  storage-level guarantee behind Unit 8's "collectible granted only on
  first completion" rule; it holds even if a caller double-invokes the
  grant. `getCollectionState` never returns null — an untouched profile
  gets `CollectionState(profileId, earnedCollectibles: [])`.

Every DAO also exposes `rowCountForProfile(String profileId)` (and
`ProfilesDao` exposes `getProfile` for the same purpose), which exist
specifically so `erasure_test.dart` can assert zero rows across every table
without depending on internal query shapes.

## Erasure (PRD §8 Unit 10)

`ProfilesDao.deleteProfile(localId)` is the *only* place cross-table
erasure happens. Rather than relying on SQLite foreign-key `ON DELETE
CASCADE` — which requires `PRAGMA foreign_keys = ON`, a pragma that is off
by default and not guaranteed to be set by every `QueryExecutor` a caller
might supply — `ProfilesDao` is given `@DriftAccessor` access to all five
tables and manually deletes every row scoped to `localId` from
`StoryProgressEntries`, `WordHelpRecords`, `TwisterProgressEntries`, and
`CollectionEntries`, then the `Profiles` row itself, all inside one
`transaction()`. This is deliberately explicit and table-enumerated: a
future table added to this unit must be added to this delete list by hand,
not assumed to cascade.

`erasure_test.dart` populates every table for two profiles, deletes one,
and asserts (a) the deleted profile has zero rows everywhere and (b) the
surviving profile's rows in every table are byte-for-byte untouched —
proving this is a scoped per-profile wipe, not a full-database reset.

## Deviations / unpinned decisions

None. Table shapes, DAO method signatures, and exception type were
transcribed directly from each frozen test file's header comment (the
pinned API surface) and from PRD §5/§8 Unit 10/§4.3. Two implementation
choices were not pinned by the ticket text itself but were unambiguous given
the frozen tests and are recorded here for the next builder:

- **Cascade mechanism**: manual per-table delete in a transaction, not
  SQLite `ON DELETE CASCADE` foreign keys — see "Erasure" above for why.
- **`recordCompletion`'s "first completion" rule**: implemented as "set
  `completedAt` iff the existing row's `completedAt` is currently null",
  which also correctly handles a row created earlier via `upsertProgress`
  with a non-completed status (no existing `completedAt` to preserve) as
  well as a row already completed by an earlier `recordCompletion` call.

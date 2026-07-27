/// Word-resolution recording for the tiered help scaffold (PRD §5
/// `WordHelpRecord`; §4.3 learning signal; §8 Unit 6; ticket
/// stuck-word-scaffold accept entries 6 and 10).
library;

import 'package:learn_to_read/data/db/daos/word_help_dao.dart';
import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';

/// The seam `StuckWordController` records word resolutions through.
///
/// Exists as its own type so the controller never depends on Drift: UI and
/// timer-choreography tests substitute a trivial in-memory double, while
/// [HelpRecorder] is the one production implementation.
abstract class HelpRecorderApi {
  /// Records that [word] was resolved (the child moved on from it), having
  /// reached help level [tier].
  ///
  /// Called for **every** resolution, helped or not — [HelpLevel.none] is a
  /// perfectly ordinary argument here and is what supplies the denominator of
  /// the §4.3 help-rate trajectory.
  Future<void> recordResolution({
    required WordToken word,
    required HelpLevel tier,
  });
}

/// Writes word resolutions into the device-local `WordHelpRecord` table for
/// one profile.
///
/// The split of DB effects is exactly the one pinned by §4.3 and the Unit 6
/// "helped words are recorded with the tier reached" rule:
///  - **every** resolution is an encounter (`WordHelpDao.recordEncounter`),
///    including unaided reads and near-miss acceptances — without this the
///    help-rate metric has no denominator and would read as a flat 100%;
///  - a resolution with a real tier ([HelpLevel.soundOut] or
///    [HelpLevel.modeled]) *additionally* calls `WordHelpDao.recordHelp`,
///    which bumps `helpCount` and stores `lastHelpLevel`.
///
/// Nothing here invents DB semantics of its own: the row-accumulation rules
/// (create-on-first-sight, never regress `lastHelpLevel` on an unaided read,
/// per-profile isolation) all live on `WordHelpDao` and are pinned by the
/// local-storage unit's own suite.
///
/// The record is invisible to the child by construction — it is a database
/// row, never a UI marker (Unit 1 ratified: helped words show no badge).
class HelpRecorder implements HelpRecorderApi {
  /// Creates a recorder writing [profileId]'s rows through [wordHelpDao].
  HelpRecorder({required this.wordHelpDao, required this.profileId});

  /// The merged local-storage DAO for `WordHelpRecord` rows.
  final WordHelpDao wordHelpDao;

  /// The profile whose rows this recorder writes (`Profile.localId`).
  final String profileId;

  @override
  Future<void> recordResolution({
    required WordToken word,
    required HelpLevel tier,
  }) async {
    await wordHelpDao.recordEncounter(
      profileId: profileId,
      wordText: word.text,
    );
    if (tier == HelpLevel.none) {
      return;
    }
    await wordHelpDao.recordHelp(
      profileId: profileId,
      wordText: word.text,
      tier: tier,
    );
  }
}

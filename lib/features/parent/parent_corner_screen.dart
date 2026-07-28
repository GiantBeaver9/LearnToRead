/// The parent corner: everything an adult can do, behind the parental gate
/// (PRD §8 Unit 10).
///
/// **Reachability.** [ParentCornerScreen] *is* the gate. It renders the real
/// [ParentalGate] — hold two opposite corners for three seconds, then solve a
/// multiplication challenge (PRD §9 A-4) — and swaps in the corner's contents
/// only once the gate reports an unlock. There is deliberately no bypass
/// parameter, no "already unlocked" constructor flag, and no persisted unlock
/// state: unlock lives in this [State] object, so a remount (leaving and
/// re-navigating to the corner) starts back at the gate. Re-entry requires
/// re-passing, which is the whole point of the gate — a corner that stays
/// open is a corner a child walks into.
///
/// **Scope.** [ParentCornerContents] composes exactly four sections —
/// profiles, pilot progress, consent, links — and nothing else. That list is
/// the v1 scope in full (PRD §8 Unit 10: "all of it — nothing more in v1"),
/// and it is enforced structurally: the four `parent-corner-section-*` keys
/// are the exhaustive set, and there is no navigation chrome (no drawer, tab
/// bar, or nav rail) that could grow a fifth destination without anyone
/// noticing. Everything is inline, on one screen, visible at once.
library;

import 'package:flutter/material.dart';
import 'package:learn_to_read/data/db/app_database.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/domain/phonics/scope_sequence_loader.dart';
// ProfilesDao (subclassed below as _NotifyingProfilesDao) comes in via
// consent_controller's re-export, which is also where the consent seam's own
// DAO dependency is declared.
import 'package:learn_to_read/features/parent/consent_controller.dart';
import 'package:learn_to_read/features/parent/parent_links.dart';
import 'package:learn_to_read/features/parent/parental_gate.dart';
import 'package:learn_to_read/features/parent/pilot_progress_view.dart';
import 'package:learn_to_read/features/parent/profile_editor.dart';

/// The gated entry point to the parent corner.
class ParentCornerScreen extends StatefulWidget {
  /// Creates the gated parent corner over [db].
  const ParentCornerScreen({
    super.key,
    required this.db,
    required this.phonicsContent,
    required this.cloudEngineInUse,
  });

  /// Device-local storage: the source for every profile, progress row, and
  /// help record the corner shows.
  final AppDatabase db;

  /// The loaded scope-and-sequence, used for age-band placement on create.
  final PhonicsContent phonicsContent;

  /// Whether a cloud speech engine is in use; gates the cloud-consent toggle.
  final bool cloudEngineInUse;

  @override
  State<ParentCornerScreen> createState() => _ParentCornerScreenState();
}

class _ParentCornerScreenState extends State<ParentCornerScreen> {
  /// Unlock state, held here and nowhere else: it dies with this [State], so
  /// a fresh mount is a fresh gate.
  bool _unlocked = false;

  Future<bool> _handleUnlocked() async {
    if (mounted) {
      setState(() => _unlocked = true);
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (!_unlocked) {
      return ParentalGate(onUnlocked: _handleUnlocked);
    }
    return ParentCornerContents(
      db: widget.db,
      phonicsContent: widget.phonicsContent,
      cloudEngineInUse: widget.cloudEngineInUse,
    );
  }
}

/// The parent corner's contents: exactly four inline sections.
///
/// Split out from [ParentCornerScreen] so the contents can be rendered (and
/// reasoned about) independently of the gate, without that separation ever
/// becoming a way to *reach* them ungated — the only caller in the app is the
/// unlocked branch of [ParentCornerScreen].
class ParentCornerContents extends StatelessWidget {
  /// Creates the corner's contents over [db].
  const ParentCornerContents({
    super.key,
    required this.db,
    required this.phonicsContent,
    required this.cloudEngineInUse,
  });

  /// Device-local storage.
  final AppDatabase db;

  /// The loaded scope-and-sequence.
  final PhonicsContent phonicsContent;

  /// Whether a cloud speech engine is in use.
  final bool cloudEngineInUse;

  @override
  Widget build(BuildContext context) {
    return _CornerBody(
      db: db,
      phonicsContent: phonicsContent,
      cloudEngineInUse: cloudEngineInUse,
    );
  }
}

/// Holds the corner's loaded state.
///
/// [ParentCornerContents] is stateless by contract, so the loading — and the
/// re-loading after a profile is created, edited, or deleted — lives here.
class _CornerBody extends StatefulWidget {
  const _CornerBody({
    required this.db,
    required this.phonicsContent,
    required this.cloudEngineInUse,
  });

  final AppDatabase db;
  final PhonicsContent phonicsContent;
  final bool cloudEngineInUse;

  @override
  State<_CornerBody> createState() => _CornerBodyState();
}

class _CornerBodyState extends State<_CornerBody> {
  /// The DAO handed to every child of this corner.
  ///
  /// Reads are plain futures rather than Drift query streams on purpose: a
  /// live query stream would keep the corner's three data-driven sections in
  /// sync automatically, but its subscription teardown schedules work that
  /// outlives the widget tree, which is exactly the kind of dangling
  /// background work a parent screen should not leave behind. The mutation
  /// hook below buys the same freshness with none of that.
  late final _NotifyingProfilesDao _profilesDao = _NotifyingProfilesDao(
    widget.db,
    _reload,
  );

  List<Profile> _profiles = const <Profile>[];
  Map<String, _ProfileProgressData> _progress =
      const <String, _ProfileProgressData>{};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  /// Re-reads every profile and its progress rows. Called on mount and after
  /// any profile mutation, so the progress and consent sections can never
  /// disagree with the profile list sitting directly above them.
  Future<void> _reload() async {
    final profiles = await _profilesDao.allProfiles();
    final progress = <String, _ProfileProgressData>{};
    for (final profile in profiles) {
      progress[profile.localId] = _ProfileProgressData(
        await widget.db.storyProgressDao.allForProfile(profile.localId),
        await widget.db.wordHelpDao.allForProfile(profile.localId),
      );
    }
    if (!mounted) return;
    setState(() {
      _profiles = profiles;
      _progress = progress;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: DesignTokens.screenBackground,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            // Each section gets an equal share of the screen and scrolls
            // within it. Four regions side by side rather than four tabs, on
            // purpose: a parent must be able to see that the corner holds
            // four things and no more.
            Expanded(
              child: _buildSection(
                sectionKey: const Key('parent-corner-section-profiles'),
                title: 'Profiles',
                child: ProfileEditor(
                  profilesDao: _profilesDao,
                  phonicsContent: widget.phonicsContent,
                ),
              ),
            ),
            Expanded(
              child: _buildSection(
                sectionKey: const Key('parent-corner-section-progress'),
                title: 'How reading is going',
                child: _buildPerProfile(
                  (profile) => PilotProgressView(
                    profile: profile,
                    storyProgress:
                        _progress[profile.localId]?.storyProgress ??
                        const <StoryProgress>[],
                    wordHelpRecords:
                        _progress[profile.localId]?.wordHelpRecords ??
                        const <WordHelpRecord>[],
                  ),
                  emptyMessage:
                      'Add a profile to see how their reading is going.',
                ),
              ),
            ),
            Expanded(
              child: _buildSection(
                sectionKey: const Key('parent-corner-section-consent'),
                title: 'Microphone',
                child: _buildPerProfile(
                  (profile) => ConsentController(
                    profile: profile,
                    profilesDao: _profilesDao,
                    cloudEngineInUse: widget.cloudEngineInUse,
                  ),
                  emptyMessage:
                      'Add a profile to choose its microphone setting.',
                ),
              ),
            ),
            Expanded(
              child: _buildSection(
                sectionKey: const Key('parent-corner-section-links'),
                title: 'About this app',
                // Scrolled here rather than inside ParentLinks: the link list
                // is a plain Column so it can also sit inside an
                // already-scrolling parent without nesting viewports.
                child: const SingleChildScrollView(child: ParentLinks()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Wraps [child] in the keyed section container plus a plain title.
  ///
  /// The key sits on the outermost container, unconditionally, so a section
  /// is present in the tree even while its data is still loading: "the corner
  /// has four sections" must never be a function of I/O timing.
  Widget _buildSection({
    required Key sectionKey,
    required String title,
    required Widget child,
  }) {
    return Container(
      key: sectionKey,
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spacingSm,
        vertical: DesignTokens.spacingXs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(title, style: _sectionTitleStyle),
          Expanded(child: child),
        ],
      ),
    );
  }

  /// Renders [builder] once per stored profile, or [emptyMessage] when there
  /// are none.
  Widget _buildPerProfile(
    Widget Function(Profile profile) builder, {
    required String emptyMessage,
  }) {
    if (_profiles.isEmpty) {
      return Text(emptyMessage, style: _emptyStyle);
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[for (final profile in _profiles) builder(profile)],
      ),
    );
  }

  static const TextStyle _sectionTitleStyle = TextStyle(
    color: DesignTokens.wordUnreadInk,
    fontFamily: DesignTokens.displayFontFamily,
    fontSize: 16.0,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle _emptyStyle = TextStyle(
    color: DesignTokens.wordUnreadInk,
    fontFamily: DesignTokens.readingFontFamily,
    fontSize: 14.0,
    fontStyle: FontStyle.italic,
  );
}

/// A [ProfilesDao] that reports every successful mutation back to the corner.
///
/// The corner's three data-driven sections are built from one profile list;
/// [ProfileEditor] and [ConsentController] both mutate that list through their
/// injected DAO. Rather than widening either widget's pinned API with a
/// "something changed" callback, the notification is taken at the one place
/// every mutation must pass through anyway. A failed mutation (for example
/// the 5th-profile cap) throws before [_onMutation] runs, so nothing reloads
/// when nothing changed.
class _NotifyingProfilesDao extends ProfilesDao {
  _NotifyingProfilesDao(super.db, this._onMutation);

  final void Function() _onMutation;

  @override
  Future<void> insertProfile(Profile profile) async {
    await super.insertProfile(profile);
    _onMutation();
  }

  @override
  Future<void> updateProfile(Profile profile) async {
    await super.updateProfile(profile);
    _onMutation();
  }

  @override
  Future<void> deleteProfile(String localId) async {
    await super.deleteProfile(localId);
    _onMutation();
  }
}

/// The two per-profile row sets the pilot progress view needs.
class _ProfileProgressData {
  const _ProfileProgressData(this.storyProgress, this.wordHelpRecords);

  final List<StoryProgress> storyProgress;
  final List<WordHelpRecord> wordHelpRecords;
}

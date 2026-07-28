/// Profile CRUD in the parent corner (PRD §8 Unit 10: "Create/edit/delete
/// profiles: name, age band (sets starting level per Unit 2), optional level
/// override" and "Deleting a profile shows a plain confirmation and erases
/// all its local data irreversibly").
///
/// Three deliberate shapes here, each of which could reasonably have been
/// built otherwise:
///
///  * **Age band places the level; editing never re-places it.** Placement
///    (`placeStartingLevel`, PRD §8 Unit 2) is a *starting* decision. Once a
///    child has read at a level, correcting a typo in their birthday must not
///    silently move them; a parent who wants to move them has the override
///    field on create and, later, the level they are actually on. So create
///    calls placement and edit does not.
///
///  * **The 5th-profile cap is surfaced, not prevented.** The button stays
///    enabled and the DAO's `MaxProfilesExceededException` is caught and
///    rendered. A disabled button with no explanation is the worst version of
///    this: the parent learns nothing. The cap itself is enforced in one
///    place only — storage — so the UI cannot drift from it.
///
///  * **Deletion is a two-step, and the first step is inert.** A single tap
///    on the delete icon opens a confirmation and touches nothing. Erasure is
///    irreversible and cascades across every table the child owns, so the
///    affordance a child could plausibly reach (one tap) must be incapable of
///    destroying anything.
library;

import 'package:flutter/material.dart';
import 'package:learn_to_read/data/db/daos/profiles_dao.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/domain/phonics/placement.dart';
import 'package:learn_to_read/domain/phonics/scope_sequence_loader.dart';

/// Monotonic suffix for the default id generator, so two profiles created in
/// the same microsecond still get distinct ids.
int _defaultIdSequence = 0;

/// Default profile-id generator: locally unique, never leaves the device.
String _defaultIdGenerator() =>
    'profile.${DateTime.now().microsecondsSinceEpoch}.${_defaultIdSequence++}';

/// The parent corner's profile list plus its create/edit/delete affordances.
class ProfileEditor extends StatefulWidget {
  /// Creates the editor over [profilesDao].
  const ProfileEditor({
    super.key,
    required this.profilesDao,
    required this.phonicsContent,
    this.idGenerator,
  });

  /// Storage for every read and mutation this editor performs, including the
  /// cascading erasure behind `deleteProfile`.
  final ProfilesDao profilesDao;

  /// The loaded scope-and-sequence, consumed via [placeStartingLevel] to
  /// compute a new profile's `currentLevelId` from its age band.
  final PhonicsContent phonicsContent;

  /// Generates `localId`s for newly created profiles. Defaults to a
  /// timestamp-based local generator; injectable so ids are deterministic
  /// under test.
  final String Function()? idGenerator;

  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  final TextEditingController _createNameController = TextEditingController();
  final TextEditingController _createOverrideController =
      TextEditingController();

  List<Profile> _profiles = const <Profile>[];
  AgeBand _createBand = AgeBand.fiveToSix;

  /// Set only when `insertProfile` throws [MaxProfilesExceededException].
  String? _capError;

  /// Set for create-form validation problems that are *not* the device cap
  /// (empty name, unknown override level id).
  String? _formError;

  /// The `localId` of the row currently in inline edit mode, if any.
  String? _editingId;
  final TextEditingController _editNameController = TextEditingController();
  AgeBand _editBand = AgeBand.fiveToSix;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _createNameController.dispose();
    _createOverrideController.dispose();
    _editNameController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final profiles = await widget.profilesDao.allProfiles();
    if (!mounted) return;
    setState(() => _profiles = profiles);
  }

  // -------------------------------------------------------------------
  // Create
  // -------------------------------------------------------------------

  Future<void> _create() async {
    final name = _createNameController.text.trim();
    final override = _createOverrideController.text.trim();

    if (name.isEmpty) {
      setState(() {
        _formError = 'Enter a name for this profile.';
        _capError = null;
      });
      return;
    }

    final String levelId;
    try {
      levelId = placeStartingLevel(
        ageBand: _createBand,
        content: widget.phonicsContent,
        parentOverrideLevelId: override.isEmpty ? null : override,
      );
    } on ArgumentError {
      setState(() {
        _formError = 'No level called "$override" exists. Leave the override '
            'empty to use the age band.';
        _capError = null;
      });
      return;
    } on StateError catch (error) {
      setState(() {
        _formError = 'Could not pick a starting level: ${error.message}';
        _capError = null;
      });
      return;
    }

    final generate = widget.idGenerator ?? _defaultIdGenerator;
    final profile = Profile(
      localId: generate(),
      displayName: name,
      ageBand: _createBand,
      currentLevelId: levelId,
      // Consent starts off, always (PRD §8 Unit 10). It is only ever turned
      // on by a deliberate parent action in the consent section.
      micConsent: false,
      cloudAsrConsent: false,
      createdAt: DateTime.now(),
    );

    try {
      await widget.profilesDao.insertProfile(profile);
      if (!mounted) return;
      setState(() {
        _capError = null;
        _formError = null;
        _createNameController.clear();
        _createOverrideController.clear();
        _createBand = AgeBand.fiveToSix;
      });
    } on MaxProfilesExceededException catch (error) {
      if (!mounted) return;
      setState(() {
        _formError = null;
        _capError =
            'This device already has ${error.max} profiles. Delete one to '
            'make room.';
      });
    }
    await _reload();
  }

  // -------------------------------------------------------------------
  // Edit
  // -------------------------------------------------------------------

  void _startEdit(Profile profile) {
    setState(() {
      _editingId = profile.localId;
      _editNameController.text = profile.displayName;
      _editBand = profile.ageBand;
    });
  }

  void _cancelEdit() {
    setState(() => _editingId = null);
  }

  Future<void> _saveEdit(Profile profile) async {
    final name = _editNameController.text.trim();
    if (name.isEmpty) return;

    await widget.profilesDao.updateProfile(
      Profile(
        localId: profile.localId,
        displayName: name,
        ageBand: _editBand,
        // Untouched on purpose: an edit is not a re-placement, and consent
        // and identity fields are owned elsewhere.
        currentLevelId: profile.currentLevelId,
        micConsent: profile.micConsent,
        cloudAsrConsent: profile.cloudAsrConsent,
        createdAt: profile.createdAt,
      ),
    );
    if (!mounted) return;
    setState(() => _editingId = null);
    await _reload();
  }

  // -------------------------------------------------------------------
  // Delete
  // -------------------------------------------------------------------

  Future<void> _confirmDelete(Profile profile) async {
    final confirmed = await showDialog<bool>(
      context: context,
      // Not barrier-dismissible: a stray tap outside the dialog should be a
      // no-op, not an ambiguous dismissal of an irreversible decision.
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        key: const Key('delete-confirm-dialog'),
        backgroundColor: DesignTokens.surfaceBackground,
        title: Text('Delete ${profile.displayName}?', style: _dialogTitleStyle),
        content: Text(
          'This permanently erases everything for ${profile.displayName} on '
          'this device: reading progress, the words they needed help with, '
          'tongue twisters, and their collection. This cannot be undone.',
          style: _dialogBodyStyle,
        ),
        actions: <Widget>[
          TextButton(
            key: Key('cancel-delete-${profile.localId}'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep profile', style: _dialogActionStyle),
          ),
          TextButton(
            key: Key('confirm-delete-${profile.localId}'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete forever', style: _dialogActionStyle),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // One call: the DAO owns the cross-table cascade in a single
    // transaction, so a half-erased profile is not a reachable state.
    await widget.profilesDao.deleteProfile(profile.localId);
    if (!mounted) return;
    if (_editingId == profile.localId) {
      setState(() => _editingId = null);
    }
    await _reload();
  }

  // -------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _buildCreateForm(),
          const SizedBox(height: DesignTokens.spacingLg),
          const Text('Profiles on this device', style: _headingStyle),
          for (final profile in _profiles) _buildRow(profile),
        ],
      ),
    );
  }

  Widget _buildCreateForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const Text('Add a profile', style: _headingStyle),
        TextField(
          key: const Key('create-name-field'),
          controller: _createNameController,
          style: _bodyStyle,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'Name',
            labelStyle: _bodyStyle,
          ),
        ),
        const SizedBox(height: DesignTokens.spacingSm),
        const Text('Age', style: _labelStyle),
        Row(
          children: <Widget>[
            for (final band in AgeBand.values)
              Padding(
                padding: const EdgeInsets.only(right: DesignTokens.spacingSm),
                child: _buildBandOption(
                  optionKey: Key('create-age-band-option-${band.name}'),
                  band: band,
                  selected: _createBand == band,
                  onTap: () => setState(() => _createBand = band),
                ),
              ),
          ],
        ),
        const SizedBox(height: DesignTokens.spacingSm),
        TextField(
          key: const Key('create-level-override-field'),
          controller: _createOverrideController,
          style: _bodyStyle,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'Starting level override (optional)',
            labelStyle: _bodyStyle,
          ),
        ),
        const SizedBox(height: DesignTokens.spacingSm),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const Key('add-profile-button'),
            onPressed: _create,
            child: const Text('Add profile', style: _labelStyle),
          ),
        ),
        if (_capError != null)
          Text(
            _capError!,
            key: const Key('profile-cap-error'),
            style: _errorStyle,
          ),
        if (_formError != null)
          Text(
            _formError!,
            key: const Key('profile-form-error'),
            style: _errorStyle,
          ),
      ],
    );
  }

  Widget _buildRow(Profile profile) {
    final editing = _editingId == profile.localId;
    return Container(
      key: Key('profile-row-${profile.localId}'),
      margin: const EdgeInsets.only(top: DesignTokens.spacingSm),
      padding: const EdgeInsets.all(DesignTokens.spacingSm),
      decoration: BoxDecoration(
        color: DesignTokens.surfaceBackground,
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: editing ? _buildEditRow(profile) : _buildDisplayRow(profile),
    );
  }

  Widget _buildDisplayRow(Profile profile) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                profile.displayName,
                key: Key('profile-name-text-${profile.localId}'),
                style: _labelStyle,
              ),
              Text(
                profile.ageBand.label,
                key: Key('profile-band-text-${profile.localId}'),
                style: _bodyStyle,
              ),
              Text(
                profile.currentLevelId,
                key: Key('profile-level-text-${profile.localId}'),
                style: _bodyStyle,
              ),
            ],
          ),
        ),
        IconButton(
          key: Key('edit-profile-${profile.localId}'),
          tooltip: 'Edit profile',
          icon: const Icon(Icons.edit, color: DesignTokens.wordUnreadInk),
          onPressed: () => _startEdit(profile),
        ),
        IconButton(
          key: Key('delete-profile-${profile.localId}'),
          tooltip: 'Delete profile',
          icon: const Icon(
            Icons.delete_outline,
            color: DesignTokens.wordUnreadInk,
          ),
          onPressed: () => _confirmDelete(profile),
        ),
      ],
    );
  }

  Widget _buildEditRow(Profile profile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        TextField(
          key: Key('edit-name-field-${profile.localId}'),
          controller: _editNameController,
          style: _bodyStyle,
          decoration: const InputDecoration(
            isDense: true,
            labelText: 'Name',
            labelStyle: _bodyStyle,
          ),
        ),
        const SizedBox(height: DesignTokens.spacingSm),
        Row(
          children: <Widget>[
            for (final band in AgeBand.values)
              Padding(
                padding: const EdgeInsets.only(right: DesignTokens.spacingSm),
                child: _buildBandOption(
                  optionKey: Key(
                    'edit-age-band-option-${profile.localId}-${band.name}',
                  ),
                  band: band,
                  selected: _editBand == band,
                  onTap: () => setState(() => _editBand = band),
                ),
              ),
          ],
        ),
        const SizedBox(height: DesignTokens.spacingSm),
        Row(
          children: <Widget>[
            TextButton(
              key: Key('cancel-edit-${profile.localId}'),
              onPressed: _cancelEdit,
              child: const Text('Cancel', style: _labelStyle),
            ),
            TextButton(
              key: Key('save-edit-${profile.localId}'),
              onPressed: () => _saveEdit(profile),
              child: const Text('Save', style: _labelStyle),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBandOption({
    required Key optionKey,
    required AgeBand band,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: optionKey,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spacingMd,
          vertical: DesignTokens.spacingXs,
        ),
        decoration: BoxDecoration(
          color: selected
              ? DesignTokens.surfaceBackground
              : DesignTokens.screenBackground,
          borderRadius: BorderRadius.circular(8.0),
          border: Border.all(
            color: selected
                ? DesignTokens.wordReadGreen
                : DesignTokens.wordUnreadInk,
            width: selected ? 2.0 : 1.0,
          ),
        ),
        child: Text(band.label, style: _bodyStyle),
      ),
    );
  }

  static const TextStyle _headingStyle = TextStyle(
    color: DesignTokens.wordUnreadInk,
    fontFamily: DesignTokens.displayFontFamily,
    fontSize: 18.0,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle _labelStyle = TextStyle(
    color: DesignTokens.wordUnreadInk,
    fontFamily: DesignTokens.readingFontFamily,
    fontSize: 15.0,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle _bodyStyle = TextStyle(
    color: DesignTokens.wordUnreadInk,
    fontFamily: DesignTokens.readingFontFamily,
    fontSize: 14.0,
  );

  static const TextStyle _errorStyle = TextStyle(
    color: DesignTokens.wordUnreadInk,
    fontFamily: DesignTokens.readingFontFamily,
    fontSize: 13.0,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle _dialogTitleStyle = TextStyle(
    color: DesignTokens.wordUnreadInk,
    fontFamily: DesignTokens.displayFontFamily,
    fontSize: 18.0,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle _dialogBodyStyle = TextStyle(
    color: DesignTokens.wordUnreadInk,
    fontFamily: DesignTokens.readingFontFamily,
    fontSize: 14.0,
  );

  static const TextStyle _dialogActionStyle = TextStyle(
    color: DesignTokens.wordUnreadInk,
    fontFamily: DesignTokens.readingFontFamily,
    fontSize: 15.0,
    fontWeight: FontWeight.bold,
  );
}

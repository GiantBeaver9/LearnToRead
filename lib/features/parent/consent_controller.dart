/// Per-child consent — the microphone toggle, the conditional cloud-processing
/// toggle, and the reading-mode decision they feed (PRD §8 Unit 10:
/// "Per-child microphone toggle (default off until enabled). A cloud
/// processing toggle appears only if a cloud engine is in use ... Consent
/// state changes take effect immediately (Unit 4 reads them per session start
/// and on change)").
///
/// **POC consent posture (PRD §6).** This is a plain-language, in-app toggle
/// and nothing more. Verifiable parental consent (COPPA) is an explicit
/// post-POC ship gate, recorded but deliberately not built here; the parental
/// gate in front of the corner is what keeps a child from flipping their own
/// microphone on.
///
/// **Why the mic-permission seam lives in this file.** This unit does not
/// depend on the listening-pipeline unit, so the plumbing needed to state the
/// consent matrix — [MicPermissionService], [MicPermissionStatus],
/// [ReadingMode] and the two resolver functions — is defined here and owned
/// here. The listening pipeline consumes these rather than inventing its own:
/// there must be exactly one answer to "may we open the microphone?".
///
/// **The default is off, and it is off by construction.** `micConsent` is a
/// non-nullable field a profile is created with (`false`, per
/// `ProfileEditor`), so there is no "unset" state that could be read
/// optimistically. [resolveReadingMode] reinforces this at the decision
/// point: anything short of explicit consent *plus* a granted OS permission
/// resolves to [ReadingMode.tapOnly].
library;

import 'package:flutter/material.dart';
import 'package:learn_to_read/data/db/daos/profiles_dao.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/user_models.dart';

export 'package:learn_to_read/data/db/daos/profiles_dao.dart'
    show ProfilesDao, MaxProfilesExceededException;

/// The OS-level microphone permission state, as reported by the platform.
enum MicPermissionStatus {
  /// The OS has granted microphone access.
  granted,

  /// The OS has refused microphone access (or the user revoked it).
  denied,

  /// The OS has not been asked yet, or gave no answer.
  notDetermined,
}

/// The seam over the platform's microphone-permission prompt.
///
/// Kept to a single method so the whole consent matrix is exercisable
/// headlessly (see [FakeMicPermissionService]) with no platform channel.
abstract class MicPermissionService {
  /// Asks the OS for microphone access, returning the resulting status.
  Future<MicPermissionStatus> requestPermission();
}

/// A [MicPermissionService] that returns a canned [result] and records
/// whether it was ever asked.
///
/// [wasRequested] is the load-bearing part: "the mic is never requested when
/// consent is off" is a privacy promise, and the only way to hold a promise
/// about a call *not* happening is to observe the call site.
class FakeMicPermissionService implements MicPermissionService {
  /// Creates a fake that always answers [result].
  FakeMicPermissionService(this.result);

  /// The status this fake always returns.
  final MicPermissionStatus result;

  bool _wasRequested = false;

  /// Whether [requestPermission] has been called at least once.
  bool get wasRequested => _wasRequested;

  @override
  Future<MicPermissionStatus> requestPermission() async {
    _wasRequested = true;
    return result;
  }
}

/// How a reading session may listen to the child.
enum ReadingMode {
  /// No microphone at all: the child advances by tapping words.
  tapOnly,

  /// On-device speech recognition (PRD §9 A-10 default).
  deviceRecognition,

  /// Cloud speech recognition — only ever reachable with an explicit,
  /// separate cloud consent *and* a cloud engine actually in use.
  cloudRecognition,
}

/// Resolves the [ReadingMode] for a session, given an already-resolved
/// permission status. Pure: makes no OS call.
///
/// The rules, in order:
///  1. No `micConsent` → [ReadingMode.tapOnly]. Nothing else is consulted.
///  2. `permissionStatus != granted` → [ReadingMode.tapOnly]. A denial, or a
///     not-yet-determined answer, is a graceful fallback and never an error:
///     tap-only is a complete way to read the app, not a degraded one.
///  3. Cloud engine in use *and* `cloudAsrConsent` → [ReadingMode.cloudRecognition].
///  4. Otherwise → [ReadingMode.deviceRecognition]. In particular, a cloud
///     engine without cloud consent falls back to on-device recognition and
///     never silently uploads audio.
ReadingMode resolveReadingMode({
  required bool micConsent,
  required MicPermissionStatus permissionStatus,
  required bool cloudEngineInUse,
  bool cloudAsrConsent = false,
}) {
  if (!micConsent) return ReadingMode.tapOnly;
  if (permissionStatus != MicPermissionStatus.granted) {
    return ReadingMode.tapOnly;
  }
  if (cloudEngineInUse && cloudAsrConsent) {
    return ReadingMode.cloudRecognition;
  }
  return ReadingMode.deviceRecognition;
}

/// The full flow a reading-screen entry (or a session start) runs.
///
/// Calls `permissionService.requestPermission()` **only** when [micConsent]
/// is true. With consent off the OS is never asked, so the child never sees a
/// microphone prompt they have not been opted into — the concrete form of
/// "the mic is never requested".
Future<ReadingMode> resolveReadingModeWithPermissionCheck({
  required bool micConsent,
  required MicPermissionService permissionService,
  required bool cloudEngineInUse,
  bool cloudAsrConsent = false,
}) async {
  if (!micConsent) return ReadingMode.tapOnly;
  final status = await permissionService.requestPermission();
  return resolveReadingMode(
    micConsent: micConsent,
    permissionStatus: status,
    cloudEngineInUse: cloudEngineInUse,
    cloudAsrConsent: cloudAsrConsent,
  );
}

/// The per-child consent controls in the parent corner.
///
/// Every toggle writes through to storage on the spot: there is no "Save"
/// button, because a consent screen with an unsaved state can leave a parent
/// believing they turned the microphone off when they did not.
class ConsentController extends StatefulWidget {
  /// Creates the consent controls for [profile].
  const ConsentController({
    super.key,
    required this.profile,
    required this.profilesDao,
    required this.cloudEngineInUse,
    this.onConsentChanged,
  });

  /// The child whose consent this controls. Read once, at mount: a fresh
  /// session start re-reads the profile from storage and mounts anew, which
  /// is exactly how "consent changes take effect immediately" is honoured
  /// across sessions.
  final Profile profile;

  /// Storage for the immediate write-through.
  final ProfilesDao profilesDao;

  /// Whether a cloud speech engine is in use. When false (the POC default,
  /// PRD §9 A-10 on-device), the cloud toggle is not rendered at all — an
  /// absent control cannot mislead a parent into thinking audio might leave
  /// the device.
  final bool cloudEngineInUse;

  /// Fired with the freshly-persisted profile on every toggle: the
  /// "tracker hook re-read on change" seam (PRD §8 Unit 10 / Unit 4).
  final void Function(Profile updated)? onConsentChanged;

  @override
  State<ConsentController> createState() => _ConsentControllerState();
}

class _ConsentControllerState extends State<ConsentController> {
  late Profile _profile;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
  }

  @override
  void didUpdateWidget(ConsentController oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.profile != oldWidget.profile) {
      _profile = widget.profile;
    }
  }

  /// Applies a consent change: repaints, starts the write-through, and
  /// notifies the tracker hook.
  ///
  /// The write is *started* synchronously and the hook notified immediately
  /// rather than after the write's future resolves. Storage is a local
  /// SQLite file whose statements are serialised in call order, so the next
  /// read cannot observe a stale value; deferring the notification, by
  /// contrast, would leave a live reading session running under withdrawn
  /// consent for as long as the disk took to answer. Consent withdrawal must
  /// win the race.
  Future<void> _apply(Profile updated) async {
    setState(() => _profile = updated);
    final write = widget.profilesDao.updateProfile(updated);
    widget.onConsentChanged?.call(updated);
    await write;
  }

  Future<void> _setMicConsent(bool value) {
    return _apply(_copyWith(micConsent: value));
  }

  Future<void> _setCloudConsent(bool value) {
    return _apply(_copyWith(cloudAsrConsent: value));
  }

  Profile _copyWith({bool? micConsent, bool? cloudAsrConsent}) => Profile(
    localId: _profile.localId,
    displayName: _profile.displayName,
    ageBand: _profile.ageBand,
    currentLevelId: _profile.currentLevelId,
    micConsent: micConsent ?? _profile.micConsent,
    cloudAsrConsent: cloudAsrConsent ?? _profile.cloudAsrConsent,
    createdAt: _profile.createdAt,
  );

  @override
  Widget build(BuildContext context) {
    final id = _profile.localId;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingSm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(_profile.displayName, style: _titleStyle),
          _buildToggleRow(
            toggleKey: Key('mic-consent-toggle-$id'),
            label: 'Microphone',
            explanation:
                'Off means reading works by tapping words. On lets the app '
                'listen while your child reads aloud.',
            value: _profile.micConsent,
            onChanged: _setMicConsent,
          ),
          if (widget.cloudEngineInUse)
            _buildToggleRow(
              toggleKey: Key('cloud-consent-toggle-$id'),
              label: 'Cloud processing',
              explanation:
                  'On sends short pieces of your child\'s speech to a server '
                  'to be recognised. Off keeps all listening on this device.',
              value: _profile.cloudAsrConsent,
              onChanged: _setCloudConsent,
            ),
        ],
      ),
    );
  }

  Widget _buildToggleRow({
    required Key toggleKey,
    required String label,
    required String explanation,
    required bool value,
    required Future<void> Function(bool value) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingXs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(label, style: _labelStyle),
                Text(explanation, style: _explanationStyle),
              ],
            ),
          ),
          const SizedBox(width: DesignTokens.spacingSm),
          Switch(
            key: toggleKey,
            value: value,
            activeColor: DesignTokens.wordReadGreen,
            onChanged: (next) => onChanged(next),
          ),
        ],
      ),
    );
  }

  static const TextStyle _titleStyle = TextStyle(
    color: DesignTokens.wordUnreadInk,
    fontFamily: DesignTokens.displayFontFamily,
    fontSize: 18.0,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle _labelStyle = TextStyle(
    color: DesignTokens.wordUnreadInk,
    fontFamily: DesignTokens.readingFontFamily,
    fontSize: 16.0,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle _explanationStyle = TextStyle(
    color: DesignTokens.wordUnreadInk,
    fontFamily: DesignTokens.readingFontFamily,
    fontSize: 13.0,
  );
}

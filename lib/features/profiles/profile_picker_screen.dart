/// The child-facing profile picker shown at launch (PRD §8 Unit 10:
/// "Up to 4 local profiles; child-facing profile picker at launch
/// (icon/avatar based, no reading required)").
///
/// This screen navigates by icon alone. Names are drawn beneath each avatar
/// for the adult standing behind the child, but nothing about selection
/// requires reading them: the tappable target is the whole tile, and the
/// identity cue is [ProfileAvatar]'s deterministic icon.
///
/// The screen is deliberately dumb — it renders the `profiles` it is given,
/// in the order given, and reports selections upward. The
/// `kMaxProfilesPerDevice` cap is enforced upstream (`ProfilesDao`
/// throws `MaxProfilesExceededException` on the 5th create), so in real use
/// this list is never longer than four; nothing here depends on that.
library;

import 'package:flutter/material.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/features/profiles/profile_avatar.dart';

/// The launch screen: one tappable, icon-first tile per local profile.
class ProfilePickerScreen extends StatelessWidget {
  /// Creates a picker over [profiles].
  const ProfilePickerScreen({
    super.key,
    required this.profiles,
    required this.onProfileSelected,
    this.onVoicePrompt,
  });

  /// The profiles to render, in list order. Never more than
  /// [kMaxProfilesPerDevice] in real use.
  final List<Profile> profiles;

  /// Fired when a tile is tapped.
  ///
  /// `profileOrdinal` is the tapped profile's **1-based** position within
  /// [profiles] — exactly the `profileOrdinal` input
  /// `SessionTracker.startSession` needs (PRD §5 "profile ordinal (1-4)").
  /// Selecting a profile is what enters that child's home (map) and starts
  /// their session; this widget owns neither of those, it only reports the
  /// selection.
  final void Function(Profile profile, int profileOrdinal) onProfileSelected;

  /// Optional voice-prompt hook, fired on tap **before** [onProfileSelected].
  ///
  /// This is the seam the (later, owner-recorded) navigation audio hangs off:
  /// a non-reading child hears "Ada!" as they tap. The audio refs themselves
  /// are owner-recorded content and are not part of this unit — hence a
  /// nullable hook rather than an audio dependency.
  final void Function(Profile profile)? onVoicePrompt;

  /// Width of a single profile tile, in logical pixels. Four tiles plus
  /// spacing fit a phone-portrait width without wrapping.
  static const double _tileWidth = 140.0;

  /// Height of a single profile tile, in logical pixels.
  static const double _tileHeight = 160.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: DesignTokens.screenBackground,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(DesignTokens.spacingLg),
            child: Wrap(
              alignment: WrapAlignment.center,
              runAlignment: WrapAlignment.center,
              spacing: DesignTokens.spacingMd,
              runSpacing: DesignTokens.spacingMd,
              children: <Widget>[
                for (var index = 0; index < profiles.length; index++)
                  _buildTile(profiles[index], index + 1),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Builds one profile tile. [ordinal] is the 1-based position reported to
  /// [onProfileSelected].
  Widget _buildTile(Profile profile, int ordinal) {
    return GestureDetector(
      key: Key('profile-picker-tile-${profile.localId}'),
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // Voice prompt first, selection second: the child should hear the
        // name as the screen changes, not after it has already changed.
        onVoicePrompt?.call(profile);
        onProfileSelected(profile, ordinal);
      },
      child: SizedBox(
        width: _tileWidth,
        height: _tileHeight,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ProfileAvatar(
              key: Key('profile-avatar-${profile.localId}'),
              profile: profile,
            ),
            const SizedBox(height: DesignTokens.spacingSm),
            Text(
              profile.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: DesignTokens.wordUnreadInk,
                fontFamily: DesignTokens.displayFontFamily,
                fontSize: 18.0,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

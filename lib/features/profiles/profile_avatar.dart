/// The icon-first identity mark for a device-local child profile
/// (PRD §8 Unit 10: "child-facing profile picker at launch (icon/avatar
/// based, no reading required)").
///
/// A pre-reader identifies their own profile by *shape and colour*, never by
/// reading the name, so every avatar renders a concrete [Icon] chosen
/// deterministically from the profile's `localId`. The mapping itself is a
/// builder decision (not PRD-pinned); only its determinism is load-bearing:
/// the same profile must always draw the same icon, on every launch and
/// every device, or the child loses the one cue they can use.
///
/// Real illustrated avatars are owner-commissioned artwork (PRD §10 OQ-4);
/// this widget paints a token-styled placeholder until they arrive.
library;

import 'package:flutter/material.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/user_models.dart';

/// A round, icon-first avatar for [profile].
///
/// Renders an [Icon] descendant chosen deterministically from
/// `profile.localId` (see [iconFor]) inside a token-styled disc. No text is
/// drawn: identification must not require reading.
class ProfileAvatar extends StatelessWidget {
  /// Creates an avatar for [profile], [size] logical pixels across.
  const ProfileAvatar({
    super.key,
    required this.profile,
    this.size = defaultSize,
  });

  /// Default avatar diameter, in logical pixels: large enough to be a
  /// comfortable child-sized touch target inside a picker tile.
  static const double defaultSize = 88.0;

  /// The profile this avatar identifies.
  final Profile profile;

  /// Diameter of the avatar disc, in logical pixels.
  final double size;

  /// The icon palette, in a fixed order. Deliberately concrete, high-contrast
  /// silhouettes (animals, plants, vehicles) rather than abstract shapes: a
  /// four-year-old can say "I'm the rocket" but not "I'm the blue hexagon".
  static const List<IconData> _icons = <IconData>[
    Icons.pets,
    Icons.rocket_launch,
    Icons.local_florist,
    Icons.star,
    Icons.sailing,
    Icons.cake,
    Icons.emoji_nature,
    Icons.music_note,
  ];

  /// Ink palette for the avatar, drawn from [DesignTokens] only.
  static const List<Color> _inks = <Color>[
    DesignTokens.wordUnreadInk,
    DesignTokens.wordReadGreen,
    DesignTokens.wordVocabBlue,
  ];

  /// A stable, platform-independent hash of [id].
  ///
  /// Dart's own `String.hashCode` is not guaranteed stable across runs or
  /// releases, which would let a child's avatar silently change between app
  /// launches. This small FNV-style fold is fully specified here instead.
  static int _stableHash(String id) {
    var hash = 17;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) % 1000003;
    }
    return hash;
  }

  /// The icon [profile] always draws, derived from its `localId`.
  static IconData iconFor(Profile profile) =>
      _icons[_stableHash(profile.localId) % _icons.length];

  /// The ink colour [profile] always draws in, derived from its `localId`.
  static Color inkFor(Profile profile) =>
      _inks[_stableHash(profile.localId) % _inks.length];

  @override
  Widget build(BuildContext context) {
    final ink = inkFor(profile);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: DesignTokens.surfaceBackground,
        shape: BoxShape.circle,
        border: Border.all(color: ink, width: 3.0),
      ),
      child: Icon(
        iconFor(profile),
        size: size / 2,
        color: ink,
        semanticLabel: profile.displayName,
      ),
    );
  }
}

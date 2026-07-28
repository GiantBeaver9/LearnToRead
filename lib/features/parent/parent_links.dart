/// The parent corner's link list: privacy policy, licenses, contact
/// (PRD §8 Unit 10 pinned contents; ticket accept entry 8: "Links present:
/// privacy policy, licenses, contact (destinations owner-supplied —
/// placeholder targets flagged)").
///
/// **OQ-7 status:** the real destinations are owner-supplied and are *not*
/// known at build time. [kParentLinkPlaceholderUrls] holds obviously-fake
/// `.invalid` targets so the surface is complete and testable; supplying the
/// real URLs is a one-map edit and blocks *pilot distribution*, not the
/// build.
///
/// This widget deliberately does not open anything itself. It reports taps
/// through [ParentLinks.onLinkTap] and leaves URL launching to the host app,
/// which keeps the whole unit headlessly testable (no `url_launcher`
/// platform channel) and keeps the placeholder URLs from ever being
/// navigated to by accident.
library;

import 'package:flutter/material.dart';
import 'package:learn_to_read/design/tokens.dart';

/// The three — and only three — links the v1 parent corner exposes.
enum ParentLinkKind {
  /// The app's privacy policy.
  privacyPolicy,

  /// Third-party open-source licenses.
  licenses,

  /// How to reach the app's owner.
  contact,
}

/// Placeholder link destinations, pending owner-supplied URLs (PRD §10 OQ-7).
///
/// Every value is under `.invalid` — a reserved TLD that can never resolve —
/// so a placeholder that escapes into a build is inert and obvious rather
/// than silently pointing somewhere wrong.
const Map<ParentLinkKind, String> kParentLinkPlaceholderUrls =
    <ParentLinkKind, String>{
      ParentLinkKind.privacyPolicy:
          'https://placeholder.invalid/learn-to-read/privacy-policy',
      ParentLinkKind.licenses:
          'https://placeholder.invalid/learn-to-read/licenses',
      ParentLinkKind.contact: 'mailto:placeholder@placeholder.invalid',
    };

/// Plain-language row labels, one per [ParentLinkKind].
const Map<ParentLinkKind, String> _kLinkLabels = <ParentLinkKind, String>{
  ParentLinkKind.privacyPolicy: 'Privacy policy',
  ParentLinkKind.licenses: 'Licenses',
  ParentLinkKind.contact: 'Contact us',
};

/// One tappable row per [ParentLinkKind].
class ParentLinks extends StatelessWidget {
  /// Creates the parent corner's link list.
  const ParentLinks({super.key, this.onLinkTap});

  /// Fired when a link row is tapped, with the row's kind and its currently
  /// configured URL (a placeholder until OQ-7 is answered).
  final void Function(ParentLinkKind kind, String url)? onLinkTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (final kind in ParentLinkKind.values) _buildRow(kind),
        const Padding(
          padding: EdgeInsets.only(top: DesignTokens.spacingSm),
          child: Text(
            'Link destinations are placeholders until supplied.',
            style: TextStyle(
              color: DesignTokens.wordUnreadInk,
              fontFamily: DesignTokens.readingFontFamily,
              fontSize: 12.0,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRow(ParentLinkKind kind) {
    final url = kParentLinkPlaceholderUrls[kind]!;
    return GestureDetector(
      key: Key('parent-link-${kind.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => onLinkTap?.call(kind, url),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          vertical: DesignTokens.spacingSm,
        ),
        child: Row(
          children: <Widget>[
            const Icon(
              Icons.open_in_new,
              size: 18.0,
              color: DesignTokens.wordUnreadInk,
            ),
            const SizedBox(width: DesignTokens.spacingSm),
            Expanded(
              child: Text(
                _kLinkLabels[kind]!,
                style: const TextStyle(
                  color: DesignTokens.wordUnreadInk,
                  fontFamily: DesignTokens.readingFontFamily,
                  fontSize: 16.0,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The pilot progress view: one plain screen per child (PRD §8 Unit 10:
/// "Pilot progress view: one plain screen per child — stories completed and
/// the words that needed help (from WordHelpRecord, with help tier). No
/// charts or trends; exists so pilot parents can report concretely").
///
/// The absence of charts is a *product* decision, not an omission. This
/// screen exists so a pilot parent can say "she finished three stories and
/// got stuck on 'elephant'" — a concrete, reportable sentence. A trend line
/// would invite comparison and gamified reading of a two-week pilot's noise,
/// which PRD §8 Unit 9 rules out ("No global/comparative elements").
///
/// The view is pure presentation over caller-supplied lists: it does its own
/// filtering (completed stories; words with `helpCount > 0`) so callers never
/// have to know the filter rules, and so a caller passing raw DAO output —
/// including encounters-only rows — is a supported case rather than a crash.
library;

import 'package:flutter/material.dart';
import 'package:learn_to_read/design/tokens.dart';
import 'package:learn_to_read/domain/models/user_models.dart';

/// Exact tier labels for a helped word, one per [HelpLevel] tier that can
/// actually reach a row (PRD §8 Unit 6 tiers).
///
/// [HelpLevel.none] is absent by construction: a row only lists when
/// `helpCount > 0`, and a word that has been helped always carries the tier
/// of its most recent help.
const Map<HelpLevel, String> kHelpTierLabels = <HelpLevel, String>{
  HelpLevel.soundOut: 'Sound-out help',
  HelpLevel.modeled: 'Modeled help',
};

/// One plain, chart-free progress screen for a single child.
class PilotProgressView extends StatelessWidget {
  /// Creates the progress view for [profile].
  const PilotProgressView({
    super.key,
    required this.profile,
    required this.storyProgress,
    required this.wordHelpRecords,
  });

  /// The child this view reports on. Strictly one child per view — there is
  /// no cross-profile or comparative surface anywhere in the app.
  final Profile profile;

  /// This child's story progress, in any status. Filtered here down to
  /// [StoryStatus.completed] for display.
  final List<StoryProgress> storyProgress;

  /// This child's word help records, in any encounter/help state. Filtered
  /// here down to `helpCount > 0`: a word that was merely *encountered* never
  /// needed help and does not belong on a "words that needed help" list.
  final List<WordHelpRecord> wordHelpRecords;

  @override
  Widget build(BuildContext context) {
    final completed = <StoryProgress>[
      for (final progress in storyProgress)
        if (progress.status == StoryStatus.completed) progress,
    ];
    final helped = <WordHelpRecord>[
      for (final record in wordHelpRecords)
        if (record.helpCount > 0) record,
    ];

    return Container(
      key: const Key('pilot-progress-view'),
      color: DesignTokens.screenBackground,
      padding: const EdgeInsets.all(DesignTokens.spacingMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(profile.displayName, style: _titleStyle),
          const SizedBox(height: DesignTokens.spacingMd),
          const Text('Stories finished', style: _headingStyle),
          Column(
            key: const Key('completed-stories-list'),
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (completed.isEmpty)
                const Text('No stories finished yet.', style: _emptyStyle)
              else
                for (final progress in completed) _buildStoryRow(progress),
            ],
          ),
          const SizedBox(height: DesignTokens.spacingMd),
          const Text('Words that needed help', style: _headingStyle),
          Column(
            key: const Key('helped-words-list'),
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (helped.isEmpty)
                const Text('No words needed help yet.', style: _emptyStyle)
              else
                for (final record in helped) _buildHelpedWordRow(record),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStoryRow(StoryProgress progress) {
    return Padding(
      key: Key('completed-story-${progress.storyId}'),
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingXs),
      child: Row(
        children: <Widget>[
          const Icon(
            Icons.check,
            size: 16.0,
            color: DesignTokens.wordReadGreen,
          ),
          const SizedBox(width: DesignTokens.spacingSm),
          Expanded(child: Text(progress.storyId, style: _bodyStyle)),
        ],
      ),
    );
  }

  Widget _buildHelpedWordRow(WordHelpRecord record) {
    return Padding(
      key: Key('helped-word-${record.wordText}'),
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.spacingXs),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(record.wordText, style: _bodyStyle)),
          const SizedBox(width: DesignTokens.spacingSm),
          Text(
            kHelpTierLabels[record.lastHelpLevel] ?? '',
            style: _tierStyle,
          ),
        ],
      ),
    );
  }

  static const TextStyle _titleStyle = TextStyle(
    color: DesignTokens.wordUnreadInk,
    fontFamily: DesignTokens.displayFontFamily,
    fontSize: 20.0,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle _headingStyle = TextStyle(
    color: DesignTokens.wordUnreadInk,
    fontFamily: DesignTokens.displayFontFamily,
    fontSize: 16.0,
    fontWeight: FontWeight.bold,
  );

  static const TextStyle _bodyStyle = TextStyle(
    color: DesignTokens.wordUnreadInk,
    fontFamily: DesignTokens.readingFontFamily,
    fontSize: 15.0,
  );

  static const TextStyle _tierStyle = TextStyle(
    color: DesignTokens.wordUnreadInk,
    fontFamily: DesignTokens.readingFontFamily,
    fontSize: 13.0,
  );

  static const TextStyle _emptyStyle = TextStyle(
    color: DesignTokens.wordUnreadInk,
    fontFamily: DesignTokens.readingFontFamily,
    fontSize: 14.0,
    fontStyle: FontStyle.italic,
  );
}

/// The analytics event vocabulary (PRD §5 "Analytics events", §8 Unit 12).
///
/// This file is deliberately tiny and dependency-free: it is the single
/// source of truth for *which* events exist and for the closed value sets
/// they carry on the wire. Adding an event here without adding it to the
/// §5 list (or vice versa) breaks `event_schema_test.dart`, which asserts
/// the set is exactly the §5 set — "no more" is an acceptance criterion,
/// not a style preference.
library;

/// The exact §5 event set. Twelve events, no more, no fewer.
///
/// Wire names are snake_case and are the only strings that ever appear in
/// a payload's `event` field; the Dart identifiers are free to be
/// lowerCamelCase without leaking that spelling onto the wire.
enum AnalyticsEventName {
  /// A reading session began (fires at profile selection — see
  /// `SessionTracker`).
  sessionStart('session_start'),

  /// A story was opened on the reading screen.
  storyStarted('story_started'),

  /// One word was attempted; carries `result` and the A-14 `wordHash`.
  wordRead('word_read'),

  /// A help tier fired for a stuck word; carries `tier`.
  helpGiven('help_given'),

  /// A story was read to the end.
  storyCompleted('story_completed'),

  /// The reading screen was left mid-story (including via session end);
  /// carries `helpInLast30s`, the §4.4 frustration marker.
  storyAbandoned('story_abandoned'),

  /// A blue vocab word's card was opened.
  vocabCardOpened('vocab_card_opened'),

  /// A collectible was awarded.
  collectibleEarned('collectible_earned'),

  /// A tongue twister was started.
  twisterStarted('twister_started'),

  /// A tongue twister was completed.
  twisterCompleted('twister_completed'),

  /// A Sound Garden card played its sound (Unit 15).
  soundCardPlayed('sound_card_played'),

  /// A Sound Garden echo attempt was scored; carries `matched` (Unit 15).
  soundCardEcho('sound_card_echo');

  const AnalyticsEventName(this.wireName);

  /// The snake_case string written to the payload's `event` field.
  final String wireName;
}

/// The three outcomes of a `word_read` event (PRD §5: "correct/near_miss/
/// helped — near-miss acceptances are deliberately distinguishable so
/// pilot data shows where 'close enough' is doing the work").
enum WordReadResult {
  /// An exact match.
  correct('correct'),

  /// A close-enough (phonetically near) acceptance — deliberately *not*
  /// counted as "help needed" by the §4.3 learning signal.
  nearMiss('near_miss'),

  /// The word was only read after help was given.
  helped('helped');

  const WordReadResult(this.wireValue);

  /// The string written to the payload's `result` field.
  final String wireValue;
}

/// The help tier carried by a `help_given` event.
///
/// There is deliberately no `none` tier: `help_given` only fires when help
/// was actually given, so a "no help" tier would be unrepresentable state.
enum HelpTier {
  /// Tier 1: sound-out highlighting.
  soundOut('sound_out'),

  /// Tier 2: the word is modeled aloud.
  modeled('modeled');

  const HelpTier(this.wireValue);

  /// The string written to the payload's `tier` field.
  final String wireValue;
}

/// Looks up an [AnalyticsEventName] by its wire string, or returns null if
/// the string is not one of the §5 events.
AnalyticsEventName? analyticsEventNameFromWire(String wireName) {
  for (final name in AnalyticsEventName.values) {
    if (name.wireName == wireName) return name;
  }
  return null;
}

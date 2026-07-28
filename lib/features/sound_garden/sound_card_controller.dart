/// Pure derivation + playback logic for one Sound Garden card (PRD §8 Unit
/// 15 "Visibility (ratified)"; ticket sound-garden accept entries 2, 3).
///
/// This file owns two independent concerns that both operate on a single
/// [GraphemeSound]:
///  - [wakeStateFor]: the pure awake/muted derivation against a profile's
///    current level (no widget, no audio, no side effect);
///  - [playSoundCard]: plays the card's phoneme audio in order, gaplessly.
///
/// Nothing here renders a widget (see `sound_card.dart` for
/// `SoundCardWidget`) or drives the echo attempt (see `echo_session.dart`).
library;

import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/phoneme_sequencer.dart';

/// Whether a card is awake (matches the profile's reach) or muted (ahead of
/// it, but still fully present and interactive -- see `sound_card.dart`).
enum CardWakeState { awake, muted }

/// Resolves [levelId] against [levels] by `Level.id`, mirroring the idiom in
/// `lib/pipeline/cumulative_grapheme_set.dart` and
/// `lib/pipeline/decodability_linter.dart`. Throws [ArgumentError] when no
/// level in [levels] carries that id.
Level _resolveLevel(List<Level> levels, String levelId) {
  return levels.firstWhere(
    (level) => level.id == levelId,
    orElse: () => throw ArgumentError.value(
      levelId,
      'levelId',
      'does not match any Level.id in `levels`',
    ),
  );
}

/// Derives [card]'s wake state against [profile] (PRD §8 Unit 15
/// "Visibility (ratified)"): awake iff `card.introducedAtLevelId`'s ordinal
/// is <= `profile.currentLevelId`'s ordinal -- an INCLUSIVE boundary, so a
/// card introduced at exactly the profile's current level is awake, never
/// muted. Ordinals are resolved via [_resolveLevel]; an id absent from
/// [levels] throws [ArgumentError] rather than silently defaulting a wake
/// state.
///
/// A muted card is still fully present in the inventory -- callers render
/// it regardless (PRD: "ALL cards visible from day one") and it stays fully
/// tappable and echoable (see `sound_card.dart`'s pinned tap-gating
/// contrast against `MapNode`).
CardWakeState wakeStateFor({
  required GraphemeSound card,
  required Profile profile,
  required List<Level> levels,
}) {
  final cardLevel = _resolveLevel(levels, card.introducedAtLevelId);
  final profileLevel = _resolveLevel(levels, profile.currentLevelId);
  return cardLevel.ordinal <= profileLevel.ordinal ? CardWakeState.awake : CardWakeState.muted;
}

/// Plays [card]'s `phonemeIds` in order, gaplessly (PRD §8 Unit 15: "tap
/// plays the card's recorded phoneme audio -- the grapheme's phonemeIds in
/// order, gapless via PhonemeSequencer").
///
/// `GraphemeSound` carries no `WordToken` to hand [PhonemeSequencer]
/// directly, so this builds a minimal synthetic one on the fly purely to
/// reuse [PhonemeSequencer]'s pinned gapless-sequencing contract (each
/// phoneme's audio is awaited to its natural end before the next one's
/// `play()` is issued) rather than re-deriving it here. The synthetic
/// token's `text` / `pronunciationAudioRef` are never read by
/// [PhonemeSequencer] -- only `graphemePhonemeMap` drives playback.
///
/// A phoneme id absent from [phonemeAudioRefs], or a ref [audioService]
/// does not recognize, stops the sequence at the failing phoneme and
/// propagates the underlying exception ([PhonemeAudioNotFoundException] or
/// [AudioRefNotFoundException]) to the caller -- no phoneme after the
/// failure plays.
Future<void> playSoundCard(
  GraphemeSound card, {
  required AudioService audioService,
  required Map<String, AudioRef> phonemeAudioRefs,
  AudioChannel channel = AudioChannel.help,
}) async {
  final sequencer = PhonemeSequencer(audioService: audioService, phonemeAudioRefs: phonemeAudioRefs);
  final syntheticToken = WordToken(
    text: card.grapheme,
    graphemePhonemeMap: [
      for (final phonemeId in card.phonemeIds) (graphemes: card.grapheme, phonemeId: phonemeId),
    ],
    pronunciationAudioRef: '',
  );
  await sequencer.playSequence(syntheticToken, channel: channel).drain<void>();
}

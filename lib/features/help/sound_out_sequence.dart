/// Tier 1 "sound it out" adapter (PRD §8 Unit 6; ticket stuck-word-scaffold
/// accept entry 2).
///
/// Turns `PhonemeSequencer`'s playback events into the `HelpState` stream the
/// reading screen renders the grapheme highlight from, so Unit 6 owns
/// *producing* the highlight state and Unit 5's reading screen owns drawing
/// it.
library;

import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/domain/models/user_models.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';
import 'package:learn_to_read/features/audio/phoneme_sequencer.dart';
import 'package:learn_to_read/features/listening/contracts/help_state.dart';

/// Plays a word's phonemes (recorded human 44-phoneme set, via
/// [PhonemeSequencer]) and publishes one [HelpState] per played grapheme
/// cluster so the reading screen can highlight it while its phoneme sounds.
///
/// This is deliberately a *thin* adapter: it introduces no reordering,
/// filtering, batching, or timing of its own. Every guarantee the highlight
/// sequence has to make is already pinned on [PhonemeSequencer] and is
/// inherited verbatim here:
///  - events arrive in `WordToken.graphemePhonemeMap` order, so a digraph
///    ("sh" in "ship") is one entry and highlights as one unit, never s-h;
///  - entries with an empty `phonemeId` (silent letters, the "e" in "cake")
///    play no audio and produce no [HelpState] at all;
///  - `PhonemeAudioNotFoundException` / `AudioRefNotFoundException` surface as
///    stream errors and stop the sequence.
///
/// The returned stream closes exactly when the underlying phoneme sequence
/// finishes. `StuckWordController` uses that close as the "Tier 1 audio is
/// over" signal that starts the T2 wait, which is why nothing here inserts a
/// tail delay of its own.
class SoundOutSequence {
  /// Creates a sound-out sequence over [phonemeSequencer].
  SoundOutSequence({required this.phonemeSequencer});

  /// The merged Unit 13 sequencer that owns phoneme ordering and playback.
  final PhonemeSequencer phonemeSequencer;

  /// Sounds [word] out, emitting one
  /// `HelpState(currentHelpTier: HelpLevel.soundOut, highlightedGraphemeIndex: i)`
  /// as each `graphemePhonemeMap[i]` cluster's phoneme starts playing.
  ///
  /// [channel] defaults to [AudioChannel.help] — Tier 1's tag, so sound-out
  /// audio ducks ambient/celebration per the pinned `DuckingPolicy` — and is
  /// forwarded verbatim to [PhonemeSequencer.playSequence] for callers (e.g.
  /// Unit 15's Sound Garden) that want a different tag.
  Stream<HelpState> play(
    WordToken word, {
    AudioChannel channel = AudioChannel.help,
  }) {
    return phonemeSequencer
        .playSequence(word, channel: channel)
        .map(
          (started) => HelpState(
            currentHelpTier: HelpLevel.soundOut,
            highlightedGraphemeIndex: started.graphemeIndex,
          ),
        );
  }
}

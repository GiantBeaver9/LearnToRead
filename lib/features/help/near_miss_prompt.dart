/// The near-miss prompt path (PRD §8 Unit 6 "Near-miss prompt"; §8 Unit 4
/// near-miss acceptance; ticket stuck-word-scaffold accept entry 7).
library;

import 'package:learn_to_read/domain/models/content_models.dart';
import 'package:learn_to_read/features/audio/audio_service.dart';

/// The brief, warm model played after Unit 4 accepts a close-enough
/// production ("gat" for "cat").
///
/// Ratified behavior this type implements: the word **still turns green** —
/// the child is never told they were wrong — and the app follows with a short
/// two-clip model of the correct word, "that's it — *cat*!": a generic,
/// reusable prompt line ([promptLineAudioRef]) and then the word's own
/// recorded pronunciation (`WordToken.pronunciationAudioRef`). The child may
/// echo it but is not required to; reading continues immediately.
///
/// **"Never escalates" is structural here, not enforced.** This class has no
/// tier, no timer, and no state machine — there is nothing in it *to*
/// escalate. It is strictly lighter than Tier 1/2, and `StuckWordController`
/// resolves the word the moment it starts this prompt, so no T1/T2 timer for
/// that word can survive to fire.
///
/// Exact prompt copy and the recorded lines are authored content (Unit 3);
/// this type only ever receives an opaque [AudioRef].
///
/// ## Dispatch order and completion
///
/// Both clips are dispatched to [audioService] in the same event-loop turn,
/// prompt line first and word second, and the returned future then waits for
/// both to finish, in that same order. Dispatching the pair up front (rather
/// than issuing the word's `play()` only after the prompt line's
/// `completionOf` resolves) is what keeps the near-miss path a single
/// fire-and-forget hand-off to the audio engine: the caller — which has
/// *already* moved reading on — never has to stay alive across clip
/// boundaries to get the second clip out. The prompt line is still played
/// first and awaited first; the returned future still does not complete until
/// both clips have ended, so callers that do want to sequence behind the
/// whole prompt can await it.
class NearMissPrompt {
  /// Creates a near-miss prompt playing [promptLineAudioRef] before each
  /// word's own pronunciation.
  NearMissPrompt({required this.audioService, required this.promptLineAudioRef});

  /// The audio seam every clip is played through.
  final AudioService audioService;

  /// The generic authored prompt line ("that's it —") that precedes the word.
  final AudioRef promptLineAudioRef;

  /// Plays the warm model for [word]: the prompt line, then [word]'s recorded
  /// pronunciation, both tagged [AudioChannel.help] so they duck ambient and
  /// celebration audio per the pinned `DuckingPolicy` exactly as Tier 1/2
  /// help audio does.
  ///
  /// Throws [AudioRefNotFoundException] if either ref is missing from the
  /// shipped pack; a missing prompt line means the word pronunciation is
  /// never dispatched at all.
  Future<void> play(WordToken word) async {
    final promptHandle = await audioService.play(
      promptLineAudioRef,
      channel: AudioChannel.help,
    );
    final wordHandle = await audioService.play(
      word.pronunciationAudioRef,
      channel: AudioChannel.help,
    );
    await audioService.completionOf(promptHandle);
    await audioService.completionOf(wordHandle);
  }
}

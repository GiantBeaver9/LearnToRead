import 'audio_service.dart';

/// The pinned ducking rule (PRD §8 Unit 13 "ducking rules (help audio ducks
/// ambient/celebration audio; nothing ducks the microphone processing)";
/// ticket audio-playback accept entry 3).
///
/// Pure and stateless: given only the [AudioChannel] that started playing,
/// it answers which other channels that implies should be ducked. There is
/// deliberately no parameter, field, or method anywhere on this type that
/// references a microphone, an ASR engine, or a "listening" state -- that
/// omission is itself the proof that this policy cannot reach the mic
/// pipeline (nothing here could even be asked to). `AudioChannel` (see
/// `audio_service.dart`) has exactly four values for the same reason: there
/// is no channel to name the mic with.
class DuckingPolicy {
  const DuckingPolicy();

  /// The set of channels that should be ducked while [playingChannel] is
  /// active. Only [AudioChannel.help] ducks anything, and only
  /// [AudioChannel.ambient] and [AudioChannel.celebration] -- narration is
  /// never ducked, and no channel other than help ducks anything at all.
  Set<AudioChannel> channelsDuckedBy(AudioChannel playingChannel) {
    switch (playingChannel) {
      case AudioChannel.help:
        return const {AudioChannel.ambient, AudioChannel.celebration};
      case AudioChannel.narration:
      case AudioChannel.celebration:
      case AudioChannel.ambient:
        return const {};
    }
  }

  /// Whether [candidate] should be ducked while [active] is playing.
  /// Directional/non-symmetric (e.g. ambient playing never ducks help) and
  /// never true for a channel against itself.
  bool shouldDuck({required AudioChannel active, required AudioChannel candidate}) {
    return channelsDuckedBy(active).contains(candidate);
  }
}

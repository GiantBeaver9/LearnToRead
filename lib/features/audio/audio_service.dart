/// Audio playback contract (PRD §8 Unit 13 "Audio system & voice pipeline";
/// ticket audio-playback accept entries 1 and 4).
///
/// `AudioService` is the single seam every feature plays audio through: an
/// opaque, source-agnostic [AudioRef] in, a [PlaybackHandle] out. Nothing on
/// this contract ever takes text, a locale, or a voice: v1 audio is entirely
/// human-recorded and shipped with packs (PRD §8 Unit 13, OQ-3); a future
/// TTS generation step is a source that produces the same kind of opaque ref,
/// not a change to this API (pinned_design, ticket audio-playback).
///
/// Channel tagging ([AudioChannel]) is how ducking is decided
/// (`ducking_policy.dart`) -- it is not a mixer/volume API. There is
/// deliberately no channel or method here that can reach the microphone /
/// ASR pipeline; see `ducking_policy.dart`'s header for the "asserted by API
/// absence" half of that guarantee.
library;

/// An opaque reference to a shipped audio asset (a pack-relative path today;
/// any string the audio pipeline can resolve tomorrow, including a future
/// TTS-generated clip id). `AudioService` never inspects or generates one --
/// it only plays what it is given.
typedef AudioRef = String;

/// The audio channels ducking rules and playback tagging operate over
/// (PRD §8 Unit 13 "ducking rules"). Exactly these four values, forever:
/// there is deliberately no fifth "mic"/"listening" value, which is the
/// compile-time proof that nothing here can duck microphone processing
/// (see `ducking_policy.dart`).
enum AudioChannel {
  /// Tiered help / sound-out audio (Unit 6). The only channel that ducks
  /// anything.
  help,

  /// Sentence and story narration read-alouds.
  narration,

  /// Celebration stingers/lines (Unit 8).
  celebration,

  /// Background/ambient loops.
  ambient,
}

/// An identifier for one in-flight (or since-finished) `play()` call.
/// Opaque outside this file's package other than its `id`, which callers may
/// use for logging/equality but should otherwise treat as a token.
class PlaybackHandle {
  const PlaybackHandle(this.id);

  final int id;

  @override
  bool operator ==(Object other) => other is PlaybackHandle && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'PlaybackHandle($id)';
}

/// Thrown by `AudioService.play` when [ref] does not resolve to a shipped
/// audio asset. This is a content/pack integrity bug (a missing shipped
/// ref), not a runtime generation fallback -- there is no TTS fallback path.
class AudioRefNotFoundException implements Exception {
  AudioRefNotFoundException(this.ref);

  final AudioRef ref;

  @override
  String toString() => 'AudioRefNotFoundException: no shipped audio for ref "$ref"';
}

/// The seam every feature plays audio through. Implementations: the
/// just_audio-backed adapter (device/real), and `FakeAudioService` (tests --
/// every downstream ticket exercises audio behavior headlessly against it).
abstract class AudioService {
  /// Starts playback of [ref] tagged with [channel] (drives ducking; see
  /// `ducking_policy.dart`). Throws [AudioRefNotFoundException] if [ref]
  /// does not resolve to a shipped asset.
  Future<PlaybackHandle> play(AudioRef ref, {required AudioChannel channel});

  /// Stops playback for [handle]. A safe no-op for an unknown or
  /// already-finished handle.
  Future<void> stop(PlaybackHandle handle);

  /// Resolves when [handle]'s playback ends, whether by [stop] or by the
  /// clip reaching its natural end. Resolves immediately for an unknown
  /// handle rather than hanging forever.
  Future<void> completionOf(PlaybackHandle handle);
}

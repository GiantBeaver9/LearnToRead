/// Listen-first sentence narration (PRD §8 Unit 5, §9 A-11 ratified;
/// ticket reading-screen accept entry 3).
///
/// At `Level.narrationEnabled` levels, opening a story plays the recorded
/// human read-aloud of the sentence once BEFORE listening begins, and an
/// ear-icon button replays it at any time, suspending recognition while it
/// plays. There is deliberately no per-word karaoke highlighting in v1
/// (A-11): narration playback never touches word state, which is why this
/// controller knows nothing about words at all.
///
/// It talks to two seams and nothing else: [AudioService] for playback, and
/// two callbacks for the microphone session, so it never needs the tracker
/// itself.
library;

import 'package:flutter/foundation.dart' show VoidCallback;

import 'package:learn_to_read/features/audio/audio_service.dart';

/// Plays and replays the recorded sentence narration.
class NarrationController {
  /// Creates a controller playing through [audioService].
  ///
  /// [pauseListening] and [resumeListening] bracket a replay so recognition
  /// never hears the recording; they are intentionally NOT used by
  /// [playInitial], where listening has not started yet.
  NarrationController({
    required AudioService audioService,
    required VoidCallback pauseListening,
    required VoidCallback resumeListening,
  })  : _audioService = audioService,
        _pauseListening = pauseListening,
        _resumeListening = resumeListening;

  final AudioService _audioService;
  final VoidCallback _pauseListening;
  final VoidCallback _resumeListening;

  bool _isPlaying = false;

  /// Whether a narration clip is playing right now.
  bool get isPlaying => _isPlaying;

  /// Plays [ref] once on the listen-first path and completes only when the
  /// clip has finished, so the caller can start listening immediately
  /// afterwards.
  ///
  /// Listening has not begun at this point, so nothing is paused or
  /// resumed.
  Future<void> playInitial(AudioRef ref) => _play(ref, bracketListening: false);

  /// Replays [ref] from the ear-icon button, suspending recognition for the
  /// duration.
  ///
  /// Listening always resumes afterwards, including when playback fails
  /// (a missing or unplayable clip is a content-integrity bug and must
  /// never strand a paused child).
  Future<void> replay(AudioRef ref) => _play(ref, bracketListening: true);

  Future<void> _play(AudioRef ref, {required bool bracketListening}) async {
    if (bracketListening) _pauseListening();
    _isPlaying = true;
    try {
      final handle = await _audioService.play(ref, channel: AudioChannel.narration);
      await _audioService.completionOf(handle);
    } catch (_) {
      // Deliberately swallowed: see the resume guarantee above. Nothing
      // about a missing clip is ever surfaced to the child.
    } finally {
      _isPlaying = false;
      if (bracketListening) _resumeListening();
    }
  }
}

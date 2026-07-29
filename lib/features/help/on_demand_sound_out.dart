/// On-demand "sound it out" for ANY word (owner direction 2026-07-29:
/// "sounding out the phonics of everything").
///
/// Tier 1 sounds out only the word the child is stuck on, when the ladder
/// decides to. [OnDemandSoundOut] is the child-initiated counterpart: a
/// long-press on any word in the reading text — unread, current, green, or
/// vocab-purple — replays that word's grapheme-by-grapheme phoneme sequence
/// with the same highlight treatment Tier 1 uses, without touching the
/// Unit 6 help ladder or recording any help. A single grapheme chip's
/// phoneme can also be played on its own ([playGrapheme]) for the tappable
/// chips in the sound-out panels.
///
/// It talks to the same seams its neighbours do and nothing else:
/// [AudioService] plus the shipped phoneme-id -> [AudioRef] map (the same
/// pair `PhonemeSequencer` is built from), and the two listening callbacks
/// `NarrationController` uses for its replay bracket. It deliberately does
/// NOT drive `PhonemeSequencer.playSequence`: that stream's playback loop
/// runs to the end of the word once started, while an on-demand pass must
/// be stoppable *between phonemes* (a second long-press supersedes the
/// first). The loop here is the same gapless play -> highlight ->
/// completionOf walk, with a cancellation check at each step.
///
/// Pinned behavior:
///  - phonemes play gaplessly in `WordToken.graphemePhonemeMap` order on
///    [AudioChannel.help] (so sound-out ducking applies exactly as Tier 1's);
///    a digraph is one entry, so it highlights as one unit;
///  - entries with an empty `phonemeId` (silent letters) play no audio and
///    emit no highlight — and [playGrapheme] on one is a gentle no-op;
///  - passes never overlap: a new [play] stops the running one first;
///  - listening is paused for the duration of a pass and ALWAYS resumed at
///    the end — including on cancellation, on a missing clip, and on any
///    audio error (the same swallow-and-resume posture as
///    `NarrationController.replay`); nothing here can strand a paused child.
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show VoidCallback;

import 'package:learn_to_read/domain/models/content_models.dart' show WordToken;
import 'package:learn_to_read/features/audio/audio_service.dart';

/// One highlight tick of an on-demand sound-out: `graphemePhonemeMap`
/// entry [graphemeIndex] of the page word at [wordIndex] is sounding now.
/// The highlight stream emits `null` when the pass ends and the panel
/// should clear.
typedef OnDemandGrapheme = ({int wordIndex, int graphemeIndex});

/// Plays one word's phoneme sequence on demand, publishing grapheme
/// highlight ticks, bracketed by pause/resume of recognition.
class OnDemandSoundOut {
  /// Wires the controller to its seams.
  ///
  /// [pauseListening] / [resumeListening] bracket every pass so recognition
  /// never hears the phoneme clips — the same two callbacks
  /// `NarrationController` takes for its ear-icon replay.
  OnDemandSoundOut({
    required this.audioService,
    required this.phonemeAudioRefs,
    required this.pauseListening,
    required this.resumeListening,
  });

  /// The single audio seam every clip is played through.
  final AudioService audioService;

  /// Phoneme id -> shipped clip ref (the same map `PhonemeSequencer` and
  /// the flashcards screen use).
  final Map<String, AudioRef> phonemeAudioRefs;

  /// Suspends recognition for the duration of a pass.
  final VoidCallback pauseListening;

  /// Resumes recognition; guaranteed to be called once per pause.
  final VoidCallback resumeListening;

  final StreamController<OnDemandGrapheme?> _highlights =
      StreamController<OnDemandGrapheme?>.broadcast();

  _Pass? _pass;
  bool _disposed = false;

  /// The grapheme currently sounding, or `null` when no pass is running
  /// (emitted once as each pass ends, so the view can clear its panel).
  Stream<OnDemandGrapheme?> get highlights => _highlights.stream;

  /// Whether a sound-out pass is running right now.
  bool get isPlaying => _pass != null;

  /// Runs one sound-out pass for [word] (rendered at page index
  /// [wordIndex]) and completes when the pass has fully ended — finished,
  /// superseded, or [cancel]led — with listening resumed.
  ///
  /// A pass already running is stopped first; the pause/resume bracket
  /// spans the whole overlap, so listening is paused exactly once and
  /// resumed exactly once however many passes chain.
  Future<void> play({required int wordIndex, required WordToken word}) async {
    if (_disposed) return;
    final pass = _Pass();
    final superseded = _pass;
    _pass = pass;
    if (superseded == null) {
      pauseListening();
    } else {
      // Never overlapping: the new request stops the old pass. Its own
      // `finally` sees itself superseded and leaves the bracket to us.
      _stopPass(superseded);
    }
    try {
      for (var g = 0;
          g < word.graphemePhonemeMap.length && !pass.cancelled;
          g++) {
        final phonemeId = word.graphemePhonemeMap[g].phonemeId;
        if (phonemeId.isEmpty) {
          continue; // Silent letter: no clip, no highlight tick.
        }
        final ref = phonemeAudioRefs[phonemeId];
        if (ref == null) {
          break; // Missing shipped clip: a content/pack bug — end quietly.
        }
        final handle = await audioService.play(ref, channel: AudioChannel.help);
        pass.handle = handle;
        if (pass.cancelled) {
          // Cancelled while the play call was in flight.
          unawaited(audioService.stop(handle));
          break;
        }
        _emit((wordIndex: wordIndex, graphemeIndex: g));
        await audioService.completionOf(handle);
      }
    } catch (_) {
      // Swallow-and-resume (NarrationController's posture): a missing or
      // unplayable clip must never surface to the child or leave listening
      // paused. The `finally` below still clears and resumes.
    } finally {
      if (identical(_pass, pass)) {
        _pass = null;
        _emit(null);
        if (!_disposed) resumeListening();
      }
    }
  }

  /// Plays exactly one grapheme cluster's phoneme clip — the tappable-chip
  /// path. No sequence, no highlight ticks, no listening bracket (chips
  /// only render inside a sound-out panel, where Tier 1 audio already
  /// plays over an open microphone).
  ///
  /// A silent letter (empty `phonemeId`), an out-of-range index, a missing
  /// clip, and an audio error are all gentle no-ops.
  Future<void> playGrapheme(WordToken word, int graphemeIndex) async {
    if (_disposed) return;
    if (graphemeIndex < 0 || graphemeIndex >= word.graphemePhonemeMap.length) {
      return;
    }
    final phonemeId = word.graphemePhonemeMap[graphemeIndex].phonemeId;
    if (phonemeId.isEmpty) {
      return; // Silent letter: nothing to hear, nothing happens.
    }
    final ref = phonemeAudioRefs[phonemeId];
    if (ref == null) {
      return; // Missing shipped clip: stay calm.
    }
    try {
      final handle = await audioService.play(ref, channel: AudioChannel.help);
      await audioService.completionOf(handle);
    } catch (_) {
      // Same swallow posture as the pass: never surfaced to the child.
    }
  }

  /// Stops the running pass, if any. The pass's own `finally` clears the
  /// highlight and resumes listening.
  void cancel() {
    final pass = _pass;
    if (pass == null) return;
    _stopPass(pass);
  }

  /// Cancels any running pass and closes [highlights]. Listening is NOT
  /// resumed on dispose — the owning screen is being torn down and owns
  /// its tracker's final state.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final pass = _pass;
    _pass = null;
    if (pass != null) _stopPass(pass);
    unawaited(_highlights.close());
  }

  void _stopPass(_Pass pass) {
    pass.cancelled = true;
    final handle = pass.handle;
    pass.handle = null;
    if (handle != null) {
      // Resolves the pass's pending completionOf, so its loop exits now.
      unawaited(audioService.stop(handle));
    }
  }

  void _emit(OnDemandGrapheme? tick) {
    if (!_highlights.isClosed) _highlights.add(tick);
  }
}

/// One pass's mutable state. Async continuations re-check
/// `identical(_pass, pass)` / `pass.cancelled` before acting, which is what
/// makes a superseded pass inert without unwinding in-flight futures (the
/// same pattern as `StuckWordController`'s `_WatchedWord`).
class _Pass {
  /// Set by [OnDemandSoundOut.cancel] / supersession; checked between
  /// every phoneme.
  bool cancelled = false;

  /// The clip playing right now, so cancellation can stop it mid-sound.
  PlaybackHandle? handle;
}

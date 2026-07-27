import 'dart:async';

import '../../domain/models/content_models.dart';
import 'audio_service.dart';

/// Emitted each time `PhonemeSequencer.playSequence` starts a phoneme's
/// audio: the reading screen's grapheme-highlight sync point (PRD §8 Unit 6
/// "highlighting each grapheme cluster ... using graphemePhonemeMap").
class PhonemeStarted {
  const PhonemeStarted({
    required this.graphemeIndex,
    required this.phonemeId,
    required this.handle,
  });

  /// Index into the source `WordToken.graphemePhonemeMap`.
  final int graphemeIndex;

  final String phonemeId;
  final PlaybackHandle handle;
}

/// Thrown (as a stream error) when a non-silent `graphemePhonemeMap` entry's
/// `phonemeId` has no entry in the sequencer's `phonemeAudioRefs` -- a
/// content/pack bug, not a runtime condition to recover from.
class PhonemeAudioNotFoundException implements Exception {
  PhonemeAudioNotFoundException(this.phonemeId);

  final String phonemeId;

  @override
  String toString() => 'PhonemeAudioNotFoundException: no audio ref for phoneme "$phonemeId"';
}

/// Plays a word's phoneme audio sequence ("kuh... aah... tuh") gaplessly, in
/// `WordToken.graphemePhonemeMap` order (PRD §8 Unit 13 "gapless sequential
/// phoneme playback"; Unit 6 sound-out; Unit 15 Sound Garden tap-to-hear;
/// ticket audio-playback accept entries 2 and 5).
///
/// Gapless here means queue construction, not wall-clock: the next
/// phoneme's `play()` is issued as soon as the previous one's
/// `AudioService.completionOf` resolves, with no delay inserted by this
/// class. The first `play()` call is issued synchronously, in the same
/// event-loop turn as `playSequence` itself, so callers can rely on
/// "instant" dispatch to the audio engine (the headless proxy for the
/// <150ms on-device latency acceptance, which is owner-measured).
class PhonemeSequencer {
  PhonemeSequencer({required this.audioService, required this.phonemeAudioRefs});

  final AudioService audioService;
  final Map<String, AudioRef> phonemeAudioRefs;

  /// Plays [word]'s phonemes in `graphemePhonemeMap` order, tagged with
  /// [channel] (defaults to [AudioChannel.help], Unit 6's Tier 1 sound-out;
  /// callers such as Unit 15's Sound Garden may override it). Entries with
  /// an empty `phonemeId` (silent letters, e.g. the "e" in "cake") are
  /// skipped: no audio, no [PhonemeStarted] event.
  ///
  /// The returned stream emits one [PhonemeStarted] per played phoneme and
  /// then closes. It emits a [PhonemeAudioNotFoundException] and closes if a
  /// phoneme has no entry in [phonemeAudioRefs]; an [AudioRefNotFoundException]
  /// from [audioService] propagates the same way. Either error stops the
  /// sequence -- no further phonemes play after a failure.
  Stream<PhonemeStarted> playSequence(WordToken word, {AudioChannel channel = AudioChannel.help}) {
    final controller = StreamController<PhonemeStarted>();
    controller.onListen = () {
      unawaited(_run(word, channel, controller));
    };
    return controller.stream;
  }

  Future<void> _run(
    WordToken word,
    AudioChannel channel,
    StreamController<PhonemeStarted> controller,
  ) async {
    try {
      for (var i = 0; i < word.graphemePhonemeMap.length; i++) {
        final phonemeId = word.graphemePhonemeMap[i].phonemeId;
        if (phonemeId.isEmpty) {
          continue; // Silent letter: valid index, no audio.
        }

        final ref = phonemeAudioRefs[phonemeId];
        if (ref == null) {
          throw PhonemeAudioNotFoundException(phonemeId);
        }

        final handle = await audioService.play(ref, channel: channel);
        controller.add(PhonemeStarted(graphemeIndex: i, phonemeId: phonemeId, handle: handle));
        await audioService.completionOf(handle);
      }
    } catch (e) {
      controller.addError(e);
    } finally {
      await controller.close();
    }
  }
}

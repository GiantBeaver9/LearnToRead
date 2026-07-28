# Audio playback (Unit 13, app half)

## Overview

The audio system is the single seam every feature plays sound through:
`AudioService` takes an opaque, source-agnostic ref and a channel tag, and
returns a handle. All v1 voice audio is human-recorded, supplied by the
product owner, and shipped inside packs (PRD §8 Unit 13, OQ-3) — nothing is
generated at runtime, and there is no text/locale/voice parameter anywhere
on this API (asserted by API shape, ticket audio-playback accept 4). A
future TTS step is just a different source for the same kind of opaque ref
and needs no app changes.

This ticket delivers interface + pure logic + fake, fully headless: no real
audio files exist in the container, and the just_audio-backed real adapter
(pinned by A-17: `just_audio` + `audio_session`) is out of this ticket's file
list — it is a thin `AudioService` implementation built and owner-verified
on device by a later integration step, not exercised by this test suite.

## Files

### `lib/features/audio/audio_service.dart`

The `AudioService` contract every feature plays audio through.

- `typedef AudioRef = String` — an opaque reference to a shipped audio asset
  (a pack-relative path today; any string the pipeline can resolve
  tomorrow, including a future TTS clip id).
- `enum AudioChannel { help, narration, celebration, ambient }` — exactly
  four values, forever. Drives ducking (`ducking_policy.dart`); not a
  mixer/volume API. There is deliberately no mic/listening value.
- `PlaybackHandle` — an opaque, value-equal (`==`/`hashCode` on `id`) token
  identifying one `play()` call.
- `AudioRefNotFoundException` — thrown by `play()` when `ref` does not
  resolve to a shipped asset (a content/pack bug, not a runtime fallback).
- `abstract class AudioService`:
  - `Future<PlaybackHandle> play(AudioRef ref, {required AudioChannel channel})`
  - `Future<void> stop(PlaybackHandle handle)` — safe no-op for an unknown
    or already-finished handle.
  - `Future<void> completionOf(PlaybackHandle handle)` — resolves on stop
    or natural end; resolves immediately (never hangs) for an unknown
    handle.

### `lib/features/audio/ducking_policy.dart`

`DuckingPolicy` — pure, stateless, pinned rule (PRD §8 Unit 13; ticket
accept 3): `AudioChannel.help` ducks `{ambient, celebration}`; nothing else
ducks anything; ducking is directional (ambient/celebration playing never
ducks help). `channelsDuckedBy(AudioChannel)` and
`shouldDuck({required active, required candidate})` are the only two
methods — there is no parameter, field, or method anywhere on this type
that references a microphone, an ASR engine, or a "listening" state. That
omission is itself the proof the policy cannot reach the mic pipeline
("asserted by API absence"); `AudioChannel` having exactly four values is
the same proof from the other direction — there is no channel to name the
mic with.

### `lib/features/audio/fake_audio_service.dart`

`FakeAudioService implements AudioService` — a headless, in-memory service
for tests. Every downstream ticket (scaffold, reading screen, vocab,
celebration, twister) asserts audio behavior against it.

- Constructor: `FakeAudioService({Set<AudioRef> missingRefs = const {},
  Duration Function()? clock, DuckingPolicy duckingPolicy = const
  DuckingPolicy()})`. `missingRefs` makes `play()` throw
  `AudioRefNotFoundException` for those refs (logging nothing). `clock` is
  injectable for deterministic timestamp assertions; the default is a
  monotonic `Stopwatch`. `duckingPolicy` is delegated to, not hardcoded —
  a test can inject a stand-in policy.
- `List<AudioCallLogEntry> get callLog` — an ordered, defensively-copied
  (`List.unmodifiable`) snapshot. Entry kinds: `PlayLogEntry`,
  `StopLogEntry`, `DuckLogEntry`, `UnduckLogEntry`, each carrying a
  clock-stamped `timestamp` so ordering can be asserted from timestamps
  alone.
- `void completePlayback(PlaybackHandle handle)` — test-control hook
  simulating a clip reaching its natural end (as opposed to `stop()`):
  resolves `completionOf(handle)` without logging a `StopLogEntry`.
- Ducking is computed from `duckingPolicy` against which channels
  currently have an active (unstopped, uncompleted) handle: a channel is
  "active" or not, so two simultaneously-active handles on the same
  channel are ducked once, not twice, and ducking a channel that already
  ended on its own logs no unduck.

### `lib/features/audio/phoneme_sequencer.dart`

`PhonemeSequencer` — plays a word's phoneme audio sequence gaplessly, in
`WordToken.graphemePhonemeMap` order (PRD §8 Unit 13/6/15; ticket accept
2 and 5).

- Constructor: `PhonemeSequencer({required AudioService audioService,
  required Map<String, AudioRef> phonemeAudioRefs})`.
- `Stream<PhonemeStarted> playSequence(WordToken word, {AudioChannel
  channel = AudioChannel.help})` — walks `graphemePhonemeMap` strictly in
  index order. Each non-silent entry (`phonemeId.isNotEmpty`) resolves
  through `phonemeAudioRefs` and is played via `audioService.play`; a
  `PhonemeStarted(graphemeIndex, phonemeId, handle)` event is emitted
  carrying the map index — the reading screen's grapheme-highlight sync
  point (Unit 6). Entries with an empty `phonemeId` (silent letters, e.g.
  the "e" in "cake") are valid indices that contribute no audio and no
  event. A digraph (e.g. `'sh'` in "ship") is one `graphemePhonemeMap`
  entry and therefore one `play()` call / one event, never split.
- Gapless is queue construction, not wall-clock: the sequencer never
  inserts its own delay between phonemes — it awaits
  `audioService.completionOf(handle)` for phoneme N before issuing
  `play()` for phoneme N+1, so the next phoneme is queued the instant the
  previous one's completion resolves.
- Low-latency: the first `play()` call is issued synchronously, in the
  same event-loop turn as `playSequence()` itself. This is the headless
  proxy for ticket accept 5's [DEVICE] "< 150ms from trigger on min-spec
  device" acceptance (A-6) — the wall-clock figure itself is owner-measured
  in profile mode and has no headless equivalent; that specific test is
  `skip`-marked with a `[DEVICE]` reason.
- Errors: a `phonemeId` absent from `phonemeAudioRefs` is a content/pack
  bug — the stream emits `PhonemeAudioNotFoundException(phonemeId)` and
  closes; no further phonemes play. An `AudioService`-level error (e.g.
  `AudioRefNotFoundException`) propagates through the stream the same way.
- `channel` defaults to `AudioChannel.help` (Unit 6 Tier 1 sound-out) but
  is fully overridable (e.g. Unit 15 Sound Garden tap-to-hear) and is
  forwarded verbatim to every `play()` call in the sequence.

## What is deliberately not here

- No TTS code path anywhere (asserted by API shape: `play()` takes only
  `(AudioRef, {required AudioChannel channel})`).
- No real just_audio/audio_session adapter — not in this ticket's file
  list. The plugin choice is pinned (A-17) for a later integration step to
  build as a thin `AudioService` adapter over constructor-injected players;
  correctness there is by inspection/owner device verification, not this
  headless suite.
- No mic/listening awareness anywhere in `AudioService` or `DuckingPolicy`
  — ducking cannot reach the microphone pipeline because there is no API
  surface through which it could.

## Recording brief

`docs/audio/recording-brief.md` is the pinned recording direction for the
product owner's narrator sessions (fixed phoneme/celebration/prompt sets,
loudness target). See that file for the full brief; Unit 3's pack-build
linter owns the actual -16 LUFS loudness *check*, this document only states
the target the narrator records to.

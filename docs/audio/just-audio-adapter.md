# just_audio adapter (`JustAudioService`)

The device-side, production implementation of the `AudioService` seam
(`lib/features/audio/audio_service.dart`), backed by `just_audio` +
`audio_session` per A-17. File:
`lib/features/audio/just_audio_service.dart`. Tests:
`test/features/audio/just_audio_service_test.dart`.

It is drop-in behavior-compatible with `FakeAudioService`, which every
downstream unit (scaffold, reading screen, vocab, celebration, twister) was
tested against: same handle allocation, same stop/completion semantics, same
policy-driven ducking bookkeeping.

## Construction and seams

```dart
JustAudioService({
  required String? Function(AudioRef ref) resolveRef,
  AudioSessionConfigurator? sessionConfigurator, // defaults to audio_session speech preset
  AudioPlayerFactory? playerFactory,             // defaults to real just_audio players
  DuckingPolicy duckingPolicy = const DuckingPolicy(),
  double duckedVolume = JustAudioService.defaultDuckedVolume, // 0.3
})
```

- **`resolveRef` (the resolver seam).** `AudioRef` is an opaque
  pack-relative path; this adapter never inspects or generates one. The
  composition root injects a resolver (backed by the installed content pack)
  that maps a ref to an **absolute file path**, or returns `null` when the
  ref is unknown. On `null`, `play()` throws `AudioRefNotFoundException`
  **before any player is created and before any session work** — a missing
  shipped ref is a pack-integrity bug, not a runtime fallback path.
- **`playerFactory`.** One player per in-flight `play()` call; disposed on
  completion/stop/error. The factory returns `JustAudioPlayerApi`, a minimal
  fakeable slice of `just_audio.AudioPlayer` (`setFilePath`, `play`, `stop`,
  `setVolume`, `dispose`). The default (`RealJustAudioPlayer`) forwards 1:1
  to a real `just_audio.AudioPlayer`; unit tests inject fakes so no platform
  channel is ever touched.
- **`sessionConfigurator`.** Runs once, lazily, before the first playback.
  The default configures `audio_session` with the speech preset (appropriate
  for a kids app whose audio is narration/phonics voice clips). Any throw is
  swallowed and not retried, so headless/test environments without platform
  channels still play; the OS keeps its default session behavior in that
  case.

## Playback lifecycle

- Handles are monotonic ints starting at 0 (matches the fake).
- After the ref resolves and the handle is allocated, the load+play chain
  (`setFilePath` → `play`) is fire-and-forget: **a playback error never
  throws out of `play()`'s future once the handle is returned** — it simply
  completes the handle (the same swallow-and-resume posture as
  `NarrationController`). The player is stopped and disposed on every exit:
  natural end, explicit `stop()`, or error.
- `stop(handle)` is a safe no-op for unknown or already-finished handles.
- `completionOf(handle)` resolves on natural completion, on `stop()`, or on
  a player error; it resolves immediately for an unknown/finished handle and
  never hangs.

## Ducking application

Which channels duck which is owned entirely by the injected `DuckingPolicy`
(pinned: only `help` ducks anything, and only `{ambient, celebration}`;
narration is never ducked; nothing can reach the mic pipeline — there is no
channel to name it with). The adapter adds only the *gain mechanics*:

- While any `help` clip is live, every live player on a ducked channel has
  its volume set to `duckedVolume` (default `0.3` — `DuckingPolicy` pins no
  gain value, so the constant lives here, constructor-tunable for on-device
  tuning).
- A clip *starting* on an already-ducked channel begins at the ducked gain
  (one volume call, never full-then-ducked).
- Ducking is recomputed from the set of currently-live channels on every
  start/finish, and only the delta is applied. With **overlapping ducking
  clips, restore happens only when the last one ends.**
- A ducked clip that ends on its own gets no restore call (its player is
  already disposed).
- Volume calls are wrapped so a `setVolume` failure can never break playback
  or teardown.

## What the unit tests cover vs what stays device-verified

Unit-tested headlessly (fakes behind the two seams; no platform channels,
no audio files):

- unknown ref throws `AudioRefNotFoundException` with no player created and
  no session work;
- monotonic handle ids, one player per `play()`, resolver-provided path
  loaded;
- `stop`/`completionOf` semantics incl. unknown/finished handles and
  idempotent stop;
- error swallowing for load-time and mid-playback errors (handle completes,
  player disposed);
- all ducking bookkeeping above, including custom `duckedVolume`;
- session configured exactly once, lazily, and a throwing configurator is
  swallowed.

Device-verified by the owner (per ticket audio-playback / A-17 — CI has no
audio device):

- actual audible playback through `just_audio`, and the real
  `audio_session` interaction (interruptions, routing);
- latency ("phoneme sound-out must feel instant") and gapless sequential
  phoneme playback feel;
- perceived loudness of the 0.3 ducked gain (tunable via the constructor if
  the owner adjusts it on device).

# Platform ASR adapter (Android) — behavior & channel protocol

The production on-device speech-recognition engine (PRD §9 A-10: platform
Android `SpeechRecognizer` with contextual biasing, behind the existing
`AsrEngine` seam). Built at owner direction for the live demo, superseding
the Unit 0 spike gate that had held `asrEngineProvider` on
`FakeAsrEngine(script: [])`.

| piece | file |
| --- | --- |
| Dart engine | `lib/features/listening/engine/platform_asr_engine.dart` (`PlatformAsrEngine implements AsrEngine`) |
| Native handler | `android/app/src/main/kotlin/com/learntoread/learn_to_read/AsrSpeechHandler.kt` |
| Registration | `MainActivity.configureFlutterEngine` (alongside the untouched spike handler) |
| Boot wiring | `lib/main.dart`: `if (Platform.isAndroid) asrEngineProvider.overrideWithValue(PlatformAsrEngine())` |
| Tests | `test/features/listening/engine/platform_asr_engine_test.dart` (mocked channels) |

The Unit 0 spike (`SpikeSpeechHandler.kt`, `lib/spike/`) stays untouched and
disposable; this adapter is its production sibling on its own channel names.

## Channel protocol

Method channel **`learn_to_read/asr/method`**:

| method | arguments | behavior |
| --- | --- | --- |
| `start` | `{ "biasingWords": [String] }` | (Re)starts continuous recognition biased toward the expected sentence words. `start` while already started is a graceful stop-then-restart. Fails with `ENGINE_UNAVAILABLE` when no recognition service exists on the device. |
| `stop` | none | Cancels recognition (discarding the in-flight utterance) and exits the restart loop. Idempotent. |

The event channel's `onCancel` (Dart-side dispose / hot restart) also ends
the loop: with no sink there is nobody to deliver to, and the loop must not
keep the mic open or the chime streams muted.

Event channel **`learn_to_read/asr/events`** — one map per hypothesis burst:

```json
{ "words": ["the cat", "the can", "a cat"],   // top alternatives, best first; never empty
  "isFinal": false }                           // false = partial, true = final
```

The Dart side maps every burst (partials **and** finals) to
`Hypothesis(wordHypotheses: words, phoneHypotheses: null)`. Phone-level
detail is intentionally absent — Android `SpeechRecognizer` exposes none
(the Unit 0 spike finding); Unit 14's sound mode approximates downstream by
phonetic distance. `isFinal` is carried on the wire (it drives the native
restart loop and is useful for debugging) but is not modelled on
`Hypothesis`.

Unrecoverable native failures surface as a **single channel error event**
(`MIC_PERMISSION_DENIED`, `ENGINE_UNAVAILABLE`) — see errors below.

## Continuous listening: the restart loop

Android `SpeechRecognizer` is utterance-scoped: it finalizes one utterance
and stops, but a child reads many utterances per page. While in the started
state the native handler automatically begins a new recognition round:

- after every `onResults` (normal end of an utterance) — immediate restart
  (posted to the main looper, never inline from the listener callback);
- after recoverable errors — `ERROR_NO_MATCH` and `ERROR_SPEECH_TIMEOUT`
  (the normal cadence of a pausing child), `ERROR_CLIENT`, and every other
  transient code — with backoff (below). The `ERROR_CLIENT` that `cancel()`
  itself fires never restarts, because `stop` clears the started flag first.

All recognizer calls run on the main thread (a `SpeechRecognizer`
requirement); delayed restarts are serialized through a
`Handler(Looper.getMainLooper())`.

### Round length (demo polish)

Each round's intent carries the round-lengthening extras (honored by
Google's recognizer on most devices, harmless where ignored):
`EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS = 5000`,
`EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS = 5000`,
`EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS = 15000` — so a child pausing
between words no longer finalizes a round every couple of seconds. A round
ending in `onResults` still restarts immediately; `NO_MATCH`/`TIMEOUT` keep
the backoff above.

### Round-chime muting (demo polish)

The system recognizer chimes on every round start/stop; the continuous loop
made that a constant bloop-bloop. While the loop is ACTIVE — from a
successful `start` until `stop`, a fatal error, or event-channel detach,
NOT per round — the native handler mutes `STREAM_NOTIFICATION` and
`STREAM_SYSTEM` (`AudioManager.adjustStreamVolume(…, ADJUST_MUTE, 0)`).
Rules:

- `STREAM_MUSIC` is never touched — the app's own narration/phoneme/TTS
  clips play there.
- Prior mute state is respected: only streams the handler itself muted are
  unmuted on loop end, and restore ALWAYS runs on every loop-end path.
- Each volume call is try/caught (some devices throw `SecurityException`
  under Do Not Disturb) and degrades silently; API < 23 keeps its chimes.
- Accepted tradeoff: other apps' notification beeps are silenced while a
  child reads.

### Restart / backoff rule

- A round that produced results (partial or final) resets the
  consecutive-error counter and restarts immediately.
- A round that errored restarts after `300ms * 2^(n-1)`, capped at
  `2000ms`, where `n` is the current run of consecutive errored rounds
  (300, 600, 1200, 2000, 2000, ...). The recognizer instance is destroyed
  and recreated on each errored restart (BUSY/CLIENT leave it unusable).
- After **8** consecutive errored rounds the engine gives up for good: one
  `ENGINE_UNAVAILABLE` error event, loop over. This is what keeps a
  `RECOGNIZER_BUSY` loop or a broken recognition service from crash-looping
  restarts.
- `ERROR_INSUFFICIENT_PERMISSIONS` is immediately fatal:
  `MIC_PERMISSION_DENIED` error event, no retry.

## Dart-side semantics (`PlatformAsrEngine`)

- **One long-lived broadcast stream.** `hypothesesStream` returns the SAME
  stream object on every access (pinned by `sharedAsrEngineProvider`'s
  header) and is never closed by `stop()` — the `AsrEngine` contract allows
  "closed OR produces no new events" after stop; here it stays open and
  silent so vocab cards / narration replays / the next page's tracker reuse
  the same pipe.
- **Lazy single subscription.** The event channel is subscribed exactly once,
  on the first `start()`; constructing the engine touches no platform
  channel.
- **Errors.** Recoverable conditions never reach Dart (handled by the native
  restart loop). Unrecoverable channel errors — including a
  `PlatformException` thrown by the `start` call itself — are logged and
  forwarded as stream *errors*, never a stream close. `ReadingTracker`
  listens with `cancelOnError: true` and owns the policy: that session
  degrades to tap mode silently while the stream stays alive for the next
  session.
- **Non-Android hosts.** Every `MissingPluginException` (tests, desktop,
  iOS until its adapter lands) is swallowed: `start` succeeds, nothing ever
  arrives — the same posture as the shipped silent `FakeAsrEngine`.
- `lib/main.dart` wires the engine on Android only; every other platform
  keeps the provider default (silent fake → tap-only reading).

## What remains device-verified ([DEVICE])

Nothing in this container runs Kotlin or a microphone. Still owner/device
work:

- **Actual recognition quality** on child voices — hypothesis cadence,
  biasing strength, near-miss transcription fidelity. The adapter is
  plumbing; the Unit 0 spike protocol (docs/spike/README.md §3b) is the
  measurement tool.
- **Kotlin compilation** — this container has no Android SDK, so
  `AsrSpeechHandler.kt` has not been compiled here. First `flutter build
  apk` / `flutter run -d <android>` on a machine with the SDK verifies it.
- **Chime muting and round length** — whether a given OEM's recognizer
  actually plays its chime on NOTIFICATION/SYSTEM (a few route it
  elsewhere), whether DND blocks the mute, and whether the
  `EXTRA_SPEECH_INPUT_*` round-length extras are honored are all
  device-dependent; verify on the demo device.
- **Playback-vs-recognizer focus behavior** — the
  `defaultAudioSessionConfiguration` change in
  `lib/features/audio/just_audio_service.dart` (media attributes,
  `gainTransientMayDuck`, `androidWillPauseWhenDucked: false`) is unit-pinned
  as a value, but smooth TTS playback across recognition rounds is audible
  only on device.
- **Emulator caveats**: in the emulator's Extended Controls → Microphone,
  "Virtual microphone uses host audio input" must be ON, or the recognizer
  hears silence. The device/image must have a recognition service — the
  **Google app** provides it; Play-store emulator images have it, AOSP
  images generally do not (`SpeechRecognizer.isRecognitionAvailable` then
  answers false and `start` fails with `ENGINE_UNAVAILABLE`).
- **Biasing floor**: `EXTRA_BIASING_STRINGS` only takes effect on API 33+;
  below that recognition runs unbiased (guarded, not an error).
- **Runtime permission**: `MainActivity` requests `RECORD_AUDIO` on first
  launch; a denial surfaces as `MIC_PERMISSION_DENIED` and the tracker
  falls back to tap.

## Mic-permission gate (known wiring gap, reported not fixed)

`micPermissionServiceProvider` still defaults to
`FakeMicPermissionService(MicPermissionStatus.notDetermined)` and
`lib/main.dart` does **not** override it. `resolveReadingMode` treats
anything but `granted` as tap-only, so on a real device the reading screen
resolves `micEnabled == false` even with the parent's mic consent ON, and
`ReadingTracker` never calls `engine.start`. Until a real permission service
(or a `granted` fake, given `MainActivity` already obtains the OS
permission) is wired at boot, the new engine is reachable by the twister
flow (which gates on profile consent only) but not by the story-reading
flow.

# Unit 0 recognition spike — owner run guide

This is the Unit 0 recognition spike (PRD.md §8 "Unit 0 — Recognition
spike"). It is a **disposable, throwaway build**: a bare-bones screen with
one hardcoded sentence, a mic start/stop control, and a live scrolling view
of raw on-device recognizer hypotheses. It exists to answer two questions
*before* Units 4-6 build on the answers:

1. Are on-device word hypotheses granular and reliable enough for the
   close-enough matcher, with young voices?
2. Is any usable phone-level detail exposed (needed by Unit 14's
   tongue-twister sound mode)?

Everything in `lib/spike/`, `ios/Runner/SpikeSpeechHandler.swift`, and
`android/.../SpikeSpeechHandler.kt` is disposable spike code — it is not
wired into the main app and shares nothing with it. The only outputs that
matter are the **hypothesis logs** and the **written verdict** described
below.

This document is for the product owner running the spike. It is **not**
exercised by `flutter test` (see the skipped test in
`test/spike/spike_channel_test.dart` for why) — the Dart-side channel
contract and log format are covered by `flutter test test/spike/`, but
actually recognizing a real child's voice on a real device is owner work.

## 0. Prerequisites

- A physical iOS or Android device (the simulator/emulator microphone is
  not representative of real recognizer behavior; SFSpeechRecognizer/Android
  SpeechRecognizer both need a real mic and, for iOS, on-device speech
  recognition to actually be exercised).
- Parental permission for every child who reads the sentence into the
  spike, per the ticket notes (OWNER-COORDINATED).
- `export PATH=/opt/flutter-sdk/bin:$PATH` (or however Flutter is on your
  `PATH` locally) and a working `flutter run` setup for the target device.

## 1. Register the native handlers locally

The spike's native handlers (`SpikeSpeechHandler.swift` /
`SpikeSpeechHandler.kt`) are self-contained files that are **not**
registered automatically — `ios/Runner/AppDelegate.swift` and
`android/.../MainActivity.kt` are owned by the platform-asr-adapter ticket,
and this ticket deliberately does not touch them (disjoint file ownership).
Register the handlers by hand, locally, before running the spike. Do not
commit these edits — revert them (or just don't commit) once you're done
with the spike run, since they're only needed to exercise disposable code.

### iOS: `ios/Runner/AppDelegate.swift`

Add one line after the existing `GeneratedPluginRegistrant.register` call:

```swift
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    SpikeSpeechHandler.register(with: self.registrar(forPlugin: "SpikeSpeechHandler")!)  // <-- add this line
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

You'll also need `NSSpeechRecognitionUsageDescription` and
`NSMicrophoneUsageDescription` entries in `ios/Runner/Info.plist` (with a
short description shown to the user in the permission prompt) if they
aren't already present — add them locally for the spike run.

### Android: `android/app/src/main/kotlin/com/learntoread/learn_to_read/MainActivity.kt`

Add an override after the existing class declaration:

```kotlin
package com.learntoread.learn_to_read

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        SpikeSpeechHandler.register(flutterEngine.dartExecutor.binaryMessenger, applicationContext)  // <-- add this
    }
}
```

You'll also need `RECORD_AUDIO` permission in
`android/app/src/main/AndroidManifest.xml` (and to grant it at runtime on
first launch) if it isn't already present — add it locally for the spike
run.

## 2. Run the spike

From the repo root, with a device connected/booted and the native handler
registered per step 1:

```sh
export PATH=/opt/flutter-sdk/bin:$PATH
flutter run -t lib/spike/spike_main.dart -d <device-id>
```

(`flutter devices` lists available `<device-id>` values.) This boots the
separate spike entrypoint (`lib/spike/spike_main.dart`), **not** the main
app's `lib/main.dart` — the spike has its own `MaterialApp` shell
(`SpikeApp`) and is not reachable from the main app's navigation.

You should see:

- The hardcoded sentence (`kSpikeSentence` in `lib/spike/spike_screen.dart`)
  displayed at the top.
- A **Start** button.
- Below it, a live-scrolling list that will show raw hypotheses (partial
  and final) as they arrive once you start recording.

## 3. Conduct sessions

The original protocol below assumes real child readers. If no child is
available, use the **adult-proxy protocol** in §3b instead — it changes
what you say into the mic and which conclusions the verdict may draw, but
nothing about how the app is operated.

For each session:

1. Tap **Start**. Grant the microphone/speech-recognition permission
   prompts the first time.
2. Read the on-screen sentence aloud, once, at a normal pace (or per the
   proxy script in §3b).
3. Watch the live hypothesis list — partial hypotheses should update as
   you speak, ending in a final hypothesis.
4. Tap **Stop**.
5. Repeat. Each Start/Stop cycle is one *session*; the app keeps every
   session's hypotheses (via `SpikeSessionLogRotator`) for as long as the
   app process stays alive, so you can run all sessions in one app launch
   without losing earlier ones.

With real children (parental permission per step 0), collect **at least 3
children's sessions** (original ticket acceptance criterion). With the
adult proxy, run the full §3b script — it needs roughly 6-8 short
sessions.

## 3b. Adult-proxy protocol (no child available)

Run each numbered item as its own Start/Stop session so the log files map
one-to-one to conditions. The point is to probe the recognizer's *behavior
under imperfect reading*, which an adult can simulate, even though adult
acoustics cannot stand in for a child's voice (see the caveat at the end).

1. **Clean baseline** — read the sentence once, naturally. Confirms the
   happy path and gives a reference log.
2. **Sounding out** — read it the way a struggling 5-year-old would:
   word by word, with the hard word stretched into its sounds
   ("kuh... aah... t... cat"). Watch whether partial hypotheses surface
   *per word* as you go, or whether the engine holds everything until you
   finish. This is the single most important condition: the tracker's
   word-advance and struggle detection (A-12) live or die on per-word
   partial cadence.
3. **Near-misses on the A-18 confusion axes** — read the sentence but
   deliberately substitute, one axis per pass:
   - "f" for "th" (*fin* for *thin* — th-fronting),
   - "w" for "r" or "l" (*wabbit* for *rabbit* — gliding),
   - "f" for "wh"/"w" (*file* for *while* — the KidSpeak W↔F axis),
   - a voicing swap (*sip* for *zip*, or *gat* for *cat*).
   What matters is what the engine *transcribes*: does "wabbit" come back
   as "rabbit" (engine auto-corrects — biasing is strong), as "wabbit"
   (faithful — the matcher's phoneme distance does the work), or as
   something unrelated? Note it per axis; A-18's acceptance widening
   assumes the faithful-or-corrected cases, not garbage.
4. **Abandon mid-word** — start a word, stop halfway, go silent. Does a
   final hypothesis still arrive, and after how long?
5. **Silence** — Start, say nothing for ~10 s, Stop. Records the engine's
   timeout/no-speech behavior (feeds the T1=4 s silence-detector design).
6. **Fast mumble** — read it quickly and indistinctly once. A rough lower
   bound on hypothesis quality.
7. *(Optional)* **Pitched-up read** — a higher-pitched, child-cadenced
   read. A weak acoustic proxy, but costs one session.

In every session, also note whether any line has `phoneDetailPresent:
true` — that single boolean answers the Unit 14 phone-level question
regardless of who is speaking.

**What the proxy can and cannot conclude.** Hypothesis cadence, partial
granularity, biasing behavior, near-miss transcription fidelity, timeout
behavior, and phone-detail availability are all legitimately answerable by
an adult — they are engine properties. What the proxy *cannot* establish
is recognition accuracy on genuine child acoustics (pitch, formants,
disfluency patterns — the reason KidSpeak exists). The verdict must say
so: mark the child-acoustics dimension **provisional**, to be revisited
with the `[DEVICE]` real-child recorded-audio contract tests when real
recordings exist. A keep/swap/hybrid verdict on the engine-property
questions is still decision-grade and unblocks Unit 4.

## 4. Where the shareable log lands

Every hypothesis event (partial and final, with whatever confidence/word
detail the platform reports) is appended, live, to a JSON-lines log file
for the current session — one file per Start/Stop cycle, named
`spike_<sessionId>_<startedAt>.jsonl` (see
`SpikeSessionLog.fileNameFor` in `lib/spike/hypothesis_log.dart`). The
screen shows the current session's log file name once you've tapped
**Start**.

The file is written to the app's documents directory on the device
(`path_provider`'s `getApplicationDocumentsDirectory()`):

- **iOS simulator/device**: pull it off with Xcode's Devices & Simulators
  window ("Download Container..."), or `xcrun simctl get_app_container` for
  a simulator, then look under `Documents/`.
- **Android**: `adb shell run-as com.learntoread.learn_to_read ls
  files/` to list, and `adb shell run-as com.learntoread.learn_to_read cat
  files/<name>.jsonl` (or `adb pull` via a debuggable-app-accessible path)
  to retrieve it.

Each line is one JSON object: the first line is a session header
(`sessionId`, `startedAt`, `sentence`, `biasingWords`); every line after
that is one hypothesis event
(`HypothesisEvent.toJson()` shape — timestamp, isFinal, text, confidence,
biasingWords, phoneDetailPresent, phoneDetail). `phoneDetailPresent`
records whether the platform payload included a `phoneDetail` key at all —
this is the field that answers the Unit 14 phone-level-detail question.

If writing to disk fails for any reason (e.g. permissions), the spike does
not crash — the in-memory session log survives for the rest of that run,
but you should confirm the file actually landed before ending the session
with a child (check step above).

## 5. Where the verdict document goes

The **written verdict** — keep on-device / swap engine / hybrid, with
sample hypothesis logs attached or referenced, and an explicit go/no-go on
both (a) A-10 (are on-device hypotheses granular/reliable enough) and (b)
phone-level detail availability — is an **owner deliverable**, not part of
this ticket's automated output. Per PRD.md §8 Unit 0 and this ticket's
acceptance criteria:

- Write the verdict as a new in-repo document (e.g.
  `docs/spike/verdict.md`, alongside this README) once you've collected
  the >= 3 children's sessions — or completed the §3b adult-proxy script,
  in which case the verdict must carry the provisional-acoustics caveat
  from §3b.
- Include or reference the collected `.jsonl` session logs (e.g. copy a
  representative sample into `docs/spike/sessions/` alongside the verdict).
- Unit 4 (the engine adapter / matching layer) cites this verdict when it
  picks the ASR engine — do not proceed with Unit 4 until this verdict
  exists.

## Troubleshooting

- **No hypotheses ever appear**: confirm the native handler is registered
  (step 1) and that microphone/speech permissions were granted on-device
  (check the OS Settings app if you dismissed the prompt).
- **`MIC_PERMISSION_DENIED` shown on screen**: the platform denied the
  permission request; check OS-level Settings for the app and re-grant.
- **`ENGINE_UNAVAILABLE` shown on screen**: the platform recognizer itself
  is unavailable (e.g. no on-device speech model downloaded on iOS, or no
  recognition service configured on the Android device/emulator image).
- **Nothing shows on an emulator/simulator**: expected — use a physical
  device (step 0).

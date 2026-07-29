# Demo guide — running LearnToRead locally

From a fresh clone to a talking, animated, story-filled app on your own
machine. Two supported targets: the **Android emulator** (primary — this is
the product's platform) and **Linux desktop** (secondary; useful for quick
visual checks).

## 0. Prerequisites (one-time, ~15 min)

1. **Flutter SDK 3.32.x** — https://docs.flutter.dev/get-started/install
   (add `flutter/bin` to PATH; `flutter --version` should work).
2. **Android Studio** — https://developer.android.com/studio (brings the
   Android SDK, emulator, and adb). Then:
   ```sh
   flutter doctor --android-licenses   # accept all
   flutter doctor                      # Flutter + Android toolchain rows green
   ```
3. **An emulator image**: Android Studio → Device Manager → Create device →
   any Pixel tablet/phone → a recent API level (34+) → Finish. (Or CLI:
   `avdmanager create avd -n demo -k "system-images;android-34;google_apis;x86_64"`.)
4. **Python 3** on PATH (for the local TTS voice — no accounts, no keys).

## 1. The one command

```sh
./tool/setup_and_run.sh
```

That's the whole setup: dependencies → demo content generation → local TTS
voicing (downloads the free Piper voice model once, ~120 MB) → pack
validation → test suite → install on the running emulator/device → content
sideload → launch. Start your emulator first (or plug in a phone with USB
debugging); the script auto-starts the first available emulator image if
none is running.

Useful flags: `--skip-tests` (much faster once you trust the build),
`--skip-tts` (keep existing audio), `--no-run` (build + validate only).

## 2. What to show in a demo (a 5-minute walkthrough)

1. **First launch** → profile picker. Tap the corner into the **parent
   gate** (hold both targets — child-proof by motor skill, not by
   reading). Create a profile: name, age band 5–6. Note aloud: no account,
   no email, nothing leaves the device.
2. **Story map** → three unlocked story nodes. Tap one nav icon and let
   the voice prompt speak ("The story map") — navigation needs zero
   reading.
3. **Open "The Cat in the Tin"** → the narrator reads it once (listen-first),
   then the waveform pill listens. The mic pipeline runs against the
   development fake until the recognition spike verdict, so **tap each word
   to simulate the child reading** — words sweep amber → green.
4. **The phonics moves** (the heart of the pitch):
   - **Long-press any word** → it sounds out grapheme by grapheme with
     letter highlighting.
   - Wait ~4 s on a word → the **"let's take it slowly"** panel appears;
     **tap individual letter chips** to hear each sound alone.
5. **Finish the page** → the dog-ear appears; **drag the corner** like a
   real book page (multi-page stories). Finish the story → the **animated
   scene plays while the voice narrates the whole story back**, then the
   celebration lands: cheer line, confetti, collectible flying to the
   collection.
6. **Sound Garden** → tap a letter-combination card, hear the sound, say
   it back (or just show the amber "listening" state); the practice loop:
   green flash + confetti + reset, curl to the next sound.
7. **Flash cards** → the phonics deck: tap the word to sound it out, flip
   for the letter-sound breakdown, swipe onward; amber/green grading.
8. **Parent corner** → the gated progress view: per-story completion and
   the invisible per-word help tracking, visible only to adults.

## 3. Linux desktop (secondary target)

```sh
flutter config --enable-linux-desktop
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev
flutter run -d linux
```

Content lives at `~/.local/share/com.learntoread.learn_to_read/` — copy
`build/sideload/starter_pack` and `build/sideload/scope_sequence.json`
there (the setup script's staging step builds `build/sideload/`). Caveats:
audio playback has no Linux backend in `just_audio` (visuals only), and
the mic pipeline is Android/iOS-native — desktop is for looking, the
emulator is for demoing.

## 4. Troubleshooting

- **First Gradle build is slow** (minutes; it downloads once). Later runs
  are fast.
- **Emulator won't start**: enable virtualization (VT-x/AMD-V) in BIOS;
  on Windows check "Windows Hypervisor Platform".
- **No sound in the emulator**: check the emulator's volume (host side)
  and that the AVD has audio enabled (default: yes).
- **Mic permission**: the app asks on first launch; if declined, re-grant
  in Android Settings → Apps. (With the fake engine the demo doesn't need
  the mic — tap-to-advance covers it.)
- **`pack build FAILED` with loudness errors**: a WAV was replaced by an
  un-normalized file — run `dart run tool/normalize_wav.dart content/demo`
  and retry.
- **Linux build fails fetching sqlite**: your network blocks sqlite.org;
  see `tool/setup_and_run.sh --skip-tts` note or build for Android instead.
- **Fresh content after edits**: rerun `./tool/setup_and_run.sh` — content
  regeneration, voicing, validation, and sideload are idempotent.

## 4b. Pre-meeting checklist (do this the night before)

The full setup path (clone → deps → content → TTS voicing → pack build)
is rehearsal-verified from a fresh clone; the one step that only runs on
your machine is the first Gradle/APK build. So:

- [ ] Run `./tool/setup_and_run.sh` end-to-end **the night before** — the
      first Gradle build is the only unrehearsed step, and it's slow once.
- [ ] Leave the emulator **running and signed into a demo profile** on
      meeting day (cold emulator boots are the #1 live-demo killer).
- [ ] **Screen-record one clean run-through** of the §2 walkthrough as
      your backup — if anything hiccups live, narrate over the recording.
- [ ] Re-run just `flutter run` on meeting day (fast after first build);
      don't re-run the full script the day of.
- [ ] Have `docs/presentation/sound-it-out-deck.html` open in a browser
      tab (it's fully offline) and the repo open in another for the
      "show me the code" moment.

## 5. What's real vs. staged (be straight in the demo)

Real: the entire reading loop, phonics engine, help ladder, 20 decodable
stories, two-voice TTS audio, animations, flashcards, Sound Garden,
per-profile SQLite progress, parental gate — all under ~1,900 tests.
Staged: speech recognition awaits the device spike (tap simulates it);
story art is the code-drawn stage until commissioned; voice is local TTS
until human recordings replace it (drop-in by filename).

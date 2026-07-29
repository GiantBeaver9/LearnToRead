#!/usr/bin/env bash
# One-shot setup + run for LearnToRead.
#
#   tool/setup_and_run.sh [--skip-tests] [--skip-tts] [--no-run]
#
# From a fresh clone this: checks the toolchain, fetches dependencies,
# generates demo content, voices it with local TTS (Piper -- downloaded
# automatically, no account/key), builds + validates the story pack, runs
# the test suite, installs the app on the connected Android device or
# emulator, sideloads the content, and launches.
set -euo pipefail
cd "$(dirname "$0")/.."

SKIP_TESTS=0; SKIP_TTS=0; NO_RUN=0
for arg in "$@"; do
  case "$arg" in
    --skip-tests) SKIP_TESTS=1 ;;
    --skip-tts) SKIP_TTS=1 ;;
    --no-run) NO_RUN=1 ;;
    *) echo "unknown option: $arg"; exit 2 ;;
  esac
done

say() { printf '\n==> %s\n' "$*"; }

# ---------------------------------------------------------------- toolchain
say "checking toolchain"
command -v flutter >/dev/null || {
  echo "flutter not found. Install: https://docs.flutter.dev/get-started/install"
  echo "(this repo targets Flutter 3.32.x)"; exit 1; }
flutter --version | head -1

say "fetching dependencies"
flutter pub get

# ---------------------------------------------------------------- content
say "generating demo content (placeholders for anything missing)"
dart run tool/demo_content.dart

# ---------------------------------------------------------------- TTS voice
TTS_DIR="build/tts"
TTS_MODEL="$TTS_DIR/en-us-libritts-high.onnx"
if [ "$SKIP_TTS" = 0 ]; then
  say "voicing content with Piper TTS (local, free)"
  if ! python3 -c "import piper" 2>/dev/null; then
    python3 -m pip install --quiet piper-tts || {
      echo "piper install failed -- continuing with existing/placeholder audio"; SKIP_TTS=1; }
  fi
  if [ "$SKIP_TTS" = 0 ] && [ ! -f "$TTS_MODEL" ]; then
    mkdir -p "$TTS_DIR"
    echo "downloading voice model (~120 MB, one time)"
    curl -L --fail -o "$TTS_DIR/voice.tar.gz" \
      "https://github.com/rhasspy/piper/releases/download/v0.0.2/voice-en-us-libritts-high.tar.gz" \
      && tar xzf "$TTS_DIR/voice.tar.gz" -C "$TTS_DIR" \
      && rm "$TTS_DIR/voice.tar.gz" \
      || { echo "voice download failed -- continuing with existing audio"; SKIP_TTS=1; }
  fi
  if [ "$SKIP_TTS" = 0 ]; then
    # Two-voice policy (PRD OQ-3): 21 primary phonics voice, 47 secondary.
    # Never overwrites human recordings (files without .tts markers).
    python3 tool/tts_generate.py --model "$TTS_MODEL" --out content/demo --force
    dart run tool/normalize_wav.dart content/demo
  fi
else
  say "skipping TTS (--skip-tts)"
fi

# ---------------------------------------------------------------- pack build
say "building + validating the story pack"
dart run tool/pack_build.dart content/demo build/starter_pack/manifest.json \
  --levels=content/demo/levels.json \
  --heart-words=content/demo/heart_words.json \
  --starter-levels=level.demo.1,level.demo.2,level.demo.3

# ---------------------------------------------------------------- tests
if [ "$SKIP_TESTS" = 0 ]; then
  say "running the test suite"
  flutter test
else
  say "skipping tests (--skip-tests)"
fi

# ---------------------------------------------------------------- device
if [ "$NO_RUN" = 1 ]; then say "done (--no-run)"; exit 0; fi

say "looking for a device"
device_ready() { command -v adb >/dev/null && adb devices | awk 'NR>1 && $2=="device"' | grep -q .; }
if ! device_ready; then
  # Try to auto-start the first available emulator image.
  EMU="$(command -v emulator || echo "$HOME/Android/Sdk/emulator/emulator")"
  if [ -x "$EMU" ] && [ -n "$("$EMU" -list-avds 2>/dev/null | head -1)" ]; then
    AVD="$("$EMU" -list-avds | head -1)"
    say "starting emulator '$AVD' (first boot can take a minute)"
    "$EMU" -avd "$AVD" >/dev/null 2>&1 &
    for _ in $(seq 1 60); do device_ready && break; sleep 5; done
    adb wait-for-device
    # Wait for full boot before installing.
    until [ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = "1" ]; do sleep 3; done
  fi
fi
if ! device_ready; then
  echo "No Android device/emulator available. Create one in Android Studio's"
  echo "Device Manager (see docs/DEMO.md §0.3), start it, and re-run — or use --no-run."
  exit 1
fi

say "installing debug app"
flutter build apk --debug
flutter install

say "sideloading content"
tool/sideload_android.sh

say "launching"
exec flutter run

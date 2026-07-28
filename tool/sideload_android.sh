#!/usr/bin/env bash
# Sideload the demo starter pack + scope & sequence into a connected Android
# emulator/device, so the app boots with content instead of an empty trail.
#
# Prereqs: `adb` on PATH, exactly one device/emulator connected (or
# ANDROID_SERIAL set), and the DEBUG app installed on it (run
# `flutter run` at least once first — `run-as` only works on debug builds).
#
# Usage: tool/sideload_android.sh
# Then fully relaunch the app (stop it, start it) to pick the content up —
# the content directories are scanned once at boot.
set -euo pipefail
cd "$(dirname "$0")/.."

PKG=com.learntoread.learn_to_read
STAGE=build/sideload/starter_pack

echo "==> generating any missing placeholder assets"
dart run tool/demo_content.dart

echo "==> building the checksummed pack manifest"
dart run tool/pack_build.dart content/demo build/starter_pack/manifest.json \
  --levels=content/demo/levels.json \
  --heart-words=content/demo/heart_words.json \
  --starter-levels=level.demo.1,level.demo.2,level.demo.3

echo "==> staging"
rm -rf build/sideload
mkdir -p "$STAGE"
cp build/starter_pack/manifest.json "$STAGE/manifest.json"
for d in words narration celebrations prompts vocab rive phonemes audio; do
  [ -d "content/demo/$d" ] && cp -r "content/demo/$d" "$STAGE/$d"
done
cp content/demo/scope_sequence.json build/sideload/scope_sequence.json

echo "==> pushing to device"
adb shell rm -rf /data/local/tmp/learntoread
adb push build/sideload /data/local/tmp/learntoread
adb shell run-as "$PKG" sh -c \
  "rm -rf files/starter_pack && mkdir -p files \
   && cp -r /data/local/tmp/learntoread/starter_pack files/starter_pack \
   && cp /data/local/tmp/learntoread/scope_sequence.json files/scope_sequence.json"
adb shell rm -rf /data/local/tmp/learntoread

echo "==> done. Fully stop and relaunch the app to load the content."

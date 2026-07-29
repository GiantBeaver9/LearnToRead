# One-shot setup + run for LearnToRead — Windows (PowerShell).
#
#   powershell -ExecutionPolicy Bypass -File tool\setup_and_run.ps1
#   ... or from PowerShell:  .\tool\setup_and_run.ps1 [-SkipTests] [-NoRun]
#
# The repo already contains the fully voiced audio set, so no TTS step is
# needed here (the bash script's Piper step exists for regenerating audio
# after content changes; do that on Linux/WSL or ask the pipeline owner).
param([switch]$SkipTests, [switch]$NoRun)
$ErrorActionPreference = "Stop"
Set-Location (Join-Path $PSScriptRoot "..")

function Say($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }

Say "checking toolchain"
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
  Write-Host "flutter not found on PATH. Install: https://docs.flutter.dev/get-started/install"
  exit 1
}
flutter --version | Select-Object -First 1

Say "fetching dependencies"
flutter pub get

Say "generating demo content (placeholders only for anything missing)"
dart run tool/demo_content.dart

Say "building + validating the story pack"
dart run tool/pack_build.dart content/demo build/starter_pack/manifest.json `
  --levels=content/demo/levels.json `
  --heart-words=content/demo/heart_words.json `
  --starter-levels=level.demo.1,level.demo.2,level.demo.3
if ($LASTEXITCODE -ne 0) { Write-Host "pack build failed"; exit 1 }

if (-not $SkipTests) {
  Say "running the test suite"
  flutter test
  if ($LASTEXITCODE -ne 0) { Write-Host "tests failed"; exit 1 }
} else { Say "skipping tests (-SkipTests)" }

if ($NoRun) { Say "done (-NoRun)"; exit 0 }

Say "locating the Android SDK (adb is usually not on PATH on Windows)"
if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
  $sdk = $env:ANDROID_HOME
  if (-not $sdk -or -not (Test-Path $sdk)) { $sdk = $env:ANDROID_SDK_ROOT }
  if (-not $sdk -or -not (Test-Path $sdk)) { $sdk = Join-Path $env:LOCALAPPDATA "Android\Sdk" }
  $platformTools = Join-Path $sdk "platform-tools"
  if (Test-Path (Join-Path $platformTools "adb.exe")) {
    $env:Path = "$platformTools;$env:Path"
    Write-Host "using adb from $platformTools"
  } else {
    Write-Host "Could not find adb.exe. Install Android Studio (or set ANDROID_HOME),"
    Write-Host "then re-run. Expected at: $platformTools\adb.exe"
    exit 1
  }
}

Say "looking for a device"
function DeviceReady {
  (adb devices 2>$null | Select-Object -Skip 1 | Where-Object { $_ -match "\bdevice$" }).Count -gt 0
}
if (-not (DeviceReady)) {
  $emu = Join-Path $env:LOCALAPPDATA "Android\Sdk\emulator\emulator.exe"
  if (Test-Path $emu) {
    $avd = (& $emu -list-avds 2>$null | Where-Object { $_ -ne "" } | Select-Object -First 1)
    if ($avd) {
      Say "starting emulator '$avd' (first boot can take a minute)"
      Start-Process $emu -ArgumentList "-avd", $avd | Out-Null
      adb wait-for-device
      do { Start-Sleep 3; $boot = (adb shell getprop sys.boot_completed 2>$null) } `
        until ("$boot".Trim() -eq "1")
    }
  }
}
if (-not (DeviceReady)) {
  Write-Host "No Android device/emulator available. Create one in Android Studio's"
  Write-Host "Device Manager (docs/DEMO.md section 0.3), start it, and re-run."
  exit 1
}

$model = (adb shell getprop ro.product.model 2>$null)
if ("$model" -match "16k") {
  Write-Host ""
  Write-Host "This emulator ('$($model.Trim())') is a 16 KB page-size image, which crashes" -ForegroundColor Yellow
  Write-Host "prebuilt native libraries at load (silent freeze on the splash screen)." -ForegroundColor Yellow
  Write-Host "Create a standard API 34/35 x86_64 'Google APIs' AVD instead (docs/DEMO.md)." -ForegroundColor Yellow
  exit 1
}

Say "building + installing debug app"
flutter build apk --debug
if ($LASTEXITCODE -ne 0) { Write-Host "apk build failed"; exit 1 }
adb install -r build\app\outputs\flutter-apk\app-debug.apk
if ($LASTEXITCODE -ne 0) { Write-Host "install failed"; exit 1 }

Say "sideloading content"
if (Test-Path build\sideload) { Remove-Item -Recurse -Force build\sideload }
New-Item -ItemType Directory -Force build\sideload\starter_pack | Out-Null
Copy-Item build\starter_pack\manifest.json build\sideload\starter_pack\manifest.json
foreach ($d in @("words","narration","celebrations","prompts","vocab","rive","phonemes","audio")) {
  if (Test-Path "content\demo\$d") { Copy-Item -Recurse "content\demo\$d" "build\sideload\starter_pack\$d" }
}
Copy-Item content\demo\scope_sequence.json build\sideload\scope_sequence.json
adb shell rm -rf /data/local/tmp/learntoread
adb push build\sideload /data/local/tmp/learntoread | Out-Null
# One adb call per step — PowerShell quoting mangles `sh -c "a && b"` chains.
adb shell run-as com.learntoread.learn_to_read rm -rf files/starter_pack
adb shell run-as com.learntoread.learn_to_read mkdir -p files
adb shell run-as com.learntoread.learn_to_read cp -r /data/local/tmp/learntoread/starter_pack files/starter_pack
adb shell run-as com.learntoread.learn_to_read cp /data/local/tmp/learntoread/scope_sequence.json files/scope_sequence.json
adb shell rm -rf /data/local/tmp/learntoread
$staged = adb shell run-as com.learntoread.learn_to_read ls files/starter_pack 2>$null
if ("$staged" -match "manifest.json") { Say "content verified on device" }
else { Write-Host "WARNING: sideload verification failed - the app will boot with an empty library" }

Say "launching (fully stop + relaunch later picks content up too)"
flutter run

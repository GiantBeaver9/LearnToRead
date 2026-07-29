# One-shot setup + run for LearnToRead — Windows (PowerShell).
#
#   powershell -ExecutionPolicy Bypass -File tool\setup_and_run.ps1
#   ... or from PowerShell:  .\tool\setup_and_run.ps1 [-SkipTests] [-NoRun] [-RebuildContent]
#
# Builds and installs the RELEASE apk. The demo content ships inside the APK
# as assets\starter_content.bin (committed) and the app extracts it into its
# support directory on first launch — no sideloading, no debug build needed.
#
# -RebuildContent regenerates the demo content, rebuilds the checksummed
# pack manifest, and re-bundles the archive (pack development only). The
# bash script's Piper TTS step is not mirrored here; (re)voice audio on
# Linux/WSL or ask the pipeline owner.
param([switch]$SkipTests, [switch]$NoRun, [switch]$RebuildContent)
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

if ($RebuildContent) {
  Say "generating demo content (placeholders only for anything missing)"
  dart run tool/demo_content.dart
  if ($LASTEXITCODE -ne 0) { Write-Host "demo content generation failed"; exit 1 }

  Say "building + validating the story pack"
  dart run tool/pack_build.dart content/demo build/starter_pack/manifest.json `
    --levels=content/demo/levels.json `
    --heart-words=content/demo/heart_words.json `
    --starter-levels=level.demo.1,level.demo.2,level.demo.3
  if ($LASTEXITCODE -ne 0) { Write-Host "pack build failed"; exit 1 }

  Say "bundling content into assets\starter_content.bin"
  dart run tool/bundle_content.dart
  if ($LASTEXITCODE -ne 0) { Write-Host "content bundling failed"; exit 1 }
} else {
  Say "using committed assets\starter_content.bin (-RebuildContent to regenerate)"
  if (-not (Test-Path "assets\starter_content.bin")) {
    Write-Host "assets\starter_content.bin is missing - re-run with -RebuildContent"
    exit 1
  }
}

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

Say "building release app (first release build takes a few minutes: R8 + AOT)"
flutter build apk --release
if ($LASTEXITCODE -ne 0) { Write-Host "apk build failed"; exit 1 }

Say "installing release app (content extracts itself on first launch)"
adb install -r build\app\outputs\flutter-apk\app-release.apk
if ($LASTEXITCODE -ne 0) { Write-Host "install failed"; exit 1 }

Say "launching"
flutter run --release

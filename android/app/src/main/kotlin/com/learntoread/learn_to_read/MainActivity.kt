package com.learntoread.learn_to_read

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Unit 0 spike channels (docs/spike/README.md). Committed so the
        // owner's spike run needs no local edits; harmless when running
        // the main app, which never opens these channels. The
        // platform-asr-adapter unit adds its own registration here
        // alongside this one.
        SpikeSpeechHandler.register(flutterEngine.dartExecutor.binaryMessenger, applicationContext)
        // Production on-device ASR adapter (PRD §9 A-10) — the native half of
        // lib/features/listening/engine/platform_asr_engine.dart.
        AsrSpeechHandler.register(flutterEngine.dartExecutor.binaryMessenger, applicationContext)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // The spike handler (and later the real ASR adapter) surfaces a
        // permission error rather than requesting the permission itself,
        // so ask up front on first launch.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            checkSelfPermission(Manifest.permission.RECORD_AUDIO) !=
                PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), 0)
        }
    }
}

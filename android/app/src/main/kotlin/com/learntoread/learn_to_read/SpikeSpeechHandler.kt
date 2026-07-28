package com.learntoread.learn_to_read

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Unit 0 recognition-spike native handler (Android).
 *
 * DISPOSABLE spike code (PRD.md §8 Unit 0) — not wired into the main app,
 * and not architected for reuse by the platform-asr-adapter ticket.
 *
 * Registration is NOT automatic: MainActivity.kt is owned by the
 * platform-asr-adapter ticket, and this ticket deliberately does not edit
 * it (disjoint file ownership; see the ticket notes). To run the spike on a
 * device, register this handler by hand — see docs/spike/README.md for the
 * exact two-line snippet to add to MainActivity.kt locally before
 * `flutter run -t lib/spike/spike_main.dart`.
 *
 * Channel contract — MUST match lib/spike/spike_channel.dart
 * (SpikeChannel.methodChannelName / SpikeChannel.eventChannelName) and the
 * payload shape lib/spike/hypothesis_log.dart
 * (HypothesisEvent.fromChannelPayload) decodes:
 *
 *   method channel "learn_to_read/spike/method":
 *     "start" -> arguments: { "sentence": String, "biasingWords": [String] }
 *     "stop"  -> arguments: none
 *
 *   event channel "learn_to_read/spike/events" emits, per hypothesis:
 *     {
 *       "timestampMs": Long,      // millis since epoch (UTC)
 *       "isFinal": Boolean,
 *       "text": String,
 *       "confidence": Double?,    // omitted if the platform has none
 *       "biasingWords": [String],
 *       // "phoneDetail" is INTENTIONALLY OMITTED: Android SpeechRecognizer
 *       // does not expose phone-level detail. Presence of the key (not its
 *       // emptiness) is what hypothesis_log.dart records as
 *       // phoneDetailPresent — this is the Unit 0 / Unit 14 question this
 *       // spike exists to answer. If a future engine swap exposes
 *       // phone-level detail, populate this key (even with an empty list)
 *       // below.
 *     }
 */
class SpikeSpeechHandler(private val context: Context) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL_NAME = "learn_to_read/spike/method"
        const val EVENT_CHANNEL_NAME = "learn_to_read/spike/events"

        /**
         * Registers the method + event channels against [messenger]. Call
         * once from MainActivity.kt's configureFlutterEngine — see
         * docs/spike/README.md.
         */
        fun register(messenger: BinaryMessenger, context: Context) {
            val instance = SpikeSpeechHandler(context)
            MethodChannel(messenger, METHOD_CHANNEL_NAME).setMethodCallHandler(instance)
            EventChannel(messenger, EVENT_CHANNEL_NAME).setStreamHandler(instance)
        }
    }

    private var speechRecognizer: SpeechRecognizer? = null
    private var eventSink: EventChannel.EventSink? = null
    private var currentBiasingWords: List<String> = emptyList()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val biasingWords = call.argument<List<String>>("biasingWords") ?: emptyList()
                start(biasingWords, result)
            }
            "stop" -> stop(result)
            else -> result.notImplemented()
        }
    }

    private fun start(biasingWords: List<String>, result: MethodChannel.Result) {
        currentBiasingWords = biasingWords

        if (!SpeechRecognizer.isRecognitionAvailable(context)) {
            result.error("ENGINE_UNAVAILABLE", "SpeechRecognizer unavailable on this device", null)
            return
        }

        val recognizer = SpeechRecognizer.createSpeechRecognizer(context)
        speechRecognizer = recognizer
        recognizer.setRecognitionListener(
            object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {}
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}
                override fun onEvent(eventType: Int, params: Bundle?) {}

                override fun onError(error: Int) {
                    eventSink?.error("ENGINE_UNAVAILABLE", "SpeechRecognizer error code $error", null)
                }

                override fun onResults(results: Bundle) {
                    emitHypothesis(results, isFinal = true)
                }

                override fun onPartialResults(partialResults: Bundle) {
                    emitHypothesis(partialResults, isFinal = false)
                }
            }
        )

        val intent =
            Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                putExtra(RecognizerIntent.EXTRA_CONFIDENCE_SCORES, true)
                // Contextual biasing (A-10): bias toward the spike's
                // hardcoded sentence's words, as passed from
                // spikeBiasingWordsFor(). EXTRA_BIASING_STRINGS is API 33+;
                // below that, biasing is unavailable on-device and this
                // extra is simply ignored by the platform.
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    putStringArrayListExtra(
                        RecognizerIntent.EXTRA_BIASING_STRINGS, ArrayList(biasingWords)
                    )
                }
            }

        recognizer.startListening(intent)
        result.success(null)
    }

    private fun stop(result: MethodChannel.Result) {
        val recognizer = speechRecognizer
        if (recognizer == null) {
            result.error("STOP_FAILED", "engine already stopped", null)
            return
        }
        recognizer.stopListening()
        recognizer.destroy()
        speechRecognizer = null
        result.success(null)
    }

    private fun emitHypothesis(results: Bundle, isFinal: Boolean) {
        val matches = results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        val text = matches?.firstOrNull() ?: ""
        val scores = results.getFloatArray(SpeechRecognizer.CONFIDENCE_SCORES)

        val payload = HashMap<String, Any?>()
        payload["timestampMs"] = System.currentTimeMillis()
        payload["isFinal"] = isFinal
        payload["text"] = text
        payload["biasingWords"] = currentBiasingWords
        if (scores != null && scores.isNotEmpty()) {
            payload["confidence"] = scores[0].toDouble()
        }

        eventSink?.success(payload)
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}

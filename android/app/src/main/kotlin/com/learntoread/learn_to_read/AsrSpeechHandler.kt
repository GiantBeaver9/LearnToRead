package com.learntoread.learn_to_read

import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Production on-device ASR handler (PRD §9 A-10; platform-asr-adapter).
 *
 * The Android half of `lib/features/listening/engine/platform_asr_engine.dart`
 * (`PlatformAsrEngine`). The channel pattern is the one PROVEN by the Unit 0
 * spike (`SpikeSpeechHandler.kt`, which stays untouched and disposable); this
 * is its production sibling on its own channel names.
 *
 * Channel contract — MUST match platform_asr_engine.dart exactly:
 *
 *   method channel "learn_to_read/asr/method":
 *     "start" -> arguments: { "biasingWords": [String] }
 *                (re)starts continuous recognition biased toward the
 *                expected sentence words. Calling start while started is a
 *                graceful stop-then-restart (the AsrEngine contract's pick).
 *     "stop"  -> arguments: none. Cancels recognition and exits the restart
 *                loop. Idempotent: stopping a stopped engine succeeds.
 *
 *   event channel "learn_to_read/asr/events" emits, per hypothesis burst:
 *     {
 *       "words": [String],   // top alternatives, best first (never empty)
 *       "isFinal": Boolean   // false for partials, true for finals
 *     }
 *     Phone-level detail is INTENTIONALLY ABSENT: Android SpeechRecognizer
 *     exposes none (the Unit 0 spike finding); the Dart side maps every
 *     payload to Hypothesis(phoneHypotheses: null).
 *
 *   Unrecoverable failures (permission denied, recognizer unavailable, or a
 *   restart loop that keeps failing) surface as a SINGLE error event on the
 *   event channel and end the loop — never a crash-loop of restarts.
 *
 * ## Continuous listening (the restart loop)
 *
 * Android SpeechRecognizer is utterance-scoped: it finalizes one utterance
 * and stops. A child reads many utterances per page, so while in the started
 * state this handler automatically begins a new recognition round:
 *   - after every onResults (the normal end of an utterance), and
 *   - after recoverable errors: ERROR_NO_MATCH, ERROR_SPEECH_TIMEOUT (the
 *     child paused), and ERROR_CLIENT (also fired after cancel — guarded by
 *     the started flag so a stop never triggers a restart).
 * Every other error code is retried through the same backoff path, EXCEPT
 * ERROR_INSUFFICIENT_PERMISSIONS which is immediately fatal.
 *
 * ## Restart backoff rule
 *
 * A round that produced results restarts immediately. A round that errored
 * restarts after BASE_RESTART_DELAY_MS * 2^(n-1) capped at
 * MAX_RESTART_DELAY_MS, where n is the current run of consecutive errored
 * rounds. Any partial or final result resets the run to zero. After
 * MAX_CONSECUTIVE_ERRORS errored rounds in a row the engine gives up: one
 * "ENGINE_UNAVAILABLE" error event, loop ends. This is what keeps a
 * RECOGNIZER_BUSY loop (or a device with a broken recognition service) from
 * spinning forever.
 *
 * ## Round-chime muting
 *
 * The system recognizer plays its listening start/stop chime on every round,
 * and the continuous loop rounds many times per page — a constant
 * bloop-bloop over the child's reading. While the loop is ACTIVE (from the
 * first successful start until stop/fatal/detach — NOT per round) the
 * NOTIFICATION and SYSTEM streams, which the chime plays on, are muted via
 * [AudioManager.adjustStreamVolume]. STREAM_MUSIC is deliberately untouched:
 * that is where the app's own narration/phoneme/TTS clips play.
 *
 * Tradeoff, accepted: other apps' notification beeps are also silenced while
 * a child is reading — a reasonable price for a chime-free reading session,
 * and the streams are ALWAYS restored when the loop ends. Only streams this
 * handler itself muted are unmuted (a stream the user already had muted
 * stays muted). Some devices throw SecurityException from volume calls under
 * Do Not Disturb; each call is wrapped and degrades silently (chimes then
 * remain audible, nothing else breaks).
 *
 * All SpeechRecognizer calls happen on the main thread (a SpeechRecognizer
 * requirement). Flutter delivers method calls on the main thread already;
 * [mainHandler] additionally serializes the delayed restarts onto it.
 */
class AsrSpeechHandler(private val context: Context) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL_NAME = "learn_to_read/asr/method"
        const val EVENT_CHANNEL_NAME = "learn_to_read/asr/events"

        /** Consecutive errored rounds tolerated before giving up for good. */
        const val MAX_CONSECUTIVE_ERRORS = 8

        /** First-retry delay after an errored round. */
        const val BASE_RESTART_DELAY_MS = 300L

        /** Backoff ceiling. */
        const val MAX_RESTART_DELAY_MS = 2000L

        /** How many alternatives to request per hypothesis (top-N words). */
        const val MAX_RESULTS = 3

        /**
         * Round-lengthening extras (Google's recognizer honors these on most
         * devices; harmless where ignored — hence device-verified only).
         * Longer rounds = fewer restarts = fewer chime/focus events. Values
         * are Int: the platform recognizer reads these extras as ints.
         */

        /** Silence after speech before the round finalizes (default ~1s). */
        const val ROUND_COMPLETE_SILENCE_MS = 5000

        /** Silence after a POSSIBLY complete utterance before finalizing. */
        const val ROUND_POSSIBLY_COMPLETE_SILENCE_MS = 5000

        /** Minimum length of one recognition round. */
        const val ROUND_MINIMUM_LENGTH_MS = 15000

        /**
         * The streams the recognizer's round chime plays on. STREAM_MUSIC is
         * deliberately absent — the app's own clips play there.
         */
        val CHIME_STREAMS = intArrayOf(
            AudioManager.STREAM_NOTIFICATION,
            AudioManager.STREAM_SYSTEM,
        )

        /**
         * Registers the method + event channels against [messenger]. Called
         * once from MainActivity.configureFlutterEngine.
         */
        fun register(messenger: BinaryMessenger, context: Context) {
            val instance = AsrSpeechHandler(context)
            MethodChannel(messenger, METHOD_CHANNEL_NAME).setMethodCallHandler(instance)
            EventChannel(messenger, EVENT_CHANNEL_NAME).setStreamHandler(instance)
        }
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val restartRunnable = Runnable { startRound() }

    private var recognizer: SpeechRecognizer? = null
    private var eventSink: EventChannel.EventSink? = null
    private var biasingWords: List<String> = emptyList()

    /** True between a successful "start" and the matching "stop"/fatal error. */
    private var started = false

    /** Current run of consecutive errored rounds (reset by any result). */
    private var consecutiveErrors = 0

    /**
     * The chime streams THIS handler muted (i.e. they were not already muted
     * when the loop started). Exactly these — and only these — are unmuted
     * when the loop ends, so a user's own pre-existing mute is respected.
     */
    private val mutedChimeStreams = mutableListOf<Int>()

    // --- method channel -----------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                val words = call.argument<List<String>>("biasingWords") ?: emptyList()
                start(words, result)
            }
            "stop" -> {
                stopInternal()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun start(words: List<String>, result: MethodChannel.Result) {
        if (!SpeechRecognizer.isRecognitionAvailable(context)) {
            result.error(
                "ENGINE_UNAVAILABLE",
                "SpeechRecognizer unavailable on this device (no recognition service)",
                null,
            )
            return
        }
        // start-while-started: graceful stop-then-restart (AsrEngine contract:
        // "implementations should handle gracefully").
        stopInternal()
        biasingWords = words
        started = true
        consecutiveErrors = 0
        // Loop-scoped, not round-scoped: muted once here, restored only by
        // stopInternal (stop / fatal / start-while-started / detach).
        muteChimeStreams()
        startRound()
        result.success(null)
    }

    private fun stopInternal() {
        started = false
        mainHandler.removeCallbacks(restartRunnable)
        recognizer?.let {
            // cancel() (not stopListening()): discard the in-flight utterance
            // rather than waiting for it to finalize — a stopped tracker must
            // not receive one last burst. The ERROR_CLIENT this can fire is
            // ignored because started is already false.
            it.cancel()
            it.destroy()
        }
        recognizer = null
        consecutiveErrors = 0
        restoreChimeStreams()
    }

    // --- round-chime muting ---------------------------------------------------

    /**
     * Mutes the streams the recognizer's listening chime plays on, for the
     * whole life of the loop. Remembers which streams it muted itself so
     * [restoreChimeStreams] never unmutes a stream the user had muted.
     * API 23+ only (ADJUST_MUTE / isStreamMute); older devices keep their
     * chimes. Every call degrades silently — some devices throw
     * SecurityException from volume adjustment under Do Not Disturb, and a
     * still-chiming loop beats a crashed one.
     */
    private fun muteChimeStreams() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        if (mutedChimeStreams.isNotEmpty()) return // Already muted by us.
        val audioManager =
            context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager ?: return
        for (stream in CHIME_STREAMS) {
            try {
                if (!audioManager.isStreamMute(stream)) {
                    audioManager.adjustStreamVolume(stream, AudioManager.ADJUST_MUTE, 0)
                    mutedChimeStreams.add(stream)
                }
            } catch (_: Exception) {
                // DND SecurityException et al.: this stream keeps its chime.
            }
        }
    }

    /** Unmutes exactly the streams [muteChimeStreams] muted. Idempotent. */
    private fun restoreChimeStreams() {
        if (mutedChimeStreams.isEmpty()) return
        val audioManager =
            context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        if (audioManager != null) {
            for (stream in mutedChimeStreams) {
                try {
                    audioManager.adjustStreamVolume(stream, AudioManager.ADJUST_UNMUTE, 0)
                } catch (_: Exception) {
                    // Best effort; never let a restore failure break teardown.
                }
            }
        }
        mutedChimeStreams.clear()
    }

    // --- the continuous-recognition loop -------------------------------------

    /** Begins one recognition round. No-op once stopped. Main thread only. */
    private fun startRound() {
        if (!started) return
        val r = recognizer ?: SpeechRecognizer.createSpeechRecognizer(context).also {
            it.setRecognitionListener(listener)
            recognizer = it
        }
        r.startListening(buildIntent())
    }

    /** Schedules the next round, [delayMs] from now. Cancels any pending one. */
    private fun scheduleRestart(delayMs: Long) {
        if (!started) return
        mainHandler.removeCallbacks(restartRunnable)
        if (delayMs <= 0L) {
            // Still posted (not called inline): restarting from inside a
            // RecognitionListener callback is flaky on some OEM recognizers.
            mainHandler.post(restartRunnable)
        } else {
            mainHandler.postDelayed(restartRunnable, delayMs)
        }
    }

    /** BASE * 2^(errorRun-1), capped at MAX. */
    private fun backoffDelayMs(): Long {
        var delay = BASE_RESTART_DELAY_MS
        for (i in 1 until consecutiveErrors) {
            delay *= 2
            if (delay >= MAX_RESTART_DELAY_MS) return MAX_RESTART_DELAY_MS
        }
        return minOf(delay, MAX_RESTART_DELAY_MS)
    }

    /** Fatal: emit one error event and end the loop. Never crash-loops. */
    private fun failFatally(code: String, message: String) {
        stopInternal()
        eventSink?.error(code, message, null)
    }

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) {}
        override fun onBeginningOfSpeech() {}
        override fun onRmsChanged(rmsdB: Float) {}
        override fun onBufferReceived(buffer: ByteArray?) {}
        override fun onEndOfSpeech() {}
        override fun onEvent(eventType: Int, params: Bundle?) {}

        override fun onPartialResults(partialResults: Bundle) {
            if (!started) return
            if (emitHypothesis(partialResults, isFinal = false)) {
                consecutiveErrors = 0
            }
        }

        override fun onResults(results: Bundle) {
            if (!started) return
            emitHypothesis(results, isFinal = true)
            consecutiveErrors = 0
            // Utterance finalized — the recognizer round is over. Start the
            // next one so listening is continuous across the whole page.
            scheduleRestart(0L)
        }

        override fun onError(error: Int) {
            // A stop (or a fatal failure) already ended the loop; the
            // ERROR_CLIENT fired by cancel() lands here and is ignored.
            if (!started) return

            if (error == SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS) {
                failFatally(
                    "MIC_PERMISSION_DENIED",
                    "RECORD_AUDIO permission not granted (SpeechRecognizer error $error)",
                )
                return
            }

            // Everything else is retried: ERROR_NO_MATCH / ERROR_SPEECH_TIMEOUT
            // are the normal cadence of a pausing child; ERROR_CLIENT,
            // ERROR_RECOGNIZER_BUSY and transient audio/network errors get the
            // same backoff path, bounded by the consecutive-error guard so a
            // busy/broken recognizer can never crash-loop restarts.
            consecutiveErrors += 1
            if (consecutiveErrors > MAX_CONSECUTIVE_ERRORS) {
                failFatally(
                    "ENGINE_UNAVAILABLE",
                    "SpeechRecognizer failed $consecutiveErrors consecutive rounds " +
                        "(last error $error); giving up",
                )
                return
            }
            // Destroy and recreate: several error codes (BUSY, CLIENT) leave
            // the recognizer instance unusable.
            recognizer?.destroy()
            recognizer = null
            scheduleRestart(backoffDelayMs())
        }
    }

    // --- recognizer config ----------------------------------------------------

    private fun buildIntent(): Intent =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, MAX_RESULTS)
            // Longer rounds (demo polish): a child pausing between words was
            // finalizing rounds every couple of seconds, so restarts (and
            // their chime/focus churn) were constant. Honored by Google's
            // recognizer on most devices; harmless where ignored. onResults
            // still restarts immediately; NO_MATCH/TIMEOUT keep the backoff.
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS,
                ROUND_COMPLETE_SILENCE_MS,
            )
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS,
                ROUND_POSSIBLY_COMPLETE_SILENCE_MS,
            )
            putExtra(
                RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS,
                ROUND_MINIMUM_LENGTH_MS,
            )
            // Contextual biasing (A-10): the expected sentence words, exactly
            // as ReadingTracker passes them ("never open-ended transcription",
            // PRD §6). EXTRA_BIASING_STRINGS is API 33+; below that the extra
            // would be unknown to the platform, so it is guarded — recognition
            // still runs, just unbiased (the spike-proven pattern).
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                putStringArrayListExtra(
                    RecognizerIntent.EXTRA_BIASING_STRINGS,
                    ArrayList(biasingWords),
                )
            }
        }

    // --- event emission ---------------------------------------------------------

    /**
     * Emits one hypothesis event; returns whether anything was emitted
     * (Android fires empty/blank partial bundles routinely — dropped here so
     * the Dart side never sees an empty wordHypotheses list).
     */
    private fun emitHypothesis(results: Bundle, isFinal: Boolean): Boolean {
        val matches =
            results.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION) ?: return false
        val words = matches.filter { it.isNotBlank() }
        if (words.isEmpty()) return false
        eventSink?.success(
            hashMapOf<String, Any?>(
                "words" to words,
                "isFinal" to isFinal,
            ),
        )
        return true
    }

    // --- event channel -----------------------------------------------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
        // Detach: nobody is listening for hypotheses any more (Dart-side
        // dispose / engine hot-restart), so a still-running loop would only
        // hold the mic and keep the chime streams muted forever. End the
        // loop — which also ALWAYS restores the muted streams.
        stopInternal()
    }
}

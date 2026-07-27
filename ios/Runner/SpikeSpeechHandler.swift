import AVFoundation
import Flutter
import Speech

/// Unit 0 recognition-spike native handler (iOS).
///
/// DISPOSABLE spike code (PRD.md §8 Unit 0) — not wired into the main app,
/// and not architected for reuse by the platform-asr-adapter ticket.
///
/// Registration is NOT automatic: `ios/Runner/AppDelegate.swift` is owned by
/// the platform-asr-adapter ticket, and this ticket deliberately does not
/// edit it (disjoint file ownership; see the ticket notes). To run the
/// spike on a device, register this handler by hand — see
/// `docs/spike/README.md` for the exact two-line snippet to add to
/// `AppDelegate.swift` locally before `flutter run -t lib/spike/spike_main.dart`.
///
/// Channel contract — MUST match `lib/spike/spike_channel.dart`
/// (`SpikeChannel.methodChannelName` / `SpikeChannel.eventChannelName`) and
/// the payload shape `lib/spike/hypothesis_log.dart`
/// (`HypothesisEvent.fromChannelPayload`) decodes:
///
///   method channel "learn_to_read/spike/method":
///     "start" -> arguments: { "sentence": String, "biasingWords": [String] }
///     "stop"  -> arguments: none
///
///   event channel "learn_to_read/spike/events" emits, per hypothesis:
///     {
///       "timestampMs": Int64,        // millis since epoch (UTC)
///       "isFinal": Bool,
///       "text": String,
///       "confidence": Double?,       // omitted if the platform has none
///       "biasingWords": [String],
///       // "phoneDetail" is INTENTIONALLY OMITTED: SFSpeechRecognizer does
///       // not expose phone-level detail as of this spike. Presence of the
///       // key (not its emptiness) is what hypothesis_log.dart records as
///       // phoneDetailPresent — this is the Unit 0 / Unit 14 question this
///       // spike exists to answer. If a future SDK exposes phone-level
///       // detail, populate this key (even with an empty array) below.
///     }
final class SpikeSpeechHandler: NSObject, FlutterStreamHandler {
    static let methodChannelName = "learn_to_read/spike/method"
    static let eventChannelName = "learn_to_read/spike/events"

    /// Registers the method + event channels against `registrar`. Call once
    /// from `AppDelegate.swift` after `GeneratedPluginRegistrant.register`
    /// — see docs/spike/README.md.
    static func register(with registrar: FlutterPluginRegistrar) {
        let instance = SpikeSpeechHandler()
        let methodChannel = FlutterMethodChannel(
            name: methodChannelName, binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(
            name: eventChannelName, binaryMessenger: registrar.messenger())
        eventChannel.setStreamHandler(instance)
        methodChannel.setMethodCallHandler { call, result in
            switch call.method {
            case "start":
                let args = call.arguments as? [String: Any]
                let biasingWords = args?["biasingWords"] as? [String] ?? []
                instance.start(biasingWords: biasingWords, result: result)
            case "stop":
                instance.stop(result: result)
            default:
                result(FlutterMethodNotImplemented)
            }
        }
    }

    private let audioEngine = AVAudioEngine()
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var eventSink: FlutterEventSink?
    private var currentBiasingWords: [String] = []

    private func start(biasingWords: [String], result: @escaping FlutterResult) {
        currentBiasingWords = biasingWords

        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            DispatchQueue.main.async {
                guard authStatus == .authorized else {
                    result(FlutterError(
                        code: "MIC_PERMISSION_DENIED",
                        message: "Speech recognition authorization denied (\(authStatus.rawValue))",
                        details: nil))
                    return
                }
                self?.beginRecognition(result: result)
            }
        }
    }

    private func beginRecognition(result: @escaping FlutterResult) {
        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        speechRecognizer = recognizer

        guard let recognizer, recognizer.isAvailable else {
            result(FlutterError(
                code: "ENGINE_UNAVAILABLE", message: "SFSpeechRecognizer unavailable", details: nil))
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Contextual biasing (A-10): bias toward the spike's hardcoded
        // sentence's words, as passed from spikeBiasingWordsFor().
        request.contextualStrings = currentBiasingWords
        recognitionRequest = request

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            result(FlutterError(code: "ENGINE_UNAVAILABLE", message: "\(error)", details: nil))
            return
        }

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) {
            [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            result(FlutterError(code: "ENGINE_UNAVAILABLE", message: "\(error)", details: nil))
            return
        }

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] taskResult, error in
            guard let self else { return }
            if let error {
                self.eventSink?(FlutterError(
                    code: "ENGINE_UNAVAILABLE", message: error.localizedDescription, details: nil))
                return
            }
            guard let taskResult else { return }
            self.emitHypothesis(from: taskResult)
        }

        result(nil)
    }

    private func stop(result: @escaping FlutterResult) {
        guard audioEngine.isRunning else {
            result(FlutterError(code: "STOP_FAILED", message: "engine already stopped", details: nil))
            return
        }
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        result(nil)
    }

    private func emitHypothesis(from taskResult: SFSpeechRecognitionResult) {
        let transcription = taskResult.bestTranscription

        var payload: [String: Any] = [
            "timestampMs": Int64(Date().timeIntervalSince1970 * 1000),
            "isFinal": taskResult.isFinal,
            "text": transcription.formattedString,
            "biasingWords": currentBiasingWords,
        ]

        // SFTranscriptionSegment.confidence is 0.0 when the platform has no
        // meaningful confidence to report; the spike reports it as-is (the
        // A-10 question is granularity/reliability, not papering over gaps).
        if let segment = transcription.segments.last {
            payload["confidence"] = Double(segment.confidence)
        }

        eventSink?(payload)
    }

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
        -> FlutterError?
    {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }
}

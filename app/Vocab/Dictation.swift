import AVFoundation
import Speech

/// Voice dictation for the Ask composer. Uses Apple's speech recognizer,
/// on-device whenever the device supports it (free, private, works offline).
@Observable
final class Dictation {
    private(set) var isRecording = false
    /// Everything recognised since `start()`; replaced as the recognizer refines it.
    private(set) var transcript = ""
    private(set) var error: String?

    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognition: SFSpeechRecognitionTask?

    func toggle() async {
        if isRecording { stop() } else { await start() }
    }

    func start() async {
        error = nil
        guard await Self.authorize() else {
            error = "Allow microphone and speech recognition in Settings to dictate."
            return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")), recognizer.isAvailable else {
            error = "Dictation isn't available right now."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            request.addsPunctuation = true
            self.request = request

            Self.installTap(on: engine.inputNode, feeding: request)
            engine.prepare()
            try engine.start()

            transcript = ""
            isRecording = true
            recognition = Self.recognize(recognizer, request) { [weak self] text, finished in
                guard let self else { return }
                if let text { self.transcript = text }
                if finished { self.stop() }
            }
        } catch {
            self.error = error.localizedDescription
            stop()
        }
    }

    func stop() {
        guard isRecording || engine.isRunning else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        recognition?.finish()
        request = nil
        recognition = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // The audio tap and recognizer callbacks run on background queues, so they
    // are built outside the main actor and hop back explicitly.

    nonisolated private static func installTap(on input: AVAudioInputNode,
                                               feeding request: SFSpeechAudioBufferRecognitionRequest) {
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func recognize(
        _ recognizer: SFSpeechRecognizer,
        _ request: SFSpeechAudioBufferRecognitionRequest,
        update: @escaping @MainActor (String?, Bool) -> Void
    ) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            let text = result?.bestTranscription.formattedString
            let finished = error != nil || (result?.isFinal ?? false)
            Task { @MainActor in update(text, finished) }
        }
    }

    nonisolated private static func authorize() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }
}

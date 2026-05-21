import Foundation
import Speech
import AVFoundation
import Combine

#if os(watchOS)
import WatchKit
#endif

/// Streams microphone audio into SFSpeechRecognizer to populate a text
/// field with the recognized transcript. Pure observable model — wire it
/// to a view that displays `transcript` and binds `isRecording` to a button.
@MainActor
final class VoiceInputController: ObservableObject {
    @Published var transcript: String = ""
    @Published var isRecording: Bool = false
    @Published var errorMessage: String? = nil
    @Published var isAuthorized: Bool = false

    private let recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private let audioEngine = AVAudioEngine()
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    /// Single completion callback set by the caller for when recognition
    /// finishes (silence detected, max duration, or explicit stop).
    var onFinish: ((String) -> Void)?

    func requestAuthorization(_ completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor in
                guard let self else { return }
                self.isAuthorized = (status == .authorized)
                if status != .authorized {
                    self.errorMessage = "Speech recognition not authorized"
                }
                completion(self.isAuthorized)
            }
        }
    }

    func start() {
        guard !isRecording else { return }
        errorMessage = nil
        transcript = ""

        requestAuthorization { [weak self] granted in
            guard granted else { return }
            self?.beginCapture()
        }
    }

    func stop() {
        guard isRecording else { return }
        finishRecognition(committing: true)
    }

    func cancel() {
        guard isRecording else { return }
        finishRecognition(committing: false)
    }

    private func beginCapture() {
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition unavailable on this device."
            return
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Audio session error: \(error.localizedDescription)"
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            errorMessage = "Audio engine start failed: \(error.localizedDescription)"
            return
        }

        isRecording = true
        #if os(watchOS)
        WKInterfaceDevice.current().play(.start)
        #endif

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                }
                if let error {
                    self.errorMessage = error.localizedDescription
                    self.finishRecognition(committing: !self.transcript.isEmpty)
                } else if result?.isFinal == true {
                    self.finishRecognition(committing: true)
                }
            }
        }
    }

    private func finishRecognition(committing: Bool) {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        isRecording = false
        #if os(watchOS)
        WKInterfaceDevice.current().play(.stop)
        #endif

        if committing, !transcript.isEmpty {
            onFinish?(transcript)
        }
    }
}

import Foundation
import Speech
import AVFoundation

/// Wraps SFSpeechRecognizer + AVAudioEngine.
/// Fires `onFinalTranscript` after `silenceInterval` seconds of silence.
@MainActor
final class SpeechManager: NSObject, ObservableObject {

    @Published var isListening  = false
    @Published var transcript   = ""        // live partial
    @Published var isAvailable  = false

    /// Called with each partial result
    var onPartialTranscript: ((String) -> Void)?
    /// Called once when speech finishes (silence timeout or explicit stop)
    var onFinalTranscript:   ((String) -> Void)?
    /// Called if permission is denied or recognition unavailable
    var onError:             ((String) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var audioEngine   = AVAudioEngine()
    private var request:      SFSpeechAudioBufferRecognitionRequest?
    private var task:         SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private let silenceInterval: TimeInterval = 1.8

    override init() {
        super.init()
        recognizer?.delegate = self
        checkAuthorization()
    }

    // MARK: - Authorization

    private func checkAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor [weak self] in
                self?.isAvailable = (status == .authorized)
                if status != .authorized {
                    self?.onError?("Speech recognition not authorized.")
                }
            }
        }
    }

    func requestPermissions() {
        AVAudioSession.sharedInstance().requestRecordPermission { _ in }
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor [weak self] in
                self?.isAvailable = (status == .authorized)
            }
        }
    }

    // MARK: - Start / Stop

    func startListening() {
        guard !isListening else { return }
        guard isAvailable else {
            onError?("Speech recognition not available — check permissions.")
            return
        }

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            onError?("Audio session error: \(error.localizedDescription)")
            return
        }

        request = SFSpeechAudioBufferRecognitionRequest()
        guard let request else { return }
        request.shouldReportPartialResults = true
        request.taskHint = .dictation

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            teardown()
            onError?("Audio engine failed: \(error.localizedDescription)")
            return
        }

        transcript  = ""
        isListening = true

        task = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.transcript = text
                    self.onPartialTranscript?(text)
                    self.armSilenceTimer()
                    if result.isFinal { self.finish(text: text) }
                } else if let error {
                    if (error as NSError).code != 301 { // 301 = cancelled, ignore
                        self.teardown()
                    }
                }
            }
        }
        armSilenceTimer()
    }

    func stopListening() {
        guard isListening else { return }
        let current = transcript
        teardown()
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            onFinalTranscript?(current.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    func cancel() {
        teardown()
    }

    // MARK: - Private

    private func armSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.stopListening() }
        }
    }

    private func finish(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        teardown()
        if !trimmed.isEmpty { onFinalTranscript?(trimmed) }
    }

    private func teardown() {
        silenceTimer?.invalidate(); silenceTimer = nil
        audioEngine.stop()
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil; task = nil
        isListening = false
        transcript  = ""
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}

// MARK: - SFSpeechRecognizerDelegate
extension SpeechManager: SFSpeechRecognizerDelegate {
    nonisolated func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
        Task { @MainActor [weak self] in self?.isAvailable = available }
    }
}

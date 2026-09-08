import AVFoundation
import Combine
import Foundation
import Speech

/// Wraps `SFSpeechRecognizer` for the KINI chat mic so the view layer doesn't
/// touch AVAudioEngine directly. Streams partial transcripts to the caller
/// via `onTranscript` as the user speaks, and produces a final transcript
/// when `stop()` is called or the recognizer flushes.
///
/// Lifetime model: create a single recognizer per chat view, call `start()`
/// when the user taps the mic, `stop()` when they tap again or close the
/// view. The recognizer cleans up its own audio session on stop.
@MainActor
final class KiniVoiceRecognizer: ObservableObject {
    @Published private(set) var isListening: Bool = false
    @Published private(set) var permissionError: String? = nil
    /// Smoothed microphone amplitude in 0…1, published live while listening so
    /// the voice UI (the animated orb) can react to how loudly the user speaks.
    /// Computed as RMS of each captured buffer, mapped with gain and low-pass
    /// smoothed so the animation reads as organic rather than jittery.
    @Published private(set) var level: CGFloat = 0

    private let recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "en-IN"))
        ?? SFSpeechRecognizer(locale: Locale.current)
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    var isAvailable: Bool { recognizer?.isAvailable == true }

    func start(onTranscript: @escaping (String) -> Void) {
        guard let recognizer, recognizer.isAvailable else {
            permissionError = "Speech recognition not available on this device."
            return
        }
        // Request authorizations in sequence (speech first, mic second).
        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            DispatchQueue.main.async {
                guard let self else { return }
                guard auth == .authorized else {
                    self.permissionError = "Allow speech recognition in Settings to use voice input."
                    return
                }
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        guard granted else {
                            self.permissionError = "Allow microphone access in Settings to use voice input."
                            return
                        }
                        self.beginRecording(onTranscript: onTranscript)
                    }
                }
            }
        }
    }

    func stop() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.finish()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        isListening = false
        level = 0
    }

    private func beginRecording(onTranscript: @escaping (String) -> Void) {
        // Reset any in-flight recognition.
        task?.cancel()
        task = nil

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
            try session.setActive(true, options: [.notifyOthersOnDeactivation])
        } catch {
            permissionError = "Audio session error: \(error.localizedDescription)"
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
            // Live amplitude for the voice orb: RMS of the first channel, mapped
            // with gain (speech RMS runs ~0.02–0.2) and low-pass smoothed on the
            // main actor so the animation reads organic, not jittery.
            guard let ch = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            if n == 0 { return }
            var sum: Float = 0
            for i in 0..<n { let s = ch[i]; sum += s * s }
            let rms = (sum / Float(n)).squareRoot()
            let norm = min(1, CGFloat(rms) * 9)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.level = self.level * 0.55 + norm * 0.45
            }
        }

        do {
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
        } catch {
            permissionError = "Couldn't start the microphone: \(error.localizedDescription)"
            return
        }

        task = recognizer?.recognitionTask(with: req) { [weak self] result, error in
            if let text = result?.bestTranscription.formattedString, !text.isEmpty {
                DispatchQueue.main.async { onTranscript(text) }
            }
            if error != nil || result?.isFinal == true {
                DispatchQueue.main.async { self?.stop() }
            }
        }
    }
}

//
//  KiniVoiceService.swift
//  Kinematic — voice I/O for the KINI assistant.
//
//  Wraps SFSpeechRecognizer for live mic transcription (on-device when
//  available) and AVSpeechSynthesizer for reading the assistant's reply
//  aloud. The view layer toggles `startListening()` / `stopListening()`
//  and binds to `@Published transcript` for the in-flight text.
//
//  Permissions:
//    - NSMicrophoneUsageDescription (Info.plist)
//    - NSSpeechRecognitionUsageDescription (Info.plist)
//

import Foundation
import AVFoundation
import Speech

@MainActor
final class KiniVoiceService: NSObject, ObservableObject {

    enum AuthState {
        case unknown, authorized, denied, restricted
    }

    /// Mirrors what the recogniser has produced so far for the current turn.
    @Published var transcript: String = ""
    /// True while the mic is actively capturing audio.
    @Published private(set) var isListening: Bool = false
    /// True while the synthesizer is speaking.
    @Published private(set) var isSpeaking: Bool = false
    /// Permission status — view shows the appropriate empty-state on `.denied`.
    @Published private(set) var micAuth: AuthState = .unknown
    @Published private(set) var speechAuth: AuthState = .unknown
    /// Surfaced when authorization fails or the recognizer errors out.
    @Published var lastError: String?

    // SFSpeechRecognizer is locale-bound; default to the device locale,
    // fall back to en-US so we always have a working recognizer.
    private let recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale.current)
        ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private let synthesizer = AVSpeechSynthesizer()

    /// Called by the view when the user pauses for ~`silenceThreshold` seconds.
    var onSilence: (() -> Void)?
    private let silenceThreshold: TimeInterval = 1.4
    private var silenceTimer: Timer?

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Authorization

    /// Request both Speech + Microphone permissions. Safe to call repeatedly.
    func requestAuthorization() async {
        // Microphone (AVAudioSession)
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                Task { @MainActor in
                    self.micAuth = granted ? .authorized : .denied
                    cont.resume()
                }
            }
        }
        // Speech recognition
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                Task { @MainActor in
                    switch status {
                    case .authorized:  self.speechAuth = .authorized
                    case .denied:      self.speechAuth = .denied
                    case .restricted:  self.speechAuth = .restricted
                    case .notDetermined: self.speechAuth = .unknown
                    @unknown default:  self.speechAuth = .unknown
                    }
                    cont.resume()
                }
            }
        }
    }

    var isAuthorized: Bool { micAuth == .authorized && speechAuth == .authorized }

    // MARK: - Listening

    /// Begin live transcription. Throws if not authorized or audio engine fails.
    func startListening() async throws {
        if !isAuthorized {
            await requestAuthorization()
            guard isAuthorized else {
                lastError = "Microphone or speech recognition permission denied."
                throw NSError(domain: "KiniVoiceService", code: 1, userInfo: [NSLocalizedDescriptionKey: lastError ?? "Permission denied"])
            }
        }
        guard let recognizer, recognizer.isAvailable else {
            lastError = "Speech recognizer unavailable."
            throw NSError(domain: "KiniVoiceService", code: 2, userInfo: [NSLocalizedDescriptionKey: lastError ?? "Unavailable"])
        }

        // If speaking, hush — we don't want the recognizer to hear the TTS.
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        try configureAudioSession()

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        transcript = ""

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()
        isListening = true

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    self.resetSilenceTimer()
                    if result.isFinal {
                        self.stopListening()
                    }
                }
                if let error {
                    // Common case: -1110 "no speech detected" when the user
                    // taps mic then doesn't speak. Surface but don't spam.
                    self.lastError = error.localizedDescription
                    self.stopListening()
                }
            }
        }
    }

    /// Stop the mic and finalize the recognition task.
    func stopListening() {
        silenceTimer?.invalidate(); silenceTimer = nil
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        request = nil
        task?.finish()
        task = nil
        isListening = false
    }

    /// Reset the "user is silent" timer. When it fires, we assume the user
    /// finished speaking and call `onSilence` — the view auto-sends.
    private func resetSilenceTimer() {
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isListening, !self.transcript.isEmpty else { return }
                self.stopListening()
                self.onSilence?()
            }
        }
    }

    // MARK: - Speaking

    /// Read the assistant's reply aloud. Cancels any in-flight utterance.
    func speak(text: String, locale: Locale = Locale.current) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        // Configure session for playback so the user hears it over the
        // earpiece / speakerphone regardless of the current mode.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true, options: [])

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: locale.identifier)
            ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func stopSpeaking() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    // MARK: - Helpers

    private func configureAudioSession() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
        try session.setActive(true, options: .notifyOthersOnDeactivation)
    }
}

extension KiniVoiceService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}

import AVFoundation
import Combine
import Foundation

/// Wraps `AVAudioRecorder` for the "Record call" flow so the view layer never
/// touches AVFoundation directly. Records to a temp `.m4a` (AAC) file, publishes
/// `isRecording` + `elapsed` for the timer UI, and funnels microphone-permission
/// handling through `requestPermission`.
///
/// Lifetime: create one recorder per `RecordCallView`. `start()` configures the
/// audio session and begins capture; `stop()` finalises the file and returns its
/// URL for upload; `cancel()` throws the recording away (rep dismissed the sheet).
/// The temp file lives in the caches/temporary dir and is cleaned up after upload.
@MainActor
final class ConversationRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var permissionDenied = false
    @Published var errorMessage: String?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var fileURL: URL?

    /// "M:SS" for the current elapsed time, for the recording timer label.
    var elapsedLabel: String {
        let total = Int(elapsed)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    /// Ask for microphone permission up front so the consent step can flip
    /// straight into recording. Completes on the main actor with the result.
    func requestPermission(_ completion: @escaping (Bool) -> Void) {
        AVAudioApplication.requestRecordPermission { granted in
            DispatchQueue.main.async {
                self.permissionDenied = !granted
                completion(granted)
            }
        }
    }

    /// Begin recording to a fresh temp `.m4a`. Returns false (and sets
    /// `errorMessage`) if the audio session or recorder could not start.
    @discardableResult
    func start() -> Bool {
        errorMessage = nil
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: [])
        } catch {
            errorMessage = "Couldn't start audio: \(error.localizedDescription)"
            return false
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("conversation-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        do {
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.delegate = self
            guard rec.record() else {
                errorMessage = "The microphone is unavailable right now."
                return false
            }
            recorder = rec
            fileURL = url
            elapsed = 0
            isRecording = true
            startTimer()
            return true
        } catch {
            errorMessage = "Couldn't start recording: \(error.localizedDescription)"
            return false
        }
    }

    /// Stop recording and return the finished file URL (nil if nothing was
    /// captured). Tears down the timer + audio session but keeps `fileURL` so
    /// the caller can upload it.
    @discardableResult
    func stop() -> URL? {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        let url = fileURL
        recorder = nil
        return url
    }

    /// Discard any in-flight recording and delete its temp file.
    func cancel() {
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        recorder = nil
        fileURL = nil
        isRecording = false
        elapsed = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func startTimer() {
        timer?.invalidate()
        // Added in `.common` mode so the timer keeps ticking while the user
        // interacts with (scrolls) the sheet.
        let t = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, let rec = self.recorder, rec.isRecording else { return }
                self.elapsed = rec.currentTime
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
}

extension ConversationRecorder: AVAudioRecorderDelegate {
    // Kept for completeness / interruptions (an incoming call ends recording).
    // `stop()` already captured the file URL, so this is a no-op.
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {}
}

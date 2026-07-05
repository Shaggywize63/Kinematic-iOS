import SwiftUI

/// Consent-gated "Record call" flow presented from the lead-detail screen.
///
/// Steps:
///   1. Consent — a toggle the rep must switch on (bilingual consent text
///      below); the Record button stays disabled until it's on.
///   2. Record — a live timer + Stop.
///   3. Working — on stop: create → upload → process → poll, showing a status
///      line ("Uploading…", "Transcribing…", "Analyzing…").
///   4. Complete — the AI insights render inline via `ConversationInsightsView`.
///
/// Only reachable when the `crm_conversation_intel` module is enabled (gated at
/// the call site in `LeadDetailView`).
struct RecordCallView: View {
    let leadId: String
    /// Fired once a recording finishes processing (or times out) so the parent
    /// can refresh its Conversations list.
    var onFinished: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = ConversationRecorder()

    /// Bilingual consent copy shown under the toggle (English + Hindi).
    private let consentText = "To serve you better, may we record this conversation? It's stored securely and used only to improve our service. / बेहतर सेवा के लिए क्या हम यह बातचीत रिकॉर्ड कर सकते हैं?"

    private enum Phase: Equatable {
        case consent
        case recording
        case working(String)   // status line: Uploading… / Transcribing… / Analyzing…
        case complete
        case failed(String)
    }

    @State private var phase: Phase = .consent
    @State private var consented = false
    @State private var micDenied = false
    @State private var insights: ConversationInsights?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch phase {
                    case .consent:               consentStep
                    case .recording:             recordingStep
                    case .working(let status):   workingStep(status)
                    case .complete:              completeStep
                    case .failed(let message):   failedStep(message)
                    }
                }
                .padding(20)
            }
            .navigationTitle("Record Call")
            .navigationBarTitleDisplayMode(.inline)
            .background(Color(uiColor: .systemBackground).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(closeLabel) {
                        recorder.cancel()
                        dismiss()
                    }
                    .tint(Brand.red)
                }
            }
            // Don't let a swipe-down abandon an in-flight recording / upload.
            .interactiveDismissDisabled(isBusy)
        }
    }

    // MARK: - Derived state

    private var isBusy: Bool {
        switch phase {
        case .recording, .working: return true
        default: return false
        }
    }

    private var closeLabel: String {
        switch phase {
        case .complete: return "Done"
        default:        return "Cancel"
        }
    }

    // MARK: - Step 1: consent

    private var consentStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            header(icon: "waveform.badge.mic",
                   title: "Record this conversation",
                   subtitle: "Capture the call so KINI can transcribe it and surface coaching insights on this lead.")

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $consented) {
                    Text("Customer consented to being recorded")
                        .font(.system(size: 15, weight: .semibold))
                }
                .tint(Brand.red)
                Text(consentText)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))

            if micDenied {
                Text("Microphone access is off. Enable it in Settings → Kinematic to record.")
                    .font(.caption)
                    .foregroundColor(Brand.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                beginRecording()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "record.circle")
                    Text("Record")
                }
                .font(.system(size: 16, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(consented ? Brand.red : Color.gray.opacity(0.4))
                .foregroundColor(.white)
                .cornerRadius(14)
            }
            .disabled(!consented)
        }
    }

    // MARK: - Step 2: recording

    private var recordingStep: some View {
        VStack(spacing: 24) {
            header(icon: "waveform",
                   title: "Recording…",
                   subtitle: "Keep your phone near the conversation. Tap Stop when you're done.")

            ZStack {
                Circle().fill(Brand.red.opacity(0.10)).frame(width: 160, height: 160)
                Circle().fill(Brand.red.opacity(0.16)).frame(width: 116, height: 116)
                VStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 30))
                        .foregroundColor(Brand.red)
                    Text(recorder.elapsedLabel)
                        .font(.system(size: 22, weight: .bold))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                }
            }
            .frame(maxWidth: .infinity)

            if let err = recorder.errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundColor(Brand.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                stopAndProcess()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "stop.fill")
                    Text("Stop")
                }
                .font(.system(size: 16, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Brand.red)
                .foregroundColor(.white)
                .cornerRadius(14)
            }
        }
    }

    // MARK: - Step 3: working

    private func workingStep(_ status: String) -> some View {
        VStack(spacing: 20) {
            header(icon: "sparkles",
                   title: "Analyzing conversation",
                   subtitle: "This usually takes under a minute. Wait here, or continue in the background — you'll get a notification when it's ready.")
            VStack(spacing: 14) {
                ProgressView().tint(Brand.red).scaleEffect(1.3)
                Text(status)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)

            // Dismiss the sheet without cancelling the pipeline — the Task
            // in `runPipeline` keeps polling and the backend will push-notify
            // on completion. Fire `onFinished` now so the parent's list
            // refreshes and shows the in-flight row immediately.
            Button {
                onFinished?()
                dismiss()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle")
                    Text("Continue in background")
                }
                .font(.system(size: 16, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color(uiColor: .secondarySystemBackground))
                .foregroundColor(Brand.red)
                .cornerRadius(14)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Brand.red.opacity(0.35), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Step 4: complete

    private var completeStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill").foregroundColor(Brand.success)
                Text("Analysis ready").font(.system(size: 18, weight: .bold))
                Spacer()
            }
            if let insights {
                ConversationInsightsView(insights: insights)
            } else {
                Text("The recording was processed but no insights were returned.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Brand.red)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
        }
    }

    // MARK: - Failed

    private func failedStep(_ message: String) -> some View {
        VStack(spacing: 18) {
            header(icon: "exclamationmark.triangle.fill",
                   title: "Couldn't finish",
                   subtitle: message)
            Button {
                insights = nil
                phase = .consent
            } label: {
                Text("Try Again")
                    .font(.system(size: 16, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Brand.red)
                    .foregroundColor(.white)
                    .cornerRadius(14)
            }
        }
    }

    // MARK: - Shared header

    private func header(icon: String, title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Brand.red.gradient)
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.white)
                }
                Text(title).font(.system(size: 20, weight: .black))
                Spacer()
            }
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Flow control

    @MainActor
    private func beginRecording() {
        recorder.requestPermission { granted in
            // The permission completion is a plain escaping closure, so hop
            // explicitly onto the main actor before touching the (@MainActor)
            // recorder / @State — safe under any concurrency mode.
            Task { @MainActor in
                guard granted else {
                    micDenied = true
                    return
                }
                micDenied = false
                if recorder.start() {
                    phase = .recording
                }
            }
        }
    }

    @MainActor
    private func stopAndProcess() {
        let url = recorder.stop()
        let duration = max(Int(recorder.elapsed), 1)
        guard let url else {
            phase = .failed("No audio was captured. Please try again.")
            return
        }
        Task { await runPipeline(url: url, duration: duration) }
    }

    /// create → upload → process → poll. Drives the status line and lands on
    /// `.complete` (with insights) or `.failed`. Runs on the main actor so the
    /// `phase` mutations are UI-safe.
    @MainActor
    private func runPipeline(url: URL, duration: Int) async {
        let repo = KinematicRepository.shared

        phase = .working("Uploading…")
        guard let created = await repo.createConversation(leadId: leadId, durationSeconds: duration) else {
            phase = .failed("Couldn't start the upload. Check your connection and try again.")
            cleanup(url)
            return
        }

        let uploaded = await repo.uploadAudio(to: created.uploadUrl, fileURL: url)
        guard uploaded else {
            phase = .failed("The audio upload didn't go through. Please try again.")
            cleanup(url)
            return
        }

        phase = .working("Transcribing…")
        let started = await repo.processConversation(id: created.id)
        guard started else {
            phase = .failed("Couldn't start processing the recording.")
            cleanup(url)
            return
        }

        // Poll every 3s until complete/failed (cap ~40 tries ≈ 2 min).
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let detail = await repo.getConversation(id: created.id) else { continue }

            // Nudge the status line to "Analyzing…" once a transcript lands.
            if detail.transcript?.isEmpty == false, phase == .working("Transcribing…") {
                phase = .working("Analyzing…")
            }
            if detail.isComplete {
                insights = detail.insights
                phase = .complete
                onFinished?()
                cleanup(url)
                return
            }
            if detail.isFailed {
                phase = .failed("Analysis failed for this recording.")
                onFinished?()
                cleanup(url)
                return
            }
        }

        // Timed out — the backend may still finish; the row will show in the
        // lead's Conversations list once it's done.
        phase = .failed("Analysis is taking longer than expected. It'll appear in this lead's conversation list once it's ready.")
        onFinished?()
        cleanup(url)
    }

    private func cleanup(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

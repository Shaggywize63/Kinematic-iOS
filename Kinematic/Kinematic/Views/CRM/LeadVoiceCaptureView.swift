import SwiftUI

/// KINI "Fill with voice" — a distinct voice-capture sheet for the lead form.
/// The rep describes a prospect out loud; on-device speech recognition streams
/// the transcript; on "Use these details" the transcript is POSTed to
/// `/crm/ai/extract-lead` and the structured fields are handed back to the
/// caller, which maps them onto the Create Lead form (still gated by the
/// field-override contract). Voice is input only — no spoken replies.
struct LeadVoiceCaptureView: View {
    @Environment(\.dismiss) private var dismiss
    let isB2C: Bool
    let onExtracted: (ExtractedLead) -> Void

    @StateObject private var voice = KiniVoiceRecognizer()
    @State private var transcript = ""
    @State private var extracting = false
    @State private var errorMessage: String?

    private let brandRed = Color(red: 0xE0/255, green: 0x1E/255, blue: 0x2C/255)

    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                VStack(spacing: 20) {
                    Spacer(minLength: 8)

                    VoiceInputOrb(level: voice.level, active: voice.isListening)
                        .frame(width: 220, height: 220)

                    VStack(spacing: 8) {
                        Text(voice.isListening ? "LISTENING…" : (transcript.isEmpty ? "TAP THE MIC TO SPEAK" : "GOT IT — REVIEW BELOW"))
                            .font(.system(size: 13, weight: .heavy))
                            .tracking(1.5)
                            .foregroundColor(brandRed)
                        Text(transcript.isEmpty
                             ? "Describe the lead — e.g. \u{201C}Rajesh Kumar from Acme Steel, mobile 98…, wants TMT bars in Pune\u{201D}"
                             : transcript)
                            .font(.system(size: 17, weight: transcript.isEmpty ? .regular : .semibold))
                            .foregroundColor(transcript.isEmpty ? .secondary : .primary)
                            .multilineTextAlignment(.center)
                            .lineLimit(6)
                            .padding(.horizontal, 26)
                    }

                    if let err = errorMessage {
                        Text(err).font(.footnote).foregroundColor(brandRed)
                            .multilineTextAlignment(.center).padding(.horizontal, 26)
                    } else if let perr = voice.permissionError {
                        Text(perr).font(.footnote).foregroundColor(.secondary)
                            .multilineTextAlignment(.center).padding(.horizontal, 26)
                    }

                    Spacer()
                    controls
                }
                .padding(.bottom, 26)
            }
            .navigationTitle("Fill with voice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { voice.stop(); dismiss() }
                }
            }
            .onDisappear { voice.stop() }
        }
    }

    private var controls: some View {
        VStack(spacing: 16) {
            Button {
                if voice.isListening {
                    voice.stop()
                } else {
                    errorMessage = nil
                    transcript = ""
                    voice.start { text in transcript = text }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(voice.isListening ? brandRed : Color(uiColor: .secondarySystemBackground))
                        .frame(width: 76, height: 76)
                        .shadow(color: voice.isListening ? brandRed.opacity(0.4) : .clear, radius: 14, y: 5)
                    Image(systemName: voice.isListening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 27, weight: .bold))
                        .foregroundColor(voice.isListening ? .white : brandRed)
                }
            }
            .disabled(extracting || !voice.isAvailable)
            .accessibilityLabel(voice.isListening ? "Stop" : "Start speaking")

            Button {
                Task { await useTranscript() }
            } label: {
                HStack(spacing: 8) {
                    if extracting { ProgressView().tint(.white) }
                    Text(extracting ? "Reading…" : "Use these details")
                        .font(.system(size: 16, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Capsule().fill(canUse ? brandRed : Color.gray.opacity(0.4)))
                .foregroundColor(.white)
            }
            .disabled(!canUse || extracting)
            .padding(.horizontal, 36)
        }
    }

    private var canUse: Bool {
        !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !voice.isListening
    }

    private func useTranscript() async {
        let t = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        voice.stop()
        extracting = true
        errorMessage = nil
        defer { extracting = false }
        do {
            let extracted = try await CRMService.shared.extractLead(transcript: t, isB2C: isB2C)
            onExtracted(extracted)
            dismiss()
        } catch {
            errorMessage = friendly(error)
        }
    }

    private func friendly(_ error: Error) -> String {
        let s = String(describing: error).lowercased()
        if s.contains("usage limit") || s.contains("monthly") {
            return "KINI has hit its monthly AI limit. Try again after it resets, or type the details in."
        }
        return "Couldn't read that — please try again, or type the details in."
    }
}

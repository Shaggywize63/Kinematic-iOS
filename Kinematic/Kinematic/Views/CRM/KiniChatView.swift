import AVFoundation
import Combine
import SwiftUI

private let brandRed = Color(red: 0xE0/255, green: 0x1E/255, blue: 0x2C/255)
private let brandRedLight = Color(red: 0xFF/255, green: 0x4D/255, blue: 0x4D/255)
private let brandBlue = Color(red: 0x1E/255, green: 0x3A/255, blue: 0x8A/255)
private let headerGradient = LinearGradient(
    colors: [brandRed, brandRedLight, brandBlue],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

/// KINI agentic copilot — chat surface with two modes:
/// 1) Tap-to-talk text: type or hold mic, hit send.
/// 2) Hands-free voice: header pill toggle. After every assistant reply,
///    TTS speaks the text; when speech ends, the mic auto-reopens for the
///    next turn. Toggling OFF silences mid-speech and cancels listening.
///
/// Tool-use results from the backend land in `m.cards` and render via
/// `KiniToolResultCard` — agentic create/update results appear inline.
struct KiniChatView: View {
    @StateObject var vm = KINIChatViewModel()
    @StateObject private var voice = KiniVoiceRecognizer()
    @StateObject private var speaker = KiniSpeaker()
    @State private var handsFree: Bool = false
    @State private var lastSpokenMessageCount: Int = 0
    @State private var pendingAutoSend: Bool = false
    var onClose: (() -> Void)? = nil

    private var capped: Bool {
        guard let u = vm.usage, !u.exempt else { return false }
        return u.remaining == 0
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if capped, let u = vm.usage {
                Text("You've used all \(u.cap) AI queries this month. The counter resets on the 1st.")
                    .font(.caption)
                    .foregroundColor(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Brand.red.opacity(0.12))
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        if vm.messages.isEmpty && !vm.isSending {
                            emptyState
                        }
                        ForEach(vm.messages) { m in
                            bubble(for: m).id(m.id)
                        }
                        if vm.isSending {
                            workingIndicator
                        } else if let last = vm.messages.last, last.role == "assistant" {
                            // Follow-up chips after every assistant turn so the
                            // conversation has obvious next steps without
                            // forcing the rep to type. Each fires the same
                            // agentic loop a typed prompt would.
                            followUpChips
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                }
                .onChange(of: vm.messages.count) { _, _ in
                    if let last = vm.messages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                    // Hands-free: speak each new assistant reply.
                    if handsFree, vm.messages.count > lastSpokenMessageCount,
                       let m = vm.messages.last, m.role == "assistant", !m.content.isEmpty {
                        speaker.speak(m.content)
                    }
                    lastSpokenMessageCount = vm.messages.count
                }
            }

            // Live voice/speech state strip — only visible during an active
            // voice interaction. Replaces guesswork about whether the mic
            // is hot or KINI is talking.
            if voice.isListening || speaker.isSpeaking {
                voiceStateStrip
            }

            Divider()

            HStack(alignment: .bottom, spacing: 8) {
                TextField(capped ? "Monthly quota reached — resets on the 1st" : "Ask KINI to act on your CRM…",
                          text: $vm.draft, axis: .vertical)
                    .lineLimit(1...4)
                    .disabled(capped)
                    .padding(10)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(12)

                if voice.isAvailable {
                    Button {
                        toggleSingleShotMic()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(voice.isListening ? brandRed : Color(uiColor: .secondarySystemBackground))
                                .frame(width: 40, height: 40)
                            Image(systemName: voice.isListening ? "mic.fill" : "mic")
                                .foregroundColor(voice.isListening ? .white : .primary)
                                .font(.system(size: 16, weight: .bold))
                        }
                    }
                    .disabled(capped || vm.isSending)
                }

                Button {
                    Task { await vm.send() }
                } label: {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [brandRed, brandRedLight],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 40, height: 40)
                        if vm.isSending {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "arrow.up")
                                .foregroundColor(.white)
                                .font(.system(size: 16, weight: .black))
                        }
                    }
                }
                .disabled(vm.draft.trimmingCharacters(in: .whitespaces).isEmpty || vm.isSending || capped)
                .opacity((vm.draft.trimmingCharacters(in: .whitespaces).isEmpty || capped) ? 0.5 : 1)
            }
            .padding()
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        // Auto-send when the recognizer ends a turn while hands-free is on.
        .onChange(of: voice.isListening) { wasListening, isNow in
            guard wasListening && !isNow else { return }
            guard pendingAutoSend else { return }
            pendingAutoSend = false
            let txt = vm.draft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !txt.isEmpty else { return }
            Task { await vm.send() }
        }
        // When speech ends, give the mic back to the user — but only if
        // hands-free is still on (toggling off mid-speech kills the loop).
        .onChange(of: speaker.isSpeaking) { wasSpeaking, isNow in
            guard wasSpeaking && !isNow else { return }
            if handsFree { startMicForAutoSend() }
        }
        .onChange(of: handsFree) { _, on in
            if on {
                // First turn — open the mic so the user can start talking.
                startMicForAutoSend()
            } else {
                voice.stop()
                speaker.stop()
            }
        }
        .onDisappear {
            voice.stop()
            speaker.stop()
        }
    }

    private func toggleSingleShotMic() {
        if voice.isListening {
            voice.stop()
        } else {
            pendingAutoSend = false        // single-shot: stream into draft, don't auto-send
            voice.start { text in vm.draft = text }
        }
    }

    private func startMicForAutoSend() {
        if voice.isListening { return }
        pendingAutoSend = true
        vm.draft = ""
        voice.start { text in vm.draft = text }
    }

    private var voiceStateStrip: some View {
        HStack(spacing: 10) {
            PulsingDot(color: voice.isListening ? brandRed : brandBlue)
            Text(voice.isListening ? "Listening…  \(vm.draft)" : "KINI is speaking…")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(voice.isListening ? brandRed : brandBlue)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Cancel") {
                voice.stop()
                speaker.stop()
                pendingAutoSend = false
            }
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(voice.isListening ? brandRed : brandBlue)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background((voice.isListening ? brandRed : brandBlue).opacity(0.08))
    }

    private var header: some View {
        HStack(spacing: 10) {
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.white.opacity(0.18))
                        .clipShape(Circle())
                }
            }
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 36, height: 36)
                Text("✦")
                    .font(.system(size: 18))
                    .foregroundColor(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Kini AI")
                        .font(.system(size: 15, weight: .black))
                        .foregroundColor(.white)
                    Text("CRM")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(Color.white.opacity(0.18))
                        .clipShape(Capsule())
                }
                Text("AGENTIC CRM COPILOT")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.2)
                    .foregroundColor(.white.opacity(0.9))
            }
            Spacer()
            // Hands-free toggle pill — turning this on starts the
            // listen→answer→speak→listen loop.
            Button { handsFree.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: handsFree ? "ear.fill" : "ear")
                        .font(.system(size: 11, weight: .bold))
                    Text(handsFree ? "Voice ON" : "Voice")
                        .font(.system(size: 10, weight: .black))
                }
                .foregroundColor(handsFree ? brandRed : .white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(handsFree ? Color.white : Color.white.opacity(0.18))
                .clipShape(Capsule())
            }
            if let u = vm.usage, !u.exempt {
                Text("\(u.used)/\(u.cap)")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(u.remaining == 0 ? Color.black.opacity(0.35) : Color.white.opacity(0.18))
                    .clipShape(Capsule())
            }
            Button(action: { vm.reset(); lastSpokenMessageCount = 0 }) {
                Text("Clear")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Color.white.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(headerGradient)
    }

    // MARK: - Empty state + suggestions

    /// What reps see the first time they open KINI in a session. The four
    /// suggested prompts are the queries Hemanth-style reps actually run
    /// (per the dashboard analytics) — tapping fills the draft so they can
    /// edit before sending. Removes the "blank box, what do I type?" hurdle.
    private var emptyState: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [brandRed, brandRedLight, brandBlue],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 72, height: 72)
                Text("K")
                    .font(.system(size: 32, weight: .black))
                    .foregroundColor(.white)
            }
            .padding(.top, 32)

            VStack(spacing: 4) {
                Text("Hi, I'm KINI")
                    .font(.system(size: 18, weight: .black))
                Text("Your CRM copilot. I can search leads, draft messages, move deals, and surface what needs your attention next.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            Text("TRY ASKING")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.top, 6)

            VStack(spacing: 8) {
                suggestionChip("Show my hottest leads this week", icon: "flame.fill")
                suggestionChip("Which deals are at risk of slipping?", icon: "exclamationmark.triangle.fill")
                suggestionChip("Draft a follow-up to my top lead", icon: "envelope.fill")
                suggestionChip("What activities are due today?", icon: "calendar")
                suggestionChip("Summarise this week's pipeline", icon: "chart.line.uptrend.xyaxis")
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func suggestionChip(_ prompt: String, icon: String) -> some View {
        Button {
            // One-tap agentic kickoff — fill the draft AND fire the turn
            // so the rep sees KINI actually act, not just a pre-filled
            // input they need to send themselves.
            vm.draft = prompt
            Task { await vm.send() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundColor(brandRed)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 24)
                Text(prompt)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(brandRed.opacity(0.18), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    /// "KINI is working…" — three staggered dots + sparkle icon. Replaces
    /// the old `typingIndicator` so the affordance reads as "agent is
    /// running tools" rather than "model is typing prose" (those have
    /// different latency profiles and the user should feel both).
    /// Three contextual continuation chips shown beneath the last
    /// assistant reply. Curated to cover the common follow-ups; each
    /// fires the same agentic turn as a typed prompt.
    private var followUpChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                followUpChip("Tell me more",   prompt: "Tell me more — expand on the last point with examples from my CRM.")
                followUpChip("Show as a list", prompt: "Show that as a structured list with the most important details first.")
                followUpChip("What's next?",   prompt: "Based on that, what's the next best action I should take?")
            }
            .padding(.horizontal, 4)
        }
        .padding(.top, 2)
    }

    private func followUpChip(_ label: String, prompt: String) -> some View {
        Button {
            vm.draft = prompt
            Task { await vm.send() }
        } label: {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(
                    Capsule().fill(Color(uiColor: .secondarySystemBackground))
                )
                .overlay(
                    Capsule().stroke(Color(uiColor: .separator).opacity(0.5), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var workingIndicator: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(brandRed.opacity(0.12)).frame(width: 32, height: 32)
                Text("✦").font(.system(size: 14)).foregroundColor(brandRed)
            }
            HStack(spacing: 4) {
                TypingDot(delay: 0.0)
                TypingDot(delay: 0.2)
                TypingDot(delay: 0.4)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(18)
            Text("KINI is working…")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
            Spacer(minLength: 40)
        }
    }

    @ViewBuilder
    private func bubble(for m: ChatMessage) -> some View {
        let isUser = m.role == "user"
        HStack {
            if isUser { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 6) {
                Text(m.content)
                    .foregroundColor(isUser ? .white : .primary)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(
                        Group {
                            if isUser {
                                LinearGradient(colors: [brandRed, brandRedLight],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                            } else {
                                Color(uiColor: .secondarySystemBackground)
                            }
                        }
                    )
                    .cornerRadius(18)
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(isUser ? Color.clear : Color(uiColor: .separator), lineWidth: 0.5)
                    )
                if let cards = m.cards, !cards.isEmpty {
                    ForEach(cards, id: \.id) { card in
                        KiniToolResultCard(card: card)
                    }
                }
            }
            if !isUser { Spacer(minLength: 40) }
        }
    }
}

/// One pulsing dot used by the typing indicator. Three of these in a row,
/// staggered by a constant delay, gives a clean "···" cadence that reads
/// as "thinking" without spinning a generic ProgressView.
private struct TypingDot: View {
    let delay: Double
    @State private var on = false

    var body: some View {
        Circle()
            .fill(Color.secondary)
            .frame(width: 6, height: 6)
            .opacity(on ? 1.0 : 0.3)
            .animation(.easeInOut(duration: 0.6).repeatForever().delay(delay), value: on)
            .onAppear { on = true }
    }
}

/// Animated dot used by the voice-state strip. Same vibe as `TypingDot` but
/// pulses by scale so it reads as "live signal" rather than "thinking".
private struct PulsingDot: View {
    let color: Color
    @State private var on = false
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
            .scaleEffect(on ? 1.0 : 0.7)
            .opacity(on ? 1.0 : 0.7)
            .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

/// Thin wrapper around `AVSpeechSynthesizer` so the SwiftUI view can observe
/// `isSpeaking` and react when speech finishes (drives the hands-free
/// listen→speak→listen loop). en-IN voice preferred to match the user base;
/// falls back to system default when unavailable.
@MainActor
final class KiniSpeaker: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking: Bool = false
    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String) {
        if text.isEmpty { return }
        // Route audio through the speaker even if a phone call earpiece
        // was last active for the session.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers, .mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true, options: [])
        let utt = AVSpeechUtterance(string: text)
        utt.voice = AVSpeechSynthesisVoice(language: "en-IN") ?? AVSpeechSynthesisVoice(language: "en-US")
        utt.rate = AVSpeechUtteranceDefaultSpeechRate
        utt.pitchMultiplier = 1.0
        synth.stopSpeaking(at: .immediate)
        synth.speak(utt)
        isSpeaking = true
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        isSpeaking = false
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}

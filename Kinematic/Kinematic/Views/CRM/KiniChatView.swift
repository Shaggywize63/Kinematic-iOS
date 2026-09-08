import AVFoundation
import Combine
import SwiftUI

// Brand palette (file-local so the redesign is self-contained).
private let brandRed = Color(red: 0xE0/255, green: 0x1E/255, blue: 0x2C/255)
private let brandRedLight = Color(red: 0xFF/255, green: 0x4D/255, blue: 0x4D/255)
private let brandBlue = Color(red: 0x1E/255, green: 0x3A/255, blue: 0x8A/255)
private let orbGradient = [brandRedLight, brandRed, brandBlue]

/// KINI agentic copilot — redesigned chat surface.
///
/// - Modern message list with an assistant avatar, refined bubbles, inline
///   tool-result cards, a "thinking" indicator, empty-state suggestions and
///   follow-up chips.
/// - Voice input: tapping the mic opens a full-screen **listening overlay**
///   built around a live voice orb that reacts to the caller's microphone
///   amplitude (`KiniVoiceRecognizer.level`). Transcription streams into the
///   composer; releasing sends.
/// - Optional hands-free loop (header toggle) still speaks replies via TTS and
///   re-opens the mic after each turn.
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
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                if capped { quotaBanner }
                transcriptList
                composer
            }

            // Full-screen listening overlay — the voice-animation centrepiece.
            if voice.isListening {
                voiceOverlay
                    .transition(.opacity.combined(with: .scale(scale: 1.02)))
                    .zIndex(10)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: voice.isListening)
        // Hands-free: after the recognizer ends a turn, auto-send the draft.
        .onChange(of: voice.isListening) { wasListening, isNow in
            guard wasListening && !isNow, pendingAutoSend else { return }
            pendingAutoSend = false
            let txt = vm.draft.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !txt.isEmpty else { return }
            Task { await vm.send() }
        }
        .onChange(of: speaker.isSpeaking) { wasSpeaking, isNow in
            guard wasSpeaking && !isNow else { return }
            if handsFree { startMicForAutoSend() }
        }
        .onChange(of: handsFree) { _, on in
            if on { startMicForAutoSend() } else { voice.stop(); speaker.stop() }
        }
        .onDisappear { voice.stop(); speaker.stop() }
    }

    // MARK: - Transcript

    private var transcriptList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 14) {
                    if vm.messages.isEmpty && !vm.isSending {
                        emptyState
                    }
                    ForEach(vm.messages) { m in
                        bubble(for: m).id(m.id)
                    }
                    if vm.isSending {
                        workingIndicator
                    } else if let last = vm.messages.last, last.role == "assistant" {
                        followUpChips
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)
            }
            .onChange(of: vm.messages.count) { _, _ in
                if let last = vm.messages.last {
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
                if handsFree, vm.messages.count > lastSpokenMessageCount,
                   let m = vm.messages.last, m.role == "assistant", !m.content.isEmpty {
                    speaker.speak(m.content)
                }
                lastSpokenMessageCount = vm.messages.count
            }
        }
    }

    // MARK: - Composer (input bar)

    private var composer: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Color(uiColor: .separator).opacity(0.0), Color(uiColor: .separator).opacity(0.35)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 1)
            HStack(alignment: .bottom, spacing: 10) {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField(capped ? "Monthly quota reached — resets on the 1st" : "Ask KINI to act on your CRM…",
                              text: $vm.draft, axis: .vertical)
                        .lineLimit(1...5)
                        .disabled(capped)
                        .font(.system(size: 15))
                        .padding(.vertical, 4)

                    if voice.isAvailable {
                        Button { enterVoiceMode() } label: {
                            Image(systemName: "mic.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(brandRed)
                                .frame(width: 30, height: 30)
                                .background(Circle().fill(brandRed.opacity(0.10)))
                        }
                        .disabled(capped || vm.isSending)
                        .accessibilityLabel("Speak to KINI")
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(Color(uiColor: .separator).opacity(0.5), lineWidth: 1))
                )

                sendButton
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemBackground))
    }

    private var sendButton: some View {
        let empty = vm.draft.trimmingCharacters(in: .whitespaces).isEmpty
        return Button { Task { await vm.send() } } label: {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: empty || capped ? [Color.gray.opacity(0.4), Color.gray.opacity(0.4)] : [brandRedLight, brandRed],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 44, height: 44)
                    .shadow(color: (empty || capped) ? .clear : brandRed.opacity(0.35), radius: 8, y: 3)
                if vm.isSending {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "arrow.up")
                        .foregroundColor(.white)
                        .font(.system(size: 17, weight: .black))
                }
            }
        }
        .disabled(empty || vm.isSending || capped)
        .animation(.easeInOut(duration: 0.15), value: empty)
    }

    // MARK: - Voice overlay (the animation)

    private var voiceOverlay: some View {
        ZStack {
            // Dimmed, blurred backdrop over the conversation.
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .overlay(Color.black.opacity(0.25).ignoresSafeArea())
                .onTapGesture { } // swallow taps behind the controls

            VStack(spacing: 28) {
                Spacer()

                VoiceOrb(level: voice.level, active: true)
                    .frame(width: 300, height: 300)

                VStack(spacing: 8) {
                    Text("Listening…")
                        .font(.system(size: 13, weight: .heavy))
                        .tracking(1.6)
                        .foregroundColor(brandRed)
                    Text(vm.draft.isEmpty ? "Say something like “show my hottest leads”" : vm.draft)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundColor(vm.draft.isEmpty ? .secondary : .primary)
                        .multilineTextAlignment(.center)
                        .lineLimit(4)
                        .padding(.horizontal, 28)
                        .animation(.easeOut(duration: 0.15), value: vm.draft)
                }

                Spacer()

                HStack(spacing: 22) {
                    // Cancel — discard what was heard.
                    Button { voice.stop(); pendingAutoSend = false; vm.draft = "" } label: {
                        overlayControl(system: "xmark", tint: .secondary, bg: Color(uiColor: .secondarySystemBackground))
                    }
                    .accessibilityLabel("Cancel voice")

                    // Send — stop the mic and fire the turn.
                    Button {
                        voice.stop()
                        let txt = vm.draft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !txt.isEmpty { Task { await vm.send() } }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [brandRedLight, brandRed], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 76, height: 76)
                                .shadow(color: brandRed.opacity(0.45), radius: 16, y: 6)
                            Image(systemName: "arrow.up")
                                .font(.system(size: 26, weight: .black))
                                .foregroundColor(.white)
                        }
                    }
                    .disabled(vm.draft.trimmingCharacters(in: .whitespaces).isEmpty)
                    .opacity(vm.draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
                    .accessibilityLabel("Send")

                    // Keyboard — bail to typing.
                    Button { voice.stop(); pendingAutoSend = false } label: {
                        overlayControl(system: "keyboard", tint: .secondary, bg: Color(uiColor: .secondarySystemBackground))
                    }
                    .accessibilityLabel("Switch to keyboard")
                }
                .padding(.bottom, 44)
            }
        }
    }

    private func overlayControl(system: String, tint: Color, bg: Color) -> some View {
        Image(systemName: system)
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(tint)
            .frame(width: 58, height: 58)
            .background(Circle().fill(bg))
            .overlay(Circle().stroke(Color(uiColor: .separator).opacity(0.5), lineWidth: 1))
    }

    private func enterVoiceMode() {
        pendingAutoSend = false     // single-shot: stream into the composer, send on the ↑ control
        vm.draft = ""
        voice.start { text in vm.draft = text }
    }

    private func startMicForAutoSend() {
        if voice.isListening { return }
        pendingAutoSend = true
        vm.draft = ""
        voice.start { text in vm.draft = text }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 11) {
            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color(uiColor: .secondarySystemBackground)))
                }
            }

            ZStack {
                Circle()
                    .fill(LinearGradient(colors: orbGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 38, height: 38)
                KiniMascotView(size: 26)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text("Kini AI")
                    .font(.system(size: 17, weight: .heavy))
                    .foregroundColor(.primary)
                HStack(spacing: 5) {
                    Circle().fill(Color.green).frame(width: 6, height: 6)
                    Text("Agentic CRM copilot")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let u = vm.usage, !u.exempt {
                Text("\(u.used)/\(u.cap)")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(u.remaining == 0 ? brandRed : .secondary)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(Color(uiColor: .secondarySystemBackground)))
            }

            Menu {
                Button { handsFree.toggle() } label: {
                    Label(handsFree ? "Turn off spoken replies" : "Turn on spoken replies",
                          systemImage: handsFree ? "speaker.slash" : "speaker.wave.2")
                }
                Button(role: .destructive) { vm.reset(); lastSpokenMessageCount = 0 } label: {
                    Label("Clear conversation", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Color(uiColor: .secondarySystemBackground)))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(uiColor: .separator).opacity(0.4)).frame(height: 0.5)
        }
    }

    private var quotaBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "hourglass").font(.system(size: 12, weight: .bold))
            Text("You've used all \(vm.usage?.cap ?? 0) AI queries this month. Resets on the 1st.")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(brandRed)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(brandRed.opacity(0.10))
    }

    // MARK: - Empty state + chips

    private var emptyState: some View {
        VStack(spacing: 18) {
            VoiceOrb(level: 0, active: false)
                .frame(width: 132, height: 132)
                .padding(.top, 26)

            VStack(spacing: 6) {
                Text("Hi, I'm KINI")
                    .font(.system(size: 22, weight: .heavy))
                Text("Your CRM copilot. I can search leads, draft messages, move deals, and surface what needs you next.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }

            Text("TRY ASKING")
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.4)
                .foregroundColor(.secondary)
                .padding(.top, 4)

            VStack(spacing: 9) {
                suggestionChip("Show my hottest leads this week", icon: "flame.fill")
                suggestionChip("Which deals are at risk of slipping?", icon: "exclamationmark.triangle.fill")
                suggestionChip("Draft a follow-up to my top lead", icon: "envelope.fill")
                suggestionChip("What activities are due today?", icon: "calendar")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 8)
    }

    private func suggestionChip(_ prompt: String, icon: String) -> some View {
        Button {
            vm.draft = prompt
            Task { await vm.send() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(brandRed)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 24)
                Text(prompt)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "arrow.up.right")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11, weight: .bold))
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(brandRed.opacity(0.14), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    private var followUpChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                followUpChip("Tell me more", prompt: "Tell me more — expand on the last point with examples from my CRM.")
                followUpChip("Show as a list", prompt: "Show that as a structured list with the most important details first.")
                followUpChip("What's next?", prompt: "Based on that, what's the next best action I should take?")
            }
            .padding(.horizontal, 44)
        }
        .padding(.top, 2)
    }

    private func followUpChip(_ label: String, prompt: String) -> some View {
        Button {
            vm.draft = prompt
            Task { await vm.send() }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(brandRed)
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Capsule().fill(brandRed.opacity(0.08)))
                .overlay(Capsule().stroke(brandRed.opacity(0.20), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var workingIndicator: some View {
        HStack(alignment: .top, spacing: 10) {
            assistantAvatar
            HStack(spacing: 5) {
                TypingDot(delay: 0.0)
                TypingDot(delay: 0.18)
                TypingDot(delay: 0.36)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(uiColor: .secondarySystemBackground)))
            Spacer(minLength: 40)
        }
    }

    private var assistantAvatar: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: orbGradient, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 30, height: 30)
            KiniMascotView(size: 20)
        }
    }

    @ViewBuilder
    private func bubble(for m: ChatMessage) -> some View {
        let isUser = m.role == "user"
        HStack(alignment: .top, spacing: 8) {
            if isUser {
                Spacer(minLength: 44)
            } else {
                assistantAvatar
            }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
                if !m.content.isEmpty {
                    Text(m.content)
                        .font(.system(size: 15))
                        .foregroundColor(isUser ? .white : .primary)
                        .padding(.horizontal, 15).padding(.vertical, 11)
                        .background(
                            Group {
                                if isUser {
                                    LinearGradient(colors: [brandRedLight, brandRed], startPoint: .topLeading, endPoint: .bottomTrailing)
                                } else {
                                    Color(uiColor: .secondarySystemBackground)
                                }
                            }
                        )
                        .clipShape(BubbleShape(isUser: isUser))
                        .overlay(isUser ? nil : BubbleShape(isUser: isUser).stroke(Color(uiColor: .separator).opacity(0.5), lineWidth: 0.5))
                }
                if let cards = m.cards, !cards.isEmpty {
                    ForEach(cards, id: \.id) { card in
                        KiniToolResultCard(card: card)
                    }
                }
            }
            if !isUser { Spacer(minLength: 44) }
        }
    }
}

// MARK: - Voice orb

/// The live voice-input animation. A radial-gradient core (KINI's mascot at the
/// centre) that scales and glows with the caller's microphone amplitude, wrapped
/// in concentric rings that ripple outward. When inactive it breathes gently so
/// the empty-state feels alive without any audio.
private struct VoiceOrb: View {
    var level: CGFloat       // 0…1 live mic amplitude
    var active: Bool
    @State private var breathe = false

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let core = side * 0.5
            let amp = max(0, min(1, level))
            ZStack {
                // Emitted rings — expand with amplitude while active.
                ForEach(0..<3, id: \.self) { i in
                    Circle()
                        .stroke(brandRed.opacity(0.22 - Double(i) * 0.06), lineWidth: 2)
                        .frame(width: core + CGFloat(i) * side * 0.14 + (active ? amp * side * 0.35 : 0),
                               height: core + CGFloat(i) * side * 0.14 + (active ? amp * side * 0.35 : 0))
                        .scaleEffect(breathe ? 1.04 : 0.96)
                        .animation(.easeInOut(duration: 2.4 + Double(i) * 0.4).repeatForever(autoreverses: true), value: breathe)
                }

                // Core orb.
                Circle()
                    .fill(RadialGradient(colors: orbGradient, center: .center, startRadius: 2, endRadius: core * 0.75))
                    .frame(width: core, height: core)
                    .scaleEffect(1 + (active ? amp * 0.30 : 0) + (breathe ? 0.02 : -0.02))
                    .shadow(color: brandRed.opacity(0.5), radius: 20 + (active ? amp * 26 : 6))
                    .overlay(
                        Circle().fill(Color.white.opacity(0.18))
                            .frame(width: core * 0.42, height: core * 0.42)
                            .offset(x: -core * 0.12, y: -core * 0.14)
                            .blur(radius: 6)
                    )

                KiniMascotView(size: core * 0.46)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .animation(.easeOut(duration: 0.12), value: level)
        }
        .onAppear { breathe = true }
        .accessibilityHidden(true)
    }
}

/// Asymmetric chat-bubble shape — a full corner radius with the tail corner
/// tightened, so user (right) and assistant (left) bubbles read directionally.
private struct BubbleShape: Shape {
    let isUser: Bool
    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 18
        let tail: CGFloat = 5
        let tl = isUser ? r : tail
        let tr = isUser ? tail : r
        var p = Path()
        p.move(to: CGPoint(x: rect.minX + tl, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX - tr, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - tr, y: rect.minY + tr), radius: tr, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + tl))
        p.addArc(center: CGPoint(x: rect.minX + tl, y: rect.minY + tl), radius: tl, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

/// One pulsing dot for the "thinking" indicator.
private struct TypingDot: View {
    let delay: Double
    @State private var on = false
    var body: some View {
        Circle()
            .fill(brandRed.opacity(0.7))
            .frame(width: 7, height: 7)
            .opacity(on ? 1.0 : 0.3)
            .scaleEffect(on ? 1.0 : 0.7)
            .animation(.easeInOut(duration: 0.6).repeatForever().delay(delay), value: on)
            .onAppear { on = true }
    }
}

/// Thin wrapper around `AVSpeechSynthesizer` for the optional hands-free loop
/// (spoken replies). en-IN preferred to match the user base.
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

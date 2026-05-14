import SwiftUI

private let brandRed = Color(red: 0xE0/255, green: 0x1E/255, blue: 0x2C/255)
private let brandRedLight = Color(red: 0xFF/255, green: 0x4D/255, blue: 0x4D/255)
private let brandBlue = Color(red: 0x1E/255, green: 0x3A/255, blue: 0x8A/255)
private let headerGradient = LinearGradient(
    colors: [brandRed, brandRedLight, brandBlue],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
)

/// KINI chat panel — mirrors the web `KinematicAI` chat surface so users see
/// the same product whether they're on dashboard or mobile.
/// - Red→blue gradient header with sparkle badge, "CRM" pill, credits chip
/// - Amber rate-limit banner when the user is at cap
/// - Gradient user bubbles + bordered assistant bubbles
struct KiniChatView: View {
    @StateObject var vm = KINIChatViewModel()
    @StateObject private var voice = KiniVoiceRecognizer()
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
                    .background(Color.orange.opacity(0.12))
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(vm.messages) { m in
                            bubble(for: m).id(m.id)
                        }
                        if vm.isSending {
                            HStack(spacing: 8) {
                                ProgressView().scaleEffect(0.7)
                                Text("KINI is thinking…")
                                    .font(.caption).foregroundColor(.gray)
                                Spacer()
                            }
                            .padding(.horizontal)
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
                }
            }

            Divider()

            HStack(alignment: .bottom, spacing: 8) {
                TextField(capped ? "Monthly quota reached — resets on the 1st" : "Ask KINI anything…",
                          text: $vm.draft, axis: .vertical)
                    .lineLimit(1...4)
                    .disabled(capped)
                    .padding(10)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .cornerRadius(12)

                // Hold-to-talk voice mic. Tap to start, tap again to stop;
                // partial transcripts stream into `vm.draft` as the user
                // speaks. Mirrors the web KinematicAI mic.
                if voice.isAvailable {
                    Button {
                        if voice.isListening {
                            voice.stop()
                        } else {
                            voice.start { text in vm.draft = text }
                        }
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
            if let u = vm.usage, !u.exempt {
                Text("\(u.used)/\(u.cap)")
                    .font(.system(size: 10, weight: .black))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(u.remaining == 0 ? Color.black.opacity(0.35) : Color.white.opacity(0.18))
                    .clipShape(Capsule())
            }
            Button(action: { vm.reset() }) {
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

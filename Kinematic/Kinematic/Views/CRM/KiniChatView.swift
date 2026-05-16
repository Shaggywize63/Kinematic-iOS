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
                            typingIndicator
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
                    .frame(width: 64, height: 64)
                Text("✦")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
            }
            .padding(.top, 32)

            VStack(spacing: 4) {
                Text("Ask KINI anything")
                    .font(.system(size: 18, weight: .black))
                Text("Pipeline, leads, follow-ups — your CRM copilot.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                suggestionChip("Show me overdue tasks",        icon: "exclamationmark.triangle.fill")
                suggestionChip("Which deals are stuck > 14 days?", icon: "clock.fill")
                suggestionChip("Top 5 leads I should call today", icon: "phone.fill")
                suggestionChip("Draft a follow-up for my best deal", icon: "envelope.fill")
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func suggestionChip(_ prompt: String, icon: String) -> some View {
        Button {
            vm.draft = prompt
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

    /// Three pulsing dots animation that replaces the static "KINI is
    /// thinking…" — feels alive in a way ProgressView doesn't.
    private var typingIndicator: some View {
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

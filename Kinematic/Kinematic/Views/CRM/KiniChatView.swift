import SwiftUI

struct KiniChatView: View {
    @StateObject var vm = KINIChatViewModel()
    @StateObject private var voice = KiniVoiceService()

    var body: some View {
        VStack(spacing: 0) {
            if vm.limitCode != nil {
                limitEmptyState
            } else {
                conversation
                Divider()
                inputBar
            }
        }
        .navigationTitle("KINI")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                KiniCreditsView(refreshTrigger: vm.creditsRefreshTrigger)
            }
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .onAppear {
            // Pipe voice transcripts straight into the draft so the user can
            // see what was heard. Auto-send fires when the user pauses.
            voice.onSilence = { [weak vm] in
                Task { @MainActor in
                    guard let vm else { return }
                    let text = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    let reply = await vm.send(overrideText: text)
                    if vm.voiceMode, let reply, !reply.isEmpty {
                        voice.speak(text: reply)
                    }
                }
            }
        }
        .onDisappear {
            voice.stopListening()
            voice.stopSpeaking()
        }
        .onChange(of: voice.transcript) { _, newValue in
            // Mirror the live transcript into the draft field so the user
            // sees what KINI heard before send-on-silence fires.
            if voice.isListening { vm.draft = newValue }
        }
    }

    // MARK: - Subviews

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(vm.messages) { m in
                        ChatBubble(message: m).id(m.id)
                    }
                    if vm.isSending {
                        HStack {
                            ProgressView().scaleEffect(0.7)
                            Text("KINI is thinking…")
                                .font(.caption).foregroundColor(.gray)
                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                    if voice.isListening {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform")
                                .foregroundColor(.indigo)
                                .symbolEffect(.pulse, isActive: true)
                            Text("Listening…")
                                .font(.caption).foregroundColor(.indigo)
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
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Ask KINI anything…", text: $vm.draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(10)
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(12)
                .disabled(voice.isListening)

            // Mic toggle — long-press could trigger push-to-talk in a future
            // pass; for now a single tap flips voice mode and starts/stops
            // capturing.
            Button {
                Task { await toggleVoice() }
            } label: {
                ZStack {
                    Circle()
                        .fill(voice.isListening
                              ? AnyShapeStyle(LinearGradient(colors: [.red, .pink], startPoint: .topLeading, endPoint: .bottomTrailing))
                              : AnyShapeStyle(Color(uiColor: .secondarySystemBackground)))
                        .frame(width: 40, height: 40)
                    Image(systemName: voice.isListening ? "mic.fill" : "mic")
                        .foregroundColor(voice.isListening ? .white : .primary)
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .disabled(vm.isSending)
            .accessibilityLabel(voice.isListening ? "Stop listening" : "Start voice mode")

            Button {
                Task {
                    let reply = await vm.send()
                    if vm.voiceMode, let reply, !reply.isEmpty {
                        voice.speak(text: reply)
                    }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 40, height: 40)
                    Image(systemName: "arrow.up")
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .black))
                }
            }
            .disabled(vm.draft.trimmingCharacters(in: .whitespaces).isEmpty || vm.isSending)
            .opacity(vm.draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
        }
        .padding()
    }

    /// Shown when the backend returns HTTP 429. Copy switches based on
    /// whether the user or the whole org tripped the cap.
    private var limitEmptyState: some View {
        let isOrg = vm.limitCode == .orgLimit
        return VStack(spacing: 14) {
            Image(systemName: "bolt.slash.fill")
                .font(.system(size: 44))
                .foregroundColor(.orange)
            Text(isOrg ? "Org limit reached" : "Monthly limit reached")
                .font(.headline)
            Text(isOrg
                 ? "Your team has used every KINI credit for this month. Ask an admin to raise the org cap, or wait until the 1st."
                 : "You’ve used every KINI credit for this month. Resets on the 1st.")
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 32)
            KiniCreditsView(refreshTrigger: vm.creditsRefreshTrigger)
                .padding(.top, 4)
            Spacer()
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func toggleVoice() async {
        if voice.isListening {
            voice.stopListening()
            return
        }
        if !voice.isAuthorized {
            await voice.requestAuthorization()
            guard voice.isAuthorized else { return }
        }
        vm.voiceMode = true
        vm.draft = ""
        do {
            try await voice.startListening()
        } catch {
            // Surface via the chat error path so the user sees what went wrong.
            vm.errorMessage = error.localizedDescription
        }
    }
}

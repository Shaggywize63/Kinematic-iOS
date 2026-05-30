//
//  ChatThreadView.swift
//  Kinematic
//
//  Conversation view — newest-first, polled every 8s, composer with
//  @-mention chip rendering via AttributedString.
//

import SwiftUI

@MainActor
final class ChatThreadViewModel: ObservableObject {
    @Published var messages: [MessagingMessage] = []
    @Published var sending = false
    @Published var title: String = "Chat"
    private var pollTask: Task<Void, Never>?
    private var threadId: String = ""

    func start(_ id: String) {
        threadId = id
        Task { await resolveTitle() }
        Task { await reload() }
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                if Task.isCancelled { break }
                await reload()
            }
        }
    }

    func stop() { pollTask?.cancel(); pollTask = nil }

    func reload() async {
        if let rows = try? await CRMService.shared.listMessagingMessages(threadId: threadId) {
            messages = rows
            await CRMService.shared.markMessagingThreadRead(threadId: threadId)
        }
    }

    func send(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        sending = true
        defer { sending = false }
        if let row = try? await CRMService.shared.sendMessagingMessage(threadId: threadId, body: trimmed) {
            messages.insert(row, at: 0)
        }
    }

    private func resolveTitle() async {
        guard let threads = try? await CRMService.shared.listMessagingThreads(),
              let t = threads.first(where: { $0.id == threadId }) else { return }
        title = t.title
    }
}

struct ChatThreadView: View {
    let threadId: String
    @StateObject private var vm = ChatThreadViewModel()
    @State private var draft: String = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if vm.messages.isEmpty {
                        Text("No messages yet — be the first to say something.")
                            .font(.footnote).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 60)
                    }
                    ForEach(vm.messages) { m in MessageBubble(m: m) }
                }
                .padding(14)
            }
            .scrollDismissesKeyboard(.interactively)
            .defaultScrollAnchor(.bottom)

            Divider()
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message — supports any language", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                Button {
                    let text = draft
                    draft = ""
                    Task { await vm.send(text) }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Circle().fill(draft.isEmpty || vm.sending ? Color.gray : Color.red))
                }
                .disabled(draft.isEmpty || vm.sending)
            }
            .padding(10)
            .background(.regularMaterial)
        }
        .navigationTitle(vm.title)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.start(threadId) }
        .onDisappear { vm.stop() }
    }
}

// MARK: - Message bubble

private struct MessageBubble: View {
    let m: MessagingMessage
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(Color(.tertiarySystemBackground)).frame(width: 30, height: 30)
                Text(String(m.senderLabel.prefix(1)).uppercased())
                    .font(.caption.weight(.bold))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(m.senderLabel).font(.footnote.weight(.bold))
                    Text(Self.formatTime(m.createdAt)).font(.caption2).foregroundStyle(.secondary)
                }
                Text(renderMentions(m.body))
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static let parser = ISO8601DateFormatter()
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter()
        f.timeZone = TimeZone(identifier: "Asia/Kolkata")
        f.locale = Locale(identifier: "en_IN")
        f.dateFormat = "h:mm a"
        return f
    }()

    private static func formatTime(_ iso: String) -> String {
        if let d = parser.date(from: iso) { return timeFmt.string(from: d) }
        // Fallback: strip fractional seconds / timezone before reparse.
        let trimmed = iso.split(separator: ".").first.map(String.init) ?? iso
        if let d = parser.date(from: trimmed + "Z") { return timeFmt.string(from: d) }
        return ""
    }

    /// Renders @[uid:Name] tokens as inline accent-coloured chips. Falls
    /// back to plain text if no tokens are present so non-mention rows
    /// don't pay the AttributedString cost.
    private func renderMentions(_ body: String) -> AttributedString {
        var out = AttributedString("")
        let pattern = #"@\[([0-9a-fA-F-]{8,})(?::([^\]]+))?\]"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return AttributedString(body) }
        let ns = body as NSString
        var lastEnd = 0
        let matches = re.matches(in: body, range: NSRange(location: 0, length: ns.length))
        if matches.isEmpty { return AttributedString(body) }
        for m in matches {
            if m.range.location > lastEnd {
                out.append(AttributedString(ns.substring(with: NSRange(location: lastEnd, length: m.range.location - lastEnd))))
            }
            let name = m.range(at: 2).location == NSNotFound ? "user" : ns.substring(with: m.range(at: 2))
            var chip = AttributedString("@\(name)")
            chip.font = .body.weight(.bold)
            chip.foregroundColor = Color.indigo
            out.append(chip)
            lastEnd = m.range.location + m.range.length
        }
        if lastEnd < ns.length {
            out.append(AttributedString(ns.substring(with: NSRange(location: lastEnd, length: ns.length - lastEnd))))
        }
        return out
    }
}

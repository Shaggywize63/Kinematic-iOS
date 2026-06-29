import Foundation
import Combine

@MainActor
final class KINIChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var draft: String = ""
    @Published var isSending = false
    @Published var errorMessage: String?
    /// Latest monthly KINI quota — drives the credits chip in the header.
    @Published var usage: KiniUsage?

    private let api = AIChatService.shared

    init() {
        messages.append(ChatMessage(
            id: UUID().uuidString,
            role: "assistant",
            content: "Hi, I’m KINI. Ask me about leads, deals, pipeline health, or say things like “draft a follow-up to ACME”.",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            toolName: nil,
            toolPayload: nil,
            cards: nil
        ))
        Task { await refreshUsage() }
    }

    func refreshUsage() async {
        if let u = await api.fetchUsage() { usage = u }
    }

    func reset() {
        messages = [ChatMessage(
            id: UUID().uuidString,
            role: "assistant",
            content: "Conversation cleared. What’s next?",
            createdAt: ISO8601DateFormatter().string(from: Date()),
            toolName: nil, toolPayload: nil, cards: nil
        )]
    }

    func send() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return }
        let userMsg = ChatMessage(
            id: UUID().uuidString,
            role: "user",
            content: text,
            createdAt: ISO8601DateFormatter().string(from: Date()),
            toolName: nil,
            toolPayload: nil,
            cards: nil
        )
        messages.append(userMsg)
        draft = ""
        isSending = true
        defer { isSending = false }

        // Backend is stateless: replay the full user/assistant transcript so
        // Claude has the conversation context. Skip the local tool/system
        // bubbles — only `user` and `assistant` roles are accepted.
        let history = messages
            .filter { $0.role == "user" || $0.role == "assistant" }
            .map { ChatTurn(role: $0.role, content: $0.content) }

        do {
            // Stamp the agentic-v2 context block from wherever the rep is in
            // the app (record detail screens set this in `.onAppear`). It's a
            // hint, not a fence — KINI still answers across every module.
            let response = try await api.chat(
                messages: history,
                context: KiniContextHolder.shared.contextDict()
            )
            let assistant = ChatMessage(
                id: UUID().uuidString,
                role: "assistant",
                content: response.text,
                createdAt: ISO8601DateFormatter().string(from: Date()),
                toolName: nil,
                toolPayload: nil,
                cards: response.cards
            )
            messages.append(assistant)
            // Backend stamps the freshest quota on every successful reply.
            if let u = response.usage { usage = u }
        } catch {
            errorMessage = error.localizedDescription
            messages.append(ChatMessage(
                id: UUID().uuidString,
                role: "assistant",
                content: "Sorry — I couldn’t reach the assistant. \(error.localizedDescription)",
                createdAt: ISO8601DateFormatter().string(from: Date()),
                toolName: nil, toolPayload: nil, cards: nil
            ))
        }
    }
}

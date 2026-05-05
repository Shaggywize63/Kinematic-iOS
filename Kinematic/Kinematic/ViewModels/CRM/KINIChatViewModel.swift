import Foundation
import Combine

@MainActor
final class KINIChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var draft: String = ""
    @Published var isSending = false
    @Published var errorMessage: String?
    private(set) var conversationId: String?

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

        do {
            let response = try await api.chat(message: text, conversationId: conversationId)
            if conversationId == nil { conversationId = response.messageId }
            let assistant = ChatMessage(
                id: response.messageId ?? UUID().uuidString,
                role: "assistant",
                content: response.reply,
                createdAt: ISO8601DateFormatter().string(from: Date()),
                toolName: nil,
                toolPayload: nil,
                cards: response.cards
            )
            messages.append(assistant)
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

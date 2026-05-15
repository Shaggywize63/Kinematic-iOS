import Foundation
import Combine

@MainActor
final class KINIChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var draft: String = ""
    @Published var isSending = false
    @Published var errorMessage: String?
    /// Set when the backend returned HTTP 429 with a structured limit code.
    /// View flips into a "monthly limit reached" empty state when non-nil.
    @Published var limitCode: KiniLimitCode?
    /// Bumped after every successful turn so the credits pill re-fetches.
    @Published var creditsRefreshTrigger: Int = 0
    /// True when voice mode is on. Chat view toggles the mic UI on this.
    @Published var voiceMode: Bool = false

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

    /// Send the current draft (or an externally-provided text from voice mode).
    /// Returns the assistant reply text on success so the caller can pipe it
    /// into TTS without re-reading `messages`.
    @discardableResult
    func send(overrideText: String? = nil) async -> String? {
        let text = (overrideText ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isSending else { return nil }
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
        if overrideText == nil { draft = "" }
        isSending = true
        defer { isSending = false }

        // Backend is stateless: replay the full user/assistant transcript so
        // Claude has the conversation context. Skip the local tool/system
        // bubbles — only `user` and `assistant` roles are accepted.
        let history = messages
            .filter { $0.role == "user" || $0.role == "assistant" }
            .map { ChatTurn(role: $0.role, content: $0.content) }

        do {
            let response = try await api.chat(messages: history)
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
            limitCode = nil
            creditsRefreshTrigger &+= 1
            return response.text
        } catch let q as KiniQuotaError {
            // Cap hit — surface the structured code so the view can flip
            // into an empty-state with the right copy. We also drop a stub
            // assistant message so the user gets immediate feedback.
            limitCode = q.code
            errorMessage = q.message
            messages.append(ChatMessage(
                id: UUID().uuidString,
                role: "assistant",
                content: q.message,
                createdAt: ISO8601DateFormatter().string(from: Date()),
                toolName: nil, toolPayload: nil, cards: nil
            ))
            return nil
        } catch {
            errorMessage = error.localizedDescription
            messages.append(ChatMessage(
                id: UUID().uuidString,
                role: "assistant",
                content: "Sorry — I couldn’t reach the assistant. \(error.localizedDescription)",
                createdAt: ISO8601DateFormatter().string(from: Date()),
                toolName: nil, toolPayload: nil, cards: nil
            ))
            return nil
        }
    }
}

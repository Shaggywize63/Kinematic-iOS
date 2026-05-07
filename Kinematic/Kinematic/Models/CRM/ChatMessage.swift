import Foundation

struct ChatMessage: Codable, Identifiable, Hashable {
    let id: String
    let role: String            // user / assistant / tool
    let content: String
    let createdAt: String?
    let toolName: String?
    let toolPayload: [String: AnyCodable]?
    let cards: [KiniCard]?

    enum CodingKeys: String, CodingKey {
        case id, role, content
        case createdAt = "created_at"
        case toolName = "tool_name"
        case toolPayload = "tool_payload"
        case cards
    }
}

struct AIChatResponse: Codable {
    /// Backend payload field is `text` (matches dashboard contract). Older
    /// builds expected `reply`; we accept either to ease the rollout.
    let text: String
    let cards: [KiniCard]?
    let toolCalls: [String]?

    enum CodingKeys: String, CodingKey {
        case text
        case reply
        case cards
        case toolCalls = "tool_calls"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let t = try c.decodeIfPresent(String.self, forKey: .text) {
            self.text = t
        } else {
            self.text = try c.decodeIfPresent(String.self, forKey: .reply) ?? ""
        }
        self.cards = try c.decodeIfPresent([KiniCard].self, forKey: .cards)
        self.toolCalls = try c.decodeIfPresent([String].self, forKey: .toolCalls)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        try c.encodeIfPresent(cards, forKey: .cards)
        try c.encodeIfPresent(toolCalls, forKey: .toolCalls)
    }
}

/// Minimal {role, content} tuple used to build the backend `messages` array.
struct ChatTurn {
    let role: String
    let content: String
}

struct AIDraftReplyResponse: Codable {
    let subject: String?
    let body: String
}

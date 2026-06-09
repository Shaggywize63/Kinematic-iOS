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
    /// Monthly AI quota snapshot stamped on every successful chat reply.
    /// Used to keep the FAB credits chip current without a separate poll.
    let usage: KiniUsage?

    enum CodingKeys: String, CodingKey {
        case text
        case reply
        case cards
        case toolCalls = "tool_calls"
        case usage
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let t = try c.decodeIfPresent(String.self, forKey: .text) {
            self.text = t
        } else {
            self.text = try c.decodeIfPresent(String.self, forKey: .reply) ?? ""
        }
        self.cards = try c.decodeIfPresent([KiniCard].self, forKey: .cards)
        // tool_calls from the backend is [{name, args}] — an array of objects,
        // not strings. Using try? so a type mismatch silently returns nil rather
        // than throwing and collapsing the entire response decode. iOS doesn't
        // render tool_calls directly (cards carry the displayable results).
        self.toolCalls = try? c.decodeIfPresent([String].self, forKey: .toolCalls)
        self.usage = try c.decodeIfPresent(KiniUsage.self, forKey: .usage)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        try c.encodeIfPresent(cards, forKey: .cards)
        try c.encodeIfPresent(toolCalls, forKey: .toolCalls)
        try c.encodeIfPresent(usage, forKey: .usage)
    }
}

/// Monthly KINI AI quota state. Drives the "used/cap" chip rendered on the
/// global FAB and inside the chat header. `exempt` callers (super-admin,
/// internal accounts) skip the chip entirely. `month` is YYYY-MM.
struct KiniUsage: Codable, Equatable {
    let used: Int
    let cap: Int
    let remaining: Int
    let exempt: Bool
    let month: String?

    enum CodingKeys: String, CodingKey {
        case used, cap, remaining, exempt, month
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.used = (try? c.decode(Int.self, forKey: .used)) ?? 0
        self.cap = (try? c.decode(Int.self, forKey: .cap)) ?? 0
        self.remaining = (try? c.decode(Int.self, forKey: .remaining)) ?? 0
        self.exempt = (try? c.decode(Bool.self, forKey: .exempt)) ?? false
        self.month = try c.decodeIfPresent(String.self, forKey: .month)
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

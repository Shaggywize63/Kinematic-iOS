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
    let messageId: String?
    let reply: String
    let cards: [KiniCard]?
    let toolCalls: [String]?

    enum CodingKeys: String, CodingKey {
        case messageId = "message_id"
        case reply
        case cards
        case toolCalls = "tool_calls"
    }
}

struct AIDraftReplyResponse: Codable {
    let subject: String?
    let body: String
}

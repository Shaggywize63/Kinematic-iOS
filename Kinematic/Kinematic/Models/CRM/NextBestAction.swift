import Foundation

struct NextBestAction: Codable, Hashable {
    let dealId: String?
    let action: String
    let rationale: String?
    let dueAt: String?
    let confidence: Double?
    let suggestedTemplate: String?

    enum CodingKeys: String, CodingKey {
        case dealId = "deal_id"
        case action, rationale
        case dueAt = "due_at"
        case confidence
        case suggestedTemplate = "suggested_template"
    }
}

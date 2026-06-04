import Foundation

/// An append-only lead update (the "Recent Updates" timeline) — mirrors the
/// web LeadUpdatesTimeline. Posted via POST /crm/leads/:id/updates.
struct LeadUpdate: Codable, Identifiable {
    let id: String
    let body: String
    let authorName: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, body
        case authorName = "author_name"
        case createdAt = "created_at"
    }
}

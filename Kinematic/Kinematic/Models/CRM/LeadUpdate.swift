import Foundation

/// An append-only lead update (the "Recent Updates" timeline) — mirrors the
/// web LeadUpdatesTimeline. Posted via POST /crm/leads/:id/updates.
struct LeadUpdate: Codable, Identifiable {
    let id: String
    let body: String
    /// Author user id — used to gate the per-row Edit/Delete affordances
    /// to the rep who wrote the note (mirrors the backend author-only
    /// PATCH / author-or-admin DELETE). Optional so legacy rows / the
    /// offline optimistic insert (which has no id) still decode.
    let authorId: String?
    let authorName: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, body
        case authorId = "author_id"
        case authorName = "author_name"
        case createdAt = "created_at"
    }

    init(id: String, body: String, authorId: String? = nil, authorName: String?, createdAt: String?) {
        self.id = id
        self.body = body
        self.authorId = authorId
        self.authorName = authorName
        self.createdAt = createdAt
    }
}

import Foundation

struct Activity: Codable, Identifiable, Hashable {
    let id: String
    let orgId: String?
    let type: String?           // call, email, meeting, note, task
    let subject: String?
    let description: String?
    let leadId: String?
    let contactId: String?
    let accountId: String?
    let dealId: String?
    let ownerId: String?
    let ownerName: String?
    /// Workflow state stamped by the backend: open / in_progress / completed / cancelled.
    /// The CRM Activities list pill renders this directly (matches the web
    /// dashboard); when nil, the row falls back to "completed" if
    /// `completedAt` is set, else "open".
    let status: String?
    let dueAt: String?
    let completedAt: String?
    let direction: String?      // inbound / outbound
    let durationMinutes: Int?
    let imageUrl: String?
    let createdAt: String?
    let updatedAt: String?

    /// Effective workflow state for UI rendering — falls back to a sensible
    /// default when the backend hasn't stamped `status` yet (older rows).
    var effectiveStatus: String {
        if let s = status?.trimmingCharacters(in: .whitespaces), !s.isEmpty { return s.lowercased() }
        return (completedAt?.isEmpty == false) ? "completed" : "open"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case orgId = "org_id"
        case type, subject, description, status
        case leadId = "lead_id"
        case contactId = "contact_id"
        case accountId = "account_id"
        case dealId = "deal_id"
        case ownerId = "owner_id"
        case ownerName = "owner_name"
        case dueAt = "due_at"
        case completedAt = "completed_at"
        case direction
        case durationMinutes = "duration_minutes"
        case imageUrl = "image_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

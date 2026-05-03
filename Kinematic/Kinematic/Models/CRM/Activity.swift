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
    let dueAt: String?
    let completedAt: String?
    let direction: String?      // inbound / outbound
    let durationMinutes: Int?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case orgId = "org_id"
        case type, subject, description
        case leadId = "lead_id"
        case contactId = "contact_id"
        case accountId = "account_id"
        case dealId = "deal_id"
        case ownerId = "owner_id"
        case dueAt = "due_at"
        case completedAt = "completed_at"
        case direction
        case durationMinutes = "duration_minutes"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

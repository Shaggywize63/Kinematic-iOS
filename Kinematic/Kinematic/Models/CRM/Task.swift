import Foundation

struct CRMTask: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String?
    let priority: String?       // low / medium / high
    let status: String?         // open / done / cancelled
    let dueAt: String?
    let completedAt: String?
    let assigneeId: String?
    let leadId: String?
    let dealId: String?
    let contactId: String?
    let accountId: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, description, priority, status
        case dueAt = "due_at"
        case completedAt = "completed_at"
        case assigneeId = "assignee_id"
        case leadId = "lead_id"
        case dealId = "deal_id"
        case contactId = "contact_id"
        case accountId = "account_id"
        case createdAt = "created_at"
    }
}

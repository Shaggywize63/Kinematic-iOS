import Foundation

/// Tasks are activities of type='task'. Field names mirror the backend
/// taskSchema in src/validators/crm.validators.ts. Status is one of
/// 'open' | 'in_progress' | 'done' | 'cancelled'.
struct CRMTask: Codable, Identifiable, Hashable {
    let id: String
    let subject: String?
    let description: String?
    let priority: String?
    let status: String?
    let dueAt: String?
    let completedAt: String?
    let assignedTo: String?
    let assignedToName: String?
    let ownerId: String?
    let ownerName: String?
    let leadId: String?
    let dealId: String?
    let contactId: String?
    let accountId: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, subject, description, priority, status
        case dueAt = "due_at"
        case completedAt = "completed_at"
        case assignedTo = "assigned_to"
        case assignedToName = "assigned_to_name"
        case ownerId = "owner_id"
        case ownerName = "owner_name"
        case leadId = "lead_id"
        case dealId = "deal_id"
        case contactId = "contact_id"
        case accountId = "account_id"
        case createdAt = "created_at"
    }

    var isDone: Bool { status == "done" }
}

import Foundation

struct CRMNote: Codable, Identifiable, Hashable {
    let id: String
    let body: String
    let leadId: String?
    let contactId: String?
    let accountId: String?
    let dealId: String?
    let createdBy: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, body
        case leadId = "lead_id"
        case contactId = "contact_id"
        case accountId = "account_id"
        case dealId = "deal_id"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }
}

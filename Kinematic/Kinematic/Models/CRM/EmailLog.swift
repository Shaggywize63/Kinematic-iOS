import Foundation

struct EmailLog: Codable, Identifiable, Hashable {
    let id: String
    let toAddress: String?
    let fromAddress: String?
    let subject: String?
    let body: String?
    let status: String?         // sent / bounced / queued
    let templateId: String?
    let leadId: String?
    let contactId: String?
    let dealId: String?
    let openedAt: String?
    let clickedAt: String?
    let sentAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case toAddress = "to_address"
        case fromAddress = "from_address"
        case subject, body, status
        case templateId = "template_id"
        case leadId = "lead_id"
        case contactId = "contact_id"
        case dealId = "deal_id"
        case openedAt = "opened_at"
        case clickedAt = "clicked_at"
        case sentAt = "sent_at"
    }
}

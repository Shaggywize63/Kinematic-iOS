import Foundation

/// An upsell — additional revenue logged against an existing deal and/or lead,
/// kept separate from the deal's own amount. Rendered as the "Upsells" section
/// on the lead- and deal-detail screens. Mirrors the backend `crm_upsells` row.
struct Upsell: Codable, Identifiable, Hashable {
    let id: String
    let dealId: String?
    let leadId: String?
    let amount: Double?
    let currency: String?
    let quantity: Double?
    let productId: String?
    let productName: String?
    let status: String?        // proposed | won | lost
    let note: String?
    let occurredAt: String?
    let createdBy: String?
    let createdByName: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case dealId = "deal_id"
        case leadId = "lead_id"
        case amount, currency, quantity
        case productId = "product_id"
        case productName = "product_name"
        case status, note
        case occurredAt = "occurred_at"
        case createdBy = "created_by"
        case createdByName = "created_by_name"
        case createdAt = "created_at"
    }
}

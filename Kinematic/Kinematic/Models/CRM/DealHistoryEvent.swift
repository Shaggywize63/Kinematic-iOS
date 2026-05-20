import Foundation

/// One row from `/api/v1/crm/deals/:id/history`. Each event carries
/// its `event_type` plus whichever from/to fields are relevant — the
/// backend only populates stage columns on stage transitions and
/// amount columns on amount edits, so everything except `id`,
/// `event_type` and `created_at` is optional.
struct DealHistoryEvent: Codable, Identifiable, Hashable {
    let id: String
    let eventType: String       // stage_changed | amount_changed | created | updated
    let fromStage: String?
    let toStage: String?
    let fromAmount: Double?
    let toAmount: Double?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case eventType  = "event_type"
        case fromStage  = "from_stage"
        case toStage    = "to_stage"
        case fromAmount = "from_amount"
        case toAmount   = "to_amount"
        case createdAt  = "created_at"
    }
}

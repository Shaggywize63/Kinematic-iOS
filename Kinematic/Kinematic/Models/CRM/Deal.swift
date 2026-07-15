import Foundation

struct Deal: Codable, Identifiable, Hashable {
    let id: String
    let orgId: String?
    let name: String
    let accountId: String?
    let contactId: String?
    let pipelineId: String?
    let stageId: String?
    let stageName: String?
    let amount: Double?
    let currency: String?
    let probability: Double?
    let winProbability: Double?
    let expectedCloseDate: String?
    let actualCloseDate: String?
    let status: String?           // open / won / lost
    let lostReason: String?
    let ownerId: String?
    let nextActionAt: String?
    let nextActionLabel: String?
    let tags: [String]?
    let createdAt: String?
    let updatedAt: String?
    // Linked lead — set on conversion-style deal creation. Product edits
    // on the deal are mirrored back onto this lead's custom_fields.
    let leadId: String?
    // Free-form jsonb. Carries the deal's own basket (`product_lines`,
    // `volume_kg`) plus `closed_quantities = { [product_id]: number }`
    // persisted by the Products section.
    let customFields: [String: AnyCodable]?
    // Server-stamped display fields — GET /deals and /deals/:id enrich
    // each row with the resolved dealer label plus the linked lead's
    // name/phone. Read-only: never included in create/PATCH bodies.
    let dealerName: String?
    let leadName: String?
    let leadPhone: String?

    enum CodingKeys: String, CodingKey {
        case id
        case orgId = "org_id"
        case name
        case accountId = "account_id"
        case contactId = "contact_id"
        case pipelineId = "pipeline_id"
        case stageId = "stage_id"
        case stageName = "stage_name"
        case amount, currency, probability
        case winProbability = "win_probability"
        case expectedCloseDate = "expected_close_date"
        case actualCloseDate = "actual_close_date"
        case status
        case lostReason = "lost_reason"
        case ownerId = "owner_id"
        case nextActionAt = "next_action_at"
        case nextActionLabel = "next_action_label"
        case tags
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case leadId = "lead_id"
        case customFields = "custom_fields"
        case dealerName = "dealer_name"
        case leadName = "lead_name"
        case leadPhone = "lead_phone"
    }
}

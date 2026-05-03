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
    }
}

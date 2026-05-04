import Foundation

struct Pipeline: Codable, Identifiable, Hashable {
    let id: String
    let orgId: String?
    let name: String
    let isDefault: Bool?
    let stages: [Stage]?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case orgId = "org_id"
        case name
        case isDefault = "is_default"
        case stages
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

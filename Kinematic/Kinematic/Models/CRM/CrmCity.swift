import Foundation

struct CrmCity: Codable, Identifiable, Hashable {
    let id: String
    let orgId: String?
    let stateId: String?
    let name: String
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case orgId = "org_id"
        case stateId = "state_id"
        case name
        case isActive = "is_active"
    }
}

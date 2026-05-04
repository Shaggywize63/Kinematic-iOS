import Foundation

struct CrmState: Codable, Identifiable, Hashable {
    let id: String
    let orgId: String?
    let name: String
    let code: String?
    let country: String?
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case orgId = "org_id"
        case name, code, country
        case isActive = "is_active"
    }
}

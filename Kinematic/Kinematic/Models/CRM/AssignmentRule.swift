import Foundation

struct AssignmentRule: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let isActive: Bool?
    let priority: Int?
    let criteria: [String: AnyCodable]?
    let assignToUserId: String?
    let assignToTeamId: String?

    enum CodingKeys: String, CodingKey {
        case id, name
        case isActive = "is_active"
        case priority, criteria
        case assignToUserId = "assign_to_user_id"
        case assignToTeamId = "assign_to_team_id"
    }
}

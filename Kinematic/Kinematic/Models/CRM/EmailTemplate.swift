import Foundation

struct EmailTemplate: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let subject: String
    let body: String
    let category: String?
    let isActive: Bool?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, subject, body, category
        case isActive = "is_active"
        case createdAt = "created_at"
    }
}

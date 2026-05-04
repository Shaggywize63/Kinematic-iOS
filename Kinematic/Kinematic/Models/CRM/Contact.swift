import Foundation

struct Contact: Codable, Identifiable, Hashable {
    let id: String
    let orgId: String?
    let firstName: String?
    let lastName: String?
    let email: String?
    let phone: String?
    let mobile: String?
    let title: String?
    let accountId: String?
    let ownerId: String?
    let department: String?
    let leadSource: String?
    let mailingAddress: String?
    let tags: [String]?
    let createdAt: String?
    let updatedAt: String?

    var displayName: String {
        let f = firstName ?? ""
        let l = lastName ?? ""
        let combined = "\(f) \(l)".trimmingCharacters(in: .whitespaces)
        return combined.isEmpty ? (email ?? "Unnamed Contact") : combined
    }

    enum CodingKeys: String, CodingKey {
        case id
        case orgId = "org_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case email, phone, mobile, title
        case accountId = "account_id"
        case ownerId = "owner_id"
        case department
        case leadSource = "lead_source"
        case mailingAddress = "mailing_address"
        case tags
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

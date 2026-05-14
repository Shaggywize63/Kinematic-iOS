import Foundation

/// A user the current caller is allowed to assign a lead/deal/activity to.
/// Backed by `GET /api/v1/users` which is admin/supervisor-gated. Client-role
/// users (CRM-only deployments) get an empty list — see
/// `CRMService.listAssignableUsers()`.
struct AssignableUser: Codable, Identifiable, Hashable {
    let id: String
    let name: String?
    let fullName: String?
    let email: String?
    let role: String?

    var displayName: String {
        if let n = name, !n.isEmpty { return n }
        if let n = fullName, !n.isEmpty { return n }
        return email ?? "User"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case fullName = "full_name"
        case email
        case role
    }
}

import Foundation

struct CRMAccount: Codable, Identifiable, Hashable {
    let id: String
    let orgId: String?
    let name: String
    let industry: String?
    let website: String?
    let phone: String?
    let employees: Int?
    let annualRevenue: Double?
    let billingAddress: String?
    let shippingAddress: String?
    let ownerId: String?
    /// The owner's name, stamped by the backend on GET / PATCH (read-only; never sent back).
    let ownerName: String?
    let parentAccountId: String?
    let territoryId: String?
    let tags: [String]?
    let description: String?
    /// Spark & Ray: an Outcome stored on the account before outcomes moved to activities. Read-only now (shown as
    /// "Outcome (earlier)" on the account detail); it is no longer entered on the account forms. Nil elsewhere.
    let outcome: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case orgId = "org_id"
        case name
        case industry, website, phone, employees
        case annualRevenue = "annual_revenue"
        case billingAddress = "billing_address"
        case shippingAddress = "shipping_address"
        case ownerId = "owner_id"
        case ownerName = "owner_name"
        case parentAccountId = "parent_account_id"
        case territoryId = "territory_id"
        case tags
        case description
        case outcome
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

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
    let parentAccountId: String?
    let territoryId: String?
    let tags: [String]?
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
        case parentAccountId = "parent_account_id"
        case territoryId = "territory_id"
        case tags
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

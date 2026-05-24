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
    let accountName: String?
    let ownerId: String?
    let department: String?
    let leadSource: String?
    let mailingAddress: String?
    let tags: [String]?
    let createdAt: String?
    let updatedAt: String?

    // B2C / consumer fields
    let isB2c: Bool?
    let dateOfBirth: String?
    let gender: String?
    let addressLine1: String?
    let addressLine2: String?
    let city: String?
    let state: String?
    let postalCode: String?
    let country: String?
    let preferredContactMethod: String?
    let marketingConsent: Bool?
    let whatsappConsent: Bool?

    // Customer 360 (B2C only)
    let loyaltyTier: String?
    let customerSince: String?
    let lifetimeValue: Double?
    let totalOrders: Int?
    let lastPurchaseAt: String?
    let referralSource: String?

    var displayName: String {
        let f = firstName ?? ""
        let l = lastName ?? ""
        let combined = "\(f) \(l)".trimmingCharacters(in: .whitespaces)
        return combined.isEmpty ? (email ?? "Unnamed Contact") : combined
    }

    var fullAddress: String? {
        let parts = [addressLine1, addressLine2, city, state, postalCode, country].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    enum CodingKeys: String, CodingKey {
        case id
        case orgId = "org_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case email, phone, mobile, title
        case accountId = "account_id"
        case accountName = "account_name"
        case ownerId = "owner_id"
        case department
        case leadSource = "lead_source"
        case mailingAddress = "mailing_address"
        case tags
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isB2c = "is_b2c"
        case dateOfBirth = "date_of_birth"
        case gender
        case addressLine1 = "address_line1"
        case addressLine2 = "address_line2"
        case city, state
        case postalCode = "postal_code"
        case country
        case preferredContactMethod = "preferred_contact_method"
        case marketingConsent = "marketing_consent"
        case whatsappConsent = "whatsapp_consent"
        case loyaltyTier = "loyalty_tier"
        case customerSince = "customer_since"
        case lifetimeValue = "lifetime_value"
        case totalOrders = "total_orders"
        case lastPurchaseAt = "last_purchase_at"
        case referralSource = "referral_source"
    }
}

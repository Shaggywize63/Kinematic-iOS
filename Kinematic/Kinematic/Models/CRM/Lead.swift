//
//  Lead.swift
//  Kinematic CRM
//
//  Mirrors /api/v1/crm/leads JSON shape from the kinematic backend.
//

import Foundation

struct Lead: Codable, Identifiable, Hashable {
    let id: String
    let orgId: String?
    let firstName: String?
    let lastName: String?
    let email: String?
    let phone: String?
    let company: String?
    let title: String?
    let source: String?
    let status: String?
    let score: Double?
    let ownerId: String?
    let assignedTo: String?
    let convertedAt: String?
    let convertedContactId: String?
    let convertedAccountId: String?
    let convertedDealId: String?
    let lastActivityAt: String?
    let nextFollowUpAt: String?
    let tags: [String]?
    let customFields: [String: AnyCodable]?
    let notes: String?
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

    var displayName: String {
        let f = firstName ?? ""
        let l = lastName ?? ""
        let combined = "\(f) \(l)".trimmingCharacters(in: .whitespaces)
        return combined.isEmpty ? (email ?? "Unnamed Lead") : combined
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
        case email
        case phone
        case company
        case title
        case source
        case status
        case score
        case ownerId = "owner_id"
        case assignedTo = "assigned_to"
        case convertedAt = "converted_at"
        case convertedContactId = "converted_contact_id"
        case convertedAccountId = "converted_account_id"
        case convertedDealId = "converted_deal_id"
        case lastActivityAt = "last_activity_at"
        case nextFollowUpAt = "next_follow_up_at"
        case tags
        case customFields = "custom_fields"
        case notes
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isB2c = "is_b2c"
        case dateOfBirth = "date_of_birth"
        case gender
        case addressLine1 = "address_line1"
        case addressLine2 = "address_line2"
        case city
        case state
        case postalCode = "postal_code"
        case country
        case preferredContactMethod = "preferred_contact_method"
        case marketingConsent = "marketing_consent"
        case whatsappConsent = "whatsapp_consent"
    }
}

/// A loose container for arbitrary JSON values (custom_fields, etc.).
struct AnyCodable: Codable, Hashable {
    let value: String?

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s; return }
        if let i = try? c.decode(Int.self)    { value = String(i); return }
        if let d = try? c.decode(Double.self) { value = String(d); return }
        if let b = try? c.decode(Bool.self)   { value = String(b); return }
        value = nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}

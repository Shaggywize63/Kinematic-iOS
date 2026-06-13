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
    let ownerName: String?
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

    // Geo coordinates — captured on add via device GPS / manual entry, or
    // backfilled from the dashboard. Plotted on the web map; shown read-only
    // on the lead detail here. Optional: most legacy leads have no fix.
    let latitude: Double?
    let longitude: Double?

    // Lifecycle (disqualify / reopen). Populated by the backend whenever
    // status flips to "unqualified" or "lost" via PATCH /leads/:id, and
    // cleared again by POST /leads/:id/reopen. Used by the lead detail
    // banner so the rep can see *why* a lead was disqualified inline.
    let lostReason: String?
    let disqualifiedAt: String?

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
        case ownerName = "owner_name"
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
        case latitude
        case longitude
        case lostReason = "lost_reason"
        case disqualifiedAt = "disqualified_at"
    }
}

/// A loose container for arbitrary JSON values (custom_fields, etc.).
/// Loose JSON box. `value` stays a `String?` for back-compat — callers that
/// only need a scalar string keep working unchanged. `raw` is the typed
/// underlying value (nested arrays / dicts included) so the Products card
/// can decode `product_lines` (array of dicts) and `closed_quantities`
/// (dict of numbers) without ditching the Codable model.
struct AnyCodable: Codable, Hashable {
    let value: String?
    let raw: AnyJSON?

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { value = s; raw = .string(s); return }
        if let i = try? c.decode(Int.self)    { value = String(i); raw = .number(Double(i)); return }
        if let d = try? c.decode(Double.self) { value = String(d); raw = .number(d); return }
        if let b = try? c.decode(Bool.self)   { value = String(b); raw = .bool(b); return }
        if let arr = try? c.decode([AnyJSON].self) { value = nil; raw = .array(arr); return }
        if let obj = try? c.decode([String: AnyJSON].self) { value = nil; raw = .object(obj); return }
        value = nil
        raw = nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        if let r = raw { try c.encode(r); return }
        try c.encode(value)
    }
}

/// Typed JSON value — replaces the older string-only AnyCodable so we can
/// round-trip nested arrays + objects (product_lines, closed_quantities).
indirect enum AnyJSON: Codable, Hashable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AnyJSON])
    case object([String: AnyJSON])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .number(Double(i)); return }
        if let d = try? c.decode(Double.self) { self = .number(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([AnyJSON].self) { self = .array(a); return }
        if let o = try? c.decode([String: AnyJSON].self) { self = .object(o); return }
        self = .null
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .number(let n): try c.encode(n)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    /// Convert back to a plain `Any` graph (matching the JSONSerialization
    /// world) so the Products card can read it through subscripts.
    var any: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let n):
            // Preserve ints when possible so subscript `as? Int` keeps working.
            if n == n.rounded(), abs(n) < Double(Int.max) { return Int(n) }
            return n
        case .string(let s): return s
        case .array(let a): return a.map { $0.any }
        case .object(let o): return o.mapValues { $0.any }
        }
    }
}

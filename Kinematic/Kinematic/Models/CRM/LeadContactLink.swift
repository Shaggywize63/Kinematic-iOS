import Foundation

/// One customer person linked to a lead (crm_lead_contacts) — Spark & Ray. `id` is the LINK row id (used to
/// re-point the primary flag), `contactId` is the underlying contact. Exactly one row per lead is primary.
struct LeadContactLink: Codable, Identifiable, Hashable {
    let id: String
    let contactId: String?
    let isPrimary: Bool
    let role: String?
    let name: String?
    let title: String?
    let phone: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case id
        case contactId = "contact_id"
        case isPrimary = "is_primary"
        case role, name, title, phone, email
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? ""
        contactId = try? c.decodeIfPresent(String.self, forKey: .contactId)
        isPrimary = (try? c.decodeIfPresent(Bool.self, forKey: .isPrimary)) ?? false
        role = try? c.decodeIfPresent(String.self, forKey: .role)
        name = try? c.decodeIfPresent(String.self, forKey: .name)
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        phone = try? c.decodeIfPresent(String.self, forKey: .phone)
        email = try? c.decodeIfPresent(String.self, forKey: .email)
    }
}

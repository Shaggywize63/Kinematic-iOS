import Foundation

/// Structured lead fields returned by `POST /api/v1/crm/ai/extract-lead` —
/// the "Fill with voice" backend. Every field is optional; the client maps
/// the non-empty ones onto the Create Lead form (still gated by the
/// field-override contract, so a value for an admin-hidden field never shows).
struct ExtractedLead: Codable {
    let firstName: String?
    let lastName: String?
    let phone: String?
    let alternateMobiles: [String]?
    let email: String?
    let company: String?
    let title: String?
    let industry: String?
    let dateOfBirth: String?          // YYYY-MM-DD when derivable
    let gender: String?               // male | female | other | prefer_not_to_say
    let addressLine1: String?
    let city: String?
    let state: String?
    let country: String?
    let preferredContactMethod: String? // email | phone | whatsapp | sms
    let notes: String?
    let sourceHint: String?
    let customFields: [String: String]?

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case phone
        case alternateMobiles = "alternate_mobiles"
        case email, company, title, industry
        case dateOfBirth = "date_of_birth"
        case gender
        case addressLine1 = "address_line1"
        case city, state, country
        case preferredContactMethod = "preferred_contact_method"
        case notes
        case sourceHint = "source_hint"
        case customFields = "custom_fields"
    }
}

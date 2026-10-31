import Foundation

// Visit bridge — connects a field plant-visit to the CRM customer graph
// (account -> site -> contacts -> opportunity), mirroring the backend
// /api/v1/crm visit bridge and the Android client. The rep captures the visit
// once; the resolved ids are stamped onto each product-survey form submission.

/// The active visit's CRM links, held on KiniAppState and read by the form
/// submit builders so every product form filled during the visit attaches to
/// the same account / site / contact / visit.
struct VisitContext {
    let accountId: String?
    let siteId: String?
    let contactId: String?
    let visitId: String?
}

/// A plant / site under a customer account (crm_sites).
struct CRMSite: Codable {
    let id: String?
    let accountId: String?
    let name: String?
    let code: String?
    let siteType: String?
    let addressLine1: String?
    let addressLine2: String?
    let city: String?
    let district: String?
    let state: String?
    let postalCode: String?
    let country: String?
    let latitude: Double?
    let longitude: Double?
    let phone: String?
    let isActive: Bool?

    enum CodingKeys: String, CodingKey {
        case id, name, code, city, district, state, country, latitude, longitude, phone
        case accountId = "account_id"
        case siteType = "site_type"
        case addressLine1 = "address_line1"
        case addressLine2 = "address_line2"
        case postalCode = "postal_code"
        case isActive = "is_active"
    }

    var displayLocation: String? {
        let parts = [city, state].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// Response of GET /crm/accounts/:id/bundle — what the app pre-fills from when
/// a rep opens an existing company.
struct AccountBundle: Codable {
    let account: CRMAccount?
    let sites: [CRMSite]
    let contacts: [Contact]
    let openDeals: [Deal]

    enum CodingKeys: String, CodingKey {
        case account, sites, contacts
        case openDeals = "open_deals"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        account = try? c.decode(CRMAccount.self, forKey: .account)
        sites = (try? c.decode([CRMSite].self, forKey: .sites)) ?? []
        contacts = (try? c.decode([Contact].self, forKey: .contacts)) ?? []
        openDeals = (try? c.decode([Deal].self, forKey: .openDeals)) ?? []
    }
}

// Visit-intake request pieces (POST /crm/visit-intake). A branch carrying only
// an id reuses an existing record; carrying fields find-or-creates it
// (de-duped server-side).
struct VisitAccountInput: Encodable {
    var id: String? = nil
    var name: String? = nil
    var domain: String? = nil
    var industry: String? = nil
    var phone: String? = nil
    var website: String? = nil
}

struct VisitSiteInput: Encodable {
    var id: String? = nil
    var name: String? = nil
    var code: String? = nil
    var siteType: String? = nil
    var addressLine1: String? = nil
    var addressLine2: String? = nil
    var city: String? = nil
    var district: String? = nil
    var state: String? = nil
    var postalCode: String? = nil
    var country: String? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil

    enum CodingKeys: String, CodingKey {
        case id, name, code, city, district, state, country, latitude, longitude
        case siteType = "site_type"
        case addressLine1 = "address_line1"
        case addressLine2 = "address_line2"
        case postalCode = "postal_code"
    }
}

struct VisitContactInput: Encodable {
    var id: String? = nil
    var firstName: String? = nil
    var lastName: String? = nil
    var email: String? = nil
    var phone: String? = nil
    var mobile: String? = nil
    var title: String? = nil
    var department: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, email, phone, mobile, title, department
        case firstName = "first_name"
        case lastName = "last_name"
    }
}

struct VisitIntakeRequest: Encodable {
    var visitId: String? = nil
    var account: VisitAccountInput
    var site: VisitSiteInput? = nil
    var contacts: [VisitContactInput]? = nil
    var purpose: String? = nil
    var latitude: Double? = nil
    var longitude: Double? = nil
    var checkInGps: String? = nil

    enum CodingKeys: String, CodingKey {
        case account, site, contacts, purpose, latitude, longitude
        case visitId = "visit_id"
        case checkInGps = "check_in_gps"
    }
}

/// Response of POST /crm/visit-intake — the resolved ids to stamp onto each
/// product-form submission for this visit.
struct VisitIntakeResult: Codable {
    let visitId: String?
    let accountId: String?
    let siteId: String?
    let contactIds: [String]

    enum CodingKeys: String, CodingKey {
        case visitId = "visit_id"
        case accountId = "account_id"
        case siteId = "site_id"
        case contactIds = "contact_ids"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        visitId = try c.decodeIfPresent(String.self, forKey: .visitId)
        accountId = try c.decodeIfPresent(String.self, forKey: .accountId)
        siteId = try c.decodeIfPresent(String.self, forKey: .siteId)
        contactIds = (try? c.decode([String].self, forKey: .contactIds)) ?? []
    }
}

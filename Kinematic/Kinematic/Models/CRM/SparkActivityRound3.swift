import Foundation

// Spark & Ray round 3 (activities, addresses, contacts): the pure logic (no UI, no network) behind
//   - the activity "Outcome" and the rule that makes it required once an activity is completed,
//   - the "Company" shown on an activity (and whether it links to an account),
//   - the Activities list's Account / User filters (query parameters),
//   - the account "Addresses" (sites) request bodies,
//   - the contact "Company" wording.
//
// Everything built on this is shown / sent ONLY for the Spark & Ray client (`SparkJourney.isActive`);
// other tenants never see these controls and never send these keys.

// MARK: - Activity outcome

enum SparkActivityOutcome {
    /// Backend cap on an activity's outcome.
    static let maxLength = 500
    static let missingMessage = "Outcome is required once the activity is completed."

    /// Surrounding whitespace removed.
    static func trimmed(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The value as it is sent: trimmed and clamped to the backend's 500 characters.
    static func clamped(_ raw: String) -> String {
        String(trimmed(raw).prefix(maxLength))
    }

    /// Whether the outcome must be filled in before saving.
    ///  - logging / creating: when the new activity will be COMPLETED, i.e. it is not a scheduled reminder and
    ///    not a task (a logged task only gets its due date, so it stays open);
    ///  - editing: when the activity being edited is already completed.
    static func isRequired(creating: Bool, scheduled: Bool, type: String, existingCompleted: Bool) -> Bool {
        if creating { return !scheduled && type != "task" }
        return existingCompleted
    }

    /// The inline error for a missing outcome (nil when it is not required, or filled in).
    static func validationError(_ raw: String, required: Bool) -> String? {
        required && trimmed(raw).isEmpty ? missingMessage : nil
    }

    /// Whether "Mark complete" on a card must ask for the outcome first: Spark only, completing (not
    /// reopening) an activity that has none yet.
    static func needsPromptOnComplete(spark: Bool, action: ActivityCompletion.Action, existingOutcome: String?) -> Bool {
        spark && action == .markComplete && trimmed(existingOutcome ?? "").isEmpty
    }

    /// PATCH body that saves just the outcome (before a "Mark complete" goes out).
    static func saveBody(_ raw: String) -> [String: Any] {
        ["outcome": clamped(raw)]
    }

    /// Whether the activity is completed (status completed / done, or stamped with a completion time).
    static func isCompleted(_ activity: Activity) -> Bool {
        ActivityCompletion.action(for: activity) == .reopen
    }
}

// MARK: - Activity company

/// What the "Company: ..." line of an activity row shows.
enum ActivityCompany {
    enum Display: Equatable {
        /// The activity's account: shown as a link to that account's detail.
        case link(id: String, name: String)
        /// Only a name (the lead's company text, no account): plain text.
        case text(String)
        case hidden
    }

    /// The company line for `activity`: nothing unless `spark`. `company_id` present means a link; only a name
    /// means plain text; neither means no line.
    static func display(for activity: Activity, spark: Bool) -> Display {
        guard spark else { return .hidden }
        let name = (activity.companyName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let id = (activity.companyId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !id.isEmpty { return .link(id: id, name: name.isEmpty ? "Company" : name) }
        if !name.isEmpty { return .text(name) }
        return .hidden
    }
}

extension Activity {
    /// This row (typically a PATCH response, which is not enriched with the company) with the Company of
    /// `previous` carried over when it has none of its own, so an edit never drops the "Company" line.
    func keepingCompany(of previous: Activity?) -> Activity {
        guard let previous, (companyId ?? "").isEmpty, (companyName ?? "").isEmpty else { return self }
        var copy = self
        copy.companyId = previous.companyId
        copy.companyName = previous.companyName
        return copy
    }
}

// MARK: - Activities list query

/// The query-string parameters of `GET /crm/activities` (also `/summary` and `/export` on the web). Blank
/// values are left out.
enum ActivityQuery {
    static func params(
        dealId: String? = nil,
        leadId: String? = nil,
        ownerId: String? = nil,
        accountId: String? = nil,
        city: String? = nil,
        state: String? = nil,
        from: String? = nil,
        to: String? = nil
    ) -> [String: String] {
        var q: [String: String] = [:]
        func put(_ key: String, _ value: String?) {
            if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { q[key] = value }
        }
        put("deal_id", dealId)
        put("lead_id", leadId)
        // owner OR assignee OR co-assignee (server side).
        put("owner_id", ownerId)
        // activities on that account or on any of its leads (server side).
        put("account_id", accountId)
        put("city", city)
        put("state", state)
        put("from", from)
        put("to", to)
        return q
    }

    /// The owner filter value the view model holds ("all" = no filter) as the parameter to send.
    static func ownerParam(_ filter: String) -> String? {
        let t = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty || t == "all" ? nil : t
    }
}

// MARK: - Account addresses (sites)

/// A site / address of an account (`crm_sites`): `GET /crm/accounts/:id/sites`.
struct AccountSite: Codable, Identifiable, Hashable {
    let id: String
    let accountId: String?
    let name: String?
    let siteType: String?
    let addressLine1: String?
    let addressLine2: String?
    let city: String?
    let state: String?
    let postalCode: String?
    let country: String?
    let latitude: Double?
    let longitude: Double?
    let phone: String?
    let notes: String?

    enum CodingKeys: String, CodingKey {
        case id, name, city, state, country, latitude, longitude, phone, notes
        case accountId = "account_id"
        case siteType = "site_type"
        case addressLine1 = "address_line1"
        case addressLine2 = "address_line2"
        case postalCode = "postal_code"
    }

    /// The row's title: its label ("Head office"), else "Address".
    var title: String {
        let t = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "Address" : t
    }

    /// "line 1, line 2" (street part only).
    var streetLine: String {
        [addressLine1, addressLine2]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// "City, State PIN".
    var localityLine: String {
        let cityState = [city, state]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        let pin = (postalCode ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return [cityState, pin].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Whether the map pin shows (real coordinates, not the (0, 0) placeholder).
    var hasCoordinates: Bool {
        LeadAddressCoordinates.isUsable(latitude: latitude, longitude: longitude)
    }
}

/// What the "Add address" / edit form holds.
struct AccountAddressDraft: Equatable {
    var label = ""
    var addressLine1 = ""
    var addressLine2 = ""
    var city = ""
    var state = ""
    var postalCode = ""
    var country = "India"
    var latitude: Double? = nil
    var longitude: Double? = nil
    var phone = ""
    var notes = ""

    static let missingLabelMessage = "Enter a label for the address (for example Head office)."

    init() {}

    /// Seed the form from an existing site (edit).
    init(site: AccountSite) {
        label = site.name ?? ""
        addressLine1 = site.addressLine1 ?? ""
        addressLine2 = site.addressLine2 ?? ""
        city = site.city ?? ""
        state = site.state ?? ""
        postalCode = site.postalCode ?? ""
        country = (site.country ?? "").isEmpty ? "India" : (site.country ?? "")
        latitude = site.latitude
        longitude = site.longitude
        phone = site.phone ?? ""
        notes = site.notes ?? ""
    }

    /// Fill the address fields (and the pin) from a picked Google place; text fields the place does not carry keep
    /// what the rep typed.
    mutating func apply(place: CRMPlaceDetail) {
        if let a = place.addressLine1, !a.isEmpty { addressLine1 = a }
        if let c = place.city, !c.isEmpty { city = c }
        if let s = place.state, !s.isEmpty { state = s }
        if let p = place.postalCode, !p.isEmpty { postalCode = p }
        // The pin follows the picked address: a place without usable coordinates drops the old pin rather than
        // leaving one that belongs to a different address.
        let pin = LeadAddressCoordinates.coordinate(from: place)
        latitude = pin?.latitude
        longitude = pin?.longitude
    }

    /// The inline error that blocks Save (the backend requires the label), nil when it can be saved.
    var validationError: String? {
        label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Self.missingLabelMessage : nil
    }

    private static func clean(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `POST /crm/sites` body: the account, the label and every filled field. Blank fields are left out;
    /// the pin only when the coordinates are real.
    func createBody(accountId: String) -> [String: Any] {
        var body: [String: Any] = ["account_id": accountId, "name": Self.clean(label)]
        let fields: [(String, String)] = [
            ("address_line1", addressLine1), ("address_line2", addressLine2), ("city", city),
            ("state", state), ("postal_code", postalCode), ("country", country),
            ("phone", phone), ("notes", notes),
        ]
        for (key, value) in fields {
            let v = Self.clean(value)
            if !v.isEmpty { body[key] = v }
        }
        if LeadAddressCoordinates.isUsable(latitude: latitude, longitude: longitude),
           let lat = latitude, let lng = longitude {
            body["latitude"] = lat
            body["longitude"] = lng
        }
        return body
    }

    /// `PATCH /crm/sites/:id` body: the label and every field, a cleared one sent as null so it really clears.
    func patchBody() -> [String: Any] {
        var body: [String: Any] = ["name": Self.clean(label)]
        let fields: [(String, String)] = [
            ("address_line1", addressLine1), ("address_line2", addressLine2), ("city", city),
            ("state", state), ("postal_code", postalCode), ("country", country),
            ("phone", phone), ("notes", notes),
        ]
        for (key, value) in fields {
            let v = Self.clean(value)
            body[key] = v.isEmpty ? NSNull() : v
        }
        if LeadAddressCoordinates.isUsable(latitude: latitude, longitude: longitude),
           let lat = latitude, let lng = longitude {
            body["latitude"] = lat
            body["longitude"] = lng
        } else {
            body["latitude"] = NSNull()
            body["longitude"] = NSNull()
        }
        return body
    }
}

// MARK: - Contact company wording

enum SparkContactCompany {
    /// The label of the account link on the contact forms / detail / list for Spark ("Account" elsewhere).
    static func label(spark: Bool, fallback: String = "Account") -> String {
        spark ? "Company" : fallback
    }

    /// The contact row's company line: the account name when the contact is linked to one. Nothing unless
    /// `spark`.
    static func line(for contact: Contact, spark: Bool) -> (id: String, name: String)? {
        guard spark else { return nil }
        let id = (contact.accountId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return nil }
        let name = (contact.accountName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return (id, name.isEmpty ? "Company" : name)
    }

    /// PATCH body for the contact edit's company picker: the account id, or null to clear it.
    static func accountPatch(selectedId: String?) -> [String: Any] {
        let id = (selectedId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return ["account_id": id.isEmpty ? NSNull() : id]
    }
}

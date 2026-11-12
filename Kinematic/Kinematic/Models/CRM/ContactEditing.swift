import Foundation

// Pure logic (no UI, no network) behind the contact screens: the edit request body, the delete confirmation
// wording, the company line on a contact row and the account detail's contacts header. Unit-tested — see
// KinematicTests/ContactEditingTests.

// MARK: - Edit body

/// What the contact edit form holds, as plain strings / flags (the same values the form's `@State` holds).
struct ContactEditDraft: Equatable {
    var firstName = ""
    var lastName = ""
    var email = ""
    var phone = ""
    var mobile = ""
    var isB2C = false
    // Business (B2B) only.
    var title = ""
    var department = ""
    // Consumer (B2C) only.
    var dateOfBirth = ""
    var gender = ""
    var addressLine1 = ""
    var city = ""
    var state = ""
    var postalCode = ""
    var country = ""
    var preferredContactMethod = ""
    var loyaltyTier = ""
    var referralSource = ""
    var marketingConsent = false
    var whatsappConsent = false
}

enum ContactEditBody {
    /// The consumer-only keys. A business contact never sends any of them.
    static let consumerOnlyKeys: [String] = [
        "date_of_birth", "gender", "address_line1", "address_line2", "city", "state", "postal_code", "country",
        "preferred_contact_method", "loyalty_tier", "referral_source", "marketing_consent", "whatsapp_consent",
    ]

    /// PATCH body for `PATCH /crm/contacts/:id`.
    ///
    /// - Business contact (`isB2C == false`): only `first_name`, `last_name`, `email`, `phone`, `mobile`,
    ///   `is_b2c`, `title` and `department`.
    /// - Consumer contact: the common keys plus the consumer-only ones.
    /// - A blank value clears the field (explicit null) EXCEPT `city`, which is simply left out when blank:
    ///   the server rejects `city: null` ("city: Expected string, received null").
    /// - `account_id` rides along ONLY when the Company was changed (`companyEditable` and the selected id
    ///   differs from the original); an empty selection unlinks (null).
    static func patch(
        _ d: ContactEditDraft,
        companyEditable: Bool,
        selectedCompanyId: String,
        originalCompanyId: String?
    ) -> [String: Any] {
        func value(_ s: String) -> Any {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? NSNull() : t
        }
        var body: [String: Any] = [
            "first_name": value(d.firstName),
            "last_name": value(d.lastName),
            "email": value(d.email),
            "phone": value(d.phone),
            "mobile": value(d.mobile),
            "is_b2c": d.isB2C,
        ]
        if !d.isB2C {
            body["title"] = value(d.title)
            body["department"] = value(d.department)
        } else {
            body["date_of_birth"] = value(d.dateOfBirth)
            body["gender"] = value(d.gender)
            body["address_line1"] = value(d.addressLine1)
            let city = d.city.trimmingCharacters(in: .whitespacesAndNewlines)
            if !city.isEmpty { body["city"] = city }
            body["state"] = value(d.state)
            body["postal_code"] = value(d.postalCode)
            body["country"] = value(d.country)
            body["preferred_contact_method"] = value(d.preferredContactMethod)
            body["loyalty_tier"] = value(d.loyaltyTier)
            body["referral_source"] = value(d.referralSource)
            body["marketing_consent"] = d.marketingConsent
            body["whatsapp_consent"] = d.whatsappConsent
        }
        if companyEditable, companyChanged(selected: selectedCompanyId, original: originalCompanyId) {
            for (key, v) in SparkContactCompany.accountPatch(selectedId: selectedCompanyId) { body[key] = v }
        }
        return body
    }

    /// Whether the picked Company differs from the one the contact had (blank and nil are the same: none).
    static func companyChanged(selected: String, original: String?) -> Bool {
        let a = selected.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = (original ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return a != b
    }
}

// MARK: - Delete

extension Notification.Name {
    /// Posted (object = the contact id, a String) after a contact is deleted from its detail screen, so the
    /// contacts list drops the row and refreshes.
    static let crmContactDeleted = Notification.Name("crm.contact.deleted")
}

enum ContactDeletion {
    /// "Delete <name>? It is removed from lists and can be recovered by support."
    static func confirmationMessage(name: String) -> String {
        "Delete \(displayName(name))? It is removed from lists and can be recovered by support."
    }

    /// The dialog title ("Delete <name>?").
    static func confirmationTitle(name: String) -> String {
        "Delete \(displayName(name))?"
    }

    private static func displayName(_ name: String) -> String {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "this contact" : t
    }

    /// `list` without the contact `id` (order kept); unchanged when it is not in the list.
    static func removing(id: String, from list: [Contact]) -> [Contact] {
        list.filter { $0.id != id }
    }
}

// MARK: - Contact row company

/// The Company / Account line under a contact in a list.
struct ContactCompanyLine: Equatable {
    /// The account's id when known (the line then links to the account); nil means plain text.
    let id: String?
    let name: String
    /// "Company" for Spark & Ray, "Account" for everyone else.
    let label: String

    /// "Company: Acme Forge".
    var text: String { "\(label): \(name)" }
}

enum ContactCompanyDisplay {
    /// The line for a contact row, or nil when there is nothing to show. The backend now returns
    /// `account_name` on every contact.
    ///  - Spark & Ray (existing behaviour): any linked contact shows a line ("Company" when the name is
    ///    missing), linking to the account.
    ///  - Everyone else: only when the contact carries an account name; it links when the id is known.
    static func line(for contact: Contact, spark: Bool) -> ContactCompanyLine? {
        let label = SparkContactCompany.label(spark: spark)
        if spark {
            guard let l = SparkContactCompany.line(for: contact, spark: true) else { return nil }
            return ContactCompanyLine(id: l.id, name: l.name, label: label)
        }
        let name = (contact.accountName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let id = (contact.accountId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return ContactCompanyLine(id: id.isEmpty ? nil : id, name: name, label: label)
    }
}

// MARK: - Account detail contacts section

enum AccountContactsDisplay {
    static let emptyText = "No contacts yet."

    /// "Contacts (3)" — the count is always shown, including "Contacts (0)".
    static func header(count: Int) -> String {
        "Contacts (\(max(0, count)))"
    }
}

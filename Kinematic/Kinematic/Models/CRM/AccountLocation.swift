import Foundation

/// The account's structured location (`crm_accounts.address_line1`, `address_line2`, `state`,
/// `postal_code`, `country`; accounts have no City) as the create / edit forms hold it, plus the payload and display rules.
///
/// Pure logic, no UI: the forms bind to its fields and the tests drive the builders directly.
///
/// Field-override contract: every key here is a built-in account field. A key the admin hides is never rendered,
/// never sent (hiding a field must not wipe the data already saved in it), and never shown on the detail;
/// the callers pass the hidden keys in as `hidden`.
struct AccountLocationDraft: Equatable {
    var addressLine1 = ""
    var addressLine2 = ""
    var state = ""
    var postalCode = ""
    var country = "India"

    /// Field-override keys (`account.<key>`) of the location block, in form order.
    static let keys = ["address_line1", "address_line2", "state", "postal_code", "country"]

    /// New account: everything blank except the Country, which defaults to India.
    init() {}

    /// Edit: exactly what is saved. A blank stays blank (the India default is for new accounts only), so
    /// opening and saving an old account does not silently stamp a country onto it.
    init(account: CRMAccount) {
        addressLine1 = account.addressLine1 ?? ""
        addressLine2 = account.addressLine2 ?? ""
        state = account.state ?? ""
        postalCode = account.postalCode ?? ""
        country = account.country ?? ""
    }

    private static func clean(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Key / trimmed value pairs of the visible fields, in form order.
    private func pairs(hidden: Set<String>) -> [(String, String)] {
        let all: [(String, String)] = [
            ("address_line1", addressLine1), ("address_line2", addressLine2), ("state", state),
            ("postal_code", postalCode), ("country", country),
        ]
        return all.filter { !hidden.contains($0.0) }.map { ($0.0, Self.clean($0.1)) }
    }

    /// `POST /crm/accounts` fields: every visible, filled-in field. Blank ones are left out.
    func createFields(hidden: Set<String> = []) -> [String: Any] {
        var out: [String: Any] = [:]
        for (key, value) in pairs(hidden: hidden) where !value.isEmpty { out[key] = value }
        return out
    }

    /// `PATCH /crm/accounts/:id` fields: every visible field, a cleared one sent as an explicit null so it
    /// really clears on the server. Never carries `city`, so a city already stored on the account is untouched.
    func patchFields(hidden: Set<String> = []) -> [String: Any] {
        var out: [String: Any] = [:]
        for (key, value) in pairs(hidden: hidden) { out[key] = value.isEmpty ? NSNull() : value }
        return out
    }

    /// Visible fields the admin marked required that are still blank, in form order. Save stays off while
    /// this is not empty.
    func missingRequired(hidden: Set<String>, required: Set<String>) -> [String] {
        pairs(hidden: hidden).filter { required.contains($0.0) && $0.1.isEmpty }.map { $0.0 }
    }

    /// The detail screen's address block: street lines, then "State PIN", then the country. Hidden
    /// parts and blank parts are dropped; empty when nothing is left (the row is then not shown at all).
    func displayLines(hidden: Set<String> = []) -> [String] {
        func value(_ key: String, _ raw: String) -> String { hidden.contains(key) ? "" : Self.clean(raw) }
        let locality = [value("state", state), value("postal_code", postalCode)]
            .filter { !$0.isEmpty }.joined(separator: " ")
        return [value("address_line1", addressLine1), value("address_line2", addressLine2),
                locality, value("country", country)].filter { !$0.isEmpty }
    }
}

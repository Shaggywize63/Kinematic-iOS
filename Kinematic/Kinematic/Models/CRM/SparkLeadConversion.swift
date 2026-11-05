import Foundation

/// Spark & Ray: converting a lead now goes through the normal deal form (Quotation / Pricing /
/// Product trial / people sections) instead of the old single-product Convert sheet. The backend
/// accepts `convert_lead: true` with `lead_id` on `POST /crm/deals`: it converts the lead (creates or
/// reuses the account + contact, no old-style deal), attaches the deal to it and sets the lead's
/// `converted_deal_id`.
///
/// Pure (no UI, no network) so it is unit-tested — see KinematicTests/SparkLeadConversionTests.
enum SparkLeadConversion {
    /// The request key the backend reads.
    static let bodyKey = "convert_lead"

    /// Separator between the company and the contact in the prefilled deal name.
    static let nameSeparator = " \u{2014} "

    private static func clean(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Convert only when the caller asked for it AND the lead is not already converted (an already
    /// converted lead just gets a normal deal attached; converting twice is never requested).
    static func shouldConvert(requested: Bool, leadAlreadyConverted: Bool) -> Bool {
        requested && !leadAlreadyConverted
    }

    /// "First Last" from the lead's name parts; nil when both are blank.
    static func contactName(firstName: String?, lastName: String?) -> String? {
        let full = "\(clean(firstName)) \(clean(lastName))".trimmingCharacters(in: .whitespaces)
        return full.isEmpty ? nil : full
    }

    /// Prefilled deal name: "Company — Contact name". Either part alone when the other is blank (or when
    /// both are the same text), and `fallback` when both are blank. The rep can edit it.
    static func defaultDealName(company: String?, contactName: String?, fallback: String = "") -> String {
        let co = clean(company)
        let person = clean(contactName)
        if !co.isEmpty && !person.isEmpty {
            if co.caseInsensitiveCompare(person) == .orderedSame { return co }
            return co + nameSeparator + person
        }
        if !co.isEmpty { return co }
        if !person.isEmpty { return person }
        return clean(fallback)
    }

    /// `defaultDealName` for a lead (its company and its own name).
    static func defaultDealName(for lead: Lead) -> String {
        defaultDealName(
            company: lead.company,
            contactName: contactName(firstName: lead.firstName, lastName: lead.lastName),
            fallback: lead.displayName
        )
    }

    /// Merge the conversion flag into a deal-create body: `convert_lead: true` only when converting AND a
    /// lead id is present (the backend needs `lead_id` to know which lead). Otherwise the body is untouched,
    /// so a plain "New deal" never carries the flag.
    static func applyConversion(to body: inout [String: Any], convert: Bool, leadId: String?) {
        guard convert, !clean(leadId).isEmpty else { return }
        body[bodyKey] = true
    }

    /// The note shown on the form while converting.
    static func note(leadName: String?) -> String {
        let name = clean(leadName)
        let who = name.isEmpty ? "this lead" : name
        return "Converting \(who) \u{2014} this creates or links the customer account."
    }

    /// The form's title: "Convert to Deal" while converting, else "New Deal".
    static func formTitle(converting: Bool) -> String {
        converting ? "Convert to Deal" : "New Deal"
    }
}

import Foundation

// Sample invoices on a lead — Spark & Ray only.
//
// A lead can hold a plain list of sample-invoice NUMBERS. There is NO invoice
// generation here: just a number to add, the list of added numbers, and a remove
// on each. No delivery details, no airway bill, no product / quantity.
//
// Storage — NO migration. The numbers live in the lead's `custom_fields` jsonb
// under the key `sample_invoices` (an array of strings). Add / remove reads the
// lead's current list, changes the array, and PATCHes the lead's `custom_fields`
// via the normal lead-update service. The whole existing blob is re-sent (with
// our key set) so no other `custom_fields` key is lost — safe whether the backend
// merges or replaces the jsonb.
//
// This is `custom_fields` jsonb, NOT a built-in lead column, so the built-in
// field-override contract does NOT apply (no `isHidden` gate). The feature is
// gated once, at the render site, on `SparkJourney.isActive`.
//
// Everything here is pure (no UI, no network) so it is unit-tested; the card and
// the view model just call in.

enum SampleInvoices {
    /// The `custom_fields` key the numbers live under.
    static let fieldKey = "sample_invoices"

    // MARK: Normalisation

    /// Clean a list of invoice numbers: trim each, drop blanks, and drop duplicates
    /// (matched case-insensitively) keeping the first occurrence's text, in order.
    static func normalize(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for item in raw {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            out.append(trimmed)
        }
        return out
    }

    // MARK: Reading

    /// The saved numbers read out of a plain `custom_fields` graph. Accepts an array
    /// under `sample_invoices` whose entries are strings (or numbers, coerced to a
    /// string); anything else reads as an empty list. The result is normalised so a
    /// card never shows a blank or duplicate row.
    static func read(customFields: [String: Any]?) -> [String] {
        guard let raw = customFields?[fieldKey] as? [Any] else { return [] }
        return normalize(raw.compactMap { stringValue($0) })
    }

    /// The saved numbers on a lead (reads the rich `custom_fields` graph).
    static func read(from lead: Lead) -> [String] {
        read(customFields: plainCustomFields(from: lead))
    }

    // MARK: Add / remove

    /// `existing` with `number` added (normalised). A blank or duplicate number is a
    /// no-op (the returned list equals `existing` normalised).
    static func adding(_ number: String, to existing: [String]) -> [String] {
        normalize(existing + [number])
    }

    /// `existing` without `number` (matched case-insensitively after trimming),
    /// normalised.
    static func removing(_ number: String, from existing: [String]) -> [String] {
        let target = number.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !target.isEmpty else { return normalize(existing) }
        return normalize(existing).filter { $0.lowercased() != target }
    }

    // MARK: Request body

    /// The PATCH body's `custom_fields` value: every existing key preserved, with
    /// `sample_invoices` set to the normalised list (an empty list clears it to `[]`).
    /// Re-sent whole so no other `custom_fields` key is lost whether the backend
    /// merges or replaces the blob.
    static func patch(customFields existing: [String: Any]?, invoices: [String]) -> [String: Any] {
        var merged = existing ?? [:]
        merged[fieldKey] = normalize(invoices)
        return merged
    }

    /// The full `["custom_fields": …]` lead-update body for `lead` after setting its
    /// sample invoices to `invoices`. Hand this straight to `updateLead(id:body:)`.
    static func updateBody(for lead: Lead, invoices: [String]) -> [String: Any] {
        ["custom_fields": patch(customFields: plainCustomFields(from: lead), invoices: invoices)]
    }

    // MARK: Helpers

    /// The lead's `custom_fields` as a plain `Any` graph (the same rich read the
    /// products card uses — the string-only fallback would drop arrays).
    static func plainCustomFields(from lead: Lead) -> [String: Any] {
        (lead.customFields ?? [:]).compactMapValues { $0.raw?.any }
    }

    /// Coerce one `custom_fields` array element to an invoice-number string: a string
    /// is trimmed (blank -> nil); an int / whole double is rendered without a decimal;
    /// anything else is ignored.
    private static func stringValue(_ any: Any) -> String? {
        if let s = any as? String {
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let i = any as? Int { return String(i) }
        if let d = any as? Double {
            if d == d.rounded(), abs(d) < 1e15 { return String(Int(d)) }
            return String(d)
        }
        return nil
    }
}

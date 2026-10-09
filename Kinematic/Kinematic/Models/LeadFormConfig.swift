// LeadFormConfig — per-client lead-form presentation (`crm_settings.config.lead_form`) and the
// custom-field option tokens that go with it. Mirrors the web's `lib/crmLeadForm.ts` +
// `lib/customFieldOptions.ts` and the Android `LeadFormConfig.kt` — keep the three in step.
//
//   lead_form: {
//     segment_labels: { b2b?: String, b2c?: String },   // "Dealer" / "Farmers"
//     address_on_b2b: Bool,                              // address block on B2B too
//     schedule_visit: { segments: ["b2b"] },             // who gets "Schedule visit"
//   }
//
// Contract: a client WITHOUT this config behaves exactly as before. Every default here is the legacy
// behaviour (B2B / B2C wording, address on B2C only, no schedule-visit control). Per-field label /
// hidden / required stays in `LeadFieldOverridesModel`.
//
// Pure Foundation (no SwiftUI) so it is unit-tested — see KinematicTests/LeadFormConfigTests.

import Foundation

struct LeadFormConfig: Equatable {
    /// Admin-chosen names for the two lead types, keyed "b2b" / "b2c".
    var segmentLabels: [String: String] = [:]
    /// Show the address block (search + GPS pin) on B2B leads, not only B2C.
    var addressOnB2b: Bool = false
    /// Lead types ("b2b" / "b2c") whose create form offers "Schedule visit".
    var scheduleVisitSegments: Set<String> = []

    private func key(_ isB2C: Bool) -> String { isB2C ? "b2c" : "b2b" }

    /// Short name of a lead type: the admin's label, else "B2B" / "B2C".
    func segmentName(isB2C: Bool) -> String { segmentLabels[key(isB2C)] ?? (isB2C ? "B2C" : "B2B") }

    /// Picker caption: the admin's label alone, else the legacy "B2B (Business)".
    func segmentPickerLabel(isB2C: Bool) -> String {
        segmentLabels[key(isB2C)] ?? (isB2C ? "B2C (Consumer)" : "B2B (Business)")
    }

    /// True when the client renamed this lead type.
    func hasCustomName(isB2C: Bool) -> Bool { segmentLabels[key(isB2C)] != nil }

    /// Does the address block show for this lead type? B2C always did; B2B only when enabled.
    func showsAddress(isB2C: Bool) -> Bool { isB2C || addressOnB2b }

    /// Does the create form offer "Schedule visit" for this lead type?
    func offersScheduleVisit(isB2C: Bool) -> Bool { scheduleVisitSegments.contains(key(isB2C)) }

    /// Naive plural of a lead-type name for the dashboard split: add "s" unless it already ends in one
    /// ("Dealer" → "Dealers", "Farmers" → "Farmers").
    static func plural(_ name: String) -> String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if n.isEmpty || n.lowercased().hasSuffix("s") { return n }
        return n + "s"
    }

    /// The dashboard's "Total leads" split — "Dealers 12 · Farmers 30" — or nil when this client never named
    /// its lead types (then the dashboard shows nothing new). Names come from `segmentName`; B2B first.
    func leadsSplitText(b2b: Int, b2c: Int) -> String? {
        guard hasCustomName(isB2C: false) || hasCustomName(isB2C: true) else { return nil }
        return "\(Self.plural(segmentName(isB2C: false))) \(b2b) · \(Self.plural(segmentName(isB2C: true))) \(b2c)"
    }

    /// Pure parser for `config.lead_form`. Anything missing or mis-typed falls back to the legacy defaults.
    static func parse(_ config: [String: AnyJSON]?) -> LeadFormConfig {
        guard case let .object(raw)? = config?["lead_form"] else { return LeadFormConfig() }
        var labels: [String: String] = [:]
        if case let .object(m)? = raw["segment_labels"] {
            for k in ["b2b", "b2c"] {
                if case let .string(s)? = m[k] {
                    let t = String(s.trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
                    if !t.isEmpty { labels[k] = t }
                }
            }
        }
        var segments = Set<String>()
        if case let .object(sv)? = raw["schedule_visit"], case let .array(arr)? = sv["segments"] {
            for item in arr {
                if case let .string(s) = item {
                    let l = s.lowercased()
                    if l == "b2b" || l == "b2c" { segments.insert(l) }
                }
            }
        }
        var onB2b = false
        if case let .bool(b)? = raw["address_on_b2b"] { onB2b = b }
        return LeadFormConfig(segmentLabels: labels, addressOnB2b: onB2b, scheduleVisitSegments: segments)
    }
}

// MARK: - Custom-field option tokens

/// Reserved tokens an admin can store in a select field's `options` list. The custom-field definition has
/// no column for "how should this dropdown behave", so — like the image field's `camera_only` / `front` —
/// the behaviour rides in the existing array. Old clients would show a token as an option, which is why
/// every renderer strips them with `visible(_:)`.
///
///   __searchable__        type-ahead list instead of a plain dropdown (crops)
///   __source:products__   the options are the product names from the Products section (name only,
///                         never price); implies searchable
enum CustomFieldOptions {
    static let searchable = "__searchable__"
    static let sourceProducts = "__source:products__"

    /// Any `__token__` — never a value the user should see or pick.
    static func isReserved(_ option: String) -> Bool { option.count >= 5 && option.hasPrefix("__") && option.hasSuffix("__") }

    /// The options a user can actually pick (reserved tokens removed).
    static func visible(_ options: [String]?) -> [String] { (options ?? []).filter { !isReserved($0) } }

    static func isProductSource(_ options: [String]?) -> Bool { (options ?? []).contains(sourceProducts) }

    static func isSearchable(_ options: [String]?) -> Bool {
        let all = options ?? []
        return all.contains(searchable) || all.contains(sourceProducts)
    }

    /// Distinct, sorted names of the active products — what a "from Products" dropdown offers.
    static func productNames(_ products: [(name: String, isActive: Bool)]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for p in products where p.isActive {
            let n = p.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if !n.isEmpty && seen.insert(n).inserted { out.append(n) }
        }
        return out.sorted()
    }
}

// MARK: - Schedule visit

/// Schedule visit on lead create: the rep picks a date and time; the server adds a planned meeting for the
/// lead's owner and the activity-reminder job notifies about 30 minutes before. Create-only.
enum ScheduleVisitRules {
    /// A moment in time as the ISO-8601 UTC string the API takes ("2026-10-12T05:00:00Z").
    static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = TimeZone(identifier: "UTC") ?? .current
        return f.string(from: date)
    }

    /// A reminder for a time that has already gone would never fire, so a visit has to be in the future.
    /// A minute of grace covers a time picked "now" and submitted a moment later.
    static func isUsable(_ date: Date, now: Date, grace: TimeInterval = 60) -> Bool {
        date >= now.addingTimeInterval(-grace)
    }

    /// "Dealer Visit — Sharma Agro"; nil when there is no description (the server then names it itself).
    static func subject(description: String?, who: String?) -> String? {
        let d = (description ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if d.isEmpty { return nil }
        let w = (who ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return w.isEmpty ? d : "\(d) — \(w)"
    }
}

// MARK: - What blocks "Create lead"

/// What blocks "Create lead" on the iOS form, as one pure function so it is tested without SwiftUI.
/// Returns the message to show, or nil when the form can be submitted.
///
/// Required-ness here is the admin's EXPLICIT choice (`explicitlyRequired`) so a client that never
/// configured it keeps the behaviour it had; the two exceptions are the ones the form always policed:
/// a visible, required Last name, and a 10-digit mobile.
@MainActor
enum LeadCreateRules {
    static func firstProblem(
        overrides o: LeadFieldOverridesModel,
        isB2C: Bool,
        firstName: String,
        lastName: String,
        phone: String,
        company: String,
        addressLine1: String,
        visitAt: Date?,
        now: Date
    ) -> String? {
        func blank(_ s: String) -> Bool { s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let form = o.leadForm
        if !o.isHidden("first_name", isB2C: isB2C), o.explicitlyRequired("first_name", isB2C: isB2C), blank(firstName) {
            return "\(o.labelFor("first_name", defaultLabel: "First name", isB2C: isB2C)) is required."
        }
        // A hidden Last name never blocks (it used to: the button stayed disabled with no field to fill).
        if !o.isHidden("last_name", isB2C: isB2C), o.requiredFor("last_name", defaultRequired: true, isB2C: isB2C), blank(lastName) {
            return "\(o.labelFor("last_name", defaultLabel: "Last name", isB2C: isB2C)) is required."
        }
        if !o.isHidden("phone", isB2C: isB2C) {
            let label = o.labelFor("phone", defaultLabel: "Primary mobile", isB2C: isB2C)
            if o.explicitlyRequired("phone", isB2C: isB2C), blank(phone) { return "\(label) is required." }
            if !blank(phone), phone.filter({ $0.isNumber }).count != 10 { return "\(label) must be a 10-digit number." }
        }
        if !isB2C, !o.isHidden("company", isB2C: isB2C), o.explicitlyRequired("company", isB2C: isB2C), blank(company) {
            return "\(o.labelFor("company", defaultLabel: "Company", isB2C: isB2C)) is required for \(form.segmentName(isB2C: false)) leads."
        }
        if form.showsAddress(isB2C: isB2C), !o.isHidden("address_line1", isB2C: isB2C),
           o.explicitlyRequired("address_line1", isB2C: isB2C), blank(addressLine1) {
            return "\(o.labelFor("address_line1", defaultLabel: "Address", isB2C: isB2C)) is required — search for it or type it in."
        }
        if let v = visitAt, form.offersScheduleVisit(isB2C: isB2C), !ScheduleVisitRules.isUsable(v, now: now) {
            return "Pick a visit time in the future — or clear it to save the lead without a visit."
        }
        return nil
    }
}

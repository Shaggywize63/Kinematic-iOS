// LeadFormConfig — per-client lead-form presentation (`crm_settings.config.lead_form`) and the
// custom-field option tokens that go with it. Mirrors the web's `lib/crmLeadForm.ts` +
// `lib/customFieldOptions.ts` and the Android `LeadFormConfig.kt` — keep the three in step.
//
//   lead_form: {
//     segment_labels: { b2b?: String, b2c?: String },   // "Dealer" / "Farmers"
//     address_on_b2b: Bool,                              // address block on B2B too
//     schedule_visit: { segments: ["b2b"] },             // who gets "Schedule visit"
//     owner_assignment: "admin_only",                    // only an admin chooses / changes a lead's owner
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
    /// `owner_assignment == "admin_only"`: only an admin may choose or change a lead's owner (a non-admin's new lead
    /// is owned by themselves). Absent = anyone who could before still can. Who counts as an admin: `LeadOwnerRules`.
    var ownerAdminOnly: Bool = false

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
        // Only the exact value "admin_only" restricts anything; any other value (or a non-string) leaves it as before.
        var adminOnly = false
        if case let .string(s)? = raw["owner_assignment"] {
            adminOnly = s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "admin_only"
        }
        return LeadFormConfig(segmentLabels: labels, addressOnB2b: onB2b, scheduleVisitSegments: segments, ownerAdminOnly: adminOnly)
    }
}

// MARK: - Who may choose a lead's owner

/// `lead_form.owner_assignment == "admin_only"`: a non-admin sees no control that chooses or changes a lead's
/// owner (create, edit, the detail screen's Assign) and never sends one. The server enforces the same rule
/// (403 OWNER_ASSIGN_FORBIDDEN "Only an admin can assign leads"), so this only removes controls that would fail.
/// The current owner is still shown as plain text. Without the flag nothing here changes any behaviour.
///
/// Pure (no session, no SwiftUI) so it is unit-tested — see KinematicTests/LeadOwnerRulesTests.
enum LeadOwnerRules {
    /// System roles the backend treats as admin for owner assignment.
    static let adminRoles: Set<String> = ["admin", "super_admin", "main_admin", "org_admin", "sub_admin", "client"]

    /// An admin role whose org role does not limit them to their own records (data scope "own" is never an admin
    /// here, whatever the system role says). A missing role is not an admin.
    static func isAdmin(role: String?, dataScope: String?) -> Bool {
        let r = (role ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard adminRoles.contains(r) else { return false }
        return (dataScope ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "own"
    }

    /// The client reserves owner assignment for admins AND this user is not one: no owner control, no owner sent.
    static func isLocked(ownerAdminOnly: Bool, role: String?, dataScope: String?) -> Bool {
        ownerAdminOnly && !isAdmin(role: role, dataScope: dataScope)
    }

    /// May this user be offered the owner controls (on top of the gates each screen already has)? An admin always;
    /// anyone else only once the settings have loaded and the client has not locked it — before that the flag is
    /// unknown, so a non-admin's picker must not flash up and vanish.
    static func mayChooseOwner(ownerAdminOnly: Bool, didLoad: Bool, role: String?, dataScope: String?) -> Bool {
        if isAdmin(role: role, dataScope: dataScope) { return true }
        return didLoad && !ownerAdminOnly
    }

    /// Whether the client reserves owner assignment for admins, once the settings load has finished — fail closed.
    ///
    /// - `loaded`: the flag the settings reply carried (`false` when the reply had no `owner_assignment`), or nil when
    ///   the load FAILED: the request errored, the reply could not be read, or it had no `config` object at all.
    /// - `cached`: the value this user last loaded successfully for this client (see `OwnerAssignmentCache`), if any.
    ///
    /// A load that succeeded decides by itself, exactly as it always did (no flag = the picker as before). A load that
    /// failed must never turn the restriction off just because nothing came back: it keeps the last-known value, and
    /// with none the restriction is ON for a non-admin (their picker stays hidden). An admin is never restricted by a
    /// failure — `isAdmin` already wins in `isLocked` / `mayChooseOwner`, this just keeps the flag honest for them.
    static func effectiveAdminOnly(loaded: Bool?, cached: Bool?, isAdmin: Bool) -> Bool {
        if let loaded { return loaded }
        if let cached { return cached }
        return !isAdmin
    }
}

// MARK: - Last-known owner-assignment setting

/// The `owner_assignment` value a user last loaded SUCCESSFULLY for a client, remembered so a later failed settings
/// load (offline, timeout, 5xx, an unreadable reply) keeps the restriction the client really has instead of
/// forgetting it. Keyed by user id + client, so one person's value never serves another, and wiped at sign-out
/// (`SessionCleanup`). Pure Foundation; the `UserDefaults` is a parameter so tests use their own suite.
enum OwnerAssignmentCache {
    /// Every key starts with this — `SessionCleanup` removes all of them at sign-out.
    static let keyPrefix = "lead_owner_admin_only."

    /// "lead_owner_admin_only.<user id>.<client id>"; nil without a user id (nothing to key it by).
    /// A user with no client of their own passes the client they picked, else "-".
    static func key(userId: String?, clientId: String?) -> String? {
        let u = (userId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if u.isEmpty { return nil }
        let c = (clientId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return keyPrefix + u + "." + (c.isEmpty ? "-" : c)
    }

    /// The remembered value; nil when there is none (never loaded, or wiped at sign-out).
    static func read(key: String?, in defaults: UserDefaults = .standard) -> Bool? {
        guard let key else { return nil }
        return defaults.object(forKey: key) as? Bool
    }

    /// Remember a value from a successful load.
    static func write(_ value: Bool, key: String?, in defaults: UserDefaults = .standard) {
        guard let key else { return }
        defaults.set(value, forKey: key)
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

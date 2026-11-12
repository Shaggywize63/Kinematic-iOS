import Foundation

// Lead number (`ref_no`) and lead type (`lead_type`) — pure logic.
//
// Both are Spark & Ray only for now (`SparkJourney.isActive`, same gate as the web). The lead
// number is server-assigned and read-only: it is displayed (and copied) but NEVER sent. The lead
// type is a NEW BUILT-IN lead field, so every render site also goes through
// `LeadFieldOverridesModel` (`isHidden` / `labelFor` / `requiredFor`, and it waits for `didLoad`);
// the helpers here only take the already-resolved booleans so they stay testable without SwiftUI.

/// The two lead types the backend accepts (`lead_type`: "requirement" | "discussion" | null).
enum LeadType: String, CaseIterable, Identifiable, Hashable {
    case requirement
    case discussion

    var id: String { rawValue }

    /// Picker / detail wording.
    var label: String {
        switch self {
        case .requirement: return "Requirement"
        case .discussion: return "Discussion"
        }
    }

    /// Parse a wire value; blank / nil / an unknown value is nil ("None").
    init?(raw: String?) {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !s.isEmpty else {
            return nil
        }
        self.init(rawValue: s)
    }
}

enum LeadNumberAndType {
    /// Key used for the field-override lookups (`lead.lead_type`).
    static let fieldKey = "lead_type"
    static let defaultLabel = "Lead Type"
    /// The picker's "no type" row.
    static let noneLabel = "None"

    // MARK: Visibility

    /// Is the lead-type control / row on screen? Spark & Ray only, held back until the settings have
    /// loaded (nothing reads as hidden before that) and dropped when the admin hid the field.
    static func isShown(isSpark: Bool, didLoad: Bool, hidden: Bool) -> Bool {
        isSpark && didLoad && !hidden
    }

    // MARK: Lead number

    /// The lead number to show: trimmed, or nil when the lead has none (nothing is shown then — no
    /// placeholder dash).
    static func refDisplay(_ ref: String?) -> String? {
        let t = (ref ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// The lead number to show for this client: nil outside Spark & Ray.
    static func refDisplay(_ ref: String?, isSpark: Bool) -> String? {
        isSpark ? refDisplay(ref) : nil
    }

    /// Placeholder of the leads-list search field; only Spark & Ray mention the lead number (the
    /// backend `q` search matches `ref_no`).
    static func searchPlaceholder(isSpark: Bool) -> String {
        isSpark ? "Search leads or lead no…" : "Search leads…"
    }

    // MARK: Lead type label

    /// "requirement" -> "Requirement". Nil / blank -> nil (nothing to show). An unexpected value is
    /// prettified ("some_type" -> "Some Type") rather than hidden.
    static func label(for raw: String?) -> String? {
        let t = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        if let known = LeadType(raw: t) { return known.label }
        return LeadStatusDisplay.prettify(t)
    }

    // MARK: Request bodies

    /// Fields to merge into a CREATE body: `lead_type` only when the control was shown and a type
    /// chosen. "None" sends nothing (a new lead simply has no type).
    static func createFields(selection: LeadType?, shown: Bool) -> [String: Any] {
        guard shown, let selection else { return [:] }
        return [fieldKey: selection.rawValue]
    }

    /// Fields to merge into an EDIT (PATCH) body. Untouched (selection equals what the lead had) or
    /// not shown -> nothing at all. Changed to a type -> that value. Changed to None -> explicit
    /// JSON null, which clears it server-side.
    static func editFields(original: String?, selection: LeadType?, shown: Bool) -> [String: Any] {
        guard shown else { return [:] }
        let before = LeadType(raw: original)
        if selection == before { return [:] }
        if let selection { return [fieldKey: selection.rawValue] }
        return [fieldKey: NSNull()]
    }

    /// The "<Label> is required." message when the admin made the (visible) field required and no
    /// type is chosen; nil otherwise.
    static func requiredProblem(shown: Bool, required: Bool, label: String, selection: LeadType?) -> String? {
        guard shown, required, selection == nil else { return nil }
        return "\(label) is required."
    }
}

/// Lead-status display helpers. Custom per-client stages (`cold_call`, `negotiation`, `finished`,
/// `trash`, …) come from `config.lead_statuses`; these keep a stage the picker does not know about
/// readable and selectable instead of snapping it to a hardcoded default.
enum LeadStatusDisplay {
    /// "cold_call" -> "Cold Call".
    static func prettify(_ value: String) -> String {
        value.split(whereSeparator: { $0 == "_" || $0 == " " })
            .map { String($0).capitalized }
            .joined(separator: " ")
    }

    /// The configured label for `value` (case-insensitive), else the prettified value.
    static func label(for value: String, options: [LeadStatusOption]) -> String {
        let key = value.lowercased()
        if let match = options.first(where: { $0.value == key }) { return match.label }
        return prettify(value)
    }

    /// The status a NEW lead should start with. With no custom set (or when `current` is one of them)
    /// `current` stands; otherwise the first open (not won / lost) configured stage, else the first.
    static func resolvedStatus(current: String, options: [LeadStatusOption]) -> String {
        if options.isEmpty || options.contains(where: { $0.value == current }) { return current }
        if let open = options.first(where: { !$0.isWon && !$0.isLost }) { return open.value }
        return options.first?.value ?? current
    }
}

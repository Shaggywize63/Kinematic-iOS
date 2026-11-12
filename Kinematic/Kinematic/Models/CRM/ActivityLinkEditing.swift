import Foundation

// Editing an existing activity: the "Linked entity" (Lead / Contact / Deal / Account / None) and the
// "Activity date & time". Pure (no UI, no network) so it is unit-tested — see
// KinematicTests/ActivityLinkEditingTests.
//
// The wire rules (PATCH /crm/activities/:id):
//  - the link is sent ONLY when it changed; the chosen `<type>_id` is set and the other three are explicit
//    JSON nulls; "None" sets all four to null;
//  - choosing a type without picking a record blocks the save ("Pick a <type> to link, or choose None.");
//  - `completed_at` is sent only when it was edited, and an untouched save sends none of these keys.

// MARK: - Link

/// What an activity can be linked to. The order is the order of precedence when a row carries several ids
/// (first present wins) and the order of the picker.
enum ActivityLinkType: String, CaseIterable, Identifiable, Equatable {
    case lead, contact, deal, account

    var id: String { rawValue }

    /// "Lead", "Contact", "Deal", "Account".
    var title: String { rawValue.capitalized }

    /// The request key: `lead_id`, `contact_id`, `deal_id`, `account_id`.
    var idKey: String { "\(rawValue)_id" }
}

/// A record an activity is linked to.
struct ActivityLink: Equatable {
    let type: ActivityLinkType
    let id: String
    var name: String?
}

/// The edit sheet's "Linked entity" state: what the activity had (`original`) and what is chosen now.
struct ActivityLinkDraft: Equatable {
    private(set) var original: ActivityLink?
    private(set) var type: ActivityLinkType?
    private(set) var pickedId: String?
    private(set) var pickedName: String?

    /// Starts on the activity's current link (or "None").
    init(original: ActivityLink? = nil) {
        self.original = original
        self.type = original?.type
        self.pickedId = original?.id
        self.pickedName = original?.name
    }

    private static func clean(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Choose the entity type (nil = "None"). Changing type clears the record; going back to the activity's
    /// own type restores its record.
    mutating func select(_ newType: ActivityLinkType?) {
        guard newType != type else { return }
        type = newType
        if let n = newType, let o = original, o.type == n {
            pickedId = o.id
            pickedName = o.name
        } else {
            pickedId = nil
            pickedName = nil
        }
    }

    /// Pick the record for the chosen type.
    mutating func pick(id: String, name: String?) {
        pickedId = id
        pickedName = name
    }

    /// The name of the activity's own link arrived late (it is fetched once when the row did not carry it).
    mutating func applyResolvedName(_ name: String) {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty, var o = original, Self.clean(o.name).isEmpty else { return }
        o.name = n
        original = o
        if type == o.type, pickedId == o.id { pickedName = n }
    }

    /// The name to show for the chosen record (nil until one is picked / resolved).
    var displayName: String? {
        let n = Self.clean(pickedName)
        return n.isEmpty ? nil : n
    }

    /// The chosen record is the activity's own link and it has no name yet (fetch it once).
    var needsNameLookup: Bool {
        guard let o = original else { return false }
        return Self.clean(o.name).isEmpty
    }

    /// Whether the link differs from the activity's current one. A type chosen without a record counts as a
    /// change (and is blocked by `validationError`).
    var isChanged: Bool {
        guard let t = type else { return original != nil }
        guard let o = original else { return true }
        return t != o.type || Self.clean(pickedId) != o.id
    }

    /// "Pick a <type> to link, or choose None." while a type is chosen but no record is.
    var validationError: String? {
        guard let t = type, Self.clean(pickedId).isEmpty else { return nil }
        return "Pick a \(t.rawValue) to link, or choose None."
    }

    /// The keys to merge into the PATCH body: nothing when the link is untouched (or incomplete); otherwise the
    /// chosen `<type>_id` plus the other three as explicit JSON nulls ("None" = all four null).
    var patch: [String: Any] {
        guard isChanged, validationError == nil else { return [:] }
        var out: [String: Any] = [:]
        for t in ActivityLinkType.allCases { out[t.idKey] = NSNull() }
        if let t = type { out[t.idKey] = Self.clean(pickedId) }
        return out
    }
}

// MARK: - Date

enum ActivityDateEditing {
    static let futureMessage = "Activity date can't be in the future."

    /// Allowed clock skew / picker rounding between "now" and a chosen date.
    static let tolerance: TimeInterval = 60

    /// The activity's own completion time (nil when it has none or it cannot be read).
    static func completedAt(of activity: Activity) -> Date? {
        let raw = (activity.completedAt ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return SparkJourney.parseISO(raw)
    }

    /// "Activity date & time" is shown only for an activity that already has `completed_at`.
    static func showsActivityDate(for activity: Activity) -> Bool {
        let raw = (activity.completedAt ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return !raw.isEmpty
    }

    /// The error for a chosen activity date that is in the future (nil when fine).
    static func validationError(for date: Date, now: Date = Date()) -> String? {
        date > now.addingTimeInterval(tolerance) ? futureMessage : nil
    }
}

// MARK: - Edit state shared between the sheet and its host

/// What the edit sheet changes besides the usual fields: the link draft and whether the date was edited.
/// The host owns it (as `@State`) and reads it when the person saves — like the "Assigned to" selection.
struct ActivityEditState: Equatable {
    var link: ActivityLinkDraft
    var dateEdited: Bool

    init(activity: Activity? = nil) {
        link = ActivityLinkDraft(original: activity.flatMap { ActivityLinkEditing.initialLink(for: $0) })
        dateEdited = false
    }

    /// The date to send: the chosen one only when it was edited (an untouched save sends no date).
    func dateToSend(_ chosen: Date) -> Date? {
        dateEdited ? chosen : nil
    }
}

enum ActivityLinkEditing {
    /// The record an activity is linked to: the first present of lead, contact, deal, account. Its name is the
    /// row's `<type>_name` when it has one.
    static func initialLink(for a: Activity) -> ActivityLink? {
        func clean(_ s: String?) -> String? {
            let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if let id = clean(a.leadId) { return ActivityLink(type: .lead, id: id, name: clean(a.leadName)) }
        if let id = clean(a.contactId) { return ActivityLink(type: .contact, id: id, name: clean(a.contactName)) }
        if let id = clean(a.dealId) { return ActivityLink(type: .deal, id: id, name: clean(a.dealName)) }
        if let id = clean(a.accountId) { return ActivityLink(type: .account, id: id, name: clean(a.accountName)) }
        return nil
    }

    /// Records whose name contains `query` (case-insensitive); everything for a blank query. Used by the deal
    /// picker, whose list endpoint has no search.
    static func filter<T>(_ items: [T], query: String, name: (T) -> String) -> [T] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter { name($0).lowercased().contains(q) }
    }
}

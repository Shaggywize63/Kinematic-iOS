import Foundation

/// A screen a notification can open.
///
/// Mirrors the Android app's `NotificationDeepLinkState.Target`, so a tap lands on the
/// same screen on both platforms. Contacts and accounts have no id-based screen on iOS
/// (their detail views take a loaded model), so an automation about one of those falls
/// back to the notification list.
enum NotificationTarget: Equatable {
    case lead(String)
    case deal(String)
    case expenseClaim(String)
    case crmHome
    case deals
    case activities
    /// Manager approvals — leave + attendance regularization.
    case leaveApprovals
    /// The rep's own leave.
    case leave
    /// The rep's own attendance regularizations.
    case regularization
    case routePlans
    case sos
    case broadcast
    case stock
    case chatThread(String)
    case chatInbox
    /// The field-force Attendance tab, where check-in lives.
    case checkIn
    /// The in-app notification list — where a push with no screen of its own lands.
    case notificationList
}

/// Which screen a notification opens.
///
/// ONE table for every way a notification can be tapped — the push banner (foreground,
/// background or app closed) and a row in the in-app list — so they can never disagree.
/// Pure Swift on purpose: it takes the flat string payload the backend sends (the APNs
/// custom keys / the row's `data` jsonb) and returns a target, so it is unit-tested
/// without any UI.
///
/// The contract lives in the backend (`docs/NOTIFICATIONS.md`, `lib/notificationRoute.ts`):
/// every payload carries a `kind`. `kind(of:)` repeats that resolution so notifications
/// from an older server, or stored before it, still route.
///
/// `nil` means "no dedicated screen": the in-app list is already the fallback for a
/// pushed notification (see `forPush`), and a tap inside the list simply does nothing.
enum NotificationRoute {

    private static func nz(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty, t != "null" else { return nil }
        return t
    }

    /// The single discriminator — `kind`, else `type`, else `nudge_kind` (as `kini_<x>`).
    static func kind(of data: [String: String]) -> String? {
        if let k = nz(data["kind"]) { return k }
        if let t = nz(data["type"]) { return t }
        if let n = nz(data["nudge_kind"]) { return "kini_\(n)" }
        return nil
    }

    private static let leadKinds: Set<String> = [
        "lead_assigned", "new_lead", "lead_pending_approval", "lead_approval_decided",
        "lead_from_google_ads", "conversation_ready",
    ]
    private static let dealKinds: Set<String> = [
        "deal_assigned", "deal_won", "deal_lost", "deal_stage_changed",
    ]
    /// Kinds that have no mobile screen of their own.
    private static let noScreen: Set<String> = [
        "route_deviation", "security_alert", "location_off", "kini_reminder", "finance_invoice_due",
    ]

    private static func byId(_ leadId: String?, _ dealId: String?) -> NotificationTarget? {
        if let l = leadId { return .lead(l) }
        if let d = dealId { return .deal(d) }
        return nil
    }

    /// The screen for `data`, or nil when the kind has none (or its id is missing).
    static func resolve(_ data: [String: String]) -> NotificationTarget? {
        let leadId = nz(data["lead_id"])
        let dealId = nz(data["deal_id"])
        let claimId = nz(data["claim_id"])
        let threadId = nz(data["thread_id"])

        guard let kind = NotificationRoute.kind(of: data) else { return byId(leadId, dealId) }

        if leadKinds.contains(kind) || kind.hasPrefix("crm_lead_") {
            if let l = leadId { return .lead(l) }
            return nil
        }
        if dealKinds.contains(kind) || kind.hasPrefix("crm_deal_") {
            if let d = dealId { return .deal(d) }
            return nil
        }

        switch kind {
        // A task / activity opens the thing it is about; a bare one opens Activities.
        case "activity_assigned", "crm_task_overdue":
            return byId(leadId, dealId) ?? NotificationTarget.activities

        // Automation: `entity` + `entity_id`, or the dynamic `<entity>_id` key.
        case "automation":
            let entity = nz(data["entity"])
            let id = nz(data["entity_id"]) ?? entity.flatMap { nz(data["\($0)_id"]) }
            switch entity {
            case "lead"?: return id.map { NotificationTarget.lead($0) }
            case "deal"?: return id.map { NotificationTarget.deal($0) }
            case "contact"?, "account"?: return nil   // no id-based screen on iOS
            default: return byId(leadId, dealId)
            }

        // Leave: a request (or its cancellation) goes to the approver; a decision to the applicant.
        case "leave_request", "leave_cancelled", "att_reg_request": return .leaveApprovals
        case "leave_decision": return .leave
        case "att_reg_decision": return .regularization

        case "missed_visits": return .routePlans
        case "sos": return .sos
        case "broadcast": return .broadcast

        case "message":
            if let t = threadId { return .chatThread(t) }
            return .chatInbox
        // A chat mention carries the thread; a lead-update mention carries the lead.
        case "mention":
            if let t = threadId { return .chatThread(t) }
            if let l = leadId { return .lead(l) }
            return nil

        case "crm_home": return .crmHome
        case "kini_cold_deals": return .deals
        // The 10-hour "don't forget to check out" reminder lands on the same attendance screen.
        case "kini_no_checkin", "checkout_reminder": return .checkIn
        case "low_stock", "stock_expiry": return .stock

        default:
            if kind.hasPrefix("expense") {
                if let c = claimId { return .expenseClaim(c) }
                return nil
            }
            // route_deviation, security_alert, location_off, kini_reminder, finance_invoice_due have
            // no mobile screen of their own. Anything else (incl. `general`) still opens its lead /
            // deal when it carries one.
            if noScreen.contains(kind) { return nil }
            return byId(leadId, dealId)
        }
    }

    /// What a tapped *push* opens: its screen, else the in-app list so the tap always lands
    /// somewhere useful. A payload that isn't a notification (no `notification_id`) opens nothing.
    static func forPush(_ data: [String: String]) -> NotificationTarget? {
        if let t = resolve(data) { return t }
        if nz(data["notification_id"]) != nil { return .notificationList }
        return nil
    }

    // MARK: - Payload helpers

    /// One payload value as a string. APNs custom keys arrive as strings (the server flattens
    /// them); the list's `data` jsonb can carry numbers and booleans.
    static func stringValue(_ v: Any) -> String? {
        if v is NSNull { return nil }
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return String(describing: v)
    }

    /// A push's `userInfo` as a flat payload, without the `aps` envelope.
    static func payload(fromUserInfo info: [AnyHashable: Any]) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in info {
            guard let key = k as? String, key != "aps" else { continue }
            if let s = stringValue(v) { out[key] = s }
        }
        return out
    }

    /// A notification row's `data` object as a flat payload.
    static func payload(fromJSON json: [String: Any]) -> [String: String] {
        var out: [String: String] = [:]
        for (key, v) in json {
            if let s = stringValue(v) { out[key] = s }
        }
        return out
    }
}

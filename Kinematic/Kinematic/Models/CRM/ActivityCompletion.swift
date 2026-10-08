import Foundation

/// Rules and request body behind the "Mark complete" / "Reopen" action on a CRM
/// activity card (mirrors the web dashboard's "✓ Mark Complete" / "↺ Reopen").
///
/// Server contract — `PATCH /crm/activities/{id}`:
///   - complete: `{ "status": "completed", "completed_at": "<now ISO-8601 UTC>" }`
///   - reopen:   `{ "status": "open", "completed_at": null }`
/// The `null` MUST reach the server explicitly or the activity stays completed,
/// which is why the body is a `[String: Any]` carrying `NSNull()` (sent through
/// `JSONSerialization`) rather than a Codable struct — the synthesized encoder
/// omits nil optionals.
enum ActivityCompletion {

    /// What a card's action button offers.
    enum Action: Equatable {
        case markComplete
        case reopen

        /// The `completed` value to send when this action is tapped.
        var targetCompleted: Bool { self == .markComplete }

        var title: String { self == .markComplete ? "Mark complete" : "Reopen" }

        var systemImage: String {
            self == .markComplete ? "checkmark.circle" : "arrow.uturn.backward.circle"
        }
    }

    /// Statuses that mean the work is done.
    static let completedStatuses: Set<String> = ["completed", "done"]
    /// Statuses that mean the work was abandoned — no action is offered.
    static let cancelledStatuses: Set<String> = ["cancelled", "canceled"]

    /// Which action an activity with this status / completed-at stamp offers:
    /// `nil` for cancelled, `.reopen` once completed (status completed/done OR a
    /// non-empty `completedAt`), otherwise `.markComplete`.
    static func action(status: String?, completedAt: String?) -> Action? {
        let s = (status ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cancelledStatuses.contains(s) { return nil }
        let stamp = (completedAt ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if completedStatuses.contains(s) || !stamp.isEmpty { return .reopen }
        return .markComplete
    }

    static func action(for activity: Activity) -> Action? {
        action(status: activity.status, completedAt: activity.completedAt)
    }

    /// PATCH body for the action. Pure (no networking, `now` injected) so it can
    /// be unit tested. Reopen carries an explicit `NSNull()` for `completed_at`.
    static func body(completed: Bool, now: Date) -> [String: Any] {
        if completed {
            return ["status": "completed", "completed_at": isoTimestamp(now)]
        }
        return ["status": "open", "completed_at": NSNull()]
    }

    /// `2026-10-08T04:12:00.000Z` — UTC, internet date-time with fractional seconds.
    static func isoTimestamp(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
}

extension Activity {
    /// This activity with its completion state (status / completedAt / updatedAt)
    /// taken from the server's PATCH response and everything else kept.
    ///
    /// The PATCH response is NOT enriched the way the list / detail GETs are — it
    /// has no `lead_name`, `contact_name`, `deal_name`, `lead_phone` or directory
    /// fields — so swapping the whole row for the response would drop the linked
    /// record name off the card. `completedAt` is taken as-is from the response so
    /// a reopen (`completed_at: null`) correctly clears it.
    func applyingCompletion(from updated: Activity) -> Activity {
        Activity(
            id: id,
            orgId: orgId,
            type: type,
            subject: subject,
            description: description,
            leadId: leadId,
            contactId: contactId,
            accountId: accountId,
            dealId: dealId,
            ownerId: ownerId,
            ownerName: ownerName,
            status: updated.status,
            dueAt: dueAt,
            completedAt: updated.completedAt,
            direction: direction,
            durationMinutes: durationMinutes,
            imageUrl: imageUrl,
            createdAt: createdAt,
            updatedAt: updated.updatedAt ?? updatedAt,
            leadName: leadName,
            leadPhone: leadPhone,
            contactName: contactName,
            dealName: dealName,
            directoryName: directoryName,
            directoryPhone: directoryPhone
        )
    }
}

extension Array where Element == Activity {
    /// Flip the row with `updated.id` to the server's completion state in place.
    /// No-op when the row has left the list in the meantime.
    mutating func applyCompletion(_ updated: Activity) {
        guard let i = firstIndex(where: { $0.id == updated.id }) else { return }
        self[i] = self[i].applyingCompletion(from: updated)
    }
}

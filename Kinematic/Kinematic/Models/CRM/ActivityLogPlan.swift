import Foundation

// Logging an activity with an Activity (done) date and / or a Scheduled (due) date. Both may be set; they never
// clear each other. Pure (no UI, no network) so it is unit-tested — see KinematicTests/ActivityLogPlanTests.
//
// Saving rules:
//  - only the Activity date (past)  -> ONE completed activity at that date;
//  - only the Scheduled date        -> ONE planned activity due at that date;
//  - neither                        -> nothing is added by this plan (the caller's own default applies);
//  - BOTH                           -> TWO activities: a completed one (completed_at = Activity date, carries the
//    outcome, no due_at) and a planned one (due_at = Scheduled date, no completed_at, no outcome). They share
//    type / subject / notes / linked entity / assignees / custom fields.

/// One activity the plan creates.
struct ActivityLogEntry: Equatable {
    enum Kind: Equatable {
        /// Done: `status = completed`, `completed_at`.
        case completed
        /// Planned follow-up: `status = open`, `due_at`.
        case planned
    }
    let kind: Kind
    let date: Date
}

enum ActivityLogPlan {
    static let futureMessage = "Activity date can't be in the future."
    static let followUpPastMessage = "The scheduled date must be in the future."
    static let loggedAndScheduledMessage = "Activity logged + follow-up scheduled"
    static let loggedMessage = "Activity logged"

    /// Allowed clock skew / picker rounding between "now" and a chosen date.
    static let tolerance: TimeInterval = 60

    /// The activities to create, completed first. Empty when neither date is set.
    static func entries(activityDate: Date?, scheduledDate: Date?) -> [ActivityLogEntry] {
        var out: [ActivityLogEntry] = []
        if let a = activityDate { out.append(ActivityLogEntry(kind: .completed, date: a)) }
        if let s = scheduledDate { out.append(ActivityLogEntry(kind: .planned, date: s)) }
        return out
    }

    /// Both dates set: the save creates two activities.
    static func createsBoth(activityDate: Date?, scheduledDate: Date?) -> Bool {
        activityDate != nil && scheduledDate != nil
    }

    /// The text after a successful save (nil for a single activity: nothing extra to say).
    static func successMessage(activityDate: Date?, scheduledDate: Date?) -> String? {
        createsBoth(activityDate: activityDate, scheduledDate: scheduledDate) ? loggedAndScheduledMessage : nil
    }

    /// "Activity date can't be in the future." for an Activity (done) date after now.
    static func activityDateError(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        return date > now.addingTimeInterval(tolerance) ? futureMessage : nil
    }

    /// The Scheduled (due) date must be ahead of now.
    static func scheduledDateError(_ date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        return date < now.addingTimeInterval(-tolerance) ? followUpPastMessage : nil
    }

    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    /// The POST body of one entry, built on `shared` (type, subject, description, links, custom fields, …).
    /// Any date / status keys already in `shared` are replaced; the planned entry never carries `completed_at`,
    /// `outcome` or the photo (which belongs to the done activity).
    static func body(for entry: ActivityLogEntry, shared: [String: Any]) -> [String: Any] {
        var body = shared
        for key in ["completed_at", "due_at", "status"] { body.removeValue(forKey: key) }
        switch entry.kind {
        case .completed:
            body["status"] = "completed"
            body["completed_at"] = iso(entry.date)
        case .planned:
            body["status"] = "open"
            body["due_at"] = iso(entry.date)
            body.removeValue(forKey: "outcome")
            body.removeValue(forKey: "image_url")
        }
        return body
    }

    /// The Spark extras of one entry: the completed activity keeps everything; the planned follow-up keeps the
    /// assignees and products but carries no outcome and no form serial (that belongs to the done activity).
    static func extras(_ extras: SparkActivityExtras, for kind: ActivityLogEntry.Kind) -> SparkActivityExtras {
        var out = extras
        if kind == .planned {
            out.outcome = ""
            out.formSerial = ""
        }
        return out
    }
}

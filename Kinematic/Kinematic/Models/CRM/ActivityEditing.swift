import Foundation

/// The request bodies for editing an existing activity, shared by every screen that edits one (the
/// Activities list and the account detail), so the two paths can never diverge.
///
/// Pure (no UI, no network) so it is unit-tested — see KinematicTests/ActivityEditingTests.
enum ActivityEditBody {
    private static func iso(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    /// PATCH body for the generic (non-Spark) edit, or nil when the subject is blank. Blank remarks clear the
    /// description; a task gets its due date and every other type is stamped completed at the chosen time —
    /// but only when `completedAt` is given: nil means the date was not edited, and an untouched date sends
    /// no `completed_at` / `due_at` / `status` at all.
    /// `assignment` (the single "Assigned to" change) is only sent for admins / managers.
    /// `linkPatch` is a changed "Linked entity" (see `ActivityLinkDraft.patch`); empty when untouched.
    static func patch(
        type: String,
        subject: String,
        description: String,
        imageUrl: String?,
        completedAt: Date?,
        customFields: [String: Any],
        assignment: [String: Any],
        canChangeAssignee: Bool,
        linkPatch: [String: Any] = [:]
    ) -> [String: Any]? {
        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSubject.isEmpty else { return nil }
        var body: [String: Any] = ["type": type, "subject": trimmedSubject]
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        body["description"] = trimmedDesc.isEmpty ? NSNull() : trimmedDesc
        if let imageUrl, !imageUrl.isEmpty { body["image_url"] = imageUrl }
        if let stamp = completedAt {
            if type != "task" {
                body["completed_at"] = iso(stamp)
                body["status"] = "completed"
            } else {
                body["due_at"] = iso(stamp)
            }
        }
        // Only touched custom fields are sent — the backend merges them over the stored blob.
        if !customFields.isEmpty { body["custom_fields"] = customFields }
        if canChangeAssignee {
            for (key, value) in assignment { body[key] = value }
        }
        for (key, value) in linkPatch { body[key] = value }
        return body
    }

    /// The pieces of the Spark edit request: the base PATCH body, the extras to send (a person who may not
    /// change assignees keeps the existing ones) and the previous extras (so only changed ones are sent).
    static func sparkPatch(
        existing: Activity,
        result: ActivityComposeResult,
        canChangeAssignees: Bool
    ) -> (body: [String: Any], extras: SparkActivityExtras, previous: SparkActivityExtras) {
        let body = SparkActivityBody.updateBody(result, existing: existing)
        let previous = existing.sparkExtras
        let extras = RecordOwnerRules.extrasForEdit(
            edited: result.extras, previous: previous, canChangeAssignees: canChangeAssignees
        )
        return (body, extras, previous)
    }
}

/// Which activity an edit entry point opens, what the sheet starts from, and how the saved row lands back in
/// the list.
enum ActivityEditRouting {
    /// The row to edit for a tapped / swiped / menu id, looked up in the CURRENT list so an edit always starts
    /// from the freshest copy; nil when the row is no longer there (e.g. a refresh removed it).
    static func target(id: String, in activities: [Activity]) -> Activity? {
        activities.first { $0.id == id }
    }

    /// `list` with the saved row swapped in at its own position (order kept); unchanged when the id is not in it.
    static func replacing(_ updated: Activity, in list: [Activity]) -> [Activity] {
        guard let index = list.firstIndex(where: { $0.id == updated.id }) else { return list }
        var out = list
        out[index] = updated.keepingCompany(of: list[index])
        return out
    }

    /// Spark & Ray edits start from the row's own remarks, so saving never wipes the description; other
    /// tenants keep the original blank start.
    static func initialDescription(for activity: Activity, spark: Bool) -> String {
        spark ? (activity.remarksText ?? "") : ""
    }

    /// Spark & Ray edits start from the row's own date (completed, else due), so saving never resets it to
    /// "now"; other tenants keep the original "now" start (nil).
    static func initialWhen(for activity: Activity, spark: Bool) -> Date? {
        spark ? SparkJourney.parseISO(activity.completedAt ?? activity.dueAt) : nil
    }

    /// The type the edit sheet opens with ("meeting" when the row has none).
    static func initialType(for activity: Activity) -> String {
        activity.type ?? "meeting"
    }
}

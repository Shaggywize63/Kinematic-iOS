import SwiftUI

extension ActivityComposeView {
    /// Save handler for the generic edit: type, subject, description, image url, the date (nil when it was not
    /// edited — an untouched date is never sent), custom fields, the single "Assigned to" change
    /// (`assigned_to`, or `[:]` when untouched) and the "Linked entity" change (`<type>_id` keys, or `[:]` when
    /// untouched).
    typealias ActivityEditSave = (String, String, String, String?, Date?, [String: Any], [String: Any], [String: Any]) async -> Void

    /// The compose view set up to EDIT an existing activity: pre-filled from the row (type, subject, remarks,
    /// date, photo), with the Spark extras (assignees / product interested / form serial) and the
    /// admin / manager-only assignee picker. The Activities list and the account detail both build their edit
    /// sheet through this, so the two always behave the same.
    ///
    /// `assignedToSelection` receives the single "Assigned to" picker's choice (nil = unchanged); it is read
    /// when the person saves. `editState` holds the "Linked entity" draft and whether the date was edited (the
    /// host creates it with `ActivityEditState(activity:)` each time it opens the sheet); it is read on save too.
    static func editing(
        _ activity: Activity,
        assignedToSelection: Binding<String?>,
        editState: Binding<ActivityEditState>,
        onSave: @escaping ActivityEditSave,
        onSparkSave: @escaping (ActivityComposeResult) async throws -> Void
    ) -> ActivityComposeView {
        let spark = SparkJourney.isActive
        return ActivityComposeView(
            initialType: ActivityEditRouting.initialType(for: activity),
            initialSubject: activity.subject ?? "",
            initialDescription: ActivityEditRouting.initialDescription(for: activity, spark: spark),
            // The date picker starts on the activity's own completion time for every tenant (Spark also falls
            // back to its due date), so an edit never starts from "now".
            initialWhen: ActivityEditRouting.initialWhen(for: activity, spark: spark)
                ?? ActivityDateEditing.completedAt(of: activity)
                ?? (activity.type == "task" ? SparkJourney.parseISO(activity.dueAt) : nil),
            allowLeadPicker: false
        ) { type, subject, desc, imageUrl, when, _, customFields in
            let assignment = RecordOwnerRules.assignedToPatch(
                original: activity.assignedTo,
                selected: assignedToSelection.wrappedValue
            )
            let state = editState.wrappedValue
            await onSave(
                type, subject, desc, imageUrl, state.dateToSend(when), customFields, assignment, state.link.patch
            )
        }
        // Show the activity's current photo; a newly attached one replaces it.
        .withExistingPhoto(activity.imageUrl)
        // Spark & Ray: an already-completed activity must keep an Outcome.
        .withExistingCompletion(SparkActivityOutcome.isCompleted(activity))
        // Spark & Ray: edit the assignees / product interested / form serial too.
        .sparkSubmit(initial: activity.sparkExtras, names: activity.sparkNames) { result in
            // Carry the link change and whether the date was edited onto the result the Spark PATCH is built from.
            var edited = result
            let state = editState.wrappedValue
            edited.whenEdited = state.dateEdited
            edited.linkPatch = state.link.patch
            try await onSparkSave(edited)
        }
        // "Linked entity" + "Activity date & time" (shown only when the activity already has completed_at).
        .editingExtras(editState, showsDate: ActivityDateEditing.showsActivityDate(for: activity))
        // Who it is assigned to can be changed (or, for Spark, cleared) by admins / managers only;
        // everyone else sees the names without a picker.
        .editingAssignment(
            assignedToId: activity.assignedTo,
            assignedToName: activity.assignedToName,
            selection: assignedToSelection
        )
    }
}

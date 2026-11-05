import SwiftUI

extension ActivityComposeView {
    /// Save handler for the generic edit: type, subject, description, image url, when, custom fields and the
    /// single "Assigned to" change (`assigned_to`, or `[:]` when untouched).
    typealias ActivityEditSave = (String, String, String, String?, Date, [String: Any], [String: Any]) async -> Void

    /// The compose view set up to EDIT an existing activity: pre-filled from the row (type, subject, remarks,
    /// date, photo), with the Spark extras (assignees / product interested / form serial) and the
    /// admin / manager-only assignee picker. The Activities list and the account detail both build their edit
    /// sheet through this, so the two always behave the same.
    ///
    /// `assignedToSelection` receives the single "Assigned to" picker's choice (nil = unchanged); it is read
    /// when the person saves.
    static func editing(
        _ activity: Activity,
        assignedToSelection: Binding<String?>,
        onSave: @escaping ActivityEditSave,
        onSparkSave: @escaping (ActivityComposeResult) async throws -> Void
    ) -> ActivityComposeView {
        let spark = SparkJourney.isActive
        return ActivityComposeView(
            initialType: ActivityEditRouting.initialType(for: activity),
            initialSubject: activity.subject ?? "",
            initialDescription: ActivityEditRouting.initialDescription(for: activity, spark: spark),
            initialWhen: ActivityEditRouting.initialWhen(for: activity, spark: spark),
            allowLeadPicker: false
        ) { type, subject, desc, imageUrl, when, _, customFields in
            let assignment = RecordOwnerRules.assignedToPatch(
                original: activity.assignedTo,
                selected: assignedToSelection.wrappedValue
            )
            await onSave(type, subject, desc, imageUrl, when, customFields, assignment)
        }
        // Show the activity's current photo; a newly attached one replaces it.
        .withExistingPhoto(activity.imageUrl)
        // Spark & Ray: edit the assignees / product interested / form serial too.
        .sparkSubmit(initial: activity.sparkExtras, names: activity.sparkNames, onSparkSave)
        // Who it is assigned to can be changed (or, for Spark, cleared) by admins / managers only;
        // everyone else sees the names without a picker.
        .editingAssignment(
            assignedToId: activity.assignedTo,
            assignedToName: activity.assignedToName,
            selection: assignedToSelection
        )
    }
}

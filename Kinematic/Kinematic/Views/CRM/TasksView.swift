import SwiftUI

/// Tasks are activities of type=task. The dashboard's tasks page redirects to
/// `/activities?type=task`; we mirror that by rendering ActivitiesView with
/// the type filter pre-set, keeping a single source of truth for due dates,
/// owner, and completion state.
struct TasksView: View {
    var body: some View {
        ActivitiesView(initialFilter: "task")
            .navigationTitle("Tasks")
    }
}

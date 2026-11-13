import Foundation
import Combine

/// Drives the "My Tasks" screen — the signed-in user's own assigned tasks.
/// Fetches `/crm/my-tasks`, keeps the status + overdue controls, and exposes
/// the tasks already grouped into Overdue / Today / Upcoming / No date via the
/// pure `MyTasksLogic`. Core CRM (all tenants) — not feature-gated.
@MainActor
final class MyTasksViewModel: ObservableObject {
    @Published var statusFilter: MyTasksStatusFilter = .all
    @Published var overdueOnly: Bool = false
    @Published private(set) var tasks: [MyTask] = []
    @Published private(set) var total: Int = 0
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// True once the first load has returned (so the screen can tell "still
    /// loading" from a genuinely empty list).
    @Published private(set) var didLoad = false

    private let api = CRMService.shared

    /// The fetched tasks grouped into the four render sections, soonest-due
    /// first. Recomputed from the current list on every access.
    var sections: [MyTaskSectionGroup] { MyTasksLogic.grouped(tasks) }

    /// Fetch with the current filters. The status / overdue controls call this
    /// after they change so the list refetches server-side (the backend owns
    /// the status + overdue filtering, not just the client grouping).
    func refresh() async {
        isLoading = true
        defer { isLoading = false; didLoad = true }
        do {
            let page = try await api.myTasks(
                status: statusFilter.apiValue,
                overdue: overdueOnly
            )
            tasks = page.tasks
            total = page.pagination?.total ?? page.tasks.count
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setStatus(_ status: MyTasksStatusFilter) async {
        guard status != statusFilter else { return }
        statusFilter = status
        await refresh()
    }

    func setOverdueOnly(_ on: Bool) async {
        guard on != overdueOnly else { return }
        overdueOnly = on
        await refresh()
    }
}

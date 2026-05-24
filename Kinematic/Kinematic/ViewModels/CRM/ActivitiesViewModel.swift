import Foundation
import Combine

@MainActor
final class ActivitiesViewModel: ObservableObject {
    @Published var activities: [Activity] = []
    @Published var typeFilter: String
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = CRMService.shared

    init(initialFilter: String = "all") {
        self.typeFilter = initialFilter
        if let cached = CRMReadCache.shared.load(.activities, as: [Activity].self) {
            self.activities = cached
        }
    }

    /// Tasks are managed separately on TasksView — keep them out of the
    /// activity timeline so completed CRM motion isn't mixed with TODOs.
    var filtered: [Activity] {
        let withoutTasks = activities.filter { ($0.type ?? "").lowercased() != "task" }
        return typeFilter == "all"
            ? withoutTasks
            : withoutTasks.filter { ($0.type ?? "") == typeFilter }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            activities = try await api.listActivities()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func log(type: String, subject: String, description: String, dealId: String?, leadId: String?) async {
        var body: [String: Any] = ["type": type, "subject": subject, "description": description]
        if let dealId { body["deal_id"] = dealId }
        if let leadId { body["lead_id"] = leadId }
        let a = await api.createActivityOrQueue(body)
        activities.insert(a, at: 0)
    }
}

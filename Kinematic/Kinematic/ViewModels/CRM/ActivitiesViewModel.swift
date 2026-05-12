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
    }

    var filtered: [Activity] {
        typeFilter == "all" ? activities : activities.filter { ($0.type ?? "") == typeFilter }
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
        do {
            var body: [String: Any] = ["type": type, "subject": subject, "description": description]
            if let dealId { body["deal_id"] = dealId }
            if let leadId { body["lead_id"] = leadId }
            let a = try await api.createActivity(body)
            activities.insert(a, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

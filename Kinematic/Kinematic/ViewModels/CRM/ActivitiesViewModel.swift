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

    func log(
        type: String,
        subject: String,
        description: String,
        dealId: String?,
        leadId: String?,
        imageUrl: String? = nil,
        completedAt: Date? = nil
    ) async {
        let trimmedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSubject.isEmpty else { return }
        do {
            var body: [String: Any] = ["type": type, "subject": trimmedSubject]
            let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedDesc.isEmpty { body["description"] = trimmedDesc }
            if let dealId { body["deal_id"] = dealId }
            if let leadId { body["lead_id"] = leadId }
            if let imageUrl, !imageUrl.isEmpty { body["image_url"] = imageUrl }
            if type != "task" {
                let stamp = completedAt ?? Date()
                body["completed_at"] = ISO8601DateFormatter().string(from: stamp)
                body["status"] = "completed"
            } else if let due = completedAt {
                body["due_at"] = ISO8601DateFormatter().string(from: due)
            }
            let a = try await api.createActivity(body)
            activities.insert(a, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

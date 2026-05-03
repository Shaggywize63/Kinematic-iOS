import Foundation

@MainActor
final class LeadDetailViewModel: ObservableObject {
    @Published var lead: Lead?
    @Published var score: LeadScore?
    @Published var activities: [Activity] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var aiBusy = false

    private let api = CRMService.shared
    let leadId: String

    init(leadId: String) { self.leadId = leadId }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let leadTask = api.getLead(id: leadId)
            async let actsTask = api.leadActivities(id: leadId)
            self.lead = try await leadTask
            self.activities = (try? await actsTask) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func runAIScore() async {
        aiBusy = true
        defer { aiBusy = false }
        do {
            score = try await api.aiScoreLead(id: leadId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func convert() async {
        do {
            let updated = try await api.convertLead(id: leadId, body: ["create_account": true, "create_deal": true])
            self.lead = updated
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

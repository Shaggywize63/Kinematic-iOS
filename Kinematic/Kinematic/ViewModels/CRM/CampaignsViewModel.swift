import Foundation

@MainActor
final class CampaignsViewModel: ObservableObject {
    @Published var campaigns: [Campaign] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = CRMService.shared

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            campaigns = try await api.listCampaigns()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

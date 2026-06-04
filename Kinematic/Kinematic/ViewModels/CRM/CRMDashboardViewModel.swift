import Foundation
import Combine
import SwiftUI

@MainActor
final class CRMDashboardViewModel: ObservableObject {
    @Published var summary: CRMAnalyticsSummary?
    @Published var funnel: [FunnelStageMetric] = []
    @Published var winRate: [WinRateBucket] = []
    @Published var forecast: [ForecastPoint] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    // ── Multi-tenant client picker (org-level admins only) ──────────────
    @Published var clients: [CRMClientOption] = []
    @Published var selectedClientId: String? = CRMClientScope.selectedClientId()

    private let api = CRMService.shared

    /// Org-level admins (no pinned `client_id` on their profile) can hop
    /// between clients; client-pinned users have a fixed scope and never see
    /// the picker. Matches the web `CrmScopeBadge` gating exactly.
    var canSwitchClient: Bool { Session.currentUser?.clientId == nil }

    /// Display name for the active scope, used in the picker label.
    var selectedClientName: String {
        guard let id = selectedClientId else { return "All Clients" }
        return clients.first(where: { $0.id == id })?.name ?? "Selected client"
    }

    func loadClientsIfNeeded() async {
        guard canSwitchClient, clients.isEmpty else { return }
        clients = (try? await api.listClients()) ?? []
    }

    /// Switch the active client. nil = org-wide ("All Clients"). Stamps the
    /// `X-Client-Id` header (via CRMClientScope) and re-pulls the dashboard.
    func selectClient(_ id: String?) async {
        selectedClientId = id
        CRMClientScope.setSelectedClientId(id)
        await refresh()
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            async let summaryTask = api.dashboardSummary()
            async let funnelTask  = api.funnel()
            async let winTask     = api.winRate()
            async let forecastTask = api.forecast()
            self.summary = try await summaryTask
            self.funnel  = (try? await funnelTask) ?? []
            self.winRate = (try? await winTask) ?? []
            self.forecast = (try? await forecastTask) ?? []
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

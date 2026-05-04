import Foundation
import SwiftUI

@MainActor
final class CRMDashboardViewModel: ObservableObject {
    @Published var summary: CRMAnalyticsSummary?
    @Published var funnel: [FunnelStageMetric] = []
    @Published var winRate: [WinRateBucket] = []
    @Published var forecast: [ForecastPoint] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = CRMService.shared

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

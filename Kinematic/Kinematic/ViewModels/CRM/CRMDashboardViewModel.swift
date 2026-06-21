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
    /// The signed-in FE's daily lead target + today's achievement (ticker).
    @Published var target: CRMTarget?

    // ── Multi-tenant client picker (org-level admins only) ──────────────
    @Published var clients: [CRMClientOption] = []
    @Published var selectedClientId: String? = CRMClientScope.selectedClientId()

    // ── Date-range preset for the dashboard ──────────────────────────
    // The user wanted "show each data by default for 7 days", so the
    // default range is .last7. The dashboard refresh re-fires whenever
    // this changes (.task(id:) in the view). Custom reveals two date
    // pickers; ISO strings get resolved from this enum + the customFrom/
    // customTo dates and forwarded to all five analytics endpoints.
    enum DateRangePreset: String, CaseIterable, Identifiable {
        case today, yesterday, last7, thisMonth, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .today: return "Today"
            case .yesterday: return "Yesterday"
            case .last7: return "Last 7 days"
            case .thisMonth: return "This month"
            case .custom: return "Custom"
            }
        }
    }
    @Published var range: DateRangePreset = .last7
    @Published var customFrom: Date = Calendar.current.startOfDay(
        for: Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    )
    @Published var customTo: Date = Calendar.current.startOfDay(for: Date())

    /// Resolve the picked preset → ISO (from, to) the backend honours.
    var rangeISO: (from: String?, to: String?) {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        switch range {
        case .today:
            return (f.string(from: startOfDay), f.string(from: Date()))
        case .yesterday:
            let yStart = cal.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay
            return (f.string(from: yStart), f.string(from: startOfDay))
        case .last7:
            let weekAgo = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            return (f.string(from: weekAgo), f.string(from: Date()))
        case .thisMonth:
            let comps = cal.dateComponents([.year, .month], from: Date())
            let monthStart = cal.date(from: comps) ?? Date()
            return (f.string(from: monthStart), f.string(from: Date()))
        case .custom:
            // Apply inclusive end-of-day on customTo so a same-day pick
            // (today → today) matches rows created later in the day.
            let endOfDay = cal.date(
                bySettingHour: 23, minute: 59, second: 59,
                of: cal.startOfDay(for: customTo)
            ) ?? customTo
            return (f.string(from: cal.startOfDay(for: customFrom)), f.string(from: endOfDay))
        }
    }

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
        // Forward the picked range to every analytics endpoint so the
        // funnel / win-rate / forecast all stay coherent with the same
        // window the headline numbers respect.
        let r = rangeISO
        do {
            async let summaryTask = api.dashboardSummary(from: r.from, to: r.to)
            async let funnelTask  = api.funnel(from: r.from, to: r.to)
            async let winTask     = api.winRate(from: r.from, to: r.to)
            async let forecastTask = api.forecast(from: r.from, to: r.to)
            async let targetTask  = api.myTarget()
            self.summary = try await summaryTask
            self.funnel  = (try? await funnelTask) ?? []
            self.winRate = (try? await winTask) ?? []
            self.forecast = (try? await forecastTask) ?? []
            self.target  = await targetTask
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

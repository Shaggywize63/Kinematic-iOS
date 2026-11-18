import Foundation
import Combine

/// Backs `SalespersonDetailView` — one rep's sales & target drill-down plus the
/// leads assigned to them. The detail endpoint is manager-gated; a 403 (or any
/// failure) leaves `detail` nil and the view shows a graceful empty state.
@MainActor
final class SalespersonDetailViewModel: ObservableObject {
    @Published var detail: SalespersonTargetDetail?
    @Published var leads: [Lead] = []
    @Published var loadingDetail = true
    @Published var month: String
    @Published var statusFilter: String?

    /// The latest month that can be viewed (no future months).
    let maxMonth: String
    private let userId: String
    private let api = CRMService.shared
    private var started = false

    init(userId: String) {
        self.userId = userId
        let m = Self.currentISTMonth()
        self.month = m
        self.maxMonth = m
    }

    /// The rep's name, resolved from the detail payload (fallback for the title).
    var displayName: String { detail?.name?.isEmpty == false ? detail!.name! : "Salesperson" }

    var shownLeads: [Lead] {
        guard let f = statusFilter else { return leads }
        return leads.filter { $0.status == f }
    }
    var leadStatuses: [String] {
        var seen = Set<String>(); var out: [String] = []
        for s in leads.compactMap({ $0.status }) where !s.isEmpty && seen.insert(s).inserted { out.append(s) }
        return out
    }

    func start() async {
        if started { return }
        started = true
        await loadLeads()
        await loadDetail()
    }

    func loadDetail() async {
        loadingDetail = true
        detail = try? await api.salespersonTarget(userId: userId, month: month)
        loadingDetail = false
    }

    private func loadLeads() async {
        leads = (try? await api.listLeadsPage(page: 1, ownerId: userId))?.leads ?? []
    }

    func prevMonth() {
        month = Self.shiftMonth(month, by: -1)
        Task { await loadDetail() }
    }
    func nextMonth() {
        let next = Self.shiftMonth(month, by: 1)
        guard next <= maxMonth else { return }
        month = next
        Task { await loadDetail() }
    }

    var canGoNext: Bool { month < maxMonth }

    // MARK: Month helpers ("YYYY-MM", IST)
    static func currentISTMonth() -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Kolkata") ?? .current
        let c = cal.dateComponents([.year, .month], from: Date())
        return String(format: "%04d-%02d", c.year ?? 1970, c.month ?? 1)
    }
    static func shiftMonth(_ ym: String, by delta: Int) -> String {
        let parts = ym.split(separator: "-")
        guard parts.count == 2, let y = Int(parts[0]), let m = Int(parts[1]) else { return ym }
        let total = y * 12 + (m - 1) + delta
        return String(format: "%04d-%02d", total / 12, total % 12 + 1)
    }
}

import Foundation
import Combine

@MainActor
final class DealsViewModel: ObservableObject {
    @Published var deals: [Deal] = []
    @Published var statusFilter: String = "open"
    @Published var dateFrom: Date? = nil
    @Published var dateTo: Date? = nil
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// See LeadsViewModel.showingCached — drives the "Cached · Xm ago"
    /// chip in the list header. Same lifecycle: set on cache hit at init,
    /// cleared after a successful network refresh, sticky on failure.
    @Published var showingCached: Bool = false

    private let api = CRMService.shared

    init() {
        if let cached = CRMReadCache.shared.load(.deals, as: [Deal].self) {
            self.deals = cached
            self.showingCached = true
        }
    }

    private static let isoDate: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            deals = try await api.listDeals(
                status: statusFilter == "all" ? nil : statusFilter,
                from: dateFrom.map { Self.isoDate.string(from: $0) },
                to: dateTo.map { Self.isoDate.string(from: $0) }
            )
            showingCached = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func create(body: [String: Any]) async {
        let d = await api.createDealOrQueue(body)
        deals.insert(d, at: 0)
    }

    func win(_ deal: Deal) async {
        if let updated = await api.winDealOrQueue(id: deal.id, amount: deal.amount) {
            replace(updated)
        }
        // nil → enqueued. UI keeps the existing row; the banner / pending
        // sync sheet surfaces the pending change.
    }

    func lose(_ deal: Deal, reason: String) async {
        if let updated = await api.loseDealOrQueue(id: deal.id, reason: reason) {
            replace(updated)
        }
    }

    private func replace(_ d: Deal) {
        if let idx = deals.firstIndex(where: { $0.id == d.id }) { deals[idx] = d }
    }
}

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

    private let api = CRMService.shared

    // Full ISO8601 timestamp (yyyy-MM-dd was silently dropping today's
    // rows — PostgREST treats a bare date `to` as midnight-UTC).
    private static let isoTimestamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withTimeZone]
        return f
    }()

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            deals = try await api.listDeals(
                status: statusFilter == "all" ? nil : statusFilter,
                from: dateFrom.map { Self.isoTimestamp.string(from: $0) },
                to: dateTo.map { Self.isoTimestamp.string(from: $0) }
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func create(body: [String: Any]) async {
        do {
            let d = try await api.createDeal(body)
            deals.insert(d, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func win(_ deal: Deal) async {
        do {
            let updated = try await api.winDeal(id: deal.id, amount: deal.amount)
            replace(updated)
        } catch { errorMessage = error.localizedDescription }
    }

    func lose(_ deal: Deal, reason: String) async {
        do {
            let updated = try await api.loseDeal(id: deal.id, reason: reason)
            replace(updated)
        } catch { errorMessage = error.localizedDescription }
    }

    private func replace(_ d: Deal) {
        if let idx = deals.firstIndex(where: { $0.id == d.id }) { deals[idx] = d }
    }
}

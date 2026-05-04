import Foundation

@MainActor
final class DealsViewModel: ObservableObject {
    @Published var deals: [Deal] = []
    @Published var statusFilter: String = "open"
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = CRMService.shared

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            deals = try await api.listDeals(status: statusFilter == "all" ? nil : statusFilter)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func create(name: String, accountId: String?, amount: Double, stageId: String?) async {
        do {
            var body: [String: Any] = ["name": name, "amount": amount, "status": "open"]
            if let accountId { body["account_id"] = accountId }
            if let stageId { body["stage_id"] = stageId }
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

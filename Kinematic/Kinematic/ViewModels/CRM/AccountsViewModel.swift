import Foundation
import Combine

@MainActor
final class AccountsViewModel: ObservableObject {
    @Published var accounts: [CRMAccount] = []
    @Published var search: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    /// See LeadsViewModel.showingCached — drives the "Cached · Xm ago" chip.
    @Published var showingCached: Bool = false

    private let api = CRMService.shared

    init() {
        if let cached = CRMReadCache.shared.load(.accounts, as: [CRMAccount].self) {
            self.accounts = cached
            self.showingCached = true
        }
    }

    var filtered: [CRMAccount] {
        guard !search.isEmpty else { return accounts }
        let q = search.lowercased()
        return accounts.filter { $0.name.lowercased().contains(q) }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            accounts = try await api.listAccounts(search: search.isEmpty ? nil : search)
            showingCached = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func create(body: [String: Any]) async {
        let a = await api.createAccountOrQueue(body)
        accounts.insert(a, at: 0)
    }
}

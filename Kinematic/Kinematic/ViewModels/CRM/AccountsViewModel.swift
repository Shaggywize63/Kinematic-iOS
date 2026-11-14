import Foundation
import Combine

@MainActor
final class AccountsViewModel: ObservableObject {
    @Published var accounts: [CRMAccount] = []
    @Published var search: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = CRMService.shared

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
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func create(body: [String: Any]) async {
        do {
            let a = try await api.createAccount(body)
            accounts.insert(a, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Throwing create used by the New Account form so it can tell a duplicate (409) from a generic failure and
    /// keep itself open. Inserts the created account at the top of the list and hands it back.
    func add(body: [String: Any]) async throws -> CRMAccount {
        let a = try await api.createAccount(body)
        accounts.insert(a, at: 0)
        return a
    }
}

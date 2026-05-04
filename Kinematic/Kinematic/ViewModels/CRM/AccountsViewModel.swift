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

    func create(name: String, industry: String, website: String, phone: String) async {
        do {
            let body: [String: Any] = [
                "name": name, "industry": industry,
                "website": website, "phone": phone
            ]
            let a = try await api.createAccount(body)
            accounts.insert(a, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

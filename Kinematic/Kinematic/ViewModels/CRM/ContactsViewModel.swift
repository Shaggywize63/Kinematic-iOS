import Foundation
import Combine

@MainActor
final class ContactsViewModel: ObservableObject {
    @Published var contacts: [Contact] = []
    @Published var search: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = CRMService.shared

    var filtered: [Contact] {
        guard !search.isEmpty else { return contacts }
        let q = search.lowercased()
        return contacts.filter {
            $0.displayName.lowercased().contains(q) ||
            ($0.email ?? "").lowercased().contains(q)
        }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            contacts = try await api.listContacts(search: search.isEmpty ? nil : search)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func create(body: [String: Any]) async {
        do {
            let c = try await api.createContact(body)
            contacts.insert(c, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

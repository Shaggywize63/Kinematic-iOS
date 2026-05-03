import Foundation

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

    func create(firstName: String, lastName: String, email: String, phone: String, accountId: String?) async {
        do {
            var body: [String: Any] = [
                "first_name": firstName, "last_name": lastName,
                "email": email, "phone": phone
            ]
            if let accountId { body["account_id"] = accountId }
            let c = try await api.createContact(body)
            contacts.insert(c, at: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

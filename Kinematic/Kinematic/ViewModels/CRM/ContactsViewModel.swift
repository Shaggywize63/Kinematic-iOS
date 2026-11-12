import Foundation
import Combine

@MainActor
final class ContactsViewModel: ObservableObject {
    @Published var contacts: [Contact] = []
    @Published var search: String = ""
    @Published var dateFrom: Date? = nil
    @Published var dateTo: Date? = nil
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = CRMService.shared

    /// ISO-8601 parser for `created_at` strings returned by the backend.
    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoParserNoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static func parseCreatedAt(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return isoParser.date(from: s) ?? isoParserNoFraction.date(from: s)
    }

    var filtered: [Contact] {
        let q = search.lowercased()
        let fromStart = dateFrom.map { Calendar.current.startOfDay(for: $0) }
        let toEnd = dateTo.map { Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: Calendar.current.startOfDay(for: $0)) ?? $0 }
        return contacts.filter { c in
            let matchesSearch = q.isEmpty ||
                c.displayName.lowercased().contains(q) ||
                (c.email ?? "").lowercased().contains(q)
            guard matchesSearch else { return false }
            if fromStart == nil && toEnd == nil { return true }
            guard let created = Self.parseCreatedAt(c.createdAt) else { return false }
            if let f = fromStart, created < f { return false }
            if let t = toEnd, created > t { return false }
            return true
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

    /// Spark & Ray: put `contact` on `account` (PATCH /crm/contacts/:id { account_id }) and swap the row in
    /// the list. Returns the server's message on failure, nil on success.
    func setAccount(contact: Contact, account: CRMAccount) async -> String? {
        do {
            let updated = try await api.patchContact(id: contact.id, body: ["account_id": account.id])
            if let i = contacts.firstIndex(where: { $0.id == contact.id }) { contacts[i] = updated }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Delete `contact` (DELETE /crm/contacts/:id), drop its row from the list and refresh. Returns the server's
    /// message on failure (the row stays), nil on success.
    func delete(contact: Contact) async -> String? {
        do {
            try await api.deleteContact(id: contact.id)
            contacts = ContactDeletion.removing(id: contact.id, from: contacts)
            await refresh()
            return nil
        } catch {
            return error.localizedDescription
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

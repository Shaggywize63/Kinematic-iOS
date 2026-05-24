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
    /// See LeadsViewModel.showingCached — drives the "Cached · Xm ago" chip.
    @Published var showingCached: Bool = false

    private let api = CRMService.shared

    init() {
        if let cached = CRMReadCache.shared.load(.contacts, as: [Contact].self) {
            self.contacts = cached
            self.showingCached = true
        }
    }

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
            showingCached = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func create(body: [String: Any]) async {
        let c = await api.createContactOrQueue(body)
        contacts.insert(c, at: 0)
    }
}

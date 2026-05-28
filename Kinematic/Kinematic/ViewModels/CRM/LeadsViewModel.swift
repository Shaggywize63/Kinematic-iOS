import Foundation
import Combine

@MainActor
final class LeadsViewModel: ObservableObject {
    @Published var leads: [Lead] = []
    @Published var search: String = ""
    @Published var statusFilter: String = "all"
    @Published var dateFrom: Date? = nil
    @Published var dateTo: Date? = nil
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = CRMService.shared
    private let location = CRMLocationStore.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Re-fetch when location filter changes
        location.$state.combineLatest(location.$city)
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in Task { await self?.refresh() } }
            .store(in: &cancellables)
    }

    var filtered: [Lead] {
        leads.filter { lead in
            (statusFilter == "all" || (lead.status ?? "") == statusFilter) &&
            (search.isEmpty || lead.displayName.lowercased().contains(search.lowercased())
             || (lead.company ?? "").lowercased().contains(search.lowercased()))
        }
    }

    private static let isoDate: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            leads = try await api.listLeads(
                status: statusFilter == "all" ? nil : statusFilter,
                search: search.isEmpty ? nil : search,
                city: location.city,
                state: location.state,
                from: dateFrom.map { Self.isoDate.string(from: $0) },
                to: dateTo.map { Self.isoDate.string(from: $0) }
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// User-visible result so the form can show "Saved offline" vs. "Saved".
    enum CreateOutcome { case online, offline, error(String) }

    func create(body: [String: Any]) async -> CreateOutcome {
        let clientId = CRMClientScope.selectedClientId()
        switch await api.createLeadOfflineAware(body: body, clientId: clientId) {
        case .success(let lead):
            leads.insert(lead, at: 0)
            return .online
        case .queued:
            // Don't insert a synthesised row — the rep sees it in the
            // "Pending sync" badge instead. Once the queue drains and
            // the server returns the real row, the next list refresh
            // surfaces it.
            return .offline
        case .error(let msg):
            errorMessage = msg
            return .error(msg)
        }
    }
}

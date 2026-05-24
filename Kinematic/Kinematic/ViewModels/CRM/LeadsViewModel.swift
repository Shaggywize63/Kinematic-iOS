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
    /// True when the list is rendering data from the on-disk cache rather
    /// than a fresh network response. Flips off after the first successful
    /// refresh; stays on through network failures so the UI keeps telling
    /// the rep "you're looking at older data". Drives the "Cached · Xm
    /// ago" chip in the list header.
    @Published var showingCached: Bool = false

    private let api = CRMService.shared
    private let location = CRMLocationStore.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Cold-start: paint the last cached snapshot instantly so the list
        // never shows an empty state while the network fetch is in flight.
        if let cached = CRMReadCache.shared.load(.leads, as: [Lead].self) {
            self.leads = cached
            self.showingCached = true
        }
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
            // Successful network refresh — the chip can disappear. We
            // deliberately don't flip this off on `catch` so the user
            // keeps seeing the "Cached" hint when network is unreachable.
            showingCached = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func create(body: [String: Any]) async {
        // Offline-aware: on network failure the lead is enqueued and an
        // optimistic row (id="pending:<uuid>") is returned so the list
        // surfaces it immediately. CRMSyncEngine swaps in the real id on
        // the next successful flush.
        let lead = await api.createLeadOrQueue(body)
        leads.insert(lead, at: 0)
    }
}

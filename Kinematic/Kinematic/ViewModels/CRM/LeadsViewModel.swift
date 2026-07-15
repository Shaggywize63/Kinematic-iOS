import Foundation
import Combine

@MainActor
final class LeadsViewModel: ObservableObject {
    @Published var leads: [Lead] = []
    @Published var search: String = ""
    @Published var statusFilter: String = "all"
    @Published var dateFrom: Date? = nil
    @Published var dateTo: Date? = nil
    // Web-parity filters. Score Grade + Minimum Score were removed at
    // the user's request — the AI grade is no longer a primary filter
    // affordance, and the slider+chip combo was clutter on every screen.
    @Published var lifecycleFilter: String = "all"  // all | subscriber | lead | mql | sql | opportunity | customer
    @Published var convertedFilter: String = "all"  // all | yes | no
    @Published var ownerFilter: String = "all"      // "all" or an owner user id
    @Published var sourceFilter: String = "all"     // "all" or a lead-source id
    // Sorting. sortKey "recent" = backend default; others map to ?sort=&order=.
    @Published var sortKey: String = "recent"
    @Published var sortAscending: Bool = false
    // Options for the owner / source pickers (loaded lazily when the sheet opens).
    @Published var owners: [AssignableUser] = []
    @Published var sources: [CRMLeadSource] = []
    @Published var isLoading = false
    @Published var isLoadingMore = false
    @Published var errorMessage: String?
    /// Server-reported total across all pages (the API caps each page at 200).
    @Published var total: Int = 0
    private var page = 1
    var hasMore: Bool { leads.count < total }

    /// Count of non-default advanced filters — drives the badge on the
    /// Filters button so reps can see a filter is active.
    var activeFilterCount: Int {
        var n = 0
        if lifecycleFilter != "all" { n += 1 }
        if convertedFilter != "all" { n += 1 }
        if ownerFilter != "all" { n += 1 }
        if sourceFilter != "all" { n += 1 }
        if dateFrom != nil || dateTo != nil { n += 1 }
        return n
    }

    func resetFilters() {
        lifecycleFilter = "all"; convertedFilter = "all"
        ownerFilter = "all"; sourceFilter = "all"
        dateFrom = nil; dateTo = nil
    }

    /// Lazily load the owner + source picker options the first time the filter
    /// sheet opens. Both are best-effort (empty on error / 403).
    func loadFilterOptions() async {
        if owners.isEmpty { owners = await api.listAssignableUsers() }
        if sources.isEmpty { sources = await api.listLeadSources() }
    }

    private let api = CRMService.shared
    private let location = CRMLocationStore.shared
    private var cancellables = Set<AnyCancellable>()
    /// In-flight debounce for search keystrokes — cancelled and replaced on
    /// every change so only the settled query (~300ms idle) hits the server.
    private var searchDebounceTask: Task<Void, Never>?

    init() {
        // Re-fetch when location filter changes
        location.$state.combineLatest(location.$city)
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in Task { await self?.refresh() } }
            .store(in: &cancellables)
    }

    // The server already applies status/search/filters, so the list shows the
    // rows as-fetched (kept as a computed for the existing call-sites).
    var filtered: [Lead] { leads }

    // Full ISO8601 with timezone — yyyy-MM-dd was the bug: the backend
    // does `lte('created_at', '2026-06-21')` which PostgREST treats as
    // `< 2026-06-21 00:00 UTC`, silently excluding every lead created
    // *during* today. With a full timestamp the comparison works as the
    // rep expects regardless of locale.
    private static let isoTimestamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withTimeZone]
        return f
    }()

    private func fetchPage(_ p: Int) async throws -> (leads: [Lead], total: Int) {
        try await api.listLeadsPage(
            page: p,
            status: statusFilter == "all" ? nil : statusFilter,
            search: search.isEmpty ? nil : search,
            city: location.city,
            state: location.state,
            from: dateFrom.map { Self.isoTimestamp.string(from: $0) },
            to: dateTo.map { Self.isoTimestamp.string(from: $0) },
            scoreGrade: nil,
            scoreGte: nil,
            lifecycle: lifecycleFilter == "all" ? nil : lifecycleFilter,
            isConverted: convertedFilter == "all" ? nil : (convertedFilter == "yes"),
            ownerId: ownerFilter == "all" ? nil : ownerFilter,
            sourceId: sourceFilter == "all" ? nil : sourceFilter,
            sort: sortKey == "recent" ? nil : sortKey,
            order: sortKey == "recent" ? nil : (sortAscending ? "asc" : "desc")
        )
    }

    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            page = 1
            let (rows, t) = try await fetchPage(1)
            leads = rows
            total = t
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Server-side search with a ~300ms keystroke debounce. Each call
    /// cancels the previous pending refresh so fast typing produces one
    /// request for the settled query instead of one per character. The
    /// query itself rides `?q=` via fetchPage — the server matches across
    /// the whole book, not just the locally-loaded pages.
    func searchChanged() {
        searchDebounceTask?.cancel()
        searchDebounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    /// Load the next page and append. Called when the last row appears.
    func loadMoreIfNeeded() async {
        guard hasMore, !isLoadingMore, !isLoading else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let next = page + 1
            let (rows, t) = try await fetchPage(next)
            // Guard against duplicates if a refresh raced in.
            let existing = Set(leads.map { $0.id })
            leads.append(contentsOf: rows.filter { !existing.contains($0.id) })
            total = t
            page = next
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

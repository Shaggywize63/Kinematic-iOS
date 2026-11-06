import Foundation
import Combine

/// Loads and caches the tenant's industries list (`config.industries` from `GET /crm/settings`) for Spark &
/// Ray, and keeps `SparkIndustries.active` pointing at it so every dropdown, colour dot, badge, map pin and
/// map filter reads the same list. Views that draw those colours observe `IndustriesStore.shared` so they
/// repaint when the list arrives.
///
/// Every other tenant is untouched: for a non-Spark client the store makes no request and holds the
/// built-in defaults.
@MainActor
final class IndustriesStore: ObservableObject {
    static let shared = IndustriesStore()

    @Published private(set) var config: IndustriesConfig = .defaults
    /// True once a load finished for the current client (success or not).
    @Published private(set) var didLoad = false

    /// The client the current `config` belongs to; a different client reloads.
    private var loadedScope: String? = nil
    /// A `loadIfNeeded` request is already in flight (many badges ask at once; only one fetch is made).
    private var loadInFlight = false

    init() {}

    /// Load once per client (cheap to call from every screen that draws industries).
    func loadIfNeeded() async {
        let scope = CRMClientScope.effectiveClientId()
        if didLoad, loadedScope == scope { return }
        if loadInFlight { return }
        loadInFlight = true
        defer { loadInFlight = false }
        await load()
    }

    /// Fetch the list. `isSpark`, `scope`, `defaults` and `fetch` are test seams (production passes none).
    /// A failed request keeps the cached (or current) list rather than falling back to the defaults.
    func load(
        isSpark: Bool = SparkJourney.isActive,
        scope: String? = CRMClientScope.effectiveClientId(),
        defaults: UserDefaults = .standard,
        using fetch: () async -> CRMService.CRMSettingsRaw? = { await CRMService.shared.getCRMSettings() }
    ) async {
        guard isSpark else {
            apply(.defaults)
            loadedScope = scope
            didLoad = true
            return
        }
        let key = IndustriesCache.key(clientId: scope)
        if loadedScope != scope {
            // A different client (or the first load): start from its cached list, else the defaults, so
            // nothing from another client's list lingers if the request below fails.
            apply(IndustriesCache.read(key: key, in: defaults) ?? .defaults)
        }
        if let raw = await fetch() {
            let fresh = IndustriesConfig.parse(settings: raw)
            apply(fresh)
            IndustriesCache.write(fresh, key: key, in: defaults)
        }
        loadedScope = scope
        didLoad = true
    }

    private func apply(_ newConfig: IndustriesConfig) {
        config = newConfig
        SparkIndustries.active = newConfig
    }
}

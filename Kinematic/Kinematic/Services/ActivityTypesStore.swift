import Foundation
import Combine

/// Holds the org's activity types (built-ins + custom ones from Settings) for every screen that shows or picks a
/// type: the compose sheet, the list's filter chips and the activity rows. One fetch is shared; a failed or empty
/// load keeps the built-in fallback so nothing ever renders without types.
@MainActor
final class ActivityTypesStore: ObservableObject {
    static let shared = ActivityTypesStore()

    /// Every active type, for names / icons / colours of any slug.
    @Published private(set) var types: [ActivityTypeDef] = ActivityTypes.fallback

    private var loadedAt: Date?
    private var inFlight = false
    private var observer: NSObjectProtocol?

    private init() {
        // A different client selection can carry different custom types.
        observer = NotificationCenter.default.addObserver(forName: CRMClientScope.didChange, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.load(force: true) }
        }
    }

    /// Fetch the types unless a fresh copy (10 minutes) is held. Safe to call from every screen's `.task`.
    func load(force: Bool = false) async {
        if inFlight { return }
        if !force, let at = loadedAt, Date().timeIntervalSince(at) < 600 { return }
        inFlight = true
        defer { inFlight = false }
        guard let fetched = await CRMService.shared.listActivityTypes() else { return }
        types = ActivityTypes.sanitize(server: fetched)
        loadedAt = Date()
    }

    /// The types a person can pick on `scheduled` (reminder) or log screens, keeping `current` selectable.
    func composerTypes(scheduled: Bool, ensuring current: String? = nil) -> [ActivityTypeDef] {
        ActivityTypes.composerTypes(types, scheduled: scheduled, ensuring: current)
    }

    func name(for slug: String?) -> String { ActivityTypes.name(for: slug, in: types) }
    func def(for slug: String?) -> ActivityTypeDef? { ActivityTypes.def(for: slug, in: types) }
}

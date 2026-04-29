import Foundation

/// In-memory TTL cache for the slow read-heavy outlet endpoints so the FE's
/// "Assigned Outlets" screen feels instant after the first fetch. This brings
/// iOS to parity with the Android OkHttp HTTP cache that ships on the same
/// branch.
///
/// Usage:
/// ```
/// if let cached = OutletCache.shared.get(MobileHomeResponse.self, key: .mobileHome) {
///     return cached
/// }
/// let fresh = try await network.getMobileHome()
/// OutletCache.shared.put(fresh, key: .mobileHome)
/// ```
final class OutletCache {
    static let shared = OutletCache()

    /// Distinct cache slots. Keep this small — every slot is fetched on home
    /// screen launch, so they collectively dominate startup time.
    enum Key: String {
        case mobileHome
        case routePlan
        case stores
        case executives
    }

    /// 30 seconds matches the Android Cache-Control max-age. Long enough to
    /// absorb pull-to-refresh tap-storms, short enough that a freshly assigned
    /// outlet appears on the next screen visit.
    private let defaultTTL: TimeInterval = 30

    private let lock = NSLock()
    private var entries: [Key: Entry] = [:]

    private struct Entry {
        let value: Any
        let expiresAt: Date
    }

    private init() {}

    /// Returns the cached value if it has not expired, or `nil` otherwise.
    func get<T>(_ type: T.Type, key: Key) -> T? {
        lock.lock(); defer { lock.unlock() }
        guard let entry = entries[key] else { return nil }
        if Date() >= entry.expiresAt {
            entries.removeValue(forKey: key)
            return nil
        }
        return entry.value as? T
    }

    /// Stores `value` for `ttl` seconds (defaults to 30s).
    func put<T>(_ value: T, key: Key, ttl: TimeInterval? = nil) {
        lock.lock(); defer { lock.unlock() }
        let expires = Date().addingTimeInterval(ttl ?? defaultTTL)
        entries[key] = Entry(value: value, expiresAt: expires)
    }

    /// Forces a refresh on the next read. Call this after a write that should
    /// invalidate the cached snapshot (e.g. logging a visit, completing a
    /// route, switching org).
    func invalidate(_ key: Key) {
        lock.lock(); defer { lock.unlock() }
        entries.removeValue(forKey: key)
    }

    /// Drop everything. Call on logout / org switch.
    func invalidateAll() {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll()
    }
}

import SwiftUI
import Combine

/// Global CRM location filter — single source of truth for the
/// state/city dropdowns rendered at the top of the CRM tabs.
/// Mirrors the dashboard's Zustand store; persists via UserDefaults.
final class CRMLocationStore: ObservableObject {
    static let shared = CRMLocationStore()

    /// The UserDefaults keys of the persisted picks (also listed in `SessionCleanup`, which wipes them at sign-out).
    static let stateKey = "crm.location.state"
    static let cityKey = "crm.location.city"

    @Published var state: String? {
        didSet { UserDefaults.standard.setValue(state, forKey: Self.stateKey) }
    }
    @Published var city: String? {
        didSet { UserDefaults.standard.setValue(city, forKey: Self.cityKey) }
    }

    private init() {
        state = UserDefaults.standard.string(forKey: Self.stateKey)
        city = UserDefaults.standard.string(forKey: Self.cityKey)
    }

    func setState(_ next: String?) {
        state = next
        city = nil
    }
    func clear() {
        state = nil
        city = nil
    }
    var isActive: Bool { state != nil || city != nil }
}

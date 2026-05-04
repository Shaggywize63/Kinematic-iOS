import SwiftUI
import Combine

/// Global CRM location filter — single source of truth for the
/// state/city dropdowns rendered at the top of the CRM tabs.
/// Mirrors the dashboard's Zustand store; persists via UserDefaults.
final class CRMLocationStore: ObservableObject {
    static let shared = CRMLocationStore()

    @Published var state: String? {
        didSet { UserDefaults.standard.setValue(state, forKey: "crm.location.state") }
    }
    @Published var city: String? {
        didSet { UserDefaults.standard.setValue(city, forKey: "crm.location.city") }
    }

    private init() {
        state = UserDefaults.standard.string(forKey: "crm.location.state")
        city = UserDefaults.standard.string(forKey: "crm.location.city")
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

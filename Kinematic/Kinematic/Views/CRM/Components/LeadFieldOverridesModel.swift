import Foundation
import Combine

/// iOS counterpart of `kinematic-dashboard/src/lib/crmFieldOverrides.ts`.
/// Loads the admin's built-in field overrides from
/// `/api/v1/crm/settings` once and exposes the same `isHidden(key)` /
/// `labelFor(key, default)` / `requiredFor(key, default)` helpers the
/// dashboard uses, so the create / edit forms surface the same
/// "hidden / required / relabel" decisions the admin configured on the
/// web console.
@MainActor
final class LeadFieldOverridesModel: ObservableObject {
    @Published private(set) var overrides: [String: FieldOverride] = [:]
    @Published private(set) var businessType: String = "both"

    struct FieldOverride: Decodable {
        let label: String?
        let required: Bool?
        let hidden: Bool?
    }

    private struct SettingsResponse: Decodable {
        let data: SettingsData?
        struct SettingsData: Decodable {
            let business_type: String?
            let config: Config?
            struct Config: Decodable {
                let field_overrides: [String: FieldOverride]?
            }
        }
    }

    /// Pull the per-tenant overrides + business_type once. Best-effort —
    /// failures leave the form in its built-in default state so a 4xx
    /// from /settings never blocks lead capture.
    func load() async {
        do {
            let url = URL(string: "https://api.kinematicapp.com/api/v1/crm/settings")!
            var req = URLRequest(url: url)
            req.timeoutInterval = 20
            if let token = CRMService.shared.authToken {
                req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
            let (data, _) = try await URLSession.shared.data(for: req)
            let decoded = try JSONDecoder().decode(SettingsResponse.self, from: data)
            overrides = decoded.data?.config?.field_overrides ?? [:]
            businessType = decoded.data?.business_type ?? "both"
        } catch { /* silent fallback */ }
    }

    /// Look up a field key for the active business-type scope. Scoped
    /// values (`lead.key@b2c`) win over the universal entry on every
    /// property they define, mirroring the web `buildFieldHelpers` merge.
    private func lookup(_ key: String, isB2C: Bool) -> FieldOverride? {
        let uni = overrides["lead.\(key)"]
        let scoped = overrides["lead.\(key)@\(isB2C ? "b2c" : "b2b")"]
        if uni == nil && scoped == nil { return nil }
        // Merge: scoped wins per-property.
        return FieldOverride(
            label: scoped?.label ?? uni?.label,
            required: scoped?.required ?? uni?.required,
            hidden: scoped?.hidden ?? uni?.hidden,
        )
    }

    func isHidden(_ key: String, isB2C: Bool) -> Bool {
        lookup(key, isB2C: isB2C)?.hidden == true
    }
    func labelFor(_ key: String, defaultLabel: String, isB2C: Bool) -> String {
        lookup(key, isB2C: isB2C)?.label ?? defaultLabel
    }
    func requiredFor(_ key: String, defaultRequired: Bool, isB2C: Bool) -> Bool {
        lookup(key, isB2C: isB2C)?.required ?? defaultRequired
    }
}

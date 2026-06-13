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

    struct FieldOverride {
        let label: String?
        let required: Bool?
        let hidden: Bool?
    }

    /// Pull the per-tenant overrides + business_type once. Routes through
    /// CRMService.getCRMSettings() so we reuse the project's auth +
    /// transport instead of poking at private state on the service.
    func load() async {
        guard let raw = await CRMService.shared.getCRMSettings() else { return }
        if let bt = raw.business_type { businessType = bt }
        // Drill into config.field_overrides which is `[String:
        // {label?, required?, hidden?}]`. AnyJSON exposes a typed
        // `.any` graph so we walk it without a second decode.
        guard
            case let .object(cfg)? = raw.config,
            case let .object(fo)? = cfg["field_overrides"]
        else { return }
        var out: [String: FieldOverride] = [:]
        for (key, val) in fo {
            guard case let .object(props) = val else { continue }
            var label: String?
            var required: Bool?
            var hidden: Bool?
            if case let .string(s)? = props["label"]    { label = s }
            if case let .bool(b)?   = props["required"] { required = b }
            if case let .bool(b)?   = props["hidden"]   { hidden = b }
            out[key] = FieldOverride(label: label, required: required, hidden: hidden)
        }
        overrides = out
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

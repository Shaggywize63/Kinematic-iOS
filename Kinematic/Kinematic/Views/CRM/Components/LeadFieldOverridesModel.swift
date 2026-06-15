import Foundation
import Combine

/// iOS counterpart of `kinematic-dashboard/src/lib/crmFieldOverrides.ts`.
/// Loads the admin's built-in field overrides from
/// `/api/v1/crm/settings` once and exposes the same `isHidden(key)` /
/// `labelFor(key, default)` / `requiredFor(key, default)` helpers the
/// dashboard uses, so the create / edit forms surface the same
/// "hidden / required / relabel" decisions the admin configured on the
/// web console.
///
/// Perf note: SwiftUI re-runs the form body on every keystroke. Reps
/// reported "too much lag" while typing into the lead form because
/// each render triggered ~45 lookups (15 fields × 3 helper calls),
/// each one doing 2 dict reads + a FieldOverride struct allocation +
/// per-property merge. We now pre-compute the merged (scoped over
/// universal) result for both B2C and B2B scopes once at `load()`
/// time and stash it in two flat dicts. Per-render calls are then a
/// single dict lookup.
@MainActor
final class LeadFieldOverridesModel: ObservableObject {
    @Published private(set) var overrides: [String: FieldOverride] = [:]
    @Published private(set) var businessType: String = "both"
    // Pre-merged per-scope snapshots — see perf note above.
    @Published private(set) var b2cMerged: [String: FieldOverride] = [:]
    @Published private(set) var b2bMerged: [String: FieldOverride] = [:]
    /// True once the /api/v1/crm/settings request has completed (success
    /// or empty). The lead form defers rendering admin-gated rows until
    /// this flips so it doesn't race the network and briefly show fields
    /// (and default labels) the admin had hidden.
    @Published private(set) var didLoad: Bool = false

    struct FieldOverride {
        let label: String?
        let required: Bool?
        let hidden: Bool?
    }

    /// Pull the per-tenant overrides + business_type once. Routes through
    /// CRMService.getCRMSettings() so we reuse the project's auth +
    /// transport instead of poking at private state on the service.
    func load() async {
        // Always flip didLoad=true at the end so the form un-blocks
        // even if the tenant has no overrides configured.
        defer { didLoad = true }
        guard let raw = await CRMService.shared.getCRMSettings() else { return }
        if let bt = raw.business_type { businessType = bt }
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
        b2cMerged = buildMerged(for: true, from: out)
        b2bMerged = buildMerged(for: false, from: out)
    }

    /// Walk the raw `lead.<key>` and `lead.<key>@scope` entries and emit a
    /// flat `key → mergedOverride` dict for the requested scope. The
    /// merge rule is "scoped wins per-property" — same as the web's
    /// `buildFieldHelpers`.
    private func buildMerged(for isB2C: Bool, from raw: [String: FieldOverride]) -> [String: FieldOverride] {
        let suffix = "@" + (isB2C ? "b2c" : "b2b")
        var keys = Set<String>()
        for k in raw.keys {
            guard k.hasPrefix("lead.") else { continue }
            // Strip the optional scope tail so universal + scoped keys
            // collapse to the same field name in the merged dict.
            let bare = k.split(separator: "@").first.map(String.init) ?? k
            // Drop the "lead." prefix to match how callers index us
            // (`isHidden("first_name")`, not `isHidden("lead.first_name")`).
            let field = String(bare.dropFirst("lead.".count))
            keys.insert(field)
        }
        var out: [String: FieldOverride] = [:]
        out.reserveCapacity(keys.count)
        for field in keys {
            let uni = raw["lead.\(field)"]
            let scoped = raw["lead.\(field)\(suffix)"]
            if uni == nil && scoped == nil { continue }
            out[field] = FieldOverride(
                label: scoped?.label ?? uni?.label,
                required: scoped?.required ?? uni?.required,
                hidden: scoped?.hidden ?? uni?.hidden,
            )
        }
        return out
    }

    /// O(1) lookup against the pre-merged scope snapshot.
    private func lookup(_ key: String, isB2C: Bool) -> FieldOverride? {
        (isB2C ? b2cMerged : b2bMerged)[key]
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

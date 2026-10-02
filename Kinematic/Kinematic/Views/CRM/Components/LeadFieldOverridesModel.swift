import Foundation
import Combine
import SwiftUI

/// One entry in a tenant's custom lead-status set, parsed from
/// `config.lead_statuses` on `/api/v1/crm/settings`. A tenant without a
/// custom set yields an empty `leadStatuses`, and each picker falls back
/// to its existing hardcoded array via `statusOptions(default:)`.
struct LeadStatusOption: Identifiable, Hashable {
    let value: String
    let label: String
    let color: String?   // hex, e.g. "#3B82F6"
    let isWon: Bool
    let isLost: Bool
    var id: String { value }
}

extension Color {
    /// Parse a CSS-style hex string ("#RGB", "#RRGGBB", "#RRGGBBAA") into a
    /// `Color`. Returns nil for anything it can't parse so callers can fall
    /// back to their existing palette. Used to colour custom lead statuses
    /// from the admin-configured hex; the project had no hex initialiser.
    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        guard let int = UInt64(s, radix: 16) else { return nil }
        let r, g, b, a: Double
        switch s.count {
        case 3: // RGB (4-bit each)
            r = Double((int >> 8) & 0xF) / 15.0
            g = Double((int >> 4) & 0xF) / 15.0
            b = Double(int & 0xF) / 15.0
            a = 1.0
        case 6: // RRGGBB
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
            a = 1.0
        case 8: // RRGGBBAA
            r = Double((int >> 24) & 0xFF) / 255.0
            g = Double((int >> 16) & 0xFF) / 255.0
            b = Double((int >> 8) & 0xFF) / 255.0
            a = Double(int & 0xFF) / 255.0
        default:
            return nil
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }
}

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
    /// Tenant's custom lead-status set parsed from `config.lead_statuses`.
    /// Empty when the tenant has no custom set configured — callers then
    /// fall back to their existing hardcoded arrays via `statusOptions`.
    @Published private(set) var leadStatuses: [LeadStatusOption] = []
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
        guard case let .object(cfg)? = raw.config else { return }
        // Custom lead statuses — sibling key of `field_overrides`. Parsed
        // independently so a tenant can configure one without the other;
        // stays empty (→ hardcoded fallback) when the key is absent/empty.
        if case let .array(statusArr)? = cfg["lead_statuses"] {
            leadStatuses = Self.parseStatusOptions(statusArr)
        }
        guard case let .object(fo)? = cfg["field_overrides"] else { return }
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

    /// Test seam: seed the merged snapshots from a raw override map without
    /// touching the network, mirroring exactly what `load()` does after
    /// decoding `/api/v1/crm/settings`. Kept `internal` (not `private`) so
    /// unit tests can exercise the merge/lookup logic deterministically.
    /// Production code paths are unchanged — `load()` still performs the
    /// real network fetch and calls the same `buildMerged`.
    func ingest(rawOverrides: [String: FieldOverride], businessType bt: String? = nil) {
        if let bt { businessType = bt }
        overrides = rawOverrides
        b2cMerged = buildMerged(for: true, from: rawOverrides)
        b2bMerged = buildMerged(for: false, from: rawOverrides)
        didLoad = true
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
    /// True only when an admin EXPLICITLY un-hid the field (persisted
    /// `hidden: false`), as opposed to it merely defaulting to visible.
    /// Business fields (company/title/industry) live on the B2B branch by
    /// default; the forms use this to decide whether to also surface them
    /// on a B2C lead, so tenants that never touched these keys keep the
    /// B2B-only behaviour untouched. Mirrors the web's
    /// `explicitlyShownOnB2C` in the lead create/edit forms.
    func explicitlyShownOnB2C(_ key: String) -> Bool {
        b2cMerged[key]?.hidden == false
    }
    func labelFor(_ key: String, defaultLabel: String, isB2C: Bool) -> String {
        lookup(key, isB2C: isB2C)?.label ?? defaultLabel
    }
    func requiredFor(_ key: String, defaultRequired: Bool, isB2C: Bool) -> Bool {
        lookup(key, isB2C: isB2C)?.required ?? defaultRequired
    }

    // ── Custom lead statuses ───────────────────────────────────────

    /// Returns the tenant's custom status options, or the supplied defaults
    /// mapped into `LeadStatusOption`s when none are configured. Keeps every
    /// picker a one-liner while preserving today's hardcoded behaviour for
    /// tenants without a custom set.
    func statusOptions(default defaults: [String]) -> [LeadStatusOption] {
        if !leadStatuses.isEmpty { return leadStatuses }
        return defaults.map {
            LeadStatusOption(
                value: $0,
                label: $0.capitalized,
                color: nil,
                isWon: $0 == "converted",
                isLost: $0 == "lost" || $0 == "unqualified"
            )
        }
    }

    /// Resolve a per-option colour: the custom option's hex if one is
    /// configured and parseable, else the caller's existing fallback.
    func color(for value: String, fallback: Color) -> Color {
        guard
            let hex = leadStatuses.first(where: { $0.value == value })?.color,
            let parsed = Color(hex: hex)
        else { return fallback }
        return parsed
    }

    /// Map the raw `config.lead_statuses` array into sorted options.
    /// Skips entries whose `value` is missing or not a valid status slug
    /// (`^[a-z][a-z0-9_]{0,63}$`). Sorted by `position` (default 0), with
    /// original order as a stable tiebreaker.
    private static func parseStatusOptions(_ arr: [AnyJSON]) -> [LeadStatusOption] {
        var scored: [(option: LeadStatusOption, position: Int)] = []
        for item in arr {
            guard case let .object(obj) = item else { continue }
            guard case let .string(value)? = obj["value"], isValidStatusValue(value) else { continue }
            var label = prettify(value)
            if case let .string(l)? = obj["label"],
               !l.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                label = l
            }
            var color: String? = nil
            if case let .string(c)? = obj["color"],
               !c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                color = c
            }
            var position = 0
            if case let .number(n)? = obj["position"] { position = Int(n) }
            var isWon = false
            if case let .bool(b)? = obj["is_won"] { isWon = b }
            var isLost = false
            if case let .bool(b)? = obj["is_lost"] { isLost = b }
            scored.append((
                LeadStatusOption(value: value, label: label, color: color, isWon: isWon, isLost: isLost),
                position
            ))
        }
        return scored.enumerated()
            .sorted { ($0.element.position, $0.offset) < ($1.element.position, $1.offset) }
            .map { $0.element.option }
    }

    /// Slug guard mirroring the backend's status-value constraint.
    private static func isValidStatusValue(_ s: String) -> Bool {
        s.range(of: "^[a-z][a-z0-9_]{0,63}$", options: .regularExpression) != nil
    }

    /// "visit_planned" -> "Visit Planned". Default label when none supplied.
    private static func prettify(_ value: String) -> String {
        value.split(separator: "_")
            .map { String($0).capitalized }
            .joined(separator: " ")
    }

    // ── Generic (any-entity) helpers ───────────────────────────────
    // The lead helpers above pre-merge into per-scope snapshots for
    // render-loop perf. Deal / contact / account forms render far fewer
    // rows and don't need that, so they use these on-demand lookups
    // straight off the full `overrides` map (which already holds every
    // entity's keys — only the lead snapshots are lead-filtered).
    //
    // `isB2C` is optional: pass it for B2B/B2C-scoped entities (contact),
    // omit (nil) for unscoped entities (deal, account). Mirrors the web's
    // buildFieldHelpers(map, entity, scope).
    private func lookupEntity(_ entity: String, _ key: String, isB2C: Bool?) -> FieldOverride? {
        let uni = overrides["\(entity).\(key)"]
        guard let scope = isB2C else { return uni }
        let scoped = overrides["\(entity).\(key)@\(scope ? "b2c" : "b2b")"]
        if uni == nil && scoped == nil { return nil }
        return FieldOverride(
            label: scoped?.label ?? uni?.label,
            required: scoped?.required ?? uni?.required,
            hidden: scoped?.hidden ?? uni?.hidden,
        )
    }
    func isHidden(entity: String, _ key: String, isB2C: Bool? = nil) -> Bool {
        lookupEntity(entity, key, isB2C: isB2C)?.hidden == true
    }
    func labelFor(entity: String, _ key: String, _ defaultLabel: String, isB2C: Bool? = nil) -> String {
        lookupEntity(entity, key, isB2C: isB2C)?.label ?? defaultLabel
    }
    func requiredFor(entity: String, _ key: String, _ defaultRequired: Bool, isB2C: Bool? = nil) -> Bool {
        lookupEntity(entity, key, isB2C: isB2C)?.required ?? defaultRequired
    }
}

import Foundation

// Spark & Ray industries config (`GET /crm/settings` -> `data.config.industries`).
//
// `[{ name, color "#RRGGBB", sub_industries: [String] }]`, order = display order. A missing / empty /
// malformed list means the built-in defaults (the 7 industries, no sub-industries). The management UI
// (add / rename / delete / colour / reorder / reset) is WEB ONLY; mobile only consumes the list.
//
// Everything here is pure (no UI, no network) so it can be unit-tested. The views and the map read the
// list through `SparkIndustries` (which delegates to `SparkIndustries.active`, kept current by
// `IndustriesStore`), and only for the Spark & Ray client (`SparkJourney.isActive`).

/// One configured industry: its name, `#RRGGBB` colour and the sub-industries it lists.
struct IndustryOption: Codable, Equatable, Hashable, Identifiable {
    let name: String
    let color: String
    let subIndustries: [String]

    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, color
        case subIndustries = "sub_industries"
    }
}

struct IndustriesConfig: Equatable {
    var industries: [IndustryOption]

    /// Grey for a blank / unknown industry (and the built-in "Other").
    static let fallbackColor = "#6B7280"

    /// The built-in list used when the tenant has not configured industries.
    static let defaults = IndustriesConfig(industries: [
        IndustryOption(name: "Manufacturing", color: "#2563EB", subIndustries: []),
        IndustryOption(name: "Automotive", color: "#DC2626", subIndustries: []),
        IndustryOption(name: "Pharma & Healthcare", color: "#16A34A", subIndustries: []),
        IndustryOption(name: "Food & Beverage", color: "#F59E0B", subIndustries: []),
        IndustryOption(name: "Construction & Infrastructure", color: "#7C3AED", subIndustries: []),
        IndustryOption(name: "Power & Energy", color: "#0891B2", subIndustries: []),
        IndustryOption(name: "Other", color: "#6B7280", subIndustries: []),
    ])

    // MARK: Parsing

    /// True for exactly `#RRGGBB`.
    static func isValidHex(_ raw: String) -> Bool {
        guard raw.count == 7, raw.hasPrefix("#") else { return false }
        return UInt32(raw.dropFirst(), radix: 16) != nil
    }

    /// Parse the `config` object of the settings reply. A missing key, a non-array, an empty array or an
    /// array with no usable entry all mean the defaults. Entries without a name are dropped, repeated names
    /// (case-insensitive) keep the first, a bad colour falls back to grey, and sub-industries are trimmed,
    /// de-duplicated and blank-free.
    static func parse(_ cfg: [String: AnyJSON]?) -> IndustriesConfig {
        guard let cfg, case let .array(items)? = cfg["industries"] else { return .defaults }
        var out: [IndustryOption] = []
        var seen = Set<String>()
        for item in items {
            guard case let .object(props) = item,
                  case let .string(rawName)? = props["name"] else { continue }
            let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { continue }
            var color = fallbackColor
            if case let .string(c)? = props["color"] {
                let trimmed = c.trimmingCharacters(in: .whitespacesAndNewlines)
                if isValidHex(trimmed) { color = trimmed.uppercased() }
            }
            out.append(IndustryOption(name: name, color: color, subIndustries: parseSubIndustries(props["sub_industries"])))
        }
        return out.isEmpty ? .defaults : IndustriesConfig(industries: out)
    }

    /// Parse the whole settings reply.
    static func parse(settings: CRMService.CRMSettingsRaw?) -> IndustriesConfig {
        guard case let .object(cfg)? = settings?.config else { return .defaults }
        return parse(cfg)
    }

    private static func parseSubIndustries(_ raw: AnyJSON?) -> [String] {
        guard case let .array(items)? = raw else { return [] }
        var seen = Set<String>()
        var out: [String] = []
        for item in items {
            guard case let .string(s) = item else { continue }
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty, seen.insert(t.lowercased()).inserted { out.append(t) }
        }
        return out
    }

    // MARK: Lookups

    /// The configured names, in display order.
    var names: [String] { industries.map { $0.name } }

    /// The entry for `industry` (case- and whitespace-insensitive), nil when it is blank or not listed.
    func option(named industry: String?) -> IndustryOption? {
        let key = (industry ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !key.isEmpty else { return nil }
        return industries.first { $0.name.lowercased() == key }
    }

    /// `#RRGGBB` for an industry: its configured colour, grey for blank / not listed.
    func color(for industry: String?) -> String {
        option(named: industry)?.color ?? IndustriesConfig.fallbackColor
    }

    /// The dropdown options for a lead's `current` industry: the configured names, plus `current` appended
    /// when it is non-blank and not listed, so a legacy / removed industry stays selectable (and is never
    /// silently changed by merely opening the form). It renders grey.
    func pickerOptions(including current: String) -> [String] {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || names.contains(current) { return names }
        return names + [current]
    }

    // MARK: Sub-industry

    /// The sub-industries `industry` lists (empty when it lists none or is not listed).
    func subIndustries(for industry: String?) -> [String] {
        option(named: industry)?.subIndustries ?? []
    }

    /// Whether the Sub-industry control is a dropdown (the chosen industry lists sub-industries) rather
    /// than today's free-text field.
    func usesSubIndustryDropdown(for industry: String?) -> Bool {
        !subIndustries(for: industry).isEmpty
    }

    /// The dropdown choices for `industry`, with the lead's `current` value appended when it is non-blank
    /// and not in the list, so a stored value stays selectable.
    func subIndustryChoices(for industry: String?, current: String) -> [String] {
        let list = subIndustries(for: industry)
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if list.isEmpty || trimmed.isEmpty || list.contains(current) { return list }
        return list + [current]
    }

    /// The Sub-industry value after the industry changed from `old` to `new`:
    ///  - `new` lists sub-industries: keep `current` only when it is one of them, else clear it;
    ///  - `new` lists none (free text): keep `current`, unless it was a sub-industry of `old`'s list (then it
    ///    belonged to the previous industry and is cleared).
    func subIndustryAfterIndustryChange(current: String, from old: String?, to new: String?) -> String {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return current }
        let newList = subIndustries(for: new)
        if !newList.isEmpty { return newList.contains(current) ? current : "" }
        return subIndustries(for: old).contains(current) ? "" : current
    }
}

// MARK: - Cache

/// Remembers the last industries list per client so a cold start paints the right colours before the
/// settings request returns (and keeps them when it fails).
enum IndustriesCache {
    static func key(clientId: String?) -> String {
        "spark.industries.v1." + ((clientId ?? "").isEmpty ? "none" : clientId!.lowercased())
    }

    static func read(key: String, in defaults: UserDefaults) -> IndustriesConfig? {
        guard let data = defaults.data(forKey: key),
              let list = try? JSONDecoder().decode([IndustryOption].self, from: data),
              !list.isEmpty else { return nil }
        return IndustriesConfig(industries: list)
    }

    static func write(_ config: IndustriesConfig, key: String, in defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(config.industries) { defaults.set(data, forKey: key) }
    }
}

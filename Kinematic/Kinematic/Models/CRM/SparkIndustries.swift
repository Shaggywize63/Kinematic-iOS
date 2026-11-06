import Foundation

/// The Industry choices for a Spark & Ray (connected-B2B company lead) lead, shown as a dropdown on the
/// lead create / edit forms. The list, colours and sub-industries come from the tenant's
/// `config.industries` (see `IndustriesConfig`), falling back to the 7 built-in defaults. Every other
/// tenant keeps the free-text Industry field.
enum SparkIndustries {
    /// The list every read goes through. `IndustriesStore` swaps it when the tenant's settings load; until
    /// then (and for any tenant without a configured list) it is the built-in defaults.
    static var active: IndustriesConfig = .defaults

    /// The built-in options, in display order.
    static let defaultOptions: [String] = IndustriesConfig.defaults.names

    /// Options in display order (configured, else the defaults).
    static var options: [String] { active.names }

    /// The picker's options for the lead's `current` industry: `options`, plus
    /// `current` appended when it is non-blank and not already listed. A legacy
    /// / free-text value therefore stays selectable and is never lost or
    /// silently changed by merely opening the form.
    static func pickerOptions(including current: String) -> [String] {
        active.pickerOptions(including: current)
    }

    /// The lead custom field Spark uses for the sub-industry (label "Industry Category"); drawn right after
    /// Industry as "Sub-industry" instead of in the generic custom-fields block.
    static let subIndustryFieldKey = "industry_category"
    static let subIndustryLabel = "Sub-industry"

    // MARK: Colours

    /// Grey used for a blank / unknown industry (and the built-in "Other").
    static let otherHex = IndustriesConfig.fallbackColor

    /// Hex colour (`#RRGGBB`) for an industry name: case-insensitive, whitespace-tolerant match on the
    /// configured industries; anything else (including nil / blank, or an industry that is no longer in the
    /// list) is grey.
    static func color(for industry: String?) -> String {
        active.color(for: industry)
    }

    /// 0...1 RGB components of `color(for:)`, for building a SwiftUI `Color` without a hex helper.
    static func rgb(for industry: String?) -> (r: Double, g: Double, b: Double) {
        rgb(hex: color(for: industry))
    }

    /// Parse `#RRGGBB` into 0...1 components; malformed input falls back to the grey.
    static func rgb(hex: String) -> (r: Double, g: Double, b: Double) {
        var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6, let v = UInt32(h, radix: 16) else {
            return (0.4196, 0.4471, 0.5020)  // #6B7280
        }
        return (Double((v >> 16) & 0xFF) / 255.0, Double((v >> 8) & 0xFF) / 255.0, Double(v & 0xFF) / 255.0)
    }

    /// The `?industry=` value for GET /crm/leads/geo: nil for "all", `__none__` for leads without an industry.
    static let noIndustryFilter = "__none__"
}

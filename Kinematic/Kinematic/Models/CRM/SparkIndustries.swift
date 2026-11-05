import Foundation

/// The fixed Industry choices for a Spark & Ray (connected-B2B company lead)
/// lead, shown as a dropdown on the lead create / edit forms. Every other
/// tenant keeps the free-text Industry field.
enum SparkIndustries {
    /// Exact options, in display order.
    static let options: [String] = [
        "Manufacturing",
        "Automotive",
        "Pharma & Healthcare",
        "Food & Beverage",
        "Construction & Infrastructure",
        "Power & Energy",
        "Other",
    ]

    /// The picker's options for the lead's `current` industry: `options`, plus
    /// `current` appended when it is non-blank and not already listed. A legacy
    /// / free-text value therefore stays selectable and is never lost or
    /// silently changed by merely opening the form.
    static func pickerOptions(including current: String) -> [String] {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || options.contains(current) { return options }
        return options + [current]
    }

    /// The lead custom field Spark uses for the sub-industry (label "Industry Category"); drawn right after
    /// Industry as "Sub-industry" instead of in the generic custom-fields block.
    static let subIndustryFieldKey = "industry_category"
    static let subIndustryLabel = "Sub-industry"

    // MARK: Colours

    /// Grey used for a blank / unknown / "Other" industry.
    static let otherHex = "#6B7280"

    /// The shared palette (identical on web / Android), keyed by lower-cased industry name.
    private static let paletteHex: [String: String] = [
        "manufacturing": "#2563EB",
        "automotive": "#DC2626",
        "pharma & healthcare": "#16A34A",
        "food & beverage": "#F59E0B",
        "construction & infrastructure": "#7C3AED",
        "power & energy": "#0891B2",
        "other": "#6B7280",
    ]

    /// Hex colour (`#RRGGBB`) for an industry name: case-insensitive, whitespace-tolerant match
    /// on the 7 known names; anything else (including nil / blank) is grey.
    static func color(for industry: String?) -> String {
        let key = (industry ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return paletteHex[key] ?? otherHex
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

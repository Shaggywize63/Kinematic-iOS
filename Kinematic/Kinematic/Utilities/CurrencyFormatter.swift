import Foundation

/// Indian Rupee currency formatting (lakhs/crores grouping).
enum CurrencyFormatter {
    private static let inrFull: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "INR"
        f.locale = Locale(identifier: "en_IN")
        f.maximumFractionDigits = 0
        return f
    }()

    /// Full INR amount with ₹ symbol and Indian grouping (e.g. ₹1,25,000).
    static func formatINR(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "₹0" }
        return inrFull.string(from: NSNumber(value: value)) ?? "₹\(Int(value))"
    }

    /// Compact INR for chart axes / dense lists (₹50L, ₹2Cr, ₹12K).
    static func formatINRCompact(_ value: Double?) -> String {
        guard let v = value, v.isFinite, v != 0 else { return "₹0" }
        let abs = Swift.abs(v)
        if abs >= 10_000_000 {
            return "\u{20B9}\(trim(v / 10_000_000))Cr"
        }
        if abs >= 100_000 {
            return "\u{20B9}\(trim(v / 100_000))L"
        }
        if abs >= 1_000 {
            return "\u{20B9}\(trim(v / 1_000))K"
        }
        return formatINR(v)
    }

    private static func trim(_ value: Double) -> String {
        let s = String(format: "%.1f", value)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }
}

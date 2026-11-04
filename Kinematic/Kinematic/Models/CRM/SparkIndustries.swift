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
}

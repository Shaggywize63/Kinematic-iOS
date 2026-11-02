import Foundation

/// How a filled form entry is named wherever an expense is linked to one: its unique reference plus the
/// day it was filled, e.g. "SRPR2627-1 · 02 Nov 2026". The reference is assigned by the backend (prefix +
/// financial-year code + running number). Pure and total — it never throws and never crashes.
enum FormRefDisplay {
    /// "SRPR2627-1 · 02 Nov 2026". Only the date when `refNo` is nil / blank, only the reference when there is
    /// no date, and "" when there is neither. A date that cannot be parsed falls back to its first 10 characters.
    static func title(refNo: String?, submittedAt: String?) -> String {
        let ref = (refNo ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let date = dayText(submittedAt)
        if ref.isEmpty { return date }
        if date.isEmpty { return ref }
        return "\(ref) · \(date)"
    }

    /// "dd MMM yyyy" in India time ("" for a nil / blank input).
    static func dayText(_ iso: String?) -> String {
        let raw = (iso ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if raw.isEmpty { return "" }
        guard let d = parse(raw) else { return String(raw.prefix(10)) }
        return dayFormatter.string(from: d)
    }

    private static func parse(_ s: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Kolkata")
        f.dateFormat = "dd MMM yyyy"
        return f
    }()
}

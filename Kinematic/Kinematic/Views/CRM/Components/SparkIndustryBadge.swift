import SwiftUI

extension Color {
    /// The Spark & Ray colour for an industry name (see `SparkIndustries.color(for:)`).
    static func sparkIndustry(_ industry: String?) -> Color {
        let c = SparkIndustries.rgb(for: industry)
        return Color(red: c.r, green: c.g, blue: c.b)
    }
}

/// A small coloured dot for an industry (picker options, map legend).
struct SparkIndustryDot: View {
    let industry: String?
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(Color.sparkIndustry(industry))
            .frame(width: size, height: size)
    }
}

/// A coloured capsule badge with the industry name (lead detail + lead rows). Renders nothing
/// for a blank industry. Callers show it for the Spark & Ray client only.
struct SparkIndustryBadge: View {
    let industry: String?
    var compact: Bool = false

    private var text: String { (industry ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        if !text.isEmpty {
            let tint = Color.sparkIndustry(text)
            HStack(spacing: 5) {
                Circle().fill(tint).frame(width: compact ? 6 : 7, height: compact ? 6 : 7)
                Text(text)
                    .font(.system(size: compact ? 10 : 11, weight: .semibold))
                    .foregroundColor(tint)
                    .lineLimit(1)
            }
            .padding(.horizontal, compact ? 7 : 9)
            .padding(.vertical, compact ? 2 : 3)
            .background(Capsule().fill(tint.opacity(0.14)))
            .accessibilityLabel("Industry \(text)")
        }
    }
}

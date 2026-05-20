import SwiftUI

/// Small uppercase pill chip used by the NBA + Win Probability cards to
/// surface the "✨ Powered by KINI AI" attribution next to the card
/// title (not in place of it). Mirrors the web dashboard's small blue
/// pill chip — but tinted with `Brand.red` to stay consistent with the
/// rest of the iOS CRM palette.
struct PoweredByKiniAIBadge: View {
    /// Compact rendering drops the sparkle glyph so the badge can sit
    /// inside a tight header row without wrapping.
    var compact: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if !compact {
                Image(systemName: "sparkles")
                    .font(.system(size: 9, weight: .black))
            }
            Text("Powered by KINI AI")
                .font(.system(size: 9, weight: .black))
                .tracking(0.8)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Brand.red.opacity(0.15)))
        .foregroundColor(Brand.red)
        .accessibilityLabel("Powered by KINI AI")
    }
}

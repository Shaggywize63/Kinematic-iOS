import SwiftUI

struct ScoreBadge: View {
    let score: Double

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame.fill").font(.system(size: 9))
            Text("\(Int(score))")
                .font(.system(size: 11, weight: .black))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .foregroundColor(color)
        .cornerRadius(6)
    }

    // Single-accent scoring: hot leads are saturated red, mid-tier are a
    // softer red, cold are grey so the row signal stays legible at a
    // glance.
    private var color: Color {
        if score >= 70 { return Brand.red }
        if score >= 40 { return Brand.red.opacity(0.75) }
        return .secondary
    }
}

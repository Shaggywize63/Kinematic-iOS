import SwiftUI

struct KiniToolResultCard: View {
    let card: KiniCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(color)
                if let title = card.title {
                    Text(title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(Color(uiColor: .label))
                }
                Spacer()
                if let metric = card.metric, let value = card.value {
                    Text("\(metric.uppercased()): \(formatted(value))")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(color)
                }
            }
            if let s = card.subtitle {
                Text(s).font(.system(size: 12)).foregroundColor(.secondary)
            }
            if let b = card.body {
                Text(b).font(.system(size: 12)).foregroundColor(Color(uiColor: .label))
            }
            if let actions = card.actions, !actions.isEmpty {
                HStack {
                    ForEach(actions) { a in
                        Text(a.label)
                            .font(.system(size: 11, weight: .bold))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(color.opacity(0.15))
                            .foregroundColor(color)
                            .cornerRadius(6)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(color.opacity(0.25), lineWidth: 1))
        )
    }

    private var icon: String {
        switch (card.kind ?? "").lowercased() {
        case "lead": return "person.crop.circle.badge.plus"
        case "deal": return "dollarsign.circle.fill"
        case "contact": return "person.fill"
        case "chart": return "chart.bar.fill"
        case "action": return "bolt.fill"
        default: return "sparkles"
        }
    }

    private var color: Color {
        switch (card.kind ?? "").lowercased() {
        case "lead": return .blue
        case "deal": return .green
        case "contact": return .orange
        case "chart": return .indigo
        case "action": return .purple
        default: return .gray
        }
    }

    private func formatted(_ v: Double) -> String {
        if abs(v) >= 1000 { return String(format: "%.1fk", v / 1000) }
        return String(format: "%.0f", v)
    }
}

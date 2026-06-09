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
        // card.kind maps to the backend "type" field: "lead_list", "deal_list",
        // "contact_list", "summary", "next_best_action", "draft_email", etc.
        switch (card.kind ?? "").lowercased() {
        case "lead_list", "lead":             return "person.crop.circle.badge.plus"
        case "deal_list", "deal":             return "dollarsign.circle.fill"
        case "contact_list", "contact":       return "person.fill"
        case "chart":                         return "chart.bar.fill"
        case "next_best_action", "action":    return "bolt.fill"
        case "summary":                       return "doc.text.fill"
        case "draft_email", "email":          return "envelope.fill"
        default:                              return "sparkles"
        }
    }

    private var color: Color {
        switch (card.kind ?? "").lowercased() {
        case "lead_list", "lead":             return Color(red: 0xE0/255, green: 0x1E/255, blue: 0x2C/255)
        case "deal_list", "deal":             return Color(red: 0x10/255, green: 0xB9/255, blue: 0x81/255)
        case "contact_list", "contact":       return Color(red: 0x63/255, green: 0x66/255, blue: 0xF1/255)
        case "next_best_action", "action":    return Color(red: 0xF5/255, green: 0x9E/255, blue: 0x0B/255)
        case "summary":                       return Color(red: 0x0E/255, green: 0xA5/255, blue: 0xE9/255)
        case "draft_email", "email":          return Color(red: 0xEC/255, green: 0x48/255, blue: 0x99/255)
        default:                              return .gray
        }
    }

    private func formatted(_ v: Double) -> String {
        if abs(v) >= 1000 { return String(format: "%.1fk", v / 1000) }
        return String(format: "%.0f", v)
    }
}

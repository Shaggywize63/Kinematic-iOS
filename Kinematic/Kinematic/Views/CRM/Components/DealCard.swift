import SwiftUI

struct DealCard: View {
    let deal: Deal
    @AppStorage("crm.deals.showWeighted") private var showWeighted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(deal.name)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color(uiColor: .label))
                .lineLimit(2)

            // Compact context line — server-stamped dealer label plus the
            // basket tonnage mirrored on custom_fields.volume_kg. Only
            // renders when at least one part is present.
            if let context = contextLine {
                Text(context)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 6) {
                Image(systemName: "indianrupeesign.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(Brand.red)
                Text(formattedAmount)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Brand.red)
                if showWeighted {
                    Text("weighted")
                        .font(.system(size: 8, weight: .black))
                        .foregroundColor(Brand.red.opacity(0.7))
                }
            }

            HStack {
                if let prob = deal.winProbability ?? deal.probability {
                    Text("\(Int(prob * 100))%")
                        .font(.system(size: 10, weight: .black))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(probColor(prob).opacity(0.18))
                        .foregroundColor(probColor(prob))
                        .cornerRadius(4)
                }
                Spacer()
                dueSoonChip
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 4, y: 1)
        )
    }

    private var formattedAmount: String {
        let raw = deal.amount ?? 0
        let value = showWeighted ? raw * (deal.winProbability ?? deal.probability ?? 0) : raw
        return CurrencyFormatter.formatINRCompact(value)
    }

    /// "Sharma Steels · 1,200 kg" — dealer name and/or volume, joined
    /// with a middot. nil when neither is available so the row doesn't
    /// reserve blank space.
    private var contextLine: String? {
        var parts: [String] = []
        if let dealer = deal.dealerName?.trimmingCharacters(in: .whitespaces), !dealer.isEmpty {
            parts.append(dealer)
        }
        if let kg = volumeKg, kg > 0 {
            let formatted = Self.kgFormatter.string(from: NSNumber(value: kg)) ?? String(Int(kg))
            parts.append("\(formatted) kg")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// custom_fields.volume_kg — tolerant of number-or-string storage.
    private var volumeKg: Double? {
        guard let any = deal.customFields?["volume_kg"]?.raw?.any else { return nil }
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let s = any as? String { return Double(s) }
        return nil
    }

    private static let kgFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.groupingSeparator = ","
        return f
    }()

    /// Three-state right-aligned chip:
    ///   - past close date    → red "OVERDUE"
    ///   - ≤7d remaining      → amber "Nd LEFT"
    ///   - everything else    → plain secondary date
    @ViewBuilder
    private var dueSoonChip: some View {
        if let close = deal.expectedCloseDate?.prefix(10),
           let date = DealCard.dateFormatter.date(from: String(close)) {
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: date)).day ?? 0
            if days < 0 {
                Text("OVERDUE")
                    .font(.system(size: 9, weight: .black))
                    .tracking(0.4)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.red.opacity(0.18))
                    .foregroundColor(.red)
                    .cornerRadius(4)
            } else if days <= 7 {
                Text("\(days)D LEFT")
                    .font(.system(size: 9, weight: .black))
                    .tracking(0.4)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.orange.opacity(0.18))
                    .foregroundColor(.orange)
                    .cornerRadius(4)
            } else {
                Text(String(close))
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
    }

    /// Re-used parser for `yyyy-MM-dd` from the backend payload. Kept as a
    /// static so it isn't re-allocated for every cell on every render.
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Band the win probability into traffic-light colours so the kanban
    /// has at-a-glance signal. ≥70% green, 40–69% amber, <40% red.
    private func probColor(_ p: Double) -> Color {
        if p >= 0.7 { return .green }
        if p >= 0.4 { return .orange }
        return .red
    }
}

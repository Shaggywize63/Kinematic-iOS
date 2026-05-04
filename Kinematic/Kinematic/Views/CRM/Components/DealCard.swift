import SwiftUI

struct DealCard: View {
    let deal: Deal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(deal.name)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Color(uiColor: .label))
                .lineLimit(2)

            HStack(spacing: 6) {
                Image(systemName: "dollarsign.circle.fill").font(.system(size: 11)).foregroundColor(.green)
                Text(formattedAmount)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.green)
            }

            HStack {
                if let prob = deal.winProbability ?? deal.probability {
                    Text("\(Int(prob * 100))%")
                        .font(.system(size: 10, weight: .black))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(probColor(prob).opacity(0.15))
                        .foregroundColor(probColor(prob))
                        .cornerRadius(4)
                }
                Spacer()
                if let close = deal.expectedCloseDate?.prefix(10) {
                    Text(String(close))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
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
        let v = deal.amount ?? 0
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = deal.currency ?? "USD"
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    private func probColor(_ p: Double) -> Color {
        if p > 0.7 { return .green }
        if p > 0.4 { return .orange }
        return .red
    }
}

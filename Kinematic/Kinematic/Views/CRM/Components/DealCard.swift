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

            HStack(spacing: 6) {
                Image(systemName: "indianrupeesign.circle.fill").font(.system(size: 11)).foregroundColor(showWeighted ? Brand.red : Brand.red)
                Text(formattedAmount)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(showWeighted ? Brand.red : Brand.red)
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
        let raw = deal.amount ?? 0
        let value = showWeighted ? raw * (deal.winProbability ?? deal.probability ?? 0) : raw
        return CurrencyFormatter.formatINRCompact(value)
    }

    private func probColor(_ p: Double) -> Color {
        if p > 0.7 { return Brand.red }
        if p > 0.4 { return Brand.red }
        return .red
    }
}

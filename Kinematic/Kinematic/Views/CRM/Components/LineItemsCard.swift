import SwiftUI

/// Read-only deal line-items panel rendered inside DealDetailView.
struct LineItemsCard: View {
    let dealId: String
    @State private var items: [DealLineItem] = []
    @State private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("LINE ITEMS")
                    .font(.system(size: 10, weight: .black))
                    .tracking(1)
                    .foregroundColor(.secondary)
                Spacer()
                if !items.isEmpty {
                    Text(CurrencyFormatter.formatINR(total))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.green)
                }
            }
            if loading {
                HStack { ProgressView().scaleEffect(0.7); Text("Loading…").font(.caption).foregroundColor(.secondary) }
            } else if items.isEmpty {
                Text("No line items linked to this deal yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(items) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.productName)
                                .font(.system(size: 13, weight: .semibold))
                            Text("\(qtyString(item.quantity)) × \(CurrencyFormatter.formatINR(item.unitPrice))")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text(CurrencyFormatter.formatINR(item.lineTotal ?? defaultTotal(item)))
                            .font(.system(size: 13, weight: .bold))
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground))
        )
        .task { await load() }
    }

    private var total: Double {
        items.reduce(0) { $0 + ($1.lineTotal ?? defaultTotal($1)) }
    }

    private func defaultTotal(_ item: DealLineItem) -> Double {
        let qty = item.quantity
        let price = item.unitPrice
        let discount = item.discountPct ?? 0
        let tax = item.taxPct ?? 0
        return qty * price * (1 - discount / 100) * (1 + tax / 100)
    }

    private func qtyString(_ value: Double) -> String {
        if value == value.rounded() { return "\(Int(value))" }
        return String(format: "%.2f", value)
    }

    private func load() async {
        loading = true
        items = (try? await CRMService.shared.dealLineItems(dealId: dealId)) ?? []
        loading = false
    }
}

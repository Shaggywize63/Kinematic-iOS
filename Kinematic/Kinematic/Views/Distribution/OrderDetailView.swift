import SwiftUI

struct OrderDetailView: View {
    let orderId: String
    @StateObject private var vm = DistributionViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let o = vm.currentOrder {
                    HStack { Text(o.order_no).font(.title3).bold(); Spacer(); statusPill(o.status) }
                    Text(o.placed_at).font(.caption).foregroundColor(.secondary)
                    Divider().padding(.vertical, 8)
                    ForEach(o.order_items ?? []) { line in
                        HStack {
                            Text("\(line.qty) × \(line.sku_name ?? line.sku_id)")
                            Spacer()
                            Text("₹\(fmt(line.total))").bold()
                        }
                        .padding(.vertical, 2)
                    }
                    Divider().padding(.vertical, 8)
                    HStack { Text("Grand total").bold(); Spacer(); Text("₹\(fmt(o.grand_total))").bold() }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding()
        }
        .navigationTitle("Order")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.loadOrder(orderId) }
    }

    private func statusPill(_ s: String) -> some View {
        Text(s)
            .font(.caption2).bold()
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color.secondary.opacity(0.15))
            .cornerRadius(8)
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? "0"
    }
}

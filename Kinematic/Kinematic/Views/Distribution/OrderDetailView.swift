import SwiftUI

struct OrderDetailView: View {
    let orderId: String
    @StateObject private var vm = DistributionViewModel()
    @State private var showCancelConfirm = false
    @State private var cancelReason = ""

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

                    // CANCEL — only for orders still in a cancellable state.
                    // The server is the source of truth for what's allowed;
                    // we gate the button on the obvious terminal states so we
                    // don't show a destructive action for a completed order.
                    if canCancel(o.status) {
                        Button(role: .destructive) {
                            showCancelConfirm = true
                        } label: {
                            HStack {
                                if vm.cancelling { ProgressView().tint(.white) }
                                else { Image(systemName: "xmark.circle.fill") }
                                Text("Cancel Order").bold()
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Color.red).foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .padding(.top, 16)
                        .disabled(vm.cancelling)
                    }
                    if let err = vm.cancelError {
                        Text(err).font(.caption).foregroundColor(.red)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }
            .padding()
        }
        .navigationTitle("Order")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.loadOrder(orderId) }
        .alert("Cancel this order?", isPresented: $showCancelConfirm) {
            TextField("Reason (optional)", text: $cancelReason)
            Button("Keep order", role: .cancel) { }
            Button("Cancel order", role: .destructive) {
                let reason = cancelReason.trimmingCharacters(in: .whitespacesAndNewlines)
                Task { _ = await vm.cancelCurrentOrder(reason: reason.isEmpty ? nil : reason) }
            }
        } message: {
            Text("This can't be undone. The customer-facing record will move to cancelled.")
        }
    }

    private func canCancel(_ s: String) -> Bool {
        let t = s.lowercased()
        return !(t == "cancelled" || t == "delivered" || t == "invoiced" || t == "dispatched")
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

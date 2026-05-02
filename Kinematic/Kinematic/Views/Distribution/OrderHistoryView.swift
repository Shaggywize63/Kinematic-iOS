import SwiftUI

struct OrderHistoryView: View {
    @StateObject private var vm = DistributionViewModel()
    @ObservedObject private var cache = OrderCache.shared

    var body: some View {
        List {
            let pending = cache.pendingForCurrentUser().orders
            if !pending.isEmpty {
                Section("Pending sync (\(pending.count))") {
                    ForEach(pending) { p in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(p.outletName ?? p.outletId).bold()
                                Spacer()
                                Text("₹\(Int(p.clientTotal))").bold()
                            }
                            Text("attempt \(p.attempt)" + (p.lastError.map { " · \($0)" } ?? "")).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                }
            }
            Section("My Orders") {
                if vm.loadingOrders {
                    ProgressView()
                } else if vm.orders.isEmpty {
                    Text("No orders yet.").foregroundColor(.secondary)
                } else {
                    ForEach(vm.orders) { o in
                        NavigationLink(destination: OrderDetailView(orderId: o.id)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(o.order_no).bold()
                                    Text("\(o.status) · \(String(o.placed_at.prefix(10)))").font(.caption2).foregroundColor(.secondary)
                                }
                                Spacer()
                                Text("₹\(Int(o.grand_total))").bold()
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Orders")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await vm.flushQueue(); await vm.loadOrders() }
                } label: { Image(systemName: "arrow.clockwise") }
            }
        }
        .task { await vm.loadOrders() }
    }
}

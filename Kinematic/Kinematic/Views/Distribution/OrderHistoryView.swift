import SwiftUI

struct OrderHistoryView: View {
    @StateObject private var vm = DistributionViewModel()
    @ObservedObject private var cache = OrderCache.shared
    @ObservedObject private var sync = DistributionSync.shared

    var body: some View {
        List {
            queueSections
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
                } label: {
                    if sync.isSending { ProgressView() } else { Image(systemName: "arrow.clockwise") }
                }
            }
        }
        .task {
            await vm.loadOrders()
            // Whatever is waiting is tried again now that the rep is looking at it.
            await vm.flushQueue()
            await vm.loadOrders()
        }
    }

    /// Orders, payments and returns saved on the phone: the ones waiting to upload, and the ones the server refused.
    @ViewBuilder private var queueSections: some View {
        let items = cache.queueItemsForCurrentUser()
        let waiting = items.filter { !$0.failed }
        let failed = items.filter { $0.failed }
        if !waiting.isEmpty {
            Section("Waiting to upload (\(waiting.count))") {
                ForEach(waiting) { item in
                    QueueRowView(item: item, onDismiss: nil)
                }
            }
        }
        if !failed.isEmpty {
            Section("Failed — the server refused these (\(failed.count))") {
                ForEach(failed) { item in
                    QueueRowView(item: item, onDismiss: { cache.dismissRejected(item) })
                }
            }
        }
    }
}

/// One order / payment / return in the offline queue. A waiting row is delivered on its own; a failed row (the
/// server refused it) is never retried and stays here until the rep dismisses it.
private struct QueueRowView: View {
    let item: DistributionQueuePolicy.QueueItem
    let onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title).font(.subheadline.weight(.semibold))
                Text(item.detail).font(.caption2).foregroundColor(.secondary)
                Text(statusText).font(.caption2).foregroundColor(item.failed ? Color.red : Color.orange)
            }
            Spacer()
            if let onDismiss = onDismiss {
                Button("Dismiss") { onDismiss() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
        }
    }

    private var statusText: String {
        if item.failed {
            return "Failed: " + (item.error ?? "rejected by the server")
        }
        var text = DistributionQueuePolicy.savedMessage
        if item.attempt > 0 { text += " · attempt \(item.attempt)" }
        if let error = item.error { text += " · " + error }
        return text
    }
}

import SwiftUI

struct OrderCartView: View {
    let outletId: String
    let outletName: String?
    let visitId: String?

    @StateObject private var vm = DistributionViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showReview = false

    var body: some View {
        VStack(spacing: 0) {
            list
            Divider()
            footer
        }
        .navigationTitle("Order")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(vm.previewing ? "Pricing…" : "Preview") { Task { await vm.runPreview(outletId: outletId) } }
                    .disabled(vm.previewing || vm.cartQty.isEmpty)
            }
        }
        .task { await vm.loadSuggest(outletId: outletId) }
        .sheet(isPresented: $showReview) {
            NavigationStack {
                OrderReviewView(outletId: outletId, outletName: outletName, visitId: visitId, vm: vm)
            }
        }
    }

    private var list: some View {
        List {
            if let err = vm.previewError {
                Text(err).foregroundColor(.red).font(.caption)
            }
            if let s = vm.suggest {
                Section(header: Text("Suggested for \(s.outlet.name)")) {
                    ForEach(s.recommendations) { r in
                        cartRow(r)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func cartRow(_ r: Recommendation) -> some View {
        let qty = vm.cartQty[r.sku_id] ?? 0
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(r.sku_name ?? r.sku_id).font(.subheadline).bold()
                Text("MRP ₹\(Int(r.mrp))  ·  Suggested \(r.suggested_qty)").font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Stepper(value: Binding(
                get: { vm.cartQty[r.sku_id] ?? 0 },
                set: { vm.setQty(skuId: r.sku_id, qty: $0) }
            ), in: 0...999) { Text("\(qty)").font(.subheadline).bold().frame(width: 32) }
                .labelsHidden()
        }
    }

    private var footer: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Total").font(.caption).foregroundColor(.secondary)
                Text(vm.preview.map { "₹\(format(($0.totals.grand_total)))" } ?? "—").font(.title2).bold()
            }
            Spacer()
            Button {
                showReview = true
            } label: {
                Text("Review →").font(.headline)
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(Color(red: 208/255, green: 30/255, blue: 44/255))
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .disabled(vm.preview == nil || (vm.preview?.totals.grand_total ?? 0) <= 0)
        }
        .padding()
        .background(Color(.systemBackground))
    }

    private func format(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? "0"
    }
}

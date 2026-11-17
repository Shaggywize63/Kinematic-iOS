import SwiftUI

/// Dealer-direct order entry (the dealer is the customer; no outlet).
///
/// Solar Seeds reps sell straight to dealers, so this flow targets a dealer
/// (distributor) instead of a retail outlet: pick an assigned dealer, browse its
/// priced catalogue, build the cart, preview server pricing, and place. The order
/// carries `distributor_id` and a nil `outlet_id` (see
/// `DistributionViewModel.submitDealer`). Companion to `OrderCartView` (the
/// outlet/beat flow); kept self-contained so it can't destabilise it.
struct DealerOrderView: View {
    @StateObject private var vm = DistributionViewModel()
    @Environment(\.dismiss) private var dismiss

    @State private var dealerId: String?
    @State private var dealerName: String?
    @State private var dealerQuery: String = ""
    @State private var query: String = ""
    // One Idempotency-Key per confirmation; a refused order spends it (new key below).
    @State private var draftKey = DistributionQueuePolicy.newKey(prefix: DistributionQueuePolicy.orderKeyPrefix)

    var body: some View {
        Group {
            if let id = dealerId {
                orderView(dealerId: id)
            } else {
                dealerPicker
            }
        }
        .navigationTitle(ClientFeatures.labelFor("menu", "dealer_order", default: "Book Order"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.loadMyDealers() }
    }

    // ── Dealer picker ──────────────────────────────────────────────────────
    private var shownDealers: [DistributorLite] {
        let q = dealerQuery.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return vm.dealers }
        return vm.dealers.filter {
            ($0.name ?? "").localizedCaseInsensitiveContains(q) ||
            ($0.code ?? "").localizedCaseInsensitiveContains(q)
        }
    }

    private var dealerPicker: some View {
        List {
            if vm.loadingDealers && vm.dealers.isEmpty {
                Text("Loading dealers…").foregroundColor(.secondary)
            } else if vm.dealers.isEmpty {
                Text("No dealers assigned to you yet.").foregroundColor(.secondary)
            } else if shownDealers.isEmpty {
                Text("No dealers match “\(dealerQuery)”.").foregroundColor(.secondary)
            } else {
                Section(header: Text("Select a dealer")) {
                    ForEach(shownDealers) { d in
                        Button {
                            dealerId = d.id
                            dealerName = d.name ?? d.code ?? d.id
                            vm.clearCart()
                            Task { await vm.loadDealerCatalogue(distributorId: d.id) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(d.name ?? d.code ?? d.id).foregroundColor(.primary)
                                    if let c = d.code, !c.isEmpty {
                                        Text(c).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $dealerQuery, prompt: "Search dealer by name or code")
    }

    // ── Catalogue + cart + preview ─────────────────────────────────────────
    @ViewBuilder
    private func orderView(dealerId id: String) -> some View {
        VStack(spacing: 0) {
            if let p = vm.preview {
                receiptList(p)
            } else {
                catalogueList
            }
            Divider()
            footer(dealerId: id)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if vm.preview == nil {
                    Button("Change") {
                        dealerId = nil; dealerName = nil; query = ""; vm.clearCart()
                    }
                } else {
                    // Back from the order summary to the product list, quantities kept.
                    Button("Edit") { vm.preview = nil; vm.previewError = nil }
                }
            }
        }
    }

    private var cartIsEmpty: Bool { vm.cartQty.values.allSatisfy { $0 <= 0 } }

    // Live order value while the rep types: qty x dealer price from the loaded
    // catalogue. The server Preview stays the authority (schemes, GST, round-off).
    private var estTotal: Double {
        let price = Dictionary((vm.catalogue?.items ?? []).map { ($0.sku_id, $0.base_price) }, uniquingKeysWith: { a, _ in a })
        return vm.cartQty.reduce(0.0) { sum, kv in kv.value > 0 ? sum + Double(kv.value) * (price[kv.key] ?? 0) : sum }
    }
    private var cartLines: Int { vm.cartQty.values.filter { $0 > 0 }.count }
    private var cartUnits: Int { vm.cartQty.values.filter { $0 > 0 }.reduce(0, +) }

    // ── Order summary (receipt) after Preview ─────────────────────────────
    private func receiptList(_ p: OrderPreview) -> some View {
        List {
            Section {
                ForEach(Array(p.lines.enumerated()), id: \.offset) { _, line in
                    receiptRow(line)
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Order summary").font(.headline).foregroundColor(.primary)
                    Text([dealerName, "\(p.lines.count) line\(p.lines.count == 1 ? "" : "s")"].compactMap { $0 }.joined(separator: "  ·  "))
                        .font(.caption)
                }
                .textCase(nil)
            }
            Section {
                totals(p.totals)
                HStack {
                    Text("Grand total").bold()
                    Spacer()
                    Text(inr(p.totals.grand_total)).bold()
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func receiptRow(_ line: PricedLine) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(line.sku_name ?? line.sku_code ?? line.sku_id).font(.subheadline).bold()
                    if line.is_free_good == true {
                        Text("FREE").font(.caption2).bold()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.green.opacity(0.2)).foregroundColor(.green)
                            .clipShape(Capsule())
                    }
                }
                Text("\(line.qty) × \(inr(line.unit_price))" + (line.gst_rate > 0 ? "  ·  GST \(Int(line.gst_rate))%" : ""))
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Text(inr(line.total)).font(.subheadline).bold()
        }
        .padding(.vertical, 2)
    }

    private var groupedItems: [(String, [CatalogueItem])] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let items = vm.catalogue?.items ?? []
        let filtered = q.isEmpty ? items : items.filter {
            ($0.sku_name ?? "").lowercased().contains(q) ||
            ($0.sku_code ?? "").lowercased().contains(q) ||
            ($0.category ?? "").lowercased().contains(q)
        }
        let groups = Dictionary(grouping: filtered) { ($0.category?.isEmpty == false ? $0.category! : "Other") }
        return groups.sorted { $0.key < $1.key }
    }

    private var catalogueList: some View {
        List {
            if let cc = vm.catalogue?.customer_class, !cc.isEmpty {
                Text("Price class: \(cc)").font(.caption).foregroundColor(.secondary)
            }
            if (vm.catalogue?.items ?? []).isEmpty {
                Text("No orderable SKUs for this dealer's price list.").foregroundColor(.secondary)
            } else {
                ForEach(groupedItems, id: \.0) { (category, rows) in
                    Section(header: Text(category.uppercased())) {
                        ForEach(rows) { item in
                            catalogueRow(item)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .searchable(text: $query, prompt: "Search by name, code or category")
    }

    private func catalogueRow(_ item: CatalogueItem) -> some View {
        let qty = vm.cartQty[item.sku_id] ?? 0
        let minQ = Int(item.min_qty ?? 0)
        let maxQ = Int(item.max_qty ?? 0)
        return HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.sku_name ?? item.sku_code ?? item.sku_id).font(.subheadline).bold()
                Text("\(item.uom)  ·  MRP \(inr(item.mrp))  ·  \(inr(item.base_price))")
                    .font(.caption).foregroundColor(.secondary)
                if minQ > 0 || maxQ > 0 {
                    Text([(minQ > 0 ? "Min \(minQ)" : nil), (maxQ > 0 ? "Max \(maxQ)" : nil)]
                            .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2).foregroundColor(.orange)
                }
            }
            Spacer()
            qtyField(item: item, qty: qty)
        }
    }

    // Editable quantity box (replaces the +/- stepper): the rep types the quantity.
    // Empty box == 0 (line removed from cart).
    private func qtyField(item: CatalogueItem, qty: Int) -> some View {
        TextField("Qty", text: Binding(
            get: { qty > 0 ? String(qty) : "" },
            set: { newVal in
                let digits = String(newVal.filter { $0.isNumber }.prefix(6))
                vm.setQty(skuId: item.sku_id, qty: Int(digits) ?? 0)
            }
        ))
        .keyboardType(.numberPad)
        .multilineTextAlignment(.center)
        .frame(width: 72)
        .textFieldStyle(.roundedBorder)
    }

    // ── Footer: credit + totals + Preview/Place ────────────────────────────
    @ViewBuilder
    private func footer(dealerId id: String) -> some View {
        VStack(spacing: 10) {
            if let c = vm.preview?.credit, c.statusValue != "na" {
                HStack {
                    Image(systemName: "creditcard")
                    Text(creditHeadline(c)).font(.caption).bold()
                    Spacer()
                }
                .foregroundColor(creditColor(c.statusValue))
            }
            if let err = vm.submitError ?? vm.previewError {
                Text(err).font(.caption).foregroundColor(.red).frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                VStack(alignment: .leading) {
                    if let p = vm.preview {
                        Text("Grand total").font(.caption).foregroundColor(.secondary)
                        Text(inr(p.totals.grand_total)).font(.title3).bold()
                    } else {
                        Text(cartLines > 0 ? "Order value · \(cartLines) item\(cartLines == 1 ? "" : "s") · \(cartUnits) qty" : "Order value")
                            .font(.caption).foregroundColor(.secondary)
                        Text(inr(estTotal)).font(.title3).bold()
                    }
                }
                Spacer()
                if vm.preview == nil {
                    Button(vm.previewing ? "Pricing…" : "Preview") {
                        Task { await vm.runPreviewDealer(distributorId: id) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.previewing || cartIsEmpty)
                } else {
                    Button(vm.submitting ? "Placing…" : "Place order") {
                        Task {
                            guard let outcome = await vm.submitDealer(distributorId: id, dealerName: dealerName, idempotencyKey: draftKey) else { return }
                            switch outcome {
                            case .synced, .queued:
                                dismiss()
                            case .rejected:
                                // That key is spent; a corrected order goes out under a new one.
                                draftKey = DistributionQueuePolicy.newKey(prefix: DistributionQueuePolicy.orderKeyPrefix)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.submitting || (vm.preview?.totals.grand_total ?? 0) <= 0)
                }
            }
        }
        .padding()
    }

    private func totals(_ t: OrderTotals) -> some View {
        VStack(spacing: 2) {
            totalRow("Taxable", t.taxable_value)
            if t.discount_total > 0 { totalRow("Discount", -t.discount_total) }
            totalRow("CGST", t.cgst)
            totalRow("SGST", t.sgst)
            if t.igst > 0 { totalRow("IGST", t.igst) }
            if t.cess > 0 { totalRow("Cess", t.cess) }
        }
    }

    private func totalRow(_ label: String, _ value: Double) -> some View {
        HStack {
            Text(label).font(.caption).foregroundColor(.secondary)
            Spacer()
            Text(inr(value)).font(.caption)
        }
    }

    private func creditHeadline(_ c: Credit) -> String {
        switch c.statusValue {
        case "exceeded":
            let over = max(0, (c.projected_balance ?? 0) - (c.credit_limit ?? 0))
            return "Over credit limit by \(inr(over))"
        case "warning":
            return "Nearing credit limit · \(inr(c.available ?? 0)) left"
        default:
            return "Within credit limit"
        }
    }

    private func creditColor(_ status: String) -> Color {
        switch status {
        case "exceeded": return .red
        case "warning":  return .orange
        default:         return .green
        }
    }

    private func inr(_ v: Double) -> String {
        let n = NSNumber(value: v)
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 2
        f.maximumFractionDigits = 2
        f.groupingSeparator = ","
        f.usesGroupingSeparator = true
        return "₹" + (f.string(from: n) ?? String(format: "%.2f", v))
    }
}

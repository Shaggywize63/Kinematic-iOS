import SwiftUI

struct OrderCartView: View {
    let outletId: String
    let outletName: String?
    let visitId: String?

    @StateObject private var vm = DistributionViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showReview = false
    @State private var showCatalogue = false

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
        .sheet(isPresented: $showCatalogue) {
            CatalogueSheet(vm: vm, outletId: outletId)
        }
    }

    private var list: some View {
        List {
            if let err = vm.previewError {
                Text(err).foregroundColor(.red).font(.caption)
            }
            // Browse the full orderable SKU list beyond the server's reorder
            // suggestions. Anything picked lands in the same `cartQty` map, so it
            // shows up below and flows into Preview / Place unchanged.
            Section {
                Button {
                    showCatalogue = true
                } label: {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        Text("Browse full catalogue")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            if let s = vm.suggest {
                Section(header: Text("Suggested for \(s.outlet.name)")) {
                    ForEach(s.recommendations) { r in
                        cartRow(r)
                    }
                }
            }
            if !extraCartItems.isEmpty {
                Section(header: Text("Added from catalogue")) {
                    ForEach(extraCartItems) { item in
                        addedRow(item)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    /// Catalogue picks that aren't part of the reorder suggestions — resolved
    /// against the loaded catalogue so we can show a name/price rather than a
    /// bare SKU id. Suggested items already render in their own section.
    private var extraCartItems: [CatalogueItem] {
        guard let cat = vm.catalogue else { return [] }
        let suggestedIds = Set(vm.suggest?.recommendations.map(\.sku_id) ?? [])
        return cat.items
            .filter { vm.cartQty[$0.sku_id] != nil && !suggestedIds.contains($0.sku_id) }
            .sorted { ($0.sku_name ?? $0.sku_id) < ($1.sku_name ?? $1.sku_id) }
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

    /// A catalogue-added cart line. The stepper enforces the SKU's max; stepping
    /// below the min removes the line (an order can't hold a below-MOQ quantity).
    private func addedRow(_ item: CatalogueItem) -> some View {
        let qty = vm.cartQty[item.sku_id] ?? 0
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.sku_name ?? item.sku_code ?? item.sku_id).font(.subheadline).bold()
                Text("\(item.uom) · MRP ₹\(format(item.mrp)) · ₹\(format(item.base_price))")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Stepper(value: Binding(
                get: { vm.cartQty[item.sku_id] ?? 0 },
                set: { newVal in
                    if newVal < catalogueMinInt(item) { vm.setQty(skuId: item.sku_id, qty: 0) }
                    else { vm.setQty(skuId: item.sku_id, qty: min(newVal, catalogueMaxInt(item))) }
                }
            ), in: 0...catalogueMaxInt(item)) {
                Text("\(qty)").font(.subheadline).bold().frame(width: 32)
            }.labelsHidden()
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Early credit hint — only when the priced preview flags the outlet
            // near/over its limit. Read-only; never blocks Review/placement.
            if let c = vm.preview?.credit, c.statusValue == "warning" || c.statusValue == "exceeded" {
                creditHint(c)
            }
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
        }
        .padding()
        .background(Color(.systemBackground))
    }

    private func creditHint(_ c: Credit) -> some View {
        let exceeded = c.statusValue == "exceeded"
        let tint: Color = exceeded ? .red : .orange
        return HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").font(.caption2)
            Text(exceeded ? "Over credit limit" : "Nearing credit limit").font(.caption).bold()
            Spacer()
        }
        .foregroundColor(tint)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(tint.opacity(0.12)))
    }

    private func format(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? "0"
    }
}

// MARK: - Catalogue browser

/// Full SKU catalogue for the outlet, searchable and grouped by category. Every
/// add/qty control writes straight into `vm.cartQty`, so selections merge into
/// the same cart the Preview/Place flow already builds from.
private struct CatalogueSheet: View {
    @ObservedObject var vm: DistributionViewModel
    let outletId: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(grouped) { group in
                    Section(group.category) {
                        ForEach(group.items) { item in
                            catalogueRow(item)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, prompt: "Search name, code or category")
            .overlay {
                if vm.catalogue == nil {
                    ProgressView()
                } else if filtered.isEmpty {
                    ContentUnavailableView(
                        "No SKUs",
                        systemImage: "shippingbox",
                        description: Text(query.isEmpty
                            ? "This outlet has no orderable catalogue yet."
                            : "No matches for “\(query)”.")
                    )
                }
            }
            .navigationTitle("Catalogue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } }
            }
            .task { if vm.catalogue == nil { await vm.loadCatalogue(outletId: outletId) } }
        }
    }

    private var filtered: [CatalogueItem] {
        let items = vm.catalogue?.items ?? []
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return items }
        return items.filter {
            ($0.sku_name?.lowercased().contains(q) ?? false)
                || ($0.sku_code?.lowercased().contains(q) ?? false)
                || ($0.category?.lowercased().contains(q) ?? false)
        }
    }

    private var grouped: [CatalogueGroup] {
        Dictionary(grouping: filtered, by: { $0.category ?? "Other" })
            .map { key, value in
                CatalogueGroup(
                    category: key,
                    items: value.sorted { ($0.sku_name ?? $0.sku_id) < ($1.sku_name ?? $1.sku_id) }
                )
            }
            .sorted { $0.category < $1.category }
    }

    private func catalogueRow(_ item: CatalogueItem) -> some View {
        let qty = vm.cartQty[item.sku_id] ?? 0
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.sku_name ?? item.sku_code ?? item.sku_id)
                    .font(.subheadline).bold()
                Text(subtitle(item))
                    .font(.caption2).foregroundColor(.secondary)
                if let hint = moqHint(item) {
                    Text(hint).font(.caption2).foregroundColor(.secondary)
                }
            }
            Spacer()
            if qty == 0 {
                Button {
                    vm.setQty(skuId: item.sku_id, qty: catalogueMinInt(item))
                } label: {
                    Text("Add").font(.subheadline).bold()
                }
                .buttonStyle(.bordered)
            } else {
                HStack(spacing: 8) {
                    Stepper(value: Binding(
                        get: { vm.cartQty[item.sku_id] ?? 0 },
                        set: { newVal in
                            let clamped = min(max(newVal, catalogueMinInt(item)), catalogueMaxInt(item))
                            vm.setQty(skuId: item.sku_id, qty: clamped)
                        }
                    ), in: catalogueRange(item)) {
                        Text("\(qty)").font(.subheadline).bold().frame(width: 32)
                    }.labelsHidden()
                    Button(role: .destructive) {
                        vm.setQty(skuId: item.sku_id, qty: 0)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func subtitle(_ item: CatalogueItem) -> String {
        ["\(item.uom)",
         "MRP ₹\(catalogueMoneyFormat(item.mrp))",
         "₹\(catalogueMoneyFormat(item.base_price))"].joined(separator: " · ")
    }

    private func moqHint(_ item: CatalogueItem) -> String? {
        var parts: [String] = []
        if let mn = item.min_qty, mn > 0 { parts.append("Min \(catalogueTrimNum(mn))") }
        if let mx = item.max_qty, mx > 0 { parts.append("Max \(catalogueTrimNum(mx))") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

private struct CatalogueGroup: Identifiable {
    let category: String
    let items: [CatalogueItem]
    var id: String { category }
}

// Shared clamp/format helpers for the catalogue controls (used by both the cart
// list and the browser sheet). `cartQty` is Int-keyed, so the Double min/max
// bounds are rounded into an integer range with a sane 1…999 fallback.
private func catalogueMinInt(_ item: CatalogueItem) -> Int {
    max(1, Int((item.min_qty ?? 1).rounded(.up)))
}
private func catalogueMaxInt(_ item: CatalogueItem) -> Int {
    guard let mx = item.max_qty, mx > 0 else { return 999 }
    return max(catalogueMinInt(item), Int(mx.rounded(.down)))
}
private func catalogueRange(_ item: CatalogueItem) -> ClosedRange<Int> {
    catalogueMinInt(item)...catalogueMaxInt(item)
}
private func catalogueMoneyFormat(_ v: Double) -> String {
    let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 2
    return f.string(from: NSNumber(value: v)) ?? "0"
}
private func catalogueTrimNum(_ v: Double) -> String {
    v == v.rounded() ? String(Int(v)) : catalogueMoneyFormat(v)
}

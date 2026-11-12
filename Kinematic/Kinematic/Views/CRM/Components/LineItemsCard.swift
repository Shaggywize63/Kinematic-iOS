import SwiftUI

/// Deal product lines on DealDetailView (connected-B2B / Spark & Ray). Each line shows Reference, name,
/// Make, Brand, Qty, Quoted, Ordered and the MAC funnel reference (blank values are hidden, a missing
/// order value shows "—"), with the quoted / ordered totals underneath. A line can be edited: make,
/// brand, order value and funnel reference (required for MAC products).
struct LineItemsCard: View {
    let dealId: String
    /// Bumped by the host (for example after the deal is closed as Won) to reload the lines.
    var refreshTick: Int = 0
    @State private var items: [DealLineItem] = []
    @State private var loading = true
    @State private var editingItem: DealLineItem? = nil
    @StateObject private var masters = LineMastersModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 11))
                    .foregroundColor(Brand.red)
                Text("PRODUCT LINES")
                    .font(.system(size: 10, weight: .black))
                    .tracking(1)
                    .foregroundColor(Brand.red)
                Spacer()
            }
            if loading {
                HStack { ProgressView().scaleEffect(0.7); Text("Loading…").font(.caption).foregroundColor(.secondary) }
            } else if items.isEmpty {
                Text("No product lines on this deal yet.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(items) { item in
                    lineRow(item)
                    Divider()
                }
                totalsRow
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground))
        )
        .task(id: refreshTick) { await load() }
        .task { await masters.load() }
        .sheet(item: $editingItem) { item in
            LineItemEditSheet(item: item, masters: masters) {
                await load()
            }
        }
    }

    private var totalsRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(DealLineTotals.quotedText(DealLineItems.quotedTotal(items)))
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Brand.red)
            if let ordered = DealLineTotals.orderedText(DealLineItems.orderedTotal(items)) {
                Text(ordered)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(Brand.red)
            }
        }
    }

    private func lineRow(_ item: DealLineItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.productName)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    editingItem = item
                } label: {
                    Image(systemName: "pencil")
                        .foregroundColor(Brand.red)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Edit line")
            }
            ForEach(item.detailRows, id: \.label) { row in
                keyValue(row.label, row.value)
            }
            keyValue("Qty", qtyString(item.quantity))
            keyValue("Quoted", CurrencyFormatter.formatINR(item.quotedValue))
            keyValue("Ordered", item.orderValue.map { CurrencyFormatter.formatINR($0) } ?? "\u{2014}")
        }
        .padding(.vertical, 4)
    }

    private func keyValue(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
                .multilineTextAlignment(.trailing)
        }
    }

    private func qtyString(_ value: Double) -> String {
        if value == value.rounded() { return "\(Int(value))" }
        return String(format: "%.2f", value)
    }

    private func load() async {
        items = (try? await CRMService.shared.dealLineItems(dealId: dealId)) ?? []
        loading = false
    }
}

/// Edit one saved line: make, brand, order value and MAC funnel reference. Save is blocked until a MAC
/// line has its funnel reference and a typed order value is a number >= 0.
private struct LineItemEditSheet: View {
    let item: DealLineItem
    @ObservedObject var masters: LineMastersModel
    let onSaved: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var makeId: String?
    @State private var makeName: String?
    @State private var brandId: String?
    @State private var brandName: String?
    @State private var orderValueText: String
    @State private var funnelRef: String
    @State private var saving = false
    @State private var errorMessage: String? = nil

    init(item: DealLineItem, masters: LineMastersModel, onSaved: @escaping () async -> Void) {
        self.item = item
        self.masters = masters
        self.onSaved = onSaved
        _makeId = State(initialValue: item.makeId)
        _makeName = State(initialValue: item.makeName)
        _brandId = State(initialValue: item.brandId)
        _brandName = State(initialValue: item.brandName)
        _orderValueText = State(initialValue: item.orderValue.map { SparkJourney.priceText($0) } ?? "")
        _funnelRef = State(initialValue: item.funnelRef ?? "")
    }

    private var blockingProblem: String? {
        if !DealLineRules.orderValueTextIsValid(orderValueText) { return DealLineRules.invalidOrderValueMessage }
        return DealLineRules.funnelProblem(brandName: brandName, funnelRef: funnelRef)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LineAttributeFields(
                        makeId: $makeId,
                        makeName: $makeName,
                        brandId: $brandId,
                        brandName: $brandName,
                        orderValueText: $orderValueText,
                        funnelRef: $funnelRef,
                        makes: masters.makes,
                        brands: masters.brands
                    )
                } header: {
                    Text(item.displayReference.map { "\(item.productName) · \($0)" } ?? item.productName)
                }
                if let errorMessage {
                    Section { Text(errorMessage).font(.footnote).foregroundColor(.red) }
                }
            }
            .navigationTitle("Edit line")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving { ProgressView() } else { Text("Save").bold() }
                    }
                    .disabled(saving || blockingProblem != nil)
                }
            }
        }
    }

    @MainActor
    private func save() async {
        if let problem = blockingProblem {
            errorMessage = problem
            return
        }
        let body = DealLineBody.patch(
            original: item,
            makeId: makeId,
            brandId: brandId,
            funnelRef: funnelRef,
            orderValueText: orderValueText
        )
        if body.isEmpty {
            dismiss()
            return
        }
        saving = true
        defer { saving = false }
        do {
            try await CRMService.shared.updateLineItem(id: item.id, body: body)
            await onSaved()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

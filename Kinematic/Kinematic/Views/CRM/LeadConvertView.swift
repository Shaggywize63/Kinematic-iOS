//
//  LeadConvertView.swift
//  Kinematic CRM
//
//  Modal sheet presented from the lead detail screen's "Convert" action.
//  Mirrors the web's LeadConvertModal: lets the rep flip the lead into an
//  Account + Deal in one shot, optionally with a multi-product line-item
//  table. The line-item table is gated to Tata Tiscon (their motion is
//  per-tonne steel sales — every other tenant keeps the simple
//  "deal_amount" path).
//
//  Three-way sync per row:
//   - editing pieces  -> kg = pieces × weight_kg ; subtotal = pieces × price
//   - editing kg      -> pieces = kg / weight_kg ; subtotal = pieces × price
//   - editing subtotal-> pieces = subtotal / price ; kg = pieces × weight_kg
//  Switching the product recomputes kg + subtotal from the current pieces
//  value, so changing brand mid-edit doesn't leave stale derived figures.
//
//  The Deal Amount field auto-sums from the rows but flips to "overridden"
//  the moment the rep types into it directly, matching the dashboard so
//  manual quotes survive subsequent row edits.
//

import SwiftUI

struct LeadConvertView: View {
    @Environment(\.dismiss) private var dismiss

    let lead: Lead
    /// Called after a successful conversion. Receives the updated Lead and
    /// (when available) the freshly-created Deal id so the caller can push
    /// the deal detail screen onto the nav stack. Deal id falls out of
    /// `lead.convertedDealId` after the server roundtrip.
    let onConverted: (_ updatedLead: Lead, _ dealId: String?) -> Void

    // MARK: Form state
    @State private var createAccount: Bool = true
    @State private var createDeal: Bool = true
    @State private var dealName: String = ""
    @State private var dealAmountText: String = ""
    /// Sticky once the rep types into the amount field — prevents the
    /// computed line-items sum from clobbering a manual override.
    @State private var amountOverridden: Bool = false

    @State private var products: [Product] = []
    @State private var loadingProducts = false
    @State private var rows: [LineItemRow] = [LineItemRow()]

    @State private var submitting = false
    @State private var errorMessage: String?

    /// Whether the line-items section is shown. Captured at init so
    /// flipping the client picker mid-sheet doesn't yank the table out
    /// from under the rep.
    private let showLineItems: Bool

    init(lead: Lead, onConverted: @escaping (_ updatedLead: Lead, _ dealId: String?) -> Void) {
        self.lead = lead
        self.onConverted = onConverted
        self.showLineItems = CRMClientScope.isTataTiscon()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    togglesCard
                    dealNameCard
                    if showLineItems {
                        lineItemsCard
                    }
                    amountCard
                    if let msg = errorMessage {
                        Text(msg)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Color.red.opacity(0.08)))
                    }
                    submitButton
                }
                .padding(16)
            }
            .navigationTitle("Convert Lead")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(submitting)
                }
            }
            .task {
                if dealName.isEmpty { dealName = defaultDealName() }
                if showLineItems { await loadProducts() }
            }
        }
        .interactiveDismissDisabled(submitting)
    }

    // MARK: - Sections

    private var togglesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Create Account", isOn: $createAccount)
            Divider()
            Toggle("Create Deal", isOn: $createDeal)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private var dealNameCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DEAL NAME")
                .font(.system(size: 10, weight: .black)).tracking(1)
                .foregroundColor(.gray)
            TextField("Deal name", text: $dealName)
                .textFieldStyle(.roundedBorder)
                .disabled(!createDeal)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private var lineItemsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("PRODUCTS")
                    .font(.system(size: 10, weight: .black)).tracking(1)
                    .foregroundColor(.gray)
                Spacer()
                if loadingProducts {
                    ProgressView().controlSize(.small)
                }
            }

            if availableProducts.isEmpty && !loadingProducts {
                Text("No active products with price & weight configured.")
                    .font(.caption).foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                // Iterate with stable identity (each LineItemRow has its
                // own UUID) so removing a middle row doesn't reshuffle
                // the textfield focus / cursor state of the survivors.
                ForEach($rows) { $row in
                    LineItemRowEditor(
                        row: $row,
                        products: availableProducts,
                        canRemove: rows.count > 1,
                        onRemove: { removeRow(id: row.id) },
                        onChange: { syncAmountFromRows() }
                    )
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color(uiColor: .tertiarySystemBackground)))
                }

                Button {
                    addRow()
                } label: {
                    Label("Add another product", systemImage: "plus.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                }
                .buttonStyle(.borderless)
                .disabled(availableProducts.isEmpty)

                totalsRow
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemBackground)))
        .disabled(!createDeal)
        .opacity(createDeal ? 1.0 : 0.5)
    }

    private var totalsRow: some View {
        let totals = computeTotals()
        return HStack(spacing: 12) {
            totalsChip(label: "LINES", value: "\(totals.lines)")
            totalsChip(label: "TOTAL KG", value: formatNumber(totals.kg))
            totalsChip(label: "TOTAL ₹", value: CurrencyFormatter.formatINR(totals.subtotal))
        }
    }

    private func totalsChip(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundColor(.gray)
            Text(value).font(.system(size: 13, weight: .bold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: .tertiarySystemBackground)))
    }

    private var amountCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("DEAL AMOUNT (₹)")
                    .font(.system(size: 10, weight: .black)).tracking(1)
                    .foregroundColor(.gray)
                Spacer()
                if showLineItems && amountOverridden {
                    Button("Reset to line-items sum") {
                        amountOverridden = false
                        syncAmountFromRows()
                    }
                    .font(.system(size: 10, weight: .bold))
                }
            }
            TextField("0", text: $dealAmountText)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .disabled(!createDeal)
                .onChange(of: dealAmountText) { _, _ in
                    // Any keystroke (other than the auto-sync writer below)
                    // flips the override flag so subsequent row edits don't
                    // overwrite the rep's manual figure.
                    if showLineItems && !suppressOverrideTracking {
                        amountOverridden = true
                    }
                }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private var submitButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack {
                if submitting { ProgressView().tint(.white) }
                Text(submitting ? "Converting…" : "Convert & open deal")
                    .font(.system(size: 15, weight: .bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.green)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .disabled(submitting || !canSubmit)
    }

    // MARK: - Derived

    /// Products with both a positive price and weight — the line-item
    /// math is undefined without both, so we hide the rest from the picker
    /// to match the web behaviour.
    private var availableProducts: [Product] {
        products.filter {
            ($0.isActive ?? true)
                && ($0.effectivePrice ?? 0) > 0
                && ($0.weightKg ?? 0) > 0
        }
    }

    private var canSubmit: Bool {
        if !createAccount && !createDeal { return false }
        return true
    }

    private func defaultDealName() -> String {
        // Web uses `{full_name | company | email} + " Opportunity"`; mirror
        // exactly so reports/dashboards group consistently across surfaces.
        let candidate: String = {
            let name = lead.displayName
            if !name.isEmpty && name != "Unnamed Lead" { return name }
            if let c = lead.company, !c.isEmpty { return c }
            if let e = lead.email, !e.isEmpty { return e }
            return "New"
        }()
        return "\(candidate) Opportunity"
    }

    private struct Totals { let lines: Int; let kg: Double; let subtotal: Double }

    private func computeTotals() -> Totals {
        let nonEmpty = rows.filter { $0.productId != nil }
        let kg = nonEmpty.reduce(0.0) { $0 + ($1.volumeKg ?? 0) }
        let sub = nonEmpty.reduce(0.0) { $0 + ($1.subtotal ?? 0) }
        return Totals(lines: nonEmpty.count, kg: kg, subtotal: sub)
    }

    // MARK: - Row management

    private func addRow() {
        rows.append(LineItemRow())
    }

    private func removeRow(id: UUID) {
        guard rows.count > 1, let idx = rows.firstIndex(where: { $0.id == id }) else { return }
        rows.remove(at: idx)
        syncAmountFromRows()
    }

    // MARK: - Amount sync

    /// Set to true while we programmatically write into `dealAmountText`
    /// so the textfield's onChange handler doesn't mis-flag the write as
    /// a manual edit.
    @State private var suppressOverrideTracking: Bool = false

    private func syncAmountFromRows() {
        guard showLineItems, !amountOverridden else { return }
        let total = computeTotals().subtotal
        suppressOverrideTracking = true
        if total > 0 {
            dealAmountText = formatPlainNumber(total)
        } else {
            dealAmountText = ""
        }
        // Re-enable tracking after the bound value propagates.
        DispatchQueue.main.async { suppressOverrideTracking = false }
    }

    // MARK: - Networking

    private func loadProducts() async {
        loadingProducts = true
        defer { loadingProducts = false }
        do {
            products = try await CRMService.shared.listProducts()
        } catch {
            // Non-fatal — the rep can still convert without line items.
            errorMessage = "Couldn't load products: \(error.localizedDescription)"
        }
    }

    private func submit() async {
        submitting = true
        defer { submitting = false }
        errorMessage = nil

        let amount = Double(dealAmountText.replacingOccurrences(of: ",", with: ""))
        let lineItems: [CRMService.ConvertLineItem]? = {
            guard showLineItems else { return nil }
            let resolved = rows.compactMap { row -> CRMService.ConvertLineItem? in
                guard let pid = row.productId else { return nil }
                // Send the row only if at least one of the three figures
                // is positive — empty rows are dropped silently.
                let hasFigure = (row.pieces ?? 0) > 0
                    || (row.volumeKg ?? 0) > 0
                    || (row.subtotal ?? 0) > 0
                guard hasFigure else { return nil }
                return CRMService.ConvertLineItem(
                    productId: pid,
                    pieces: row.pieces,
                    volumeKg: row.volumeKg,
                    subtotal: row.subtotal
                )
            }
            return resolved.isEmpty ? nil : resolved
        }()

        do {
            let updated = try await CRMService.shared.convertLead(
                id: lead.id,
                createAccount: createAccount,
                createDeal: createDeal,
                dealName: createDeal ? dealName.trimmingCharacters(in: .whitespaces) : nil,
                dealAmount: createDeal ? amount : nil,
                dealLineItems: lineItems
            )
            onConverted(updated, updated.convertedDealId)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Number formatting

    private func formatNumber(_ value: Double) -> String {
        if value == 0 { return "0" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Plain (no thousands separators) variant for writing back into the
    /// amount textfield — the decimal pad keyboard doesn't accept commas.
    private func formatPlainNumber(_ value: Double) -> String {
        if value == 0 { return "" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Row model

/// One product line in the convert sheet. All three numeric fields are
/// optional because the user might be mid-typing — we only persist whatever
/// is set when the rep hits submit, and the backend canonicalises the row
/// from the product master so trailing precision in the client values
/// doesn't matter.
struct LineItemRow: Identifiable, Hashable {
    let id = UUID()
    var productId: String?
    var pieces: Double?
    var volumeKg: Double?
    var subtotal: Double?
}

// MARK: - Row editor

private struct LineItemRowEditor: View {
    @Binding var row: LineItemRow
    let products: [Product]
    let canRemove: Bool
    let onRemove: () -> Void
    /// Called after every auto-sync so the parent can refresh the amount
    /// sum + totals chips without us reaching up into its state.
    let onChange: () -> Void

    @State private var piecesText: String = ""
    @State private var kgText: String = ""
    @State private var subtotalText: String = ""

    /// Suppress the textfield onChange handlers while we're writing
    /// programmatically — otherwise the auto-sync would recurse.
    @State private var syncing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                productPicker
                    .frame(maxWidth: .infinity, alignment: .leading)
                if canRemove {
                    Button {
                        onRemove()
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }

            HStack(spacing: 8) {
                numericField(label: "Pieces", text: $piecesText) { newValue in
                    handlePiecesChange(newValue)
                }
                numericField(label: "Kg", text: $kgText) { newValue in
                    handleKgChange(newValue)
                }
                numericField(label: "₹", text: $subtotalText) { newValue in
                    handleSubtotalChange(newValue)
                }
            }
        }
    }

    private var productPicker: some View {
        Menu {
            ForEach(products) { p in
                Button(p.name) { selectProduct(p) }
            }
        } label: {
            HStack {
                Text(currentProductName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(row.productId == nil ? .secondary : .primary)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.down").font(.caption).foregroundColor(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: .systemBackground)))
        }
    }

    private var currentProductName: String {
        guard let pid = row.productId,
              let p = products.first(where: { $0.id == pid }) else {
            return "Select product"
        }
        return p.name
    }

    private func numericField(
        label: String,
        text: Binding<String>,
        onEdit: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 9, weight: .heavy)).tracking(0.5).foregroundColor(.gray)
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
                .onChange(of: text.wrappedValue) { _, newValue in
                    guard !syncing else { return }
                    onEdit(newValue)
                }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sync helpers

    private func selectProduct(_ product: Product) {
        row.productId = product.id
        // If pieces is already set, recompute kg + subtotal from the new
        // product's price/weight. Otherwise just leave the row empty so
        // the rep can type whichever dimension they prefer first.
        if let pieces = row.pieces, pieces > 0,
           let price = product.effectivePrice, let weight = product.weightKg,
           price > 0, weight > 0 {
            let kg = pieces * weight
            let sub = pieces * price
            row.volumeKg = kg
            row.subtotal = sub
            writeBack(pieces: pieces, kg: kg, subtotal: sub)
        }
        onChange()
    }

    private func handlePiecesChange(_ raw: String) {
        let value = parse(raw)
        row.pieces = value
        guard let product = currentProduct(),
              let price = product.effectivePrice, let weight = product.weightKg,
              price > 0, weight > 0,
              let pieces = value, pieces >= 0 else {
            onChange(); return
        }
        let kg = pieces * weight
        let sub = pieces * price
        row.volumeKg = kg
        row.subtotal = sub
        writeBack(pieces: pieces, kg: kg, subtotal: sub, skip: .pieces)
        onChange()
    }

    private func handleKgChange(_ raw: String) {
        let value = parse(raw)
        row.volumeKg = value
        guard let product = currentProduct(),
              let price = product.effectivePrice, let weight = product.weightKg,
              price > 0, weight > 0,
              let kg = value, kg >= 0 else {
            onChange(); return
        }
        let pieces = kg / weight
        let sub = pieces * price
        row.pieces = pieces
        row.subtotal = sub
        writeBack(pieces: pieces, kg: kg, subtotal: sub, skip: .kg)
        onChange()
    }

    private func handleSubtotalChange(_ raw: String) {
        let value = parse(raw)
        row.subtotal = value
        guard let product = currentProduct(),
              let price = product.effectivePrice, let weight = product.weightKg,
              price > 0, weight > 0,
              let subtotal = value, subtotal >= 0 else {
            onChange(); return
        }
        let pieces = subtotal / price
        let kg = pieces * weight
        row.pieces = pieces
        row.volumeKg = kg
        writeBack(pieces: pieces, kg: kg, subtotal: subtotal, skip: .subtotal)
        onChange()
    }

    private enum Field { case pieces, kg, subtotal }

    /// Write the derived figures back into the text bindings without
    /// re-triggering the change handlers. `skip` is the field the rep is
    /// currently typing into — we leave that one alone so the cursor /
    /// keystrokes stay coherent.
    private func writeBack(pieces: Double, kg: Double, subtotal: Double, skip: Field? = nil) {
        syncing = true
        if skip != .pieces { piecesText = format(pieces) }
        if skip != .kg { kgText = format(kg) }
        if skip != .subtotal { subtotalText = format(subtotal) }
        DispatchQueue.main.async { syncing = false }
    }

    private func currentProduct() -> Product? {
        guard let pid = row.productId else { return nil }
        return products.first { $0.id == pid }
    }

    private func parse(_ s: String) -> Double? {
        let cleaned = s.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty else { return nil }
        return Double(cleaned)
    }

    private func format(_ value: Double) -> String {
        if value == 0 { return "" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.usesGroupingSeparator = false
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        return f.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

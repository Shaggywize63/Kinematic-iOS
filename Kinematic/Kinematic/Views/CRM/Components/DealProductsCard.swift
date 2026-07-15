import SwiftUI
import Combine

/// Products section for the deal detail screen. Replaces the legacy
/// LineItemsCard. Reads the deal's own `custom_fields.product_lines`
/// (falling back to the linked lead's rows for legacy deals) and
/// renders one row per product with these columns:
///
///   Product · Quantity · Closed Qty · Balance · Est. Amt · Closed Amt · Bal. Amt
///
/// Closed Quantity is editable; rep taps the Save button to persist
/// `deal.custom_fields.closed_quantities = { [product_id]: number }`.
/// Mirrors the web pattern: one PATCH per Save = one deal_history note
/// row (vs N rows from the previous debounced auto-save).
///
/// Arrow logic on Balance / Balance Amount:
///   closed < estimated → RED ▼ (short of target)
///   closed > estimated → GREEN ▲ (over-delivered)
///   zero               → em-dash
/// The displayed number always strips the sign.
///
/// Amount math: amount = (price / weight_kg) × (quantity × unitFactor)
/// where unitFactor = 1 for kg and 1000 for tonne.

struct DealProductsCard: View {
    let dealId: String

    @State private var loading: Bool = true
    @State private var leadId: String?
    @State private var rows: [ProductRow] = []
    @State private var closed: [String: Double] = [:]
    @State private var drafts: [String: String] = [:]
    @State private var dealCustomFields: [String: Any] = [:]
    @State private var savedClosed: [String: Double] = [:]
    @State private var saving: Bool = false

    struct ProductRow: Identifiable {
        let id: String  // == productId
        let productName: String
        let estimated: Double
        let unit: String
        let price: Double
        let weightKg: Double
        let unitFactor: Double
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Eyebrow header — matches the SUMMARY / LINKED / HISTORY
            // section headers on DealDetailView.
            HStack(spacing: 8) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 11))
                    .foregroundColor(Brand.red)
                Text("PRODUCTS")
                    .font(.system(size: 10, weight: .black))
                    .tracking(1)
                    .foregroundColor(Brand.red)
                Spacer()
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        .task { await load() }
    }

    @ViewBuilder
    private var content: some View {
        if loading {
            HStack {
                ProgressView()
                Text("Loading…").font(.caption).foregroundColor(.secondary)
            }
        } else if rows.isEmpty && leadId == nil {
            Text("No product lines on this deal yet. Add them from Edit Deal to track quantities here.")
                .font(.caption)
                .foregroundColor(.secondary)
        } else if rows.isEmpty {
            Text("No product lines yet. Add them from Edit Deal (or capture them on the lead form) to see them here.")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .center, spacing: 8) {
                        hdr("Product", width: 140)
                        hdr("Quantity", width: 80)
                        hdr("Closed Qty", width: 110)
                        hdr("Balance", width: 110)
                        hdr("Est. Amt", width: 110)
                        hdr("Closed Amt", width: 110)
                        hdr("Bal. Amt", width: 130)
                    }
                    Divider()
                    ForEach(rows) { row in
                        let closedVal = closed[row.id] ?? 0
                        let draftVal = drafts[row.id]
                        let estAmt = amountFor(row: row, qty: row.estimated)
                        let closedAmt = amountFor(row: row, qty: closedVal)
                        HStack(alignment: .center, spacing: 8) {
                            cell(row.productName, width: 140)
                            cell(
                                "\(pretty(row.estimated))\(row.unit.isEmpty ? "" : " \(row.unit)")",
                                width: 80
                            )
                            TextField("0", text: Binding(
                                get: { draftVal ?? (closedVal > 0 ? pretty(closedVal) : "") },
                                set: { newVal in
                                    drafts[row.id] = newVal
                                    if newVal.isEmpty {
                                        closed.removeValue(forKey: row.id)
                                    } else if let n = Double(newVal) {
                                        closed[row.id] = n
                                    }
                                }
                            ))
                            .keyboardType(.decimalPad)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)

                            BalanceCell(estimated: row.estimated, closed: closedVal, currency: false)
                                .frame(width: 110, alignment: .leading)
                            cell(fmtINR(estAmt), width: 110)
                            cell(fmtINR(closedAmt), width: 110)
                            BalanceCell(estimated: estAmt, closed: closedAmt, currency: true)
                                .frame(width: 130, alignment: .leading)
                        }
                        .padding(.vertical, 8)
                        Divider()
                    }
                }
            }
            HStack {
                Spacer()
                if dirty {
                    Button("Reset") {
                        closed = savedClosed
                        drafts = [:]
                    }
                    .disabled(saving)
                }
                Button {
                    Task { await saveClosed() }
                } label: {
                    HStack(spacing: 6) {
                        if saving { ProgressView().scaleEffect(0.7) }
                        Text(saving ? "Saving…" : "Save")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!dirty || saving)
            }
            .padding(.top, 4)
        }
    }

    private var dirty: Bool {
        !loading && closed != savedClosed
    }

    private func hdr(_ text: String, width: CGFloat) -> some View {
        Text(text.uppercased())
            .font(.caption2.bold())
            .foregroundColor(.secondary)
            .frame(width: width, alignment: .leading)
    }

    private func cell(_ text: String, width: CGFloat) -> some View {
        Text(text)
            .font(.body)
            .frame(width: width, alignment: .leading)
    }

    // MARK: – Load

    @MainActor
    private func load() async {
        loading = true
        defer { loading = false }
        do {
            let deal = try await CRMService.shared.getDeal(id: dealId)
            leadId = deal.leadId
            // Use the rich `raw.any` graph so nested arrays/dicts decode
            // — the old `.value` path was string-only and dropped
            // closed_quantities / product_lines.
            let cf: [String: Any] = (deal.customFields ?? [:]).compactMapValues { $0.raw?.any }
            dealCustomFields = cf
            if let map = cf["closed_quantities"] as? [String: Any] {
                var out: [String: Double] = [:]
                for (k, v) in map {
                    if let n = v as? Double { out[k] = n }
                    else if let n = v as? Int { out[k] = Double(n) }
                    else if let s = v as? String, let n = Double(s) { out[k] = n }
                }
                closed = out
            } else {
                closed = [:]
            }
            savedClosed = closed
            let products = (try? await CRMService.shared.listProducts()) ?? []
            let productMap = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
            // Prefer the DEAL's own basket — the deal-edit form persists
            // product_lines on the deal itself now. Fall back to the linked
            // lead's rows for legacy deals that only mirrored onto the lead.
            var lines: [[String: Any]] = (cf["product_lines"] as? [[String: Any]]) ?? []
            if lines.isEmpty, let lid = deal.leadId {
                let lead = try await CRMService.shared.getLead(id: lid)
                let leadCf: [String: Any] = (lead.customFields ?? [:]).compactMapValues { $0.raw?.any }
                lines = {
                    if let arr = leadCf["product_lines"] as? [[String: Any]], !arr.isEmpty { return arr }
                    let pid = leadCf["product_interested"] as? String
                    let qty = leadCf["quantity"]
                    let unit = leadCf["measuring_unit"] as? String
                    if pid != nil || qty != nil { return [["product_id": pid as Any, "quantity": qty as Any, "measuring_unit": unit as Any]] }
                    return []
                }()
            }
            rows = lines.compactMap { l -> ProductRow? in
                guard let pid = l["product_id"] as? String, !pid.isEmpty else { return nil }
                let p = productMap[pid]
                let qty: Double = {
                    if let n = l["quantity"] as? Double { return n }
                    if let n = l["quantity"] as? Int { return Double(n) }
                    if let s = l["quantity"] as? String { return Double(s) ?? 0 }
                    return 0
                }()
                let unit = (l["measuring_unit"] as? String) ?? ""
                let unitFactor: Double = (unit.lowercased() == "tonne") ? 1000 : 1
                return ProductRow(
                    id: pid,
                    productName: p?.name ?? String(pid.prefix(8)),
                    estimated: qty,
                    unit: unit,
                    price: p?.unitPrice ?? 0,
                    weightKg: p?.weightKg ?? 0,
                    unitFactor: unitFactor,
                )
            }
        } catch {
            // Swallow; UI just shows the empty state.
        }
    }

    // MARK: – Persist (explicit Save button)

    @MainActor
    private func saveClosed() async {
        if saving { return }
        saving = true
        defer { saving = false }
        var next = dealCustomFields
        next["closed_quantities"] = closed.reduce(into: [String: Double]()) { $0[$1.key] = $1.value }
        do {
            _ = try await CRMService.shared.patchDeal(id: dealId, body: ["custom_fields": next])
            dealCustomFields = next
            savedClosed = closed
        } catch {
            // Swallow; user can retry from the same Save button.
        }
    }

    // MARK: – Math + formatters

    private func amountFor(row: ProductRow, qty: Double) -> Double {
        if row.price <= 0 || qty <= 0 { return 0 }
        // Weight-based pricing is Tata-only; everyone else is price × qty.
        if ClientFeatures.isTataTiscon {
            if row.weightKg <= 0 { return 0 }
            return (row.price / row.weightKg) * (qty * row.unitFactor)
        }
        return row.price * qty
    }

    private func pretty(_ v: Double) -> String {
        if v == v.rounded() { return String(Int(v)) }
        return String(format: "%.2f", v)
    }

    private func fmtINR(_ v: Double) -> String {
        if v <= 0 { return "—" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.groupingSeparator = ","
        return "₹\(f.string(from: NSNumber(value: v)) ?? String(format: "%.0f", v))"
    }
}

private struct BalanceCell: View {
    let estimated: Double
    let closed: Double
    let currency: Bool

    var body: some View {
        let absVal = abs(closed - estimated)
        let display: String = {
            if currency {
                let f = NumberFormatter()
                f.numberStyle = .decimal
                f.maximumFractionDigits = 0
                f.groupingSeparator = ","
                return "₹\(f.string(from: NSNumber(value: absVal)) ?? "0")"
            }
            if absVal == absVal.rounded() { return String(Int(absVal)) }
            return String(format: "%.2f", absVal)
        }()
        // closed < estimated → RED ▼ ; otherwise (equal OR over) → GREEN ▲
        // When the rep hits the target exactly we still show "0" with the
        // green up-arrow (signals "target met").
        Group {
            if closed < estimated {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                    Text(display).bold()
                }
                .foregroundColor(Color(red: 0.94, green: 0.27, blue: 0.27))
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                    Text(display).bold()
                }
                .foregroundColor(Color(red: 0.06, green: 0.72, blue: 0.51))
            }
        }
        .font(.body)
    }
}

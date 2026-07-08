import SwiftUI
import Combine

/// iOS counterpart of the web ProductLinesSection / Android
/// CrmProductLinesSection. Renders the four product-line custom fields
/// (product_interested / quantity / measuring_unit / estimated_amount)
/// as one Card per product line plus an "Add another product" button.
///
/// Estimated Amount auto-computes per row:
///
///   amount = (product.price / product.weight_kg) × (quantity × unitFactor)
///
/// where unitFactor is 1000 for "Tonne" and 1 for "Kg". Rounded to 2 dp.
///
/// Rows persist on `customFields.text["product_lines"]` (JSON-encoded
/// array of dicts). Row 0 is mirrored onto the legacy single-field
/// keys (product_interested / quantity / measuring_unit / estimated_amount)
/// so reports and exports that read those scalars keep working — and
/// the sum of line amounts goes to estimated_amount so the basket total
/// matches the web/Android total.

@MainActor
final class ProductLinesModel: ObservableObject {
    @Published var products: [Product] = []
    @Published var lines: [ProductLine] = [ProductLine()]

    struct ProductLine: Identifiable, Equatable {
        let id = UUID()
        var productId: String?
        var quantityText: String = ""
        var measuringUnit: String?
        // Cached display amount — recomputed each setter call so the UI
        // doesn't need a separate derivedStateOf.
        var estimatedAmount: Double = 0
    }

    func load() async {
        if let items = try? await CRMService.shared.listProducts() {
            products = items.filter { $0.isActive != false }
        }
    }

    /// Seed `lines` from an existing record's `custom_fields` blob so the
    /// edit form lands on the rep's previously-captured rows. Reads the
    /// rich `raw.any` graph (product_lines array) when present, otherwise
    /// falls back to the legacy single-field shape. Idempotent — calling
    /// twice just re-seeds with the latest values.
    func hydrate(from raw: [String: AnyCodable]?) {
        guard let raw else { return }
        let pairs = raw.compactMapValues { $0.raw?.any }
        if let arr = pairs["product_lines"] as? [[String: Any]], !arr.isEmpty {
            lines = arr.map { row in
                var l = ProductLine()
                if let pid = row["product_id"] as? String { l.productId = pid }
                if let q = row["quantity"] as? Double { l.quantityText = String(q) }
                else if let q = row["quantity"] as? Int { l.quantityText = String(q) }
                else if let q = row["quantity"] as? String { l.quantityText = q }
                if let u = row["measuring_unit"] as? String { l.measuringUnit = u }
                l.estimatedAmount = computeAmount(l)
                return l
            }
            return
        }
        // Legacy fallback — seed a single row from the four scalar keys
        // so older leads still surface a row to the rep.
        let pid = pairs["product_interested"] as? String
        let qty: Double? = {
            if let n = pairs["quantity"] as? Double { return n }
            if let n = pairs["quantity"] as? Int { return Double(n) }
            if let s = pairs["quantity"] as? String { return Double(s) }
            return nil
        }()
        let unit = pairs["measuring_unit"] as? String
        if pid != nil || qty != nil {
            var l = ProductLine()
            l.productId = pid
            if let q = qty { l.quantityText = String(q) }
            l.measuringUnit = unit
            l.estimatedAmount = computeAmount(l)
            lines = [l]
        }
    }

    func computeAmount(_ line: ProductLine) -> Double {
        guard let id = line.productId, !id.isEmpty,
              let p = products.first(where: { $0.id == id }) else { return 0 }
        let price = p.unitPrice ?? 0
        let qty = Double(line.quantityText) ?? 0
        guard price > 0, qty > 0 else { return 0 }
        // Weight-based pricing (amount = price ÷ weight × tonne/kg factor) is
        // bespoke to Tata Tiscon, whose TMT is sold by the tonne. Every other
        // tenant prices simply as price × quantity.
        if ClientFeatures.isTataTiscon {
            let weight = p.weightKg ?? 0
            guard weight > 0 else { return 0 }
            let factor = (line.measuringUnit?.lowercased() == "tonne") ? 1000.0 : 1.0
            let raw = (price / weight) * (qty * factor)
            return (raw * 100).rounded() / 100
        }
        let raw = price * qty
        return (raw * 100).rounded() / 100
    }

    func updateLine(at idx: Int, transform: (inout ProductLine) -> Void) {
        guard idx < lines.count else { return }
        var l = lines[idx]
        transform(&l)
        l.estimatedAmount = computeAmount(l)
        lines[idx] = l
    }

    func addLine() {
        lines.append(ProductLine())
    }

    func removeLine(at idx: Int) {
        guard idx < lines.count else { return }
        if lines.count <= 1 {
            // Never drop the last row — clear it instead so the rep
            // can't end up with zero slots.
            lines[idx] = ProductLine()
            return
        }
        lines.remove(at: idx)
    }

    var basketTotal: Double {
        lines.reduce(0) { $0 + $1.estimatedAmount }
    }

    /// Plain JSON-serialisable rows + legacy mirror keys for merging into
    /// the lead's custom_fields blob on save.
    var jsonValues: [String: Any] {
        var out: [String: Any] = [:]
        let rows: [[String: Any]] = lines.map { l in
            var dict: [String: Any] = [:]
            if let id = l.productId, !id.isEmpty { dict["product_id"] = id }
            if let qty = Double(l.quantityText) { dict["quantity"] = qty }
            if let u = l.measuringUnit, !u.isEmpty { dict["measuring_unit"] = u }
            if l.estimatedAmount > 0 { dict["estimated_amount"] = l.estimatedAmount }
            return dict
        }
        out["product_lines"] = rows
        if let head = lines.first {
            if let id = head.productId, !id.isEmpty { out["product_interested"] = id }
            if let qty = Double(head.quantityText) { out["quantity"] = qty }
            if let u = head.measuringUnit, !u.isEmpty { out["measuring_unit"] = u }
        }
        let total = basketTotal
        if total > 0 { out["estimated_amount"] = total }
        return out
    }
}

struct ProductLinesSection: View {
    @ObservedObject var model: ProductLinesModel

    var body: some View {
        Section {
            // Header card — kept compact so it doesn't dwarf the inputs.
            VStack(alignment: .leading, spacing: 4) {
                Text("Products of Interest")
                    .font(.headline)
                Text("Pick a product and quantity; the estimated amount fills in automatically from \(ClientFeatures.isTataTiscon ? "price ÷ weight × quantity" : "price × quantity").")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if model.basketTotal > 0 {
                    Text("Basket total: ₹\(formatINR(model.basketTotal))")
                        .font(.subheadline.bold())
                        .padding(.top, 2)
                }
            }
            .padding(.vertical, 4)

            ForEach(Array(model.lines.enumerated()), id: \.element.id) { idx, _ in
                LineRowView(model: model, index: idx)
                    .padding(.vertical, 6)
            }

            Button {
                model.addLine()
            } label: {
                Label("Add another product", systemImage: "plus.circle.fill")
            }
        }
    }

    private func formatINR(_ v: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: v)) ?? "\(v)"
    }
}

/// One Card-style row binding directly to model.lines[index].
private struct LineRowView: View {
    @ObservedObject var model: ProductLinesModel
    let index: Int

    var body: some View {
        // Defensive clamp against the rare race where a remove happens
        // mid-layout. Pulled into a local so the body stays a single
        // expression — multi-statement view bodies need an explicit
        // `return` and complicate the type checker.
        let safeIdx = min(index, max(0, model.lines.count - 1))
        let line = model.lines[safeIdx]
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Product \(index + 1)")
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                Spacer()
                Button(role: .destructive) {
                    model.removeLine(at: index)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            // Product Interested — Picker.
            Picker("Product Interested", selection: Binding(
                get: { line.productId ?? "" },
                set: { newId in
                    model.updateLine(at: index) { $0.productId = newId.isEmpty ? nil : newId }
                }
            )) {
                Text("—").tag("")
                ForEach(model.products) { p in
                    Text(productLabel(p)).tag(p.id)
                }
            }

            // Quantity + Unit on the same row.
            HStack {
                TextField("Quantity", text: Binding(
                    get: { line.quantityText },
                    set: { newVal in
                        model.updateLine(at: index) { $0.quantityText = newVal }
                    }
                ))
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)

                // Tonne/Kg selector only for Tata Tiscon (weight-based pricing);
                // other tenants price by piece so the unit is meaningless.
                if ClientFeatures.isTataTiscon {
                    Picker("Unit", selection: Binding(
                        get: { line.measuringUnit ?? "" },
                        set: { newUnit in
                            model.updateLine(at: index) { $0.measuringUnit = newUnit.isEmpty ? nil : newUnit }
                        }
                    )) {
                        Text("Unit").tag("")
                        Text("Kg").tag("Kg")
                        Text("Tonne").tag("Tonne")
                    }
                    .pickerStyle(.menu)
                }
            }

            // Estimated Amount — readonly.
            HStack {
                Text("Estimated Amount")
                    .foregroundColor(.secondary)
                Spacer()
                Text(line.estimatedAmount > 0
                     ? "₹\(format2(line.estimatedAmount))"
                     : "Auto")
                    .foregroundColor(line.estimatedAmount > 0 ? .primary : .secondary)
                    .font(.body.monospacedDigit())
            }
            .padding(.top, 2)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
    }

    private func productLabel(_ p: Product) -> String {
        if let sku = p.sku, !sku.isEmpty { return "\(p.name) (\(sku))" }
        return p.name
    }

    private func format2(_ v: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.groupingSeparator = ","
        return formatter.string(from: NSNumber(value: v)) ?? "\(v)"
    }
}

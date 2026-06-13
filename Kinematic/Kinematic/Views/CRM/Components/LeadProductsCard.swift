import SwiftUI

/// Read-only Products section for the lead detail screen. Renders the
/// rows the rep captured on the lead form (custom_fields.product_lines)
/// — same shape the deal page's DealProductsCard reads, minus the
/// editable Closed Quantity column. Mirrors the web LeadDetailsPanel's
/// "Products of Interest" card.
///
/// Each row shows:
///   Product Name  ·  Quantity (with unit)  ·  Estimated Amount
///
/// If the lead has more than one product line we append a Basket Total
/// row so the rep sees the aggregate at a glance.

struct LeadProductsCard: View {
    let lead: Lead

    @State private var rows: [Row] = []
    @State private var loading = true

    private struct Row: Identifiable {
        let id: String  // == productId, or a uuid string for the legacy seed row
        let productName: String
        let quantity: Double
        let unit: String
        let estimated: Double
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Products of Interest")
                .font(.title3.bold())
            content
        }
        .padding(14)
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
        } else if rows.isEmpty {
            Text("No products captured on this lead yet.")
                .font(.caption)
                .foregroundColor(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { r in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.productName)
                                .font(.body)
                                .fontWeight(.semibold)
                            HStack(spacing: 6) {
                                Text("\(pretty(r.quantity))\(r.unit.isEmpty ? "" : " \(r.unit)")")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Text(fmtINR(r.estimated))
                            .font(.body.monospacedDigit())
                            .foregroundColor(r.estimated > 0 ? .primary : .secondary)
                    }
                    .padding(.vertical, 8)
                    if r.id != rows.last?.id { Divider() }
                }
                if rows.count > 1 {
                    Divider().padding(.vertical, 4)
                    let total = rows.reduce(0) { $0 + $1.estimated }
                    HStack {
                        Text("Basket Total")
                            .font(.body.bold())
                        Spacer()
                        Text(fmtINR(total))
                            .font(.body.bold().monospacedDigit())
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @MainActor
    private func load() async {
        loading = true
        defer { loading = false }
        // Resolve UUIDs to product names through the products catalogue.
        let products = (try? await CRMService.shared.listProducts()) ?? []
        let productMap = Dictionary(uniqueKeysWithValues: products.map { ($0.id, $0) })
        // Read the lead's custom_fields via the AnyCodable rich raw graph
        // — the string-only fallback would drop product_lines silently.
        let cf: [String: Any] = (lead.customFields ?? [:]).compactMapValues { $0.raw?.any }

        var lines: [[String: Any]] = []
        if let arr = cf["product_lines"] as? [[String: Any]], !arr.isEmpty {
            lines = arr
        } else if cf["product_interested"] != nil || cf["quantity"] != nil {
            lines = [[
                "product_id": cf["product_interested"] as Any,
                "quantity": cf["quantity"] as Any,
                "measuring_unit": cf["measuring_unit"] as Any,
                "estimated_amount": cf["estimated_amount"] as Any,
            ]]
        }

        rows = lines.compactMap { l -> Row? in
            guard let pid = l["product_id"] as? String, !pid.isEmpty else { return nil }
            let qty: Double = {
                if let n = l["quantity"] as? Double { return n }
                if let n = l["quantity"] as? Int { return Double(n) }
                if let s = l["quantity"] as? String { return Double(s) ?? 0 }
                return 0
            }()
            let unit = (l["measuring_unit"] as? String) ?? ""
            let unitFactor: Double = unit.lowercased() == "tonne" ? 1000 : 1
            // Prefer the cached estimated_amount; fall back to recomputing
            // from price + weight when the line was saved before that
            // mirror landed.
            let cached: Double = {
                if let n = l["estimated_amount"] as? Double { return n }
                if let n = l["estimated_amount"] as? Int { return Double(n) }
                return 0
            }()
            let p = productMap[pid]
            let estimated: Double = {
                if cached > 0 { return cached }
                let price = p?.unitPrice ?? 0
                let weight = p?.weightKg ?? 0
                if price <= 0 || weight <= 0 || qty <= 0 { return 0 }
                return (price / weight) * (qty * unitFactor)
            }()
            return Row(
                id: pid,
                productName: p?.name ?? String(pid.prefix(8)),
                quantity: qty,
                unit: unit,
                estimated: estimated,
            )
        }
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

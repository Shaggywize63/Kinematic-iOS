import SwiftUI

/// GST tax-invoice document for a placed order. Loads GET /salesman/orders/
/// {orderId}/invoice on appear; the endpoint 404s until the order is invoiced,
/// which the VM surfaces as `invoice == nil` after `invoiceLoaded` — rendered
/// here as a graceful "not available yet" state rather than an error.
struct InvoiceView: View {
    let orderId: String
    @StateObject private var vm = DistributionViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if vm.loadingInvoice && !vm.invoiceLoaded {
                ProgressView().frame(maxWidth: .infinity).padding(.top, 60)
            } else if let inv = vm.invoice {
                content(inv)
            } else {
                unavailable
            }
        }
        .navigationTitle("Invoice")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) { Button("Done") { dismiss() } }
        }
        .task { await vm.loadInvoice(orderId: orderId) }
    }

    // MARK: - Loaded document

    private func content(_ inv: Invoice) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(inv)
                Divider()
                lineSection(inv)
                Divider()
                summary(inv)
            }
            .padding()
        }
    }

    // MARK: Header

    private func header(_ inv: Invoice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("TAX INVOICE").font(.headline).bold()
                Spacer()
                if let no = inv.invoice_no, !no.isEmpty {
                    Text(no).font(.subheadline).bold()
                }
            }
            if let issued = formattedDate(inv.issued_at) { labelRow("Date", issued) }
            if let irn = inv.irn, !irn.isEmpty { labelRow("IRN", irn) }
            if let bt = inv.bill_type, !bt.isEmpty { labelRow("Bill type", bt) }

            partyBlock(title: "Seller",
                       name: inv.distributor?.name,
                       gstin: inv.distributor?.gstin,
                       address: inv.distributor?.address,
                       extra: placeOfSupply(inv))
            partyBlock(title: "Buyer",
                       name: inv.outlet?.name,
                       gstin: inv.buyer_gstin,
                       address: inv.outlet?.address,
                       extra: inv.buyer_state_code.flatMap { $0.isEmpty ? nil : "State code \($0)" })
        }
    }

    private func partyBlock(title: String, name: String?, gstin: String?, address: String?, extra: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased()).font(.caption2).foregroundColor(.secondary)
            Text((name?.isEmpty == false) ? name! : "—").font(.subheadline).bold()
            if let g = gstin, !g.isEmpty { Text("GSTIN: \(g)").font(.caption).foregroundColor(.secondary) }
            if let a = address, !a.isEmpty { Text(a).font(.caption).foregroundColor(.secondary) }
            if let e = extra, !e.isEmpty { Text(e).font(.caption2).foregroundColor(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }

    private func labelRow(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.caption).foregroundColor(.secondary)
            Spacer()
            Text(v).font(.caption).foregroundColor(.primary).multilineTextAlignment(.trailing)
        }
    }

    // MARK: Line items (HSN-wise)

    private func lineSection(_ inv: Invoice) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Items").font(.caption).foregroundColor(.secondary)
            let items = inv.invoice_items ?? []
            if items.isEmpty {
                Text("No line items.").font(.subheadline).foregroundColor(.secondary)
            } else {
                ForEach(Array(items.enumerated()), id: \.offset) { _, line in
                    lineRow(line)
                }
            }
        }
    }

    private func lineRow(_ line: InvoiceItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .top) {
                Text(line.sku_name ?? "—").font(.subheadline).bold()
                Spacer()
                Text("₹\(fmt(line.total ?? 0))").font(.subheadline).bold()
            }
            HStack(spacing: 8) {
                if let hsn = line.hsn_code, !hsn.isEmpty { Text("HSN \(hsn)") }
                Text(qtyText(line))
                if let tv = line.taxable_value { Text("Taxable ₹\(fmt(tv))") }
                if let g = line.gst_rate { Text("GST \(trim(g))%") }
            }
            .font(.caption2).foregroundColor(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func qtyText(_ line: InvoiceItem) -> String {
        let q = line.qty.map { trim($0) } ?? "—"
        let u = line.uom ?? ""
        let base = u.isEmpty ? q : "\(q) \(u)"
        if let up = line.unit_price { return "\(base) × ₹\(fmt(up))" }
        return base
    }

    // MARK: Tax summary

    private func summary(_ inv: Invoice) -> some View {
        VStack(spacing: 6) {
            if let d = inv.discount_total, d > 0 { discountRow(d) }
            amountRow("Taxable value", inv.taxable_value, showZero: true)
            amountRow("CGST", inv.cgst)
            amountRow("SGST", inv.sgst)
            amountRow("IGST", inv.igst)
            amountRow("Cess", inv.cess)
            amountRow("Round off", inv.round_off)
            HStack {
                Text("Grand total").font(.headline)
                Spacer()
                Text("₹\(fmt(inv.grand_total ?? 0))").font(.headline)
            }
            .padding(.top, 4)
        }
    }

    /// A tax/total line. Hidden when the value is missing, or zero (unless
    /// `showZero`) — so an intra-state invoice shows CGST/SGST and an
    /// inter-state one shows IGST, without both sets cluttering the summary.
    @ViewBuilder
    private func amountRow(_ k: String, _ v: Double?, showZero: Bool = false) -> some View {
        if let v = v, showZero || v != 0 {
            HStack {
                Text(k).foregroundColor(.secondary).font(.subheadline)
                Spacer()
                Text("₹\(fmt(v))").font(.subheadline)
            }
        }
    }

    private func discountRow(_ v: Double) -> some View {
        HStack {
            Text("Discount").foregroundColor(.secondary).font(.subheadline)
            Spacer()
            Text("−₹\(fmt(v))").font(.subheadline).foregroundColor(.green)
        }
    }

    // MARK: Empty / not-invoiced state

    private var unavailable: some View {
        ContentUnavailableView(
            "Invoice not available yet",
            systemImage: "doc.text.magnifyingglass",
            description: Text("This order hasn't been invoiced. The GST invoice appears here once the distributor raises it.")
        )
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Formatting

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? "0"
    }

    private func trim(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : fmt(v)
    }

    private func placeOfSupply(_ inv: Invoice) -> String? {
        let pos = inv.distributor?.place_of_supply ?? inv.place_of_supply
        guard let pos = pos, !pos.isEmpty else { return nil }
        return "Place of supply: \(pos)"
    }

    /// Parse the ISO `issued_at` (with or without fractional seconds) and render
    /// a compact IN-locale date; fall back to the raw string. Mirrors
    /// OrderDetailView.receiptDate.
    private func formattedDate(_ iso: String?) -> String? {
        guard let iso = iso, !iso.isEmpty else { return nil }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso) ?? {
            parser.formatOptions = [.withInternetDateTime]
            return parser.date(from: iso)
        }()
        guard let d = date else { return iso }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_IN")
        out.dateFormat = "dd MMM yyyy, h:mm a"
        return out.string(from: d)
    }
}

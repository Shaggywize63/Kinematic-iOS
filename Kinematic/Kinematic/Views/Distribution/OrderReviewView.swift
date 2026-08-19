import SwiftUI

struct OrderReviewView: View {
    let outletId: String
    let outletName: String?
    let visitId: String?
    @ObservedObject var vm: DistributionViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            content
            Divider()
            footer
        }
        .navigationTitle("Confirm Order")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .navigationBarLeading) { Button("Close") { dismiss() } } }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let p = vm.preview {
                    sectionTitle("Items")
                    ForEach(p.lines) { line in
                        HStack {
                            Text("\(line.qty) × \(line.sku_name ?? line.sku_id)").font(.subheadline)
                            if line.is_free_good == true { freeBadge }
                            Spacer()
                            Text("₹\(fmt(line.total))").font(.subheadline).bold()
                        }
                    }
                    Divider().padding(.vertical, 8)
                    totals(p.totals)
                    if let credit = p.credit { creditBanner(credit) }
                }
                if let err = vm.submitError {
                    Text(err).foregroundColor(.red).font(.caption).padding(.top, 8)
                }
            }
            .padding()
        }
    }

    private func sectionTitle(_ s: String) -> some View {
        Text(s).font(.caption).foregroundColor(.secondary)
    }

    private func totals(_ t: OrderTotals) -> some View {
        VStack(spacing: 6) {
            if t.discount_total > 0 { discountRow(t.discount_total) }
            row("Taxable", t.taxable_value)
            row("CGST",    t.cgst)
            row("SGST",    t.sgst)
            if t.igst > 0 { row("IGST", t.igst) }
            if t.cess > 0 { row("Cess", t.cess) }
            HStack {
                Text("Grand total").font(.headline)
                Spacer()
                Text("₹\(fmt(t.grand_total))").font(.headline)
            }.padding(.top, 4)
        }
    }

    private func row(_ k: String, _ v: Double) -> some View {
        HStack { Text(k).foregroundColor(.secondary).font(.subheadline); Spacer(); Text("₹\(fmt(v))").font(.subheadline) }
    }

    /// Applied scheme/discount total, rendered as a green subtraction so the
    /// saving reads distinctly from the tax rows above the grand total.
    private func discountRow(_ v: Double) -> some View {
        HStack {
            Text("Discount").foregroundColor(.secondary).font(.subheadline)
            Spacer()
            Text("−₹\(fmt(v))").font(.subheadline).foregroundColor(.green)
        }
    }

    /// FREE badge for scheme free-goods lines. Mirrors the capsule badge idiom
    /// used elsewhere (e.g. PlanogramComplianceView.badge).
    private var freeBadge: some View {
        Text("FREE")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(.green)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.18))
            .clipShape(Capsule())
    }

    // MARK: - Credit banner
    //
    // Read-only order-time credit snapshot from the preview response. Never
    // blocks placement — informational only. Hidden entirely when the outlet
    // has no limit set (status "na").

    @ViewBuilder
    private func creditBanner(_ c: Credit) -> some View {
        let status = c.statusValue
        if status != "na" {
            let tint = creditTint(status)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: creditIcon(status)).font(.caption)
                    Text(creditHeadline(c)).font(.subheadline).bold()
                    Spacer()
                }
                .foregroundColor(tint)
                HStack {
                    creditStat("Limit", c.credit_limit)
                    Spacer()
                    creditStat("Balance", c.current_balance)
                    Spacer()
                    creditStat("After order", c.projected_balance)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(tint.opacity(0.1)))
        }
    }

    private func creditStat(_ label: String, _ value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value.map { "₹\(fmt($0))" } ?? "—").font(.caption).foregroundColor(.primary)
        }
    }

    private func creditTint(_ status: String) -> Color {
        switch status {
        case "ok":       return .green
        case "warning":  return .orange
        case "exceeded": return .red
        default:         return .secondary
        }
    }

    private func creditIcon(_ status: String) -> String {
        switch status {
        case "ok":       return "checkmark.seal.fill"
        case "warning":  return "exclamationmark.triangle.fill"
        case "exceeded": return "xmark.octagon.fill"
        default:         return "creditcard"
        }
    }

    private func creditHeadline(_ c: Credit) -> String {
        switch c.statusValue {
        case "warning":
            return "Nearing credit limit · ₹\(fmt(c.available ?? 0)) left"
        case "exceeded":
            let over = max(0, (c.projected_balance ?? 0) - (c.credit_limit ?? 0))
            return "Over credit limit by ₹\(fmt(over))"
        default:
            return "Within credit limit"
        }
    }

    private var footer: some View {
        Button {
            Task {
                await vm.submit(outletId: outletId, outletName: outletName, visitId: visitId)
                if vm.lastQueuedOrder != nil { dismiss() }
            }
        } label: {
            Text(vm.submitting ? "Placing…" : "Place Order")
                .frame(maxWidth: .infinity).font(.headline).padding(.vertical, 14)
                .background(Color(red: 208/255, green: 30/255, blue: 44/255))
                .foregroundColor(.white).cornerRadius(12)
        }
        .disabled(vm.preview == nil || vm.submitting)
        .padding()
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: v)) ?? "0"
    }
}

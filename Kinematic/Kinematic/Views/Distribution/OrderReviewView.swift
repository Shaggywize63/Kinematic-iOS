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
                            Spacer()
                            Text("₹\(fmt(line.total))").font(.subheadline).bold()
                        }
                    }
                    Divider().padding(.vertical, 8)
                    totals(p.totals)
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

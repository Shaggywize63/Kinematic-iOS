import SwiftUI
import UIKit

/// Generate Proposal — pick the products a lead is interested in, generate an
/// AI-tailored, branded PDF on the backend, then share it by WhatsApp / email
/// or save it to the phone via the system share sheet (LeadShareActivitySheet).
struct GenerateProposalView: View {
    let lead: Lead
    @Environment(\.dismiss) private var dismiss

    struct Line: Identifiable {
        let id = UUID()
        let product: Product
        var quantity: Double
        var discountPct: Double
    }

    @State private var products: [Product] = []
    @State private var lines: [Line] = []
    @State private var title = "Product Proposal"
    @State private var busy = false
    @State private var errorText: String?
    @State private var generated: Proposal?
    @State private var preparingShare = false
    @State private var shareItems: [Any] = []
    @State private var showShare = false

    private func inr(_ n: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency; f.currencyCode = "INR"; f.maximumFractionDigits = 2
        f.locale = Locale(identifier: "en_IN")
        return f.string(from: NSNumber(value: n)) ?? "INR \(n)"
    }

    private func lineNet(_ l: Line) -> Double {
        (l.product.unitPrice ?? 0) * l.quantity * (1 - l.discountPct / 100)
    }
    private var subtotal: Double { lines.reduce(0) { $0 + (($1.product.unitPrice ?? 0) * $1.quantity) } }
    private var discountTotal: Double { lines.reduce(0) { $0 + (($1.product.unitPrice ?? 0) * $1.quantity * ($1.discountPct / 100)) } }
    private var taxTotal: Double { lines.reduce(0) { $0 + (lineNet($1) * ((($1.product.taxPct ?? 18)) / 100)) } }
    private var grandTotal: Double { subtotal - discountTotal + taxTotal }

    var body: some View {
        NavigationStack {
            Form {
                if let gen = generated {
                    resultSections(gen)
                } else {
                    builderSections
                }
            }
            .navigationTitle("Generate Proposal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                if generated == nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { Task { await generate() } } label: {
                            if busy { ProgressView() } else { Text("Generate").bold() }
                        }
                        .disabled(busy || lines.isEmpty)
                    }
                }
            }
            .task { if products.isEmpty { products = (try? await CRMService.shared.listProducts()) ?? [] } }
            .sheet(isPresented: $showShare) { LeadShareActivitySheet(items: shareItems) }
        }
    }

    @ViewBuilder private var builderSections: some View {
        Section("Proposal") {
            TextField("Title", text: $title)
            Text("For \(lead.displayName)").font(.footnote).foregroundColor(.secondary)
        }
        Section {
            Menu {
                ForEach(products) { p in
                    Button(action: { addProduct(p) }) {
                        Text(p.unitPrice != nil ? "\(p.name) — \(inr(p.unitPrice ?? 0))" : p.name)
                    }
                }
            } label: {
                Label(products.isEmpty ? "Loading products…" : "Add product", systemImage: "plus.circle.fill")
            }
            .disabled(products.isEmpty)
        }
        Section("Products") {
            if lines.isEmpty {
                Text("No products added yet.").foregroundColor(.secondary)
            } else {
                ForEach($lines) { $line in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(line.product.name).font(.headline)
                        Stepper("Qty: \(Int(line.quantity))", value: $line.quantity, in: 1...99999, step: 1)
                        HStack {
                            Text("Discount %")
                            Spacer()
                            TextField("0", value: $line.discountPct, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 70)
                        }
                        HStack {
                            Spacer()
                            Text(inr(lineNet(line))).font(.subheadline).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { lines.remove(atOffsets: $0) }
            }
        }
        if !lines.isEmpty {
            Section("Summary") {
                totalRow("Subtotal", subtotal)
                if discountTotal > 0 { totalRow("Discount", -discountTotal) }
                totalRow("GST", taxTotal)
                totalRow("Grand Total", grandTotal, bold: true)
            }
        }
        if let e = errorText {
            Section { Text(e).foregroundColor(.red).font(.footnote) }
        }
    }

    @ViewBuilder private func resultSections(_ gen: Proposal) -> some View {
        Section {
            Label("Proposal \(gen.proposalNumber ?? "") generated", systemImage: "checkmark.seal.fill")
                .foregroundColor(.green)
            if let t = gen.grandTotal { totalRow("Grand Total", t, bold: true) }
        }
        if let note = gen.coverNote, !note.isEmpty {
            Section("Cover note") { Text(note).font(.footnote).foregroundColor(.secondary) }
        }
        Section {
            Button {
                Task { await prepareShare(gen) }
            } label: {
                if preparingShare { ProgressView() } else { Label("Share / Save PDF", systemImage: "square.and.arrow.up") }
            }
            .disabled(preparingShare || (gen.pdfUrl ?? "").isEmpty)
        } footer: {
            Text("Opens the share sheet — send on WhatsApp or email, or Save to Files on your phone.")
        }
        if let e = errorText {
            Section { Text(e).foregroundColor(.red).font(.footnote) }
        }
    }

    private func totalRow(_ label: String, _ value: Double, bold: Bool = false) -> some View {
        HStack {
            Text(label).fontWeight(bold ? .bold : .regular)
            Spacer()
            Text(inr(value)).fontWeight(bold ? .bold : .regular)
        }
    }

    private func addProduct(_ p: Product) {
        lines.append(Line(product: p, quantity: 1, discountPct: 0))
    }

    private func generate() async {
        errorText = nil; busy = true
        defer { busy = false }
        let items: [[String: Any]] = lines.map { l in
            [
                "product_id": l.product.id,
                "name": l.product.name,
                "sku": l.product.sku ?? "",
                "unit": l.product.unit ?? "",
                "unit_price": l.product.unitPrice ?? 0,
                "quantity": l.quantity,
                "discount_pct": l.discountPct,
                "tax_rate_pct": l.product.taxPct ?? 18,
            ]
        }
        do {
            let p = try await CRMService.shared.createProposal(leadId: lead.id, title: title, items: items)
            generated = p
            await prepareShare(p)   // auto-open the share sheet on success
        } catch {
            errorText = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Download the signed PDF to a temp file and present the system share sheet.
    private func prepareShare(_ gen: Proposal) async {
        guard let urlStr = gen.pdfUrl, let url = URL(string: urlStr) else { return }
        errorText = nil; preparingShare = true
        defer { preparingShare = false }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let name = "Proposal-\(gen.proposalNumber ?? gen.id).pdf".replacingOccurrences(of: "/", with: "-")
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            try data.write(to: tmp, options: .atomic)
            shareItems = [tmp]
            showShare = true
        } catch {
            errorText = "Could not prepare the PDF to share."
        }
    }
}

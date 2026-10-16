import SwiftUI

/// "Upsells" section for the lead- and deal-detail screens — additional revenue
/// logged against an existing customer, kept separate from the deal's own value.
/// Pass a dealId OR a leadId. Lists upsells newest-first with a running "won"
/// total and an inline add form (amount, product, qty, status, date, note).
struct UpsellsSectionView: View {
    var dealId: String? = nil
    var leadId: String? = nil

    @State private var rows: [Upsell] = []
    @State private var loading = true
    @State private var adding = false
    @State private var saving = false
    @State private var errorMsg: String?

    // form
    @State private var amount = ""
    @State private var product = ""
    @State private var quantity = ""
    @State private var status = "won"
    @State private var occurredAt = ""
    @State private var note = ""

    private var wonTotal: Double {
        rows.filter { ($0.status ?? "won").lowercased() == "won" }.reduce(0) { $0 + ($1.amount ?? 0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("UPSELLS")
                    .font(.system(size: 11, weight: .black))
                    .tracking(0.8)
                    .foregroundColor(Brand.red)
                if wonTotal > 0 {
                    Text("\(inr(wonTotal)) won")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(red: 0x10/255, green: 0xB9/255, blue: 0x81/255))
                }
                Spacer()
                if !adding {
                    Button {
                        adding = true
                    } label: {
                        Label("Add", systemImage: "plus")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .tint(Brand.red)
                }
            }

            if adding { addForm }

            if loading {
                Text("Loading…").font(.footnote).foregroundColor(.secondary)
            } else if rows.isEmpty {
                Text("No upsells logged yet").font(.footnote).foregroundColor(.secondary)
            } else {
                ForEach(rows) { u in
                    UpsellRowView(upsell: u, onDelete: { remove(u.id) })
                    if u.id != rows.last?.id { Divider() }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground)))
        .task(id: taskKey) { await load() }
    }

    private var taskKey: String { "\(dealId ?? "")|\(leadId ?? "")" }

    @ViewBuilder private var addForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Amount (₹)", text: $amount)
                .keyboardType(.decimalPad)
                .textFieldStyle(.roundedBorder)
            TextField("Product / what", text: $product)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 10) {
                TextField("Qty", text: $quantity)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
                TextField("Date (YYYY-MM-DD)", text: $occurredAt)
                    .textFieldStyle(.roundedBorder)
            }
            Picker("Status", selection: $status) {
                Text("Won").tag("won")
                Text("Proposed").tag("proposed")
                Text("Lost").tag("lost")
            }
            .pickerStyle(.segmented)
            TextField("Note", text: $note)
                .textFieldStyle(.roundedBorder)
            if let e = errorMsg {
                Text(e).font(.caption).foregroundColor(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { resetForm(); adding = false; errorMsg = nil }
                    .buttonStyle(.bordered)
                Button(saving ? "Saving…" : "Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .tint(Brand.red)
                    .disabled(saving || amount.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .tertiarySystemBackground)))
    }

    private func resetForm() {
        amount = ""; product = ""; quantity = ""; status = "won"; occurredAt = ""; note = ""
    }

    private func load() async {
        loading = true
        rows = (try? await CRMService.shared.listUpsells(dealId: dealId, leadId: leadId)) ?? []
        loading = false
    }

    private func save() {
        errorMsg = nil
        saving = true
        var body: [String: Any] = ["amount": amount.trimmingCharacters(in: .whitespaces), "status": status]
        if let d = dealId, !d.isEmpty { body["deal_id"] = d }
        if let l = leadId, !l.isEmpty { body["lead_id"] = l }
        let p = product.trimmingCharacters(in: .whitespaces); if !p.isEmpty { body["product_name"] = p }
        let q = quantity.trimmingCharacters(in: .whitespaces); if !q.isEmpty { body["quantity"] = q }
        let oc = occurredAt.trimmingCharacters(in: .whitespaces); if !oc.isEmpty { body["occurred_at"] = oc }
        let n = note.trimmingCharacters(in: .whitespaces); if !n.isEmpty { body["note"] = n }
        Task {
            do {
                _ = try await CRMService.shared.createUpsell(body)
                await load()
                resetForm()
                saving = false
                adding = false
            } catch {
                saving = false
                errorMsg = error.localizedDescription
            }
        }
    }

    private func remove(_ id: String) {
        Task {
            try? await CRMService.shared.deleteUpsell(id: id)
            await load()
        }
    }
}

private struct UpsellRowView: View {
    let upsell: Upsell
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(inr(upsell.amount)).font(.system(size: 15, weight: .bold))
                    if let q = upsell.quantity {
                        Text("× \(q.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(q)) : String(q))")
                            .font(.caption).foregroundColor(.secondary)
                    }
                    Text(statusLabel).font(.system(size: 11, weight: .bold)).foregroundColor(statusColor)
                }
                if let p = upsell.productName, !p.isEmpty { Text(p).font(.subheadline) }
                if let n = upsell.note, !n.isEmpty { Text(n).font(.caption).foregroundColor(.secondary) }
                if !meta.isEmpty { Text(meta).font(.caption2).foregroundColor(.secondary) }
            }
            Spacer()
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private var meta: String {
        [String(upsell.occurredAt?.prefix(10) ?? ""), upsell.createdByName ?? ""]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
    private var statusLabel: String {
        switch (upsell.status ?? "won").lowercased() {
        case "proposed": return "Proposed"
        case "lost": return "Lost"
        default: return "Won"
        }
    }
    private var statusColor: Color {
        switch (upsell.status ?? "won").lowercased() {
        case "proposed": return Color(red: 0x63/255, green: 0x66/255, blue: 0xF1/255)
        case "lost": return Color(red: 0xEF/255, green: 0x44/255, blue: 0x44/255)
        default: return Color(red: 0x10/255, green: 0xB9/255, blue: 0x81/255)
        }
    }
}

/// ₹ with Indian digit grouping.
private func inr(_ v: Double?) -> String {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.locale = Locale(identifier: "en_IN")
    f.maximumFractionDigits = 2
    return "₹" + (f.string(from: NSNumber(value: v ?? 0)) ?? "0")
}

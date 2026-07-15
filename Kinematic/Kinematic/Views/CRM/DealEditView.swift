import SwiftUI

struct DealEditView: View {
    let deal: Deal
    let stages: [Stage]
    let onSaved: (Deal) -> Void
    @Environment(\.dismiss) private var dismiss

    // Fixed follow-up action set — same slugs the web / Android deal-edit
    // pickers use and the backend maps to a friendly reminder subject.
    private static let nextActions: [(slug: String, label: String)] = [
        ("call", "Call"), ("whatsapp", "WhatsApp"), ("meeting", "Meeting"),
        ("site_visit", "Site Visit"), ("email", "Email"), ("follow_up", "Follow-up"),
    ]

    @State private var name: String
    @State private var amount: String
    @State private var stageId: String
    @State private var probability: String
    @State private var closeDate: String
    // Next Action → scheduled follow-up (action type + due date). Replaces the
    // old free-text field, which never persisted (crm_deals has no column).
    @State private var nextActionType: String
    @State private var nextActionDate: String
    @State private var saving = false
    @State private var errorMessage: String?

    // Admin-defined deal custom fields (e.g. the SRS Dealer lookup). Seeded
    // from the deal's stored custom_fields once defs load; edited values ride
    // the PATCH, which the backend merges into the stored blob.
    @StateObject private var customFields = CustomFieldsModel()

    // Products of Interest editor — steel-dealer tenants only. The basket
    // is the DEAL's own custom_fields.product_lines (with volume_kg kept
    // in sync); when the deal has a linked lead the rows are also
    // mirrored back onto that lead so lead-level reports stay consistent.
    @StateObject private var productLines = ProductLinesModel()
    // Only persist the basket if it was actually hydrated — guards
    // against a half-initialised model clobbering real rows with the
    // empty default row.
    @State private var productsLoaded = false

    private var showProducts: Bool { ClientFeatures.isTataTiscon }

    init(deal: Deal, stages: [Stage], onSaved: @escaping (Deal) -> Void) {
        self.deal = deal
        self.stages = stages
        self.onSaved = onSaved
        _name = State(initialValue: deal.name)
        _amount = State(initialValue: deal.amount.map { String(Int($0)) } ?? "")
        _stageId = State(initialValue: deal.stageId ?? "")
        _probability = State(initialValue: deal.probability.map { String(Int($0 * 100)) } ?? "")
        _closeDate = State(initialValue: deal.expectedCloseDate.map { String($0.prefix(10)) } ?? "")
        let cf = deal.customFields ?? [:]
        _nextActionType = State(initialValue: (cf["next_action_type"]?.raw?.any as? String) ?? "")
        _nextActionDate = State(initialValue: (cf["next_action_at"]?.raw?.any as? String).map { String($0.prefix(10)) } ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Name", text: $name)
                    TextField("Amount (₹)", text: $amount).keyboardType(.numberPad)
                }
                Section("Stage") {
                    Picker("Stage", selection: $stageId) {
                        Text("—").tag("")
                        ForEach(stages) { s in
                            Text(s.name).tag(s.id)
                        }
                    }
                    TextField("Probability (%)", text: $probability).keyboardType(.numberPad)
                }
                Section("Timing") {
                    TextField("Expected close (YYYY-MM-DD)", text: $closeDate)
                }

                // Products of Interest — fix a mis-entered product after the
                // deal was created. Edits the deal's own basket (and mirrors
                // to the linked lead when one exists).
                if showProducts {
                    ProductLinesSection(model: productLines)
                }

                // Admin-defined deal custom fields (Dealer lookup, …).
                // Self-gates on loaded defs; renders nothing when none exist.
                CustomFieldsSection(model: customFields)

                Section("Next Action") {
                    Picker("Action", selection: $nextActionType) {
                        Text("None").tag("")
                        ForEach(Self.nextActions, id: \.slug) { a in
                            Text(a.label).tag(a.slug)
                        }
                    }
                    if !nextActionType.isEmpty {
                        TextField("Due date (YYYY-MM-DD)", text: $nextActionDate)
                        if nextActionDate.isEmpty {
                            Text("Pick a due date to schedule this as a reminder.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Edit Deal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: { if saving { ProgressView() } else { Text("Save") } }
                        .disabled(saving || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .task {
                await customFields.load(entity: "deal")
                customFields.hydrate(from: deal.customFields)
            }
            .task {
                guard showProducts else { return }
                await productLines.load()
                // Hydrate from the DEAL's own custom_fields — the deal
                // carries its own product_lines basket now, so the edit
                // form no longer round-trips through the linked lead.
                productLines.hydrate(from: deal.customFields)
                // Legacy fallback: deals converted before the deal carried
                // its own basket have product_lines only on the linked
                // lead — seed from there so the editor isn't empty, and
                // the next save migrates the rows onto the deal.
                let dealHasLines = (deal.customFields?["product_lines"]?.raw?.any as? [Any])?.isEmpty == false
                if !dealHasLines, let lid = deal.leadId,
                   let lead = try? await CRMService.shared.getLead(id: lid) {
                    productLines.hydrate(from: lead.customFields)
                }
                productsLoaded = true
            }
            .alert("Update failed", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() async {
        saving = true; defer { saving = false }
        var body: [String: Any] = ["name": name]
        body["amount"] = Double(amount) ?? 0
        if !stageId.isEmpty { body["stage_id"] = stageId }
        if let p = Double(probability) { body["probability"] = p / 100.0 }
        body["expected_close_date"] = closeDate.isEmpty ? NSNull() : closeDate
        // Follow-up → deal.custom_fields { next_action_type, next_action_at }.
        // Backend spawns a planned reminder when it changes; nulls clear it.
        var followUp: [String: Any] = [:]
        if !nextActionType.isEmpty, !nextActionDate.isEmpty {
            followUp["next_action_type"] = nextActionType
            followUp["next_action_at"] = nextActionDate
        } else {
            followUp["next_action_type"] = NSNull()
            followUp["next_action_at"] = NSNull()
        }
        // Admin-defined custom-field edits + the follow-up pair. The backend
        // PATCH merges into the stored blob, so unrelated keys survive.
        var mergedCf = customFields.jsonValues
        for (k, v) in followUp { mergedCf[k] = v }
        // Basket → the DEAL's OWN custom_fields: product_lines rows plus the
        // volume_kg mirror (qty × 1000 for tonnes). Never touches `amount` —
        // the ₹ figure stays whatever the rep typed above. Skipped entirely
        // when the deal never had a basket AND the editor still holds the
        // single empty default row, so plain field edits don't stamp an
        // empty `product_lines: [{}]` onto every deal (or, via the lead
        // mirror below, wipe a legacy lead-side basket).
        let basketRows = (productLines.jsonValues["product_lines"] as? [[String: Any]]) ?? []
        let hadDealLines = (deal.customFields?["product_lines"]?.raw?.any as? [[String: Any]])?.isEmpty == false
        let writeBasket = showProducts && productsLoaded
            && (basketRows.contains(where: { !$0.isEmpty }) || hadDealLines)
        if writeBasket {
            mergedCf["product_lines"] = basketRows
            let volumeKg = productLines.lines.reduce(0.0) { acc, l in
                guard let qty = Double(l.quantityText), qty > 0 else { return acc }
                let factor = (l.measuringUnit?.lowercased() == "tonne") ? 1000.0 : 1.0
                return acc + qty * factor
            }
            mergedCf["volume_kg"] = (volumeKg * 100).rounded() / 100
        }
        body["custom_fields"] = mergedCf
        do {
            let updated = try await CRMService.shared.patchDeal(id: deal.id, body: body)
            // Keep mirroring the corrected basket onto the linked lead so
            // lead-level reports reflect it. Deals with no linked lead
            // simply skip the mirror.
            if writeBasket, let lid = deal.leadId {
                _ = try? await CRMService.shared.updateLead(id: lid, body: ["custom_fields": productLines.jsonValues])
            }
            onSaved(updated)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

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

    // Products of Interest editor — Tata/Kaiyo only, and only when the deal
    // has a linked lead (the basket lives on that lead's custom_fields).
    @StateObject private var productLines = ProductLinesModel()
    // Only write the basket back if we actually loaded it — otherwise a
    // transient lead-fetch failure would clobber a real basket with the
    // empty default row.
    @State private var productsLoaded = false

    private var showProducts: Bool { ClientFeatures.isTataTiscon && deal.leadId != nil }

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
                // deal was created. Edits the linked lead's basket.
                if showProducts {
                    ProductLinesSection(model: productLines)
                }

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
                guard showProducts, let lid = deal.leadId else { return }
                await productLines.load()
                if let lead = try? await CRMService.shared.getLead(id: lid) {
                    productLines.hydrate(from: lead.customFields)
                    productsLoaded = true
                }
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
        body["custom_fields"] = followUp
        do {
            let updated = try await CRMService.shared.patchDeal(id: deal.id, body: body)
            // Write the corrected basket back onto the linked lead (only when
            // it was actually loaded) so the deal Products card + report reflect it.
            if showProducts, productsLoaded, let lid = deal.leadId {
                _ = try? await CRMService.shared.updateLead(id: lid, body: ["custom_fields": productLines.jsonValues])
            }
            onSaved(updated)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

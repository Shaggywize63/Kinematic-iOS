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
                    // Amount is fixed once the deal exists — market prices
                    // change but a created deal's value must not. Shown for
                    // reference only; the backend also rejects amount edits.
                    HStack {
                        Text("Amount (₹)")
                        Spacer()
                        Text(amount.isEmpty ? "—" : amount)
                            .foregroundColor(.secondary)
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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
            .alert("Update failed", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() async {
        saving = true; defer { saving = false }
        // Price lock: `amount` is NOT sent — a deal's value, products basket
        // and volume are fixed at creation (market prices drift; the deal
        // must not). The backend strips those keys from every PATCH too, so
        // old builds can't bypass the lock either.
        var body: [String: Any] = ["name": name]
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
        body["custom_fields"] = mergedCf
        do {
            let updated = try await CRMService.shared.patchDeal(id: deal.id, body: body)
            onSaved(updated)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

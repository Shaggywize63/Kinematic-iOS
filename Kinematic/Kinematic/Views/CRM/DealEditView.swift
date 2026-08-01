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
    // Account + pipeline are editable on the edit form to match the create
    // form (a deal's account/pipeline can legitimately change after creation).
    @State private var accountId: String
    @State private var pipelineId: String
    @State private var stageId: String
    @State private var probability: String
    @State private var closeDate: String
    // Next Action → scheduled follow-up (action type + due date). Replaces the
    // old free-text field, which never persisted (crm_deals has no column).
    @State private var nextActionType: String
    @State private var nextActionDate: String
    @State private var saving = false
    @State private var errorMessage: String?

    // Pipelines + the stage list for the selected pipeline. Seeded from the
    // stages the detail screen passed in, then reloaded when the pipeline
    // changes so the stage picker always matches the chosen pipeline.
    @State private var pipelines: [Pipeline] = []
    @State private var editStages: [Stage]

    // Admin-defined deal custom fields (e.g. the SRS Dealer lookup). Seeded
    // from the deal's stored custom_fields once defs load; edited values ride
    // the PATCH, which the backend merges into the stored blob.
    @StateObject private var customFields = CustomFieldsModel()
    /// Built-in field overrides (hide / relabel / require) for deal columns.
    @StateObject private var fieldOverrides = LeadFieldOverridesModel()

    init(deal: Deal, stages: [Stage], onSaved: @escaping (Deal) -> Void) {
        self.deal = deal
        self.stages = stages
        self.onSaved = onSaved
        _name = State(initialValue: deal.name)
        _amount = State(initialValue: deal.amount.map { String(Int($0)) } ?? "")
        _accountId = State(initialValue: deal.accountId ?? "")
        _pipelineId = State(initialValue: deal.pipelineId ?? "")
        _stageId = State(initialValue: deal.stageId ?? "")
        _editStages = State(initialValue: stages)
        _probability = State(initialValue: deal.probability.map { String(Int($0 * 100)) } ?? "")
        _closeDate = State(initialValue: deal.expectedCloseDate.map { String($0.prefix(10)) } ?? "")
        let cf = deal.customFields ?? [:]
        _nextActionType = State(initialValue: (cf["next_action_type"]?.raw?.any as? String) ?? "")
        _nextActionDate = State(initialValue: (cf["next_action_at"]?.raw?.any as? String).map { String($0.prefix(10)) } ?? "")
    }

    private var currentPipeline: Pipeline? {
        pipelines.first(where: { $0.id == pipelineId })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    if !fieldOverrides.isHidden(entity: "deal", "name") {
                        TextField(fieldOverrides.labelFor(entity: "deal", "name", "Name"), text: $name)
                    }
                    // Amount is fixed once the deal exists — market prices
                    // change but a created deal's value must not. Shown for
                    // reference only; edit the Products basket below to change
                    // the deal's value through the sanctioned recompute path.
                    if !fieldOverrides.isHidden(entity: "deal", "amount") {
                        HStack {
                            Text(fieldOverrides.labelFor(entity: "deal", "amount", "Amount (₹)"))
                            Spacer()
                            Text(amount.isEmpty ? "—" : amount)
                                .foregroundColor(.secondary)
                            Image(systemName: "lock.fill")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    if !fieldOverrides.isHidden(entity: "deal", "account_id") {
                        TextField(fieldOverrides.labelFor(entity: "deal", "account_id", "Account ID (optional)"), text: $accountId)
                    }
                }

                if !pipelines.isEmpty && (!fieldOverrides.isHidden(entity: "deal", "pipeline_id") || !fieldOverrides.isHidden(entity: "deal", "stage_id")) {
                    Section("Pipeline") {
                        if !fieldOverrides.isHidden(entity: "deal", "pipeline_id") {
                            if pipelines.count == 1 {
                                HStack {
                                    Text(currentPipeline?.name ?? "Default pipeline")
                                    Spacer()
                                    Text("· default")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                            } else {
                                Picker(fieldOverrides.labelFor(entity: "deal", "pipeline_id", "Pipeline"), selection: $pipelineId) {
                                    ForEach(pipelines) { p in
                                        if p.isDefault == true {
                                            Text("\(p.name) (default)").tag(p.id)
                                        } else {
                                            Text(p.name).tag(p.id)
                                        }
                                    }
                                }
                                .onChange(of: pipelineId) { _, newId in
                                    Task { await loadStages(pipelineId: newId, resetSelection: true) }
                                }
                            }
                        }
                        if !fieldOverrides.isHidden(entity: "deal", "stage_id") && !editStages.isEmpty {
                            Picker(fieldOverrides.labelFor(entity: "deal", "stage_id", "Stage"), selection: $stageId) {
                                Text("—").tag("")
                                ForEach(editStages) { s in Text(s.name).tag(s.id) }
                            }
                        }
                        if !fieldOverrides.isHidden(entity: "deal", "probability") {
                            TextField(fieldOverrides.labelFor(entity: "deal", "probability", "Probability (%)"), text: $probability)
                                .keyboardType(.numberPad)
                        }
                    }
                }

                if !fieldOverrides.isHidden(entity: "deal", "expected_close_date") {
                    Section("Timing") {
                        TextField(fieldOverrides.labelFor(entity: "deal", "expected_close_date", "Expected close (YYYY-MM-DD)"), text: $closeDate)
                    }
                }

                // Admin-defined deal custom fields (Dealer lookup, …).
                // Self-gates on loaded defs; renders nothing when none exist.
                CustomFieldsSection(model: customFields)

                // Products basket — the same self-contained editor the deal
                // detail screen uses. Editing here saves product_lines onto the
                // deal (recomputing its value) through the sanctioned products
                // path, so the generic amount price-lock stays intact.
                if ClientFeatures.isTataTiscon {
                    Section {
                        DealProductsCard(dealId: deal.id)
                    }
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
                        .disabled(saving || (!fieldOverrides.isHidden(entity: "deal", "name") && name.trimmingCharacters(in: .whitespaces).isEmpty))
                }
            }
            .task {
                await customFields.load(entity: "deal")
                customFields.hydrate(from: deal.customFields)
            }
            .task { await fieldOverrides.load() }
            .task { await loadPipelines() }
            .alert("Update failed", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func loadPipelines() async {
        pipelines = (try? await CRMService.shared.listPipelines()) ?? []
        if pipelineId.isEmpty {
            let preferred = pipelines.first(where: { $0.isDefault == true }) ?? pipelines.first
            if let preferred { pipelineId = preferred.id }
        }
        // Only fetch stages if we weren't handed a matching list already.
        if !pipelineId.isEmpty && editStages.isEmpty {
            await loadStages(pipelineId: pipelineId, resetSelection: false)
        }
    }

    private func loadStages(pipelineId: String, resetSelection: Bool) async {
        editStages = (try? await CRMService.shared.listStages(pipelineId: pipelineId)) ?? []
        // Keep the current stage if it still belongs to the pipeline; otherwise
        // fall back to the first stage so the picker never points at a stale id.
        if resetSelection || !editStages.contains(where: { $0.id == stageId }) {
            stageId = editStages.first?.id ?? ""
        }
    }

    private func save() async {
        saving = true; defer { saving = false }
        // Price lock: `amount` is NOT sent — a deal's value, products basket
        // and volume are fixed here (edit the Products basket to change value).
        // The backend strips those keys from every PATCH too.
        var body: [String: Any] = ["name": name]
        body["account_id"] = accountId.trimmingCharacters(in: .whitespaces).isEmpty ? NSNull() : accountId
        if !pipelineId.isEmpty { body["pipeline_id"] = pipelineId }
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
        // PATCH merges into the stored blob, so unrelated keys (incl. the
        // product basket edited above) survive.
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

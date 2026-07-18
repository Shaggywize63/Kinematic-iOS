import SwiftUI

struct DealCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var accountId = ""
    @State private var amount: Double = 0
    @State private var hasCloseDate = false
    @State private var expectedCloseDate = Calendar.current.date(byAdding: .month, value: 1, to: Date()) ?? Date()
    @State private var pipelines: [Pipeline] = []
    @State private var stages: [Stage] = []
    @State private var pipelineId: String = ""
    @State private var stageId: String = ""

    /// Admin-defined deal custom fields (e.g. the SRS Dealer lookup).
    /// Same model + section the lead / activity forms use; renders
    /// nothing when the tenant has no entity_type='deal' defs.
    @StateObject private var customFields = CustomFieldsModel()
    /// Built-in field overrides (hide / relabel / require) for deal columns,
    /// configured on the web Settings → Custom Fields page. Deals aren't
    /// B2B/B2C-scoped so no isB2C is passed.
    @StateObject private var fieldOverrides = LeadFieldOverridesModel()
    /// Multi-row product basket (product interest) for steel dealers —
    /// writes custom_fields.product_lines + the legacy single-product
    /// mirrors, and its estimated_amount total seeds the deal amount.
    @StateObject private var productLines = ProductLinesModel()

    let onSubmit: ([String: Any]) async -> Void

    private var currentPipeline: Pipeline? {
        pipelines.first(where: { $0.id == pipelineId })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Deal") {
                    if !fieldOverrides.isHidden(entity: "deal", "name") {
                        TextField(fieldOverrides.labelFor(entity: "deal", "name", "Deal name"), text: $name)
                    }
                    if !fieldOverrides.isHidden(entity: "deal", "amount") {
                        HStack {
                            Text(fieldOverrides.labelFor(entity: "deal", "amount", "Amount (₹)"))
                            Spacer()
                            TextField("0", value: $amount, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
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
                                // Single pipeline: show a read-only label instead of a
                                // useless picker. Matches the web dashboard's behaviour
                                // where the dropdown collapses to a static "Default
                                // pipeline" affordance when there's nothing to choose.
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
                                    Task { await loadStages(pipelineId: newId) }
                                }
                            }
                        }
                        if !fieldOverrides.isHidden(entity: "deal", "stage_id") && !stages.isEmpty {
                            Picker(fieldOverrides.labelFor(entity: "deal", "stage_id", "Stage"), selection: $stageId) {
                                ForEach(stages) { s in Text(s.name).tag(s.id) }
                            }
                        }
                    }
                }

                if !fieldOverrides.isHidden(entity: "deal", "expected_close_date") {
                    Section(fieldOverrides.labelFor(entity: "deal", "expected_close_date", "Close date")) {
                        Toggle("Set expected close date", isOn: $hasCloseDate)
                        if hasCloseDate {
                            DatePicker("Expected close", selection: $expectedCloseDate, displayedComponents: .date)
                        }
                    }
                }

                // Admin-defined deal custom fields (Dealer lookup, …).
                // Self-gates on loaded defs; renders nothing when none exist.
                CustomFieldsSection(model: customFields)

                // Steel dealers (Tata Tiscon + BMW) capture the product
                // basket on the deal itself — multiple products with
                // per-line qty/unit and weight- or piece-based pricing.
                // Mirrors the web dashboard's deal-create form.
                if ClientFeatures.isTataTiscon {
                    ProductLinesSection(model: productLines)
                }
            }
            .navigationTitle("New Deal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await onSubmit(buildBody())
                            dismiss()
                        }
                    }.disabled(!fieldOverrides.isHidden(entity: "deal", "name") && name.isEmpty)
                }
            }
            .task { await loadPipelines() }
            .task { await customFields.load(entity: "deal") }
            .task { await fieldOverrides.load() }
            .task { await productLines.load() }
        }
    }

    private func loadPipelines() async {
        pipelines = (try? await CRMService.shared.listPipelines()) ?? []
        if pipelineId.isEmpty {
            // Prefer the org's default pipeline; fall back to the first one so
            // we never end up with an empty selection when at least one
            // pipeline exists.
            let preferred = pipelines.first(where: { $0.isDefault == true }) ?? pipelines.first
            if let preferred { pipelineId = preferred.id }
        }
        if !pipelineId.isEmpty { await loadStages(pipelineId: pipelineId) }
    }

    private func loadStages(pipelineId: String) async {
        stages = (try? await CRMService.shared.listStages(pipelineId: pipelineId)) ?? []
        if stageId.isEmpty, let first = stages.first { stageId = first.id }
    }

    private func buildBody() -> [String: Any] {
        var body: [String: Any] = ["name": name, "amount": amount, "status": "open"]
        if !accountId.isEmpty { body["account_id"] = accountId }
        if !pipelineId.isEmpty { body["pipeline_id"] = pipelineId }
        if !stageId.isEmpty { body["stage_id"] = stageId }
        if hasCloseDate {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            body["expected_close_date"] = f.string(from: expectedCloseDate)
        }
        // Merge the product basket into custom_fields last so its
        // product_lines + legacy mirrors win over any stale generic values.
        var cf = customFields.jsonValues
        for (k, v) in productLines.jsonValues { cf[k] = v }
        if !cf.isEmpty { body["custom_fields"] = cf }
        // When the rep didn't type an amount, default it to the basket
        // total so the deal value matches the picked products.
        if amount == 0, let total = productLines.jsonValues["estimated_amount"] as? Double, total > 0 {
            body["amount"] = total
        }
        return body
    }
}

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

    let onSubmit: ([String: Any]) async -> Void

    private var currentPipeline: Pipeline? {
        pipelines.first(where: { $0.id == pipelineId })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Deal") {
                    TextField("Deal name", text: $name)
                    HStack {
                        Text("Amount (₹)")
                        Spacer()
                        TextField("0", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    TextField("Account ID (optional)", text: $accountId)
                }

                if !pipelines.isEmpty {
                    Section("Pipeline") {
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
                            Picker("Pipeline", selection: $pipelineId) {
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
                        if !stages.isEmpty {
                            Picker("Stage", selection: $stageId) {
                                ForEach(stages) { s in Text(s.name).tag(s.id) }
                            }
                        }
                    }
                }

                Section("Close date") {
                    Toggle("Set expected close date", isOn: $hasCloseDate)
                    if hasCloseDate {
                        DatePicker("Expected close", selection: $expectedCloseDate, displayedComponents: .date)
                    }
                }

                // Admin-defined deal custom fields (Dealer lookup, …).
                // Self-gates on loaded defs; renders nothing when none exist.
                CustomFieldsSection(model: customFields)
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
                    }.disabled(name.isEmpty)
                }
            }
            .task { await loadPipelines() }
            .task { await customFields.load(entity: "deal") }
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
        let cf = customFields.jsonValues
        if !cf.isEmpty { body["custom_fields"] = cf }
        return body
    }
}

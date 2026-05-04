import SwiftUI

struct DealEditView: View {
    let deal: Deal
    let stages: [Stage]
    let onSaved: (Deal) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var amount: String
    @State private var stageId: String
    @State private var probability: String
    @State private var closeDate: String
    @State private var nextAction: String
    @State private var saving = false
    @State private var errorMessage: String?

    init(deal: Deal, stages: [Stage], onSaved: @escaping (Deal) -> Void) {
        self.deal = deal
        self.stages = stages
        self.onSaved = onSaved
        _name = State(initialValue: deal.name)
        _amount = State(initialValue: deal.amount.map { String(Int($0)) } ?? "")
        _stageId = State(initialValue: deal.stageId ?? "")
        _probability = State(initialValue: deal.probability.map { String(Int($0 * 100)) } ?? "")
        _closeDate = State(initialValue: deal.expectedCloseDate.map { String($0.prefix(10)) } ?? "")
        _nextAction = State(initialValue: "")
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
                    TextField("Next action", text: $nextAction)
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
        body["next_action"] = nextAction.isEmpty ? NSNull() : nextAction
        do {
            let updated = try await CRMService.shared.patchDeal(id: deal.id, body: body)
            onSaved(updated)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

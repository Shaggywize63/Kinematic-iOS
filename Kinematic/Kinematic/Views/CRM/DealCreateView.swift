import SwiftUI

struct DealCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var accountId = ""
    @State private var amount: Double = 0

    let onSubmit: (String, String?, Double) async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Deal") {
                    TextField("Deal name", text: $name)
                    TextField("Amount", value: $amount, format: .number)
                        .keyboardType(.decimalPad)
                    TextField("Account ID (optional)", text: $accountId)
                }
            }
            .navigationTitle("New Deal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await onSubmit(name, accountId.isEmpty ? nil : accountId, amount)
                            dismiss()
                        }
                    }.disabled(name.isEmpty)
                }
            }
        }
    }
}

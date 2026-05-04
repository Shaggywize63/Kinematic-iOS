import SwiftUI

struct AccountCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var industry = ""
    @State private var website = ""
    @State private var phone = ""

    let onSubmit: (String, String, String, String) async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    TextField("Company name", text: $name)
                    TextField("Industry", text: $industry)
                    TextField("Website", text: $website).autocapitalization(.none)
                    TextField("Phone", text: $phone).keyboardType(.phonePad)
                }
            }
            .navigationTitle("New Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await onSubmit(name, industry, website, phone)
                            dismiss()
                        }
                    }.disabled(name.isEmpty)
                }
            }
        }
    }
}

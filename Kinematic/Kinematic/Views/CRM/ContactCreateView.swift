import SwiftUI

struct ContactCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var firstName = ""
    @State private var lastName  = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var accountId = ""

    let onSubmit: (String, String, String, String, String?) async -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("First name", text: $firstName)
                    TextField("Last name", text: $lastName)
                }
                Section("Contact") {
                    TextField("Email", text: $email).keyboardType(.emailAddress).autocapitalization(.none)
                    TextField("Phone", text: $phone).keyboardType(.phonePad)
                }
                Section("Account") {
                    TextField("Account ID (optional)", text: $accountId)
                }
            }
            .navigationTitle("New Contact")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await onSubmit(firstName, lastName, email, phone, accountId.isEmpty ? nil : accountId)
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

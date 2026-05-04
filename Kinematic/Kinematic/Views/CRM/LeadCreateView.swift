import SwiftUI

struct LeadCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var company = ""
    @State private var source = "web"

    let onSubmit: (String, String, String, String, String, String) async -> Void

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
                Section("Company") {
                    TextField("Company", text: $company)
                    Picker("Source", selection: $source) {
                        ForEach(["web", "referral", "event", "cold_call", "social", "other"], id: \.self) {
                            Text($0.capitalized).tag($0)
                        }
                    }
                }
            }
            .navigationTitle("New Lead")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            await onSubmit(firstName, lastName, email, company, phone, source)
                            dismiss()
                        }
                    }
                    .disabled(firstName.isEmpty && email.isEmpty)
                }
            }
        }
    }
}

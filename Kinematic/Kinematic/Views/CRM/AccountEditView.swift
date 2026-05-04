import SwiftUI

struct AccountEditView: View {
    let account: CRMAccount
    let onSaved: (CRMAccount) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var industry: String
    @State private var website: String
    @State private var phone: String
    @State private var revenue: String
    @State private var employees: String
    @State private var description: String
    @State private var saving = false
    @State private var errorMessage: String?

    init(account: CRMAccount, onSaved: @escaping (CRMAccount) -> Void) {
        self.account = account
        self.onSaved = onSaved
        _name = State(initialValue: account.name)
        _industry = State(initialValue: account.industry ?? "")
        _website = State(initialValue: account.website ?? "")
        _phone = State(initialValue: account.phone ?? "")
        _revenue = State(initialValue: account.annualRevenue.map { String(Int($0)) } ?? "")
        _employees = State(initialValue: account.employees.map { String($0) } ?? "")
        _description = State(initialValue: account.description ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Identity") {
                    TextField("Name", text: $name)
                    TextField("Industry", text: $industry)
                    TextField("Website", text: $website).keyboardType(.URL).autocapitalization(.none)
                }
                Section("Contact") {
                    TextField("Phone", text: $phone).keyboardType(.phonePad)
                }
                Section("Size") {
                    TextField("Annual revenue (₹)", text: $revenue).keyboardType(.numberPad)
                    TextField("Employees", text: $employees).keyboardType(.numberPad)
                }
                Section("About") {
                    TextEditor(text: $description).frame(minHeight: 100)
                }
            }
            .navigationTitle("Edit Account")
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
        body["industry"] = industry.isEmpty ? NSNull() : industry
        body["website"] = website.isEmpty ? NSNull() : website
        body["phone"] = phone.isEmpty ? NSNull() : phone
        body["annual_revenue"] = Double(revenue) ?? NSNull()
        body["employees"] = Int(employees) ?? NSNull()
        body["description"] = description.isEmpty ? NSNull() : description
        do {
            let updated = try await CRMService.shared.patchAccount(id: account.id, body: body)
            onSaved(updated)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

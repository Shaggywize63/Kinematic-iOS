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
    /// Built-in field overrides (hide / relabel / require) for account columns.
    @StateObject private var fieldOverrides = LeadFieldOverridesModel()

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
                    if !fieldOverrides.isHidden(entity: "account", "name") {
                        TextField(fieldOverrides.labelFor(entity: "account", "name", "Name"), text: $name)
                    }
                    // Picker pre-selects whatever was already stored, even
                    // if it's a legacy free-text value not in the curated
                    // list — the picker keeps the existing tag visible so
                    // the rep sees what's there without it silently
                    // clearing on first edit.
                    if !fieldOverrides.isHidden(entity: "account", "industry") {
                        Picker(fieldOverrides.labelFor(entity: "account", "industry", "Industry"), selection: $industry) {
                            Text("— Select industry —").tag("")
                            if !industry.isEmpty && !CRM_INDUSTRIES.contains(industry) {
                                Text(industry).tag(industry)
                            }
                            ForEach(CRM_INDUSTRIES, id: \.self) { i in
                                Text(i).tag(i)
                            }
                        }
                    }
                    if !fieldOverrides.isHidden(entity: "account", "website") {
                        TextField(fieldOverrides.labelFor(entity: "account", "website", "Website"), text: $website).keyboardType(.URL).autocapitalization(.none)
                    }
                }
                if !fieldOverrides.isHidden(entity: "account", "phone") {
                    Section("Contact") {
                        TextField(fieldOverrides.labelFor(entity: "account", "phone", "Phone"), text: $phone).keyboardType(.phonePad)
                    }
                }
                if !fieldOverrides.isHidden(entity: "account", "annual_revenue") || !fieldOverrides.isHidden(entity: "account", "employees") {
                    Section("Size") {
                        if !fieldOverrides.isHidden(entity: "account", "annual_revenue") {
                            TextField(fieldOverrides.labelFor(entity: "account", "annual_revenue", "Annual revenue (₹)"), text: $revenue).keyboardType(.numberPad)
                        }
                        if !fieldOverrides.isHidden(entity: "account", "employees") {
                            TextField(fieldOverrides.labelFor(entity: "account", "employees", "Employees"), text: $employees).keyboardType(.numberPad)
                        }
                    }
                }
                Section("About") {
                    TextEditor(text: $description).frame(minHeight: 100)
                }
            }
            .task { await fieldOverrides.load() }
            .navigationTitle("Edit Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: { if saving { ProgressView() } else { Text("Save") } }
                        .disabled(saving || (!fieldOverrides.isHidden(entity: "account", "name") && name.trimmingCharacters(in: .whitespaces).isEmpty))
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

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
    /// Saved Address / State / City / PIN / Country, preloaded (gated per field by `AccountLocationSection`).
    @State private var location: AccountLocationDraft
    @State private var saving = false
    @State private var errorMessage: String?
    /// Built-in field overrides (hide / relabel / require) for account columns.
    @StateObject private var fieldOverrides = LeadFieldOverridesModel()
    /// Owner picker: the chosen user id (starts as the current owner) and who can be picked. Only admins /
    /// managers may change an owner (`RecordOwnerRules`), so the list is only fetched for them.
    @State private var ownerId: String
    @State private var owners: [AssignableUser] = []

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
        _ownerId = State(initialValue: account.ownerId ?? "")
        _location = State(initialValue: AccountLocationDraft(account: account))
    }

    /// Built-in field contract: wait for the admin's overrides, honour a hidden `owner_id`. On top of that
    /// only an admin / manager (not a data-scope "own" user) may change an owner at all.
    private var showsOwnerPicker: Bool {
        fieldOverrides.didLoad
            && RecordOwnerRules.currentUserCanChange
            && !fieldOverrides.isHidden(entity: "account", "owner_id")
            && !owners.isEmpty
    }

    /// Spark & Ray: the Industry choices come from the tenant's `config.industries` list (a stored value that is
    /// not in it stays selectable); everyone else keeps the curated generic list.
    @ObservedObject private var industries = IndustriesStore.shared

    private var industryChoices: [String] {
        SparkJourney.isActive ? SparkIndustries.pickerOptions(including: industry) : CRM_INDUSTRIES
    }

    @ViewBuilder
    private var ownerSection: some View {
        if showsOwnerPicker {
            Section("Ownership") {
                RecordOwnerPickerRow(
                    label: fieldOverrides.labelFor(entity: "account", "owner_id", "Owner"),
                    users: owners,
                    currentOwnerId: account.ownerId,
                    currentOwnerName: account.ownerName,
                    selectedId: $ownerId
                )
            }
        }
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
                            if !industry.isEmpty && !industryChoices.contains(industry) {
                                Text(industry).tag(industry)
                            }
                            ForEach(industryChoices, id: \.self) { i in
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
                AccountLocationSection(draft: $location, fieldOverrides: fieldOverrides)
                ownerSection
                Section("About") {
                    TextEditor(text: $description).frame(minHeight: 100)
                }
            }
            .task { await fieldOverrides.load() }
            .task { if SparkJourney.isActive { await industries.loadIfNeeded() } }
            .task {
                if RecordOwnerRules.currentUserCanChange {
                    owners = await CRMService.shared.listAssignableUsers()
                }
            }
            .navigationTitle("Edit Account")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { Task { await save() } } label: { if saving { ProgressView() } else { Text("Save") } }
                        .disabled(saveDisabled)
                }
            }
            .alert("Update failed", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private var saveDisabled: Bool {
        saving
            || (!fieldOverrides.isHidden(entity: "account", "name") && name.trimmingCharacters(in: .whitespaces).isEmpty)
            || location.isIncomplete(fieldOverrides)
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
        // Address / State / City / PIN / Country: a visible field the rep cleared goes as null; a hidden one is
        // left out so hiding it never wipes what is saved.
        body.merge(location.patchFields(hidden: AccountLocationDraft.hiddenKeys(fieldOverrides))) { _, new in new }
        // The owner rides the PATCH only when an allowed person actually picked someone else — never
        // otherwise (the server also drops it for anyone who may not reassign).
        if showsOwnerPicker {
            RecordOwnerRules.applyOwner(original: account.ownerId, selected: ownerId, to: &body)
        }
        do {
            let updated = try await CRMService.shared.patchAccount(id: account.id, body: body)
            onSaved(updated)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

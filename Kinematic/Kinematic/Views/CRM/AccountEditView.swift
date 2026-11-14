import SwiftUI

struct AccountEditView: View {
    let account: CRMAccount
    let onSaved: (CRMAccount) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var industry: String
    @State private var description: String
    /// Saved Address / State / PIN / Country, preloaded (gated per field by `AccountLocationSection`).
    @State private var location: AccountLocationDraft
    @State private var saving = false
    @State private var errorMessage: String?
    /// Built-in field overrides (hide / relabel / require) for account columns.
    @StateObject private var fieldOverrides = LeadFieldOverridesModel()

    init(account: CRMAccount, onSaved: @escaping (CRMAccount) -> Void) {
        self.account = account
        self.onSaved = onSaved
        _name = State(initialValue: account.name)
        _industry = State(initialValue: account.industry ?? "")
        _description = State(initialValue: account.description ?? "")
        _location = State(initialValue: AccountLocationDraft(account: account))
    }

    /// Spark & Ray: the Industry choices come from the tenant's `config.industries` list (a stored value that is
    /// not in it stays selectable); everyone else keeps the curated generic list.
    @ObservedObject private var industries = IndustriesStore.shared

    private var industryChoices: [String] {
        SparkJourney.isActive ? SparkIndustries.pickerOptions(including: industry) : CRM_INDUSTRIES
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
                }
                AccountLocationSection(draft: $location, fieldOverrides: fieldOverrides)
                Section("About") {
                    TextEditor(text: $description).frame(minHeight: 100)
                }
            }
            .task { await fieldOverrides.load() }
            .task { if SparkJourney.isActive { await industries.loadIfNeeded() } }
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
        // website / phone / annual_revenue / employees and the owner are no longer shown or editable here (owner
        // stays set server-side for access scoping), so none of them ride the PATCH.
        var body: [String: Any] = ["name": name]
        body["industry"] = industry.isEmpty ? NSNull() : industry
        body["description"] = description.isEmpty ? NSNull() : description
        // Address / State / PIN / Country: a visible field the rep cleared goes as null; a hidden one is
        // left out so hiding it never wipes what is saved.
        body.merge(location.patchFields(hidden: AccountLocationDraft.hiddenKeys(fieldOverrides))) { _, new in new }
        do {
            let updated = try await CRMService.shared.patchAccount(id: account.id, body: body)
            onSaved(updated)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

import SwiftUI

struct AccountCreateView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var industry = ""
    @State private var description = ""
    /// Address, State, PIN code and Country (gated per field by `AccountLocationSection`).
    @State private var location = AccountLocationDraft()
    /// Geofence from a picked Google place (built-in `latitude` / `longitude` columns). Set only from a pick —
    /// there is no visible row and the rep never types it, so it is kept separate from the address block and from
    /// the manually-typed company name (Google's legal name is often wrong).
    @State private var pickedCoordinate: LeadCoordinate?
    /// Built-in field overrides (hide / relabel / require) for account columns.
    @StateObject private var fieldOverrides = LeadFieldOverridesModel()
    @State private var saving = false
    /// A blocking duplicate: the backend's 409 found an account with this name. We keep the form open and point
    /// the rep at the existing account instead of surfacing a generic error.
    @State private var duplicate: AccountDuplicateInfo?
    /// A non-duplicate failure (shown in an alert).
    @State private var errorMessage: String?
    /// The existing account, fetched when the rep taps "Open it" on the duplicate notice; drives navigation.
    @State private var existingAccount: CRMAccount?
    @State private var openingExisting = false

    /// Throwing create: returns the created account, or throws `CRMServiceError.duplicateAccount` on a 409 so this
    /// form can keep itself open and link to the existing account.
    let onSubmit: ([String: Any]) async throws -> CRMAccount

    /// Spark & Ray: the Industry choices come from the tenant's `config.industries` list; everyone else keeps
    /// the curated generic list.
    @ObservedObject private var industries = IndustriesStore.shared

    private var industryChoices: [String] {
        SparkJourney.isActive ? SparkIndustries.pickerOptions(including: industry) : CRM_INDUSTRIES
    }

    /// The Google address search fills address line 1 / state / PIN code, so it is offered only once the admin's
    /// overrides loaded and at least one of those rows is visible (hiding the whole address block hides it too).
    private var showsAddressSearch: Bool {
        fieldOverrides.didLoad
            && (!fieldOverrides.isHidden(entity: "account", "address_line1")
                || !fieldOverrides.isHidden(entity: "account", "state")
                || !fieldOverrides.isHidden(entity: "account", "postal_code"))
    }

    private func saveTapped() {
        Task { await save() }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        duplicate = nil
        do {
            _ = try await onSubmit(buildBody())
            dismiss()
        } catch CRMServiceError.duplicateAccount(let info) {
            // Not a generic error: keep the form open and point the rep at the account that already exists.
            duplicate = info
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Fetch the existing duplicate account and push its detail screen.
    private func openExisting(_ info: AccountDuplicateInfo) {
        openingExisting = true
        Task {
            defer { openingExisting = false }
            if let account = try? await CRMService.shared.getAccount(id: info.id) {
                existingAccount = account
            } else {
                errorMessage = "Couldn't open the existing account."
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let dup = duplicate {
                    Section {
                        duplicateNotice(dup)
                    }
                }
                Section("Account") {
                    if !fieldOverrides.isHidden(entity: "account", "name") {
                        // Company name stays a manual text input — kept separate from the address search below,
                        // because Google's legal name for a place is often wrong.
                        TextField(fieldOverrides.labelFor(entity: "account", "name", "Company name"), text: $name)
                    }
                    // Industry dropdown — the tenant's own managed industries for Spark & Ray (`config.industries`
                    // via IndustriesStore), the curated generic list otherwise.
                    if !fieldOverrides.isHidden(entity: "account", "industry") {
                        Picker(fieldOverrides.labelFor(entity: "account", "industry", "Industry"), selection: $industry) {
                            Text("— Select industry —").tag("")
                            ForEach(industryChoices, id: \.self) { i in
                                Text(i).tag(i)
                            }
                        }
                    }
                }
                if showsAddressSearch {
                    Section("Find address (Google)") {
                        // A picked place fills the address rows + the lat/lng geofence. City is ignored (accounts
                        // have none). Kept apart from the Company name above.
                        AddressSearchField(
                            addressLine1: $location.addressLine1,
                            city: .constant(""),
                            state: $location.state,
                            postalCode: $location.postalCode,
                            onPicked: { detail in pickedCoordinate = LeadAddressCoordinates.coordinate(from: detail) }
                        )
                        if let c = pickedCoordinate, LeadAddressCoordinates.isUsable(latitude: c.latitude, longitude: c.longitude) {
                            Label("Map pin set from the address", systemImage: "mappin.circle.fill")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                AccountLocationSection(draft: $location, fieldOverrides: fieldOverrides)
                Section("Description") {
                    TextField("Notes about this account…", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .task { await fieldOverrides.load() }
            .task { if SparkJourney.isActive { await industries.loadIfNeeded() } }
            .navigationTitle("New Account")
            .navigationDestination(item: $existingAccount) { account in
                AccountDetailView(account: account)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button { saveTapped() } label: {
                        if saving { ProgressView() } else { Text("Save") }
                    }
                    .disabled(saveDisabled)
                }
            }
            .alert("Create failed", isPresented: .init(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    /// Inline duplicate notice: the name that already exists + a button to open that account.
    private func duplicateNotice(_ info: AccountDuplicateInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(AccountDuplicate.message(for: info, fallbackName: name), systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Brand.red)
            Button {
                openExisting(info)
            } label: {
                HStack(spacing: 6) {
                    if openingExisting { ProgressView().controlSize(.mini) }
                    Text("Open the existing account")
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(Brand.red)
            }
            .disabled(openingExisting)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var saveDisabled: Bool {
        saving
            || (!fieldOverrides.isHidden(entity: "account", "name") && name.isEmpty)
            || location.isIncomplete(fieldOverrides)
    }

    private func buildBody() -> [String: Any] {
        var body: [String: Any] = ["name": name]
        if !industry.isEmpty { body["industry"] = industry }
        if !description.isEmpty { body["description"] = description }
        // Address / State / PIN / Country: only the fields the admin left visible and the rep filled in.
        body.merge(location.createFields(hidden: AccountLocationDraft.hiddenKeys(fieldOverrides))) { _, new in new }
        // Geofence from the picked place — sent only when both are real coordinates.
        if let c = pickedCoordinate, LeadAddressCoordinates.isUsable(latitude: c.latitude, longitude: c.longitude) {
            body["latitude"] = c.latitude
            body["longitude"] = c.longitude
        }
        return body
    }
}

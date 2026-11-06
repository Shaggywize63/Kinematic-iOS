import SwiftUI

// Spark & Ray account "Addresses": the account's sites (`/crm/accounts/:id/sites`, `/crm/sites`) listed on the
// account detail, with "+ Add address", edit and delete. The form searches addresses with the same Google
// places search the lead create form uses (`AddressSearchField`), then lets the rep edit the fields.
// Shown ONLY for the Spark & Ray client (`SparkJourney.isActive`).

struct SparkAccountAddressesSection: View {
    let accountId: String

    @State private var sites: [AccountSite] = []
    @State private var loading = false
    @State private var editorSite: AccountSite? = nil
    @State private var adding = false
    @State private var deleting: AccountSite? = nil
    @State private var errorText: String? = nil

    init(accountId: String) {
        self.accountId = accountId
    }

    private let api = CRMService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            addButton
            if sites.isEmpty {
                emptyRow
            } else {
                ForEach(sites) { site in
                    siteRow(site)
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $adding) { addSheet }
        .sheet(item: $editorSite) { site in editSheet(for: site) }
        .alert("Delete this address?", isPresented: Binding(
            get: { deleting != nil },
            set: { if !$0 { deleting = nil } }
        )) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Delete", role: .destructive) {
                if let site = deleting { Task { await delete(site) } }
                deleting = nil
            }
        } message: {
            Text(deleting?.title ?? "")
        }
        .alert("Couldn't update addresses", isPresented: Binding(
            get: { errorText != nil },
            set: { if !$0 { errorText = nil } }
        )) {
            Button("OK", role: .cancel) { errorText = nil }
        } message: { Text(errorText ?? "") }
    }

    // MARK: Pieces

    private var header: some View {
        HStack(spacing: 6) {
            Text("ADDRESSES").font(.system(size: 11, weight: .black)).tracking(1).foregroundColor(Brand.red)
            if !sites.isEmpty {
                Text("\(sites.count)")
                    .font(.system(size: 10, weight: .black))
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.gray.opacity(0.15))
                    .foregroundColor(.secondary)
                    .clipShape(Capsule())
            }
            Spacer()
            if loading { ProgressView().controlSize(.mini) }
        }
    }

    private var addButton: some View {
        Button {
            adding = true
        } label: {
            Label("Add address", systemImage: "plus.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Brand.red.opacity(0.10))
                .foregroundColor(Brand.red)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.red.opacity(0.30), lineWidth: 1))
                .cornerRadius(10)
        }
    }

    private var emptyRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.slash").foregroundColor(.gray.opacity(0.5))
            Text("No addresses added").font(.caption).foregroundColor(.gray)
            Spacer()
        }
        .padding(.vertical, 6).padding(.horizontal, 4)
    }

    private func siteRow(_ site: AccountSite) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: site.hasCoordinates ? "mappin.circle.fill" : "building.2")
                .foregroundColor(Brand.red)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(site.title).font(.system(size: 14, weight: .semibold))
                if !site.streetLine.isEmpty {
                    Text(site.streetLine).font(.caption).foregroundColor(.secondary)
                }
                if !site.localityLine.isEmpty {
                    Text(site.localityLine).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer(minLength: 0)
            Menu {
                Button { editorSite = site } label: { Label("Edit", systemImage: "pencil") }
                Button(role: .destructive) { deleting = site } label: { Label("Delete", systemImage: "trash") }
            } label: {
                Image(systemName: "ellipsis.circle").foregroundColor(.secondary)
            }
            .accessibilityLabel("Address actions")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
        .contentShape(Rectangle())
        .onTapGesture { editorSite = site }
    }

    private var addSheet: some View {
        SparkAddressFormSheet(title: "Add address", draft: AccountAddressDraft()) { draft in
            let created = try await api.createSite(draft.createBody(accountId: accountId))
            sites.append(created)
        }
    }

    private func editSheet(for site: AccountSite) -> some View {
        SparkAddressFormSheet(title: "Edit address", draft: AccountAddressDraft(site: site)) { draft in
            let updated = try await api.updateSite(id: site.id, body: draft.patchBody())
            if let i = sites.firstIndex(where: { $0.id == site.id }) { sites[i] = updated }
        }
    }

    // MARK: Data

    private func load() async {
        loading = true
        defer { loading = false }
        if let fresh = try? await api.accountSites(id: accountId) { sites = fresh }
    }

    private func delete(_ site: AccountSite) async {
        do {
            try await api.deleteSite(id: site.id)
            sites.removeAll { $0.id == site.id }
        } catch {
            errorText = error.localizedDescription
        }
    }
}

/// The add / edit address form: a Label, the Google address search, and the editable fields. `onSave` throws so
/// the server's message shows in the form.
struct SparkAddressFormSheet: View {
    let title: String
    let onSave: (AccountAddressDraft) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: AccountAddressDraft
    @State private var saving = false
    @State private var errorText: String? = nil
    @State private var showLabelError = false

    init(title: String, draft: AccountAddressDraft, onSave: @escaping (AccountAddressDraft) async throws -> Void) {
        self.title = title
        self.onSave = onSave
        _draft = State(initialValue: draft)
    }

    var body: some View {
        NavigationStack {
            Form {
                labelSection
                searchSection
                fieldsSection
                if let err = errorText {
                    Section { Text(err).font(.footnote).foregroundColor(.red) }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if saving { ProgressView() } else { Text("Save").fontWeight(.semibold) }
                    }
                    .disabled(saving)
                }
            }
        }
    }

    private var labelSection: some View {
        Section {
            TextField("Label (e.g. Head office)", text: $draft.label)
            if showLabelError, let err = draft.validationError {
                Text(err).font(.footnote).foregroundColor(.red)
            }
        } header: {
            Text("Label (required)")
        }
    }

    private var searchSection: some View {
        Section("Search address") {
            AddressSearchField(
                addressLine1: $draft.addressLine1,
                city: $draft.city,
                state: $draft.state,
                postalCode: $draft.postalCode,
                onPicked: { place in
                    // The text fields were just filled by the search; take the pin from the place too.
                    draft.apply(place: place)
                }
            )
            if LeadAddressCoordinates.isUsable(latitude: draft.latitude, longitude: draft.longitude) {
                Label("Map pin set from the address", systemImage: "mappin.circle.fill")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var fieldsSection: some View {
        Section("Address") {
            TextField("Address line 1", text: $draft.addressLine1)
            TextField("Address line 2", text: $draft.addressLine2)
            TextField("City", text: $draft.city)
            TextField("State", text: $draft.state)
            TextField("PIN code", text: $draft.postalCode).keyboardType(.numberPad)
            TextField("Country", text: $draft.country)
            TextField("Phone (optional)", text: $draft.phone).keyboardType(.phonePad)
            TextField("Notes (optional)", text: $draft.notes, axis: .vertical).lineLimit(1...4)
        }
    }

    private func save() async {
        if draft.validationError != nil {
            showLabelError = true
            return
        }
        saving = true
        errorText = nil
        defer { saving = false }
        do {
            try await onSave(draft)
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }
}

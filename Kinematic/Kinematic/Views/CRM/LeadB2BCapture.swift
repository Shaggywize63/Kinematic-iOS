import SwiftUI

// B2B lead capture (Spark & Ray): a company typeahead that links an existing CRM
// account and reveals its known contacts on revisit, plus a repeatable list of
// contacts-with-requirements. Gated to Spark on the lead form because the backend
// only links lead contacts for that client.

enum LeadB2B {
    /// The Spark & Ray client id — mirrors the backend B2B_LEAD_CLIENT_IDS gate.
    static let sparkClientId = "c0218852-0a19-4dd0-b9fa-72f9e32ed0d8"
}

/// One person captured on a B2B lead, with what they asked for.
struct LeadContactDraft: Identifiable {
    let id = UUID()
    var firstName = ""
    var lastName = ""
    var title = ""
    var phone = ""
    var email = ""
    var requirement = ""

    var isBlank: Bool {
        firstName.isEmpty && lastName.isEmpty && title.isEmpty &&
        phone.isEmpty && email.isEmpty && requirement.isEmpty
    }

    /// JSON-serializable dict for the lead-create `contacts[]` (nil when blank). Keys
    /// match the backend leadContactSchema.
    var asPayload: [String: Any]? {
        if isBlank { return nil }
        var d: [String: Any] = [:]
        if !firstName.isEmpty { d["first_name"] = firstName }
        if !lastName.isEmpty { d["last_name"] = lastName }
        if !email.isEmpty { d["email"] = email }
        if !phone.isEmpty { d["phone"] = phone }
        if !title.isEmpty { d["title"] = title }
        if !requirement.isEmpty { d["requirement"] = requirement }
        return d
    }
}

/// Company field with a live account typeahead. Selecting an existing account sets
/// `selectedAccountId` (linked on the backend) and shows that company's known contacts.
struct CompanyPickerField: View {
    @Binding var company: String
    @Binding var selectedAccountId: String?
    let label: String

    @State private var results: [CRMAccount] = []
    @State private var bundle: AccountBundle? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField(label, text: $company)
                .onChange(of: company) { _, newValue in
                    selectedAccountId = nil
                    bundle = nil
                    Task { await search(newValue) }
                }
            if selectedAccountId == nil, !results.isEmpty {
                ForEach(results) { acc in
                    Button {
                        selectedAccountId = acc.id
                        company = acc.name
                        results = []
                        Task { await loadBundle(acc.id) }
                    } label: {
                        Label(acc.name, systemImage: "building.2")
                            .font(.subheadline)
                    }
                }
            }
            if selectedAccountId != nil {
                let known = bundle?.contacts ?? []
                Label(
                    "Existing customer" + (known.isEmpty ? "" : " · " + known.prefix(6).map { $0.displayName }.joined(separator: ", ")),
                    systemImage: "checkmark.circle.fill"
                )
                .font(.caption)
                .foregroundColor(.green)
            }
        }
    }

    private func search(_ q: String) async {
        let query = q.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else { results = []; return }
        let hits = (try? await CRMService.shared.listAccounts(search: query)) ?? []
        results = Array(hits.prefix(6))
    }

    private func loadBundle(_ id: String) async {
        bundle = try? await CRMService.shared.accountBundle(id: id)
    }
}

/// Repeatable "Contacts & requirements" section for the B2B lead form.
struct LeadContactsSection: View {
    @Binding var contacts: [LeadContactDraft]

    var body: some View {
        Section("Contacts & requirements") {
            ForEach($contacts) { $c in
                VStack(spacing: 6) {
                    TextField("First name", text: $c.firstName)
                    TextField("Last name", text: $c.lastName)
                    TextField("Designation", text: $c.title)
                    TextField("Phone", text: $c.phone).keyboardType(.phonePad)
                    TextField("Email", text: $c.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    TextField("Requirement", text: $c.requirement, axis: .vertical).lineLimit(2...4)
                }
                .padding(.vertical, 4)
            }
            .onDelete { idx in
                contacts.remove(atOffsets: idx)
                if contacts.isEmpty { contacts = [LeadContactDraft()] }
            }
            Button {
                contacts.append(LeadContactDraft())
            } label: {
                Label("Add another person", systemImage: "plus.circle")
            }
        }
    }
}

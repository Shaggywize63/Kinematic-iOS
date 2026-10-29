import SwiftUI

/// A person met during the visit (new entry; the backend de-dupes by
/// phone/email, so re-entering a known person converges on their record).
private struct ContactDraft: Identifiable {
    let id = UUID()
    var firstName: String = ""
    var lastName: String = ""
    var title: String = ""
    var department: String = ""
    var phone: String = ""
    var email: String = ""

    var isBlank: Bool {
        firstName.isEmpty && lastName.isEmpty && title.isEmpty &&
        department.isEmpty && phone.isEmpty && email.isEmpty
    }
}

/// "New plant visit" — the merged lead/activity entry point. The rep picks (or
/// creates) the customer, picks (or creates) the plant/site, records the people
/// met, then taps through to the product-survey forms. visit-intake resolves
/// everything to CRM rows (de-duped); the returned ids are stashed on
/// KiniAppState so every product form filled next attaches to this visit.
struct MergedVisitView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: KiniAppState

    // Customer
    @State private var companyQuery: String = ""
    @State private var accountResults: [CRMAccount] = []
    @State private var selectedAccountId: String? = nil
    @State private var selectedAccountName: String? = nil
    @State private var bundle: AccountBundle? = nil

    // Plant / site
    @State private var selectedSiteId: String? = nil
    @State private var newSiteName: String = ""
    @State private var siteCity: String = ""
    @State private var siteState: String = ""

    // People met
    @State private var contacts: [ContactDraft] = [ContactDraft()]
    @State private var purpose: String = ""

    @State private var isBusy = false
    @State private var errorMsg: String? = nil
    @State private var showForms = false

    private var hasCompany: Bool { selectedAccountId != nil || !companyQuery.trimmingCharacters(in: .whitespaces).isEmpty }
    private var sites: [CRMSite] { bundle?.sites ?? [] }

    var body: some View {
        Form {
            // ── Customer ──────────────────────────────────────────
            Section("Customer") {
                TextField("Company name", text: $companyQuery)
                    .textInputAutocapitalization(.words)
                    .onChange(of: companyQuery) { _, newValue in
                        selectedAccountId = nil
                        selectedAccountName = nil
                        bundle = nil
                        Task { await searchAccounts(newValue) }
                    }
                if selectedAccountId == nil {
                    ForEach(accountResults) { acc in
                        Button {
                            selectedAccountId = acc.id
                            selectedAccountName = acc.name
                            companyQuery = acc.name
                            accountResults = []
                            Task { await loadBundle(acc.id) }
                        } label: {
                            HStack {
                                Text(acc.name)
                                Spacer()
                                if let ind = acc.industry, !ind.isEmpty {
                                    Text(ind).font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                if let name = selectedAccountName {
                    Label("Existing customer: \(name)", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    let known = (bundle?.contacts ?? [])
                    if !known.isEmpty {
                        Text("Known contacts: " + known.prefix(6).map { contactName($0) }.joined(separator: ", "))
                            .font(.caption).foregroundColor(.secondary)
                    }
                } else if !companyQuery.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("No match selected — \u{201C}\(companyQuery)\u{201D} will be added as a new company.")
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            // ── Plant / site ──────────────────────────────────────
            Section("Plant / site") {
                if !sites.isEmpty {
                    ForEach(sites.indices, id: \.self) { i in
                        let s = sites[i]
                        Button {
                            selectedSiteId = s.id
                            newSiteName = ""
                        } label: {
                            HStack {
                                Image(systemName: selectedSiteId == s.id ? "largecircle.fill.circle" : "circle")
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading) {
                                    Text(s.name ?? "Site")
                                    if let loc = s.displayLocation { Text(loc).font(.caption).foregroundColor(.secondary) }
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                TextField(sites.isEmpty ? "Plant / site name" : "New plant name", text: $newSiteName)
                    .onChange(of: newSiteName) { _, v in if !v.isEmpty { selectedSiteId = nil } }
                if !newSiteName.trimmingCharacters(in: .whitespaces).isEmpty {
                    TextField("City", text: $siteCity)
                    TextField("State", text: $siteState)
                }
            }

            // ── People met ────────────────────────────────────────
            Section("People you met") {
                ForEach($contacts) { $c in
                    VStack(spacing: 6) {
                        TextField("First name", text: $c.firstName)
                        TextField("Last name", text: $c.lastName)
                        TextField("Designation", text: $c.title)
                        TextField("Department", text: $c.department)
                        TextField("Phone", text: $c.phone).keyboardType(.phonePad)
                        TextField("Email", text: $c.email).keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { idx in
                    contacts.remove(atOffsets: idx)
                    if contacts.isEmpty { contacts = [ContactDraft()] }
                }
                Button {
                    contacts.append(ContactDraft())
                } label: {
                    Label("Add another person", systemImage: "plus.circle")
                }
            }

            Section {
                TextField("Visit purpose (optional)", text: $purpose, axis: .vertical)
            }

            Section {
                Button {
                    Task { await startVisit() }
                } label: {
                    HStack {
                        Spacer()
                        if isBusy { ProgressView() } else { Text("Start visit & choose product form").bold() }
                        Spacer()
                    }
                }
                .disabled(!hasCompany || isBusy)
            }
        }
        .navigationTitle("New plant visit")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Close") { dismiss() }
            }
        }
        .alert("Couldn't start the visit", isPresented: Binding(get: { errorMsg != nil }, set: { if !$0 { errorMsg = nil } })) {
            Button("OK", role: .cancel) { errorMsg = nil }
        } message: {
            Text(errorMsg ?? "")
        }
        .sheet(isPresented: $showForms) {
            AdHocFormsView()
        }
    }

    private func contactName(_ c: Contact) -> String {
        let n = [c.firstName, c.lastName].compactMap { $0 }.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? (c.email ?? "Contact") : n
    }

    private func searchAccounts(_ q: String) async {
        let query = q.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else { await MainActor.run { accountResults = [] }; return }
        let rows = (try? await CRMService.shared.listAccounts(search: query)) ?? []
        await MainActor.run { if selectedAccountId == nil { accountResults = Array(rows.prefix(6)) } }
    }

    private func loadBundle(_ id: String) async {
        let b = try? await CRMService.shared.accountBundle(id: id)
        await MainActor.run { bundle = b }
    }

    private func startVisit() async {
        await MainActor.run { isBusy = true }
        let trimmedCompany = companyQuery.trimmingCharacters(in: .whitespaces)
        let account = VisitAccountInput(
            id: selectedAccountId,
            name: selectedAccountId == nil ? (trimmedCompany.isEmpty ? nil : trimmedCompany) : nil
        )
        var site: VisitSiteInput? = nil
        if let sid = selectedSiteId {
            site = VisitSiteInput(id: sid)
        } else if !newSiteName.trimmingCharacters(in: .whitespaces).isEmpty {
            site = VisitSiteInput(
                name: newSiteName.trimmingCharacters(in: .whitespaces),
                city: siteCity.trimmingCharacters(in: .whitespaces).isEmpty ? nil : siteCity.trimmingCharacters(in: .whitespaces),
                state: siteState.trimmingCharacters(in: .whitespaces).isEmpty ? nil : siteState.trimmingCharacters(in: .whitespaces)
            )
        }
        let people: [VisitContactInput] = contacts.filter { !$0.isBlank }.map {
            VisitContactInput(
                firstName: $0.firstName.isEmpty ? nil : $0.firstName,
                lastName: $0.lastName.isEmpty ? nil : $0.lastName,
                phone: $0.phone.isEmpty ? nil : $0.phone,
                title: $0.title.isEmpty ? nil : $0.title,
                department: $0.department.isEmpty ? nil : $0.department
            )
        }
        let req = VisitIntakeRequest(
            account: account,
            site: site,
            contacts: people.isEmpty ? nil : people,
            purpose: purpose.trimmingCharacters(in: .whitespaces).isEmpty ? nil : purpose.trimmingCharacters(in: .whitespaces)
        )
        let result = try? await CRMService.shared.visitIntake(req)
        await MainActor.run {
            isBusy = false
            if let r = result, r.accountId != nil {
                appState.setVisitContext(VisitContext(
                    accountId: r.accountId,
                    siteId: r.siteId,
                    contactId: r.contactIds.first,
                    visitId: r.visitId
                ))
                showForms = true
            } else {
                errorMsg = "Check your connection and try again."
            }
        }
    }
}

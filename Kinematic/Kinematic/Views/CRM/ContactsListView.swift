import SwiftUI

struct ContactsListView: View {
    @StateObject var vm = ContactsViewModel()
    @State private var showCreate = false
    @State private var showDateFilter = false
    /// Spark & Ray: the contact whose account is being set / changed (context menu on a row), and any error.
    @State private var accountPickerContact: Contact? = nil
    @State private var accountAssignError: String? = nil
    /// The contact awaiting delete confirmation (long-press menu on a row), and the server's message when a
    /// delete fails (the row stays).
    @State private var deletingContact: Contact? = nil
    @State private var deleteError: String? = nil
    /// Built-in field overrides: the Company / Account line is the contact's `account_id` field, so it is gated
    /// (hidden / relabelled by the admin) and only rendered once the settings have loaded.
    @StateObject private var fieldOverrides = LeadFieldOverridesModel()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.gray)
                TextField("Search contacts…", text: $vm.search)
                    .textFieldStyle(.plain)
                    .autocapitalization(.none)
                if vm.dateFrom != nil || vm.dateTo != nil {
                    Button { vm.dateFrom = nil; vm.dateTo = nil } label: {
                        Image(systemName: "calendar.badge.minus").foregroundColor(.red)
                    }
                }
                Button { showDateFilter = true } label: {
                    Image(systemName: "calendar")
                        .foregroundColor(vm.dateFrom != nil || vm.dateTo != nil ? Brand.red : .gray)
                }
            }
            .padding(10)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(10)
            .padding(.horizontal)

            ScrollView {
                LazyVStack(spacing: 10) {
                    if vm.isLoading && vm.contacts.isEmpty {
                        ProgressView().padding(.top, 40)
                    } else if vm.filtered.isEmpty {
                        emptyState
                    } else {
                        ForEach(vm.filtered) { c in
                            contactLink(c)
                        }
                    }
                }
                .padding()
            }
            .refreshable { await vm.refresh() }
            .sheet(item: $accountPickerContact) { c in
                accountPicker(for: c)
            }
            .alert("Couldn't update", isPresented: Binding(
                get: { accountAssignError != nil },
                set: { if !$0 { accountAssignError = nil } }
            )) {
                Button("OK", role: .cancel) { accountAssignError = nil }
            } message: { Text(accountAssignError ?? "") }
            .confirmationDialog(
                ContactDeletion.confirmationTitle(name: deletingContact?.displayName ?? ""),
                isPresented: Binding(
                    get: { deletingContact != nil },
                    set: { if !$0 { deletingContact = nil } }
                ),
                titleVisibility: .visible,
                presenting: deletingContact
            ) { c in
                Button("Delete", role: .destructive) {
                    Task { deleteError = await vm.delete(contact: c) }
                }
                Button("Cancel", role: .cancel) {}
            } message: { c in
                Text(ContactDeletion.confirmationMessage(name: c.displayName))
            }
            .alert("Couldn't delete", isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK", role: .cancel) { deleteError = nil }
            } message: { Text(deleteError ?? "") }
        }
        .navigationTitle("Contacts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showCreate) {
            ContactCreateView { body in
                await vm.create(body: body)
            }
        }
        .sheet(isPresented: $showDateFilter) {
            DateRangeFilterSheet(from: $vm.dateFrom, to: $vm.dateTo, label: "Created date") {}
        }
        .task { await vm.refresh() }
        .task { await fieldOverrides.load() }
        // A contact deleted from its detail screen: drop the row now, then refresh.
        .onReceive(NotificationCenter.default.publisher(for: .crmContactDeleted)) { note in
            if let id = note.object as? String {
                vm.contacts = ContactDeletion.removing(id: id, from: vm.contacts)
            }
            Task { await vm.refresh() }
        }
    }

    @ViewBuilder
    private func contactLink(_ c: Contact) -> some View {
        if let company = companyLine(for: c) {
            companyCard(c, company: company)
                .contextMenu { rowMenu(for: c) }
        } else {
            NavigationLink(destination: ContactDetailView(contact: c)) {
                contactRow(c)
            }
            .buttonStyle(.plain)
            .contextMenu { rowMenu(for: c) }
        }
    }

    /// The row's Company (Spark & Ray) / Account line, gated through the built-in field overrides: nothing until
    /// they have loaded, nothing when the admin hid `account_id`, and labelled as the admin named it.
    private func companyLine(for c: Contact) -> ContactCompanyLine? {
        guard fieldOverrides.didLoad else { return nil }
        let isB2C = c.isB2c == true
        guard !fieldOverrides.isHidden(entity: "contact", "account_id", isB2C: isB2C),
              let line = ContactCompanyDisplay.line(for: c, spark: SparkJourney.isActive) else { return nil }
        let label = fieldOverrides.labelFor(
            entity: "contact", "account_id", SparkContactCompany.label(spark: SparkJourney.isActive), isB2C: isB2C
        )
        return ContactCompanyLine(id: line.id, name: line.name, label: label)
    }

    /// Long-press menu: the Spark company action (when it applies) and Delete.
    @ViewBuilder
    private func rowMenu(for c: Contact) -> some View {
        accountMenu(for: c)
        Button(role: .destructive) {
            deletingContact = c
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// A contact row with its Company (Spark & Ray) / Account (everyone else) underneath. When the account id is
    /// known the line is its own link to the account, so the row's link and the company's link sit side by side
    /// (never nested) inside one card; otherwise it is plain text.
    private func companyCard(_ c: Contact, company: ContactCompanyLine) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(destination: ContactDetailView(contact: c)) {
                contactRowContent(c)
                    .padding(12)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let accountId = company.id {
                NavigationLink(destination: AccountDetailLoader(accountId: accountId, name: company.name)) {
                    companyLabel(company, linked: true)
                }
                .buttonStyle(.plain)
            } else {
                companyLabel(company, linked: false)
            }
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func companyLabel(_ company: ContactCompanyLine, linked: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "building.2.fill").font(.system(size: 10, weight: .semibold))
            Text(company.text)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
            if linked {
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .bold))
            }
            Spacer(minLength: 0)
        }
        .foregroundColor(Brand.red)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .contentShape(Rectangle())
    }

    /// Spark & Ray: "Add to a company" / "Change company" for a business contact.
    @ViewBuilder
    private func accountMenu(for c: Contact) -> some View {
        if SparkJourney.isActive && c.isB2c != true {
            Button {
                accountPickerContact = c
            } label: {
                Label((c.accountId ?? "").isEmpty ? "Add to a company" : "Change company", systemImage: "building.2")
            }
        }
    }

    private func accountPicker(for c: Contact) -> some View {
        SparkAccountPickerSheet { account in
            Task { accountAssignError = await vm.setAccount(contact: c, account: account) }
        }
    }

    private func contactRow(_ c: Contact) -> some View {
        contactRowContent(c)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemBackground))
            )
    }

    private func contactRowContent(_ c: Contact) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Brand.red.opacity(0.2)).frame(width: 40, height: 40)
                Text(initials(c)).font(.system(size: 13, weight: .black)).foregroundColor(Brand.red)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(c.displayName).font(.system(size: 14, weight: .semibold))
                if let e = c.email { Text(e).font(.caption).foregroundColor(.secondary) }
            }
            Spacer()
            if c.phone != nil { Image(systemName: "phone.fill").foregroundColor(Brand.red).font(.caption) }
        }
    }

    private func initials(_ c: Contact) -> String {
        let s = "\(c.firstName?.prefix(1) ?? "")\(c.lastName?.prefix(1) ?? "")".uppercased()
        return s.isEmpty ? "C" : s
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.fill").font(.system(size: 40)).foregroundColor(.gray.opacity(0.4))
            Text("No contacts yet.").foregroundColor(.gray)
        }.padding(.top, 60)
    }
}

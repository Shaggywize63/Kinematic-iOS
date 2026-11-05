import SwiftUI

struct ContactsListView: View {
    @StateObject var vm = ContactsViewModel()
    @State private var showCreate = false
    @State private var showDateFilter = false
    /// Spark & Ray: the contact whose account is being set / changed (context menu on a row), and any error.
    @State private var accountPickerContact: Contact? = nil
    @State private var accountAssignError: String? = nil

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
    }

    private func contactLink(_ c: Contact) -> some View {
        NavigationLink(destination: ContactDetailView(contact: c)) {
            contactRow(c)
        }
        .buttonStyle(.plain)
        .contextMenu { accountMenu(for: c) }
    }

    /// Spark & Ray: "Add to an account" / "Change account" for a business contact.
    @ViewBuilder
    private func accountMenu(for c: Contact) -> some View {
        if SparkJourney.isActive && c.isB2c != true {
            Button {
                accountPickerContact = c
            } label: {
                Label((c.accountId ?? "").isEmpty ? "Add to an account" : "Change account", systemImage: "building.2")
            }
        }
    }

    private func accountPicker(for c: Contact) -> some View {
        SparkAccountPickerSheet { account in
            Task { accountAssignError = await vm.setAccount(contact: c, account: account) }
        }
    }

    private func contactRow(_ c: Contact) -> some View {
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
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemBackground))
        )
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

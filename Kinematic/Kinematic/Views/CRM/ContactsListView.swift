import SwiftUI

struct ContactsListView: View {
    @StateObject var vm = ContactsViewModel()
    @State private var showCreate = false
    @State private var showDateFilter = false

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
                        .foregroundColor(vm.dateFrom != nil || vm.dateTo != nil ? .indigo : .gray)
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
                            NavigationLink(destination: ContactDetailView(contact: c)) {
                                contactRow(c)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .refreshable { await vm.refresh() }
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

    private func contactRow(_ c: Contact) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.orange.opacity(0.2)).frame(width: 40, height: 40)
                Text(initials(c)).font(.system(size: 13, weight: .black)).foregroundColor(.orange)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(c.displayName).font(.system(size: 14, weight: .semibold))
                if let e = c.email { Text(e).font(.caption).foregroundColor(.secondary) }
            }
            Spacer()
            if c.phone != nil { Image(systemName: "phone.fill").foregroundColor(.green).font(.caption) }
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

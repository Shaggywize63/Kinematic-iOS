import SwiftUI

struct LeadsListView: View {
    @StateObject var vm = LeadsViewModel()
    @State private var showCreate = false
    @State private var showImport = false

    let statusOptions = ["all", "new", "contacted", "qualified", "unqualified", "converted"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.gray)
                TextField("Search leads…", text: $vm.search)
                    .textFieldStyle(.plain)
                    .autocapitalization(.none)
            }
            .padding(10)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(10)
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(statusOptions, id: \.self) { s in
                        Button {
                            vm.statusFilter = s
                            Task { await vm.refresh() }
                        } label: {
                            Text(s.uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(vm.statusFilter == s ? Color.blue : Color(uiColor: .secondarySystemBackground))
                                .foregroundColor(vm.statusFilter == s ? .white : .gray)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    if vm.isLoading && vm.leads.isEmpty {
                        ProgressView().padding(.top, 40)
                    } else if vm.filtered.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 40))
                                .foregroundColor(.gray.opacity(0.4))
                            Text("No leads yet.").foregroundColor(.gray)
                            Button("Create lead") { showCreate = true }
                                .buttonStyle(.borderedProminent)
                        }
                        .padding(.top, 60)
                    } else {
                        ForEach(vm.filtered) { lead in
                            NavigationLink(destination: LeadDetailView(leadId: lead.id)) {
                                LeadRow(lead: lead)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
            .refreshable { await vm.refresh() }
        }
        .navigationTitle("Leads")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { showCreate = true } label: { Label("New lead", systemImage: "plus") }
                    Button { showImport = true } label: { Label("Import CSV", systemImage: "square.and.arrow.down") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showCreate) {
            LeadCreateView { firstName, lastName, email, company, phone, source in
                await vm.create(firstName: firstName, lastName: lastName, email: email, company: company, phone: phone, source: source)
            }
        }
        .sheet(isPresented: $showImport) {
            LeadImportView()
        }
        .task { await vm.refresh() }
        .onChange(of: vm.search) { _ in
            Task { await vm.refresh() }
        }
    }
}

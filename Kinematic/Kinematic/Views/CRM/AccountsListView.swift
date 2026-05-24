import SwiftUI

struct AccountsListView: View {
    @StateObject var vm = AccountsViewModel()
    @State private var showCreate = false

    var body: some View {
        VStack(spacing: 0) {
            CachedSnapshotChip(
                showing: vm.showingCached,
                lastFetched: CRMReadCache.shared.lastFetched(.accounts)
            )
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.gray)
                TextField("Search accounts…", text: $vm.search)
                    .textFieldStyle(.plain).autocapitalization(.none)
            }
            .padding(10)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(10)
            .padding(.horizontal)

            ScrollView {
                LazyVStack(spacing: 10) {
                    if vm.isLoading && vm.accounts.isEmpty {
                        ProgressView().padding(.top, 40)
                    } else if vm.filtered.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "building.2").font(.system(size: 40)).foregroundColor(.gray.opacity(0.4))
                            Text("No accounts yet.").foregroundColor(.gray)
                        }.padding(.top, 60)
                    } else {
                        ForEach(vm.filtered) { a in
                            NavigationLink(destination: AccountDetailView(account: a)) {
                                AccountSummaryCard(account: a)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .refreshable { await vm.refresh() }
        }
        .navigationTitle("Accounts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showCreate) {
            AccountCreateView { body in
                await vm.create(body: body)
            }
        }
        .task { await vm.refresh() }
    }
}

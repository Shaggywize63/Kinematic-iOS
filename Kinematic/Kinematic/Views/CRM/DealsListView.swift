import SwiftUI

struct DealsListView: View {
    @StateObject var vm = DealsViewModel()
    @State private var showCreate = false
    let statusOptions = ["open", "won", "lost", "all"]

    var body: some View {
        VStack(spacing: 0) {
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
                                .background(vm.statusFilter == s ? Color.indigo : Color(uiColor: .secondarySystemBackground))
                                .foregroundColor(vm.statusFilter == s ? .white : .gray)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding()
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    if vm.deals.isEmpty {
                        Text("No deals.").foregroundColor(.gray).padding(.top, 60)
                    } else {
                        ForEach(vm.deals) { d in
                            NavigationLink(destination: DealDetailView(dealId: d.id, initialDeal: d)) {
                                DealCard(deal: d)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding()
            }
            .refreshable { await vm.refresh() }
        }
        .navigationTitle("Deals")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showCreate) {
            DealCreateView { name, accountId, amount in
                await vm.create(name: name, accountId: accountId, amount: amount, stageId: nil)
            }
        }
        .task { await vm.refresh() }
    }
}

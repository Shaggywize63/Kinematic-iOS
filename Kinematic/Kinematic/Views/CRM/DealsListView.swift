import SwiftUI

struct DealsListView: View {
    @StateObject var vm = DealsViewModel()
    @State private var showCreate = false
    @State private var showDateFilter = false
    @AppStorage("crm.deals.showWeighted") private var showWeighted: Bool = false
    let statusOptions = ["open", "won", "lost", "all"]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: showWeighted ? "scalemass.fill" : "indianrupeesign.circle.fill")
                    .foregroundColor(showWeighted ? Brand.red : Brand.red)
                    .font(.caption)
                Text(showWeighted ? "Weighted" : "Cost")
                    .font(.caption2).foregroundColor(.secondary)
                Spacer()
                Toggle("", isOn: $showWeighted).labelsHidden().tint(Brand.red)
            }
            .padding(.horizontal).padding(.top, 8)
            HStack {
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
                                    .background(vm.statusFilter == s ? Brand.red : Color(uiColor: .secondarySystemBackground))
                                    .foregroundColor(vm.statusFilter == s ? .white : .gray)
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.leading)
                }
                Button { showDateFilter = true } label: {
                    Image(systemName: "calendar")
                        .foregroundColor(vm.dateFrom != nil || vm.dateTo != nil ? Brand.red : .gray)
                        .padding(.trailing, 12)
                }
                if vm.dateFrom != nil || vm.dateTo != nil {
                    Button { vm.dateFrom = nil; vm.dateTo = nil; Task { await vm.refresh() } } label: {
                        Image(systemName: "xmark.circle.fill").foregroundColor(.red).padding(.trailing, 8)
                    }
                }
            }
            .padding(.vertical, 8)

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
            DealCreateView { body in
                await vm.create(body: body)
            }
        }
        .sheet(isPresented: $showDateFilter) {
            DateRangeFilterSheet(from: $vm.dateFrom, to: $vm.dateTo, label: "Close date") {
                Task { await vm.refresh() }
            }
        }
        .task { await vm.refresh() }
    }
}

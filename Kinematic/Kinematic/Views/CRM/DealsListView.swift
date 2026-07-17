import SwiftUI

struct DealsListView: View {
    @StateObject var vm = DealsViewModel()
    @State private var showCreate = false
    @State private var showDateFilter = false
    /// Inline edit — long-press a row → Edit opens the edit sheet in place.
    /// Stages are loaded for the tapped deal's pipeline before presenting so
    /// the stage picker is populated (mirrors the detail screen).
    @State private var editingDeal: Deal? = nil
    @State private var editingStages: [Stage] = []
    @AppStorage("crm.deals.showWeighted") private var showWeightedStored: Bool = false
    // Tata-only weighted view (see ClientFeatureGates). Every other
    // client keeps the simpler raw-amount display.
    private var showWeighted: Bool {
        ClientFeatures.isTataTiscon ? showWeightedStored : false
    }
    let statusOptions = ["open", "won", "lost", "all"]

    var body: some View {
        VStack(spacing: 0) {
            if ClientFeatures.isTataTiscon {
                HStack(spacing: 8) {
                    Image(systemName: showWeighted ? "scalemass.fill" : "indianrupeesign.circle.fill")
                        .foregroundColor(Brand.red)
                        .font(.caption)
                    Text(showWeighted ? "Weighted" : "Cost")
                        .font(.caption2).foregroundColor(.secondary)
                    Spacer()
                    Toggle("", isOn: Binding(get: { showWeightedStored }, set: { showWeightedStored = $0 }))
                        .labelsHidden().tint(Brand.red)
                }
                .padding(.horizontal).padding(.top, 8)
            }
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
                            .contextMenu {
                                Button {
                                    Task {
                                        editingStages = (try? await CRMService.shared.listStages(pipelineId: d.pipelineId ?? "")) ?? []
                                        editingDeal = d
                                    }
                                } label: { Label("Edit", systemImage: "pencil") }
                            }
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
                NavigationLink(destination: ChatListView()) {
                    Image(systemName: "bubble.left.and.bubble.right")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showCreate) {
            DealCreateView { body in
                await vm.create(body: body)
            }
        }
        .sheet(item: $editingDeal) { d in
            // Inline edit — same override-aware DealEditView the detail screen
            // uses. Refresh the list on save so the row reflects the change.
            DealEditView(deal: d, stages: editingStages) { _ in Task { await vm.refresh() } }
        }
        .sheet(isPresented: $showDateFilter) {
            DateRangeFilterSheet(from: $vm.dateFrom, to: $vm.dateTo, label: "Close date") {
                Task { await vm.refresh() }
            }
        }
        .task { await vm.refresh() }
    }
}

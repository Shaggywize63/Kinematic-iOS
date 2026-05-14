import SwiftUI

struct DealKanbanView: View {
    @StateObject var vm = DealKanbanViewModel()
    @State private var movingDeal: Deal?
    @State private var selectedStageId: String? = nil
    @AppStorage("crm.deals.showWeighted") private var showWeighted: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            if let pipeline = vm.pipelines.first(where: { $0.id == vm.selectedPipelineId }) {
                HStack {
                    Text(pipeline.name)
                        .font(.headline)
                    Spacer()
                    Menu {
                        ForEach(vm.pipelines) { p in
                            Button(p.name) {
                                vm.selectedPipelineId = p.id
                                Task { await vm.load() }
                            }
                        }
                    } label: {
                        HStack {
                            Text("Switch").font(.caption)
                            Image(systemName: "chevron.down")
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            // Cost / Weighted toggle
            HStack(spacing: 8) {
                Image(systemName: showWeighted ? "scalemass.fill" : "indianrupeesign.circle.fill")
                    .foregroundColor(showWeighted ? .indigo : .green)
                    .font(.caption)
                Text(showWeighted ? "Weighted value (amount × win prob)" : "Cost (raw amount)")
                    .font(.caption2).foregroundColor(.secondary)
                Spacer()
                Toggle("", isOn: $showWeighted).labelsHidden().tint(.indigo)
            }
            .padding(.horizontal).padding(.bottom, 6)

            // Mobile-first pipeline layout: horizontally-scrolling stage
            // chips (each with deal count + ₹ total), then a vertical list
            // of deals for the selected stage. The previous horizontal-kanban
            // forced side-scrolling per tap which is unworkable on phones.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(vm.stages) { stage in
                        let deals = vm.dealsFor(stageId: stage.id)
                        let total = deals.reduce(0.0) { acc, d in
                            acc + (d.amount ?? 0) * (showWeighted ? (d.winProbability ?? 0) : 1.0)
                        }
                        Button(action: { selectedStageId = stage.id }) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(stage.name).font(.system(size: 13, weight: .bold))
                                Text("\(deals.count) • \(CurrencyFormatter.formatINR(total))")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 999)
                                    .fill(selectedStageId == stage.id ? Color.indigo.opacity(0.18) : Color(uiColor: .secondarySystemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 999)
                                    .stroke(selectedStageId == stage.id ? Color.indigo : Color.clear, lineWidth: 1.5)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }

            let activeStageId = selectedStageId ?? vm.stages.first?.id
            let visibleDeals = activeStageId.map { vm.dealsFor(stageId: $0) } ?? []
            if visibleDeals.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray").font(.title).foregroundColor(.secondary)
                    Text("No deals in this stage yet.").font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(visibleDeals) { deal in
                            VStack(spacing: 0) {
                                NavigationLink(destination: DealDetailView(dealId: deal.id)) {
                                    DealCard(deal: deal)
                                }
                                .buttonStyle(.plain)
                                HStack {
                                    Button("Move to another stage") { movingDeal = deal }
                                        .font(.caption).foregroundColor(.indigo)
                                    Spacer()
                                }
                                .padding(.horizontal, 14)
                                .padding(.bottom, 10)
                            }
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemBackground)))
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 40)
                }
            }
        }
        .navigationTitle("Pipeline")
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .task { await vm.load() }
        .overlay {
            if vm.isLoading && vm.deals.isEmpty {
                ProgressView().scaleEffect(1.3)
            }
        }
        .confirmationDialog("Move deal to stage", isPresented: Binding(
            get: { movingDeal != nil },
            set: { if !$0 { movingDeal = nil } }
        )) {
            ForEach(vm.stages.filter { $0.id != movingDeal?.stageId }) { stage in
                Button(stage.name) {
                    if let deal = movingDeal {
                        Task { await vm.move(deal: deal, toStage: stage.id) }
                    }
                    movingDeal = nil
                }
            }
            Button("Cancel", role: .cancel) { movingDeal = nil }
        }
    }
}

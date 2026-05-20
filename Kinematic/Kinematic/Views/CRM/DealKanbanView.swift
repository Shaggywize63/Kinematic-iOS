import SwiftUI

struct DealKanbanView: View {
    @StateObject var vm = DealKanbanViewModel()
    @State private var movingDeal: Deal?
    @State private var selectedStageId: String? = nil
    @AppStorage("crm.deals.showWeighted") private var showWeighted: Bool = false

    var body: some View {
        Group {
            // First-load shell: show a single ProgressView until pipelines
            // resolve so the rep doesn't see a half-rendered, no-data UI
            // that looks frozen during the 3-call fan-out
            // (listPipelines → listStages + listDeals).
            if vm.pipelines.isEmpty && vm.isLoading {
                loadingShell
            } else {
                loadedBody
            }
        }
        .navigationTitle("Pipeline")
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .task { await vm.load() }
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

    // MARK: - Loading shell

    private var loadingShell: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView().tint(Brand.red).scaleEffect(1.3)
            Text("Loading pipeline…")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Loaded body

    private var loadedBody: some View {
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
                    .foregroundColor(Brand.red)
                    .font(.caption)
                Text(showWeighted ? "Weighted value (amount × win prob)" : "Cost (raw amount)")
                    .font(.caption2).foregroundColor(.secondary)
                Spacer()
                Toggle("", isOn: $showWeighted).labelsHidden().tint(Brand.red)
            }
            .padding(.horizontal).padding(.bottom, 6)

            // Mobile-first pipeline layout: horizontally-scrolling stage
            // chips (each with deal count + ₹ total), then a vertical list
            // of deals for the selected stage. LazyHStack so wide pipelines
            // don't render every chip up-front.
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 8) {
                    ForEach(vm.stages) { stage in
                        stageChip(stage)
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
                                        .font(.caption).foregroundColor(Brand.red)
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
    }

    // MARK: - Stage chip

    /// Pulled out into its own view so the LazyHStack only builds chips
    /// that are about to scroll into view, and reads the precomputed
    /// per-stage rollups from the VM (O(1)) instead of filtering +
    /// reducing the deals array on every render.
    @ViewBuilder
    private func stageChip(_ stage: Stage) -> some View {
        let count = vm.dealsFor(stageId: stage.id).count
        let total = showWeighted ? vm.weightedTotal(stageId: stage.id)
                                 : vm.rawTotal(stageId: stage.id)
        Button(action: { selectedStageId = stage.id }) {
            VStack(alignment: .leading, spacing: 4) {
                Text(stage.name).font(.system(size: 13, weight: .bold))
                Text("\(count) • \(CurrencyFormatter.formatINR(total))")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 999)
                    .fill(selectedStageId == stage.id ? Brand.red.opacity(0.18) : Color(uiColor: .secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 999)
                    .stroke(selectedStageId == stage.id ? Brand.red : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

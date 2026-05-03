import SwiftUI

struct DealKanbanView: View {
    @StateObject var vm = DealKanbanViewModel()
    @State private var movingDeal: Deal?

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

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(vm.stages) { stage in
                        StageColumn(
                            stage: stage,
                            deals: vm.dealsFor(stageId: stage.id),
                            onMove: { deal in
                                movingDeal = deal
                            }
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 40)
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

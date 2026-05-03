import Foundation

@MainActor
final class DealKanbanViewModel: ObservableObject {
    @Published var pipelines: [Pipeline] = []
    @Published var selectedPipelineId: String?
    @Published var stages: [Stage] = []
    @Published var deals: [Deal] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let api = CRMService.shared

    func dealsFor(stageId: String) -> [Deal] {
        deals.filter { $0.stageId == stageId }
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            pipelines = try await api.listPipelines()
            let pipeline = pipelines.first(where: { $0.isDefault == true }) ?? pipelines.first
            selectedPipelineId = pipeline?.id
            if let id = selectedPipelineId {
                async let stagesTask = api.listStages(pipelineId: id)
                async let dealsTask  = api.listDeals(pipelineId: id, status: "open")
                stages = (try? await stagesTask) ?? []
                deals  = (try? await dealsTask) ?? []
                stages.sort { ($0.order ?? 0) < ($1.order ?? 0) }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func move(deal: Deal, toStage stageId: String) async {
        do {
            let updated = try await api.moveDealStage(id: deal.id, stageId: stageId)
            if let idx = deals.firstIndex(where: { $0.id == updated.id }) {
                deals[idx] = updated
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

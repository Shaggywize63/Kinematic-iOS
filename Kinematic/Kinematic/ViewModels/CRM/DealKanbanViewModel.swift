import Foundation
import Combine

@MainActor
final class DealKanbanViewModel: ObservableObject {
    @Published var pipelines: [Pipeline] = []
    @Published var selectedPipelineId: String?
    @Published var stages: [Stage] = []
    @Published var deals: [Deal] = []
    @Published var isLoading = false
    @Published var errorMessage: String?

    /// Cached per-stage rollup so the view body doesn't re-filter + reduce
    /// the deals array on every render. Recomputed in `load()` and after
    /// each successful `move()` (when a deal's stage_id changes).
    @Published private(set) var dealsByStageId: [String: [Deal]] = [:]
    @Published private(set) var rawTotalByStageId: [String: Double] = [:]
    @Published private(set) var weightedTotalByStageId: [String: Double] = [:]

    private let api = CRMService.shared

    func dealsFor(stageId: String) -> [Deal] {
        dealsByStageId[stageId] ?? []
    }

    /// Cost (raw amount) total for a stage. Used by the kanban chip when
    /// the Weighted toggle is OFF.
    func rawTotal(stageId: String) -> Double {
        rawTotalByStageId[stageId] ?? 0
    }

    /// Weighted total (amount × win_probability) for a stage. Used by the
    /// kanban chip when the Weighted toggle is ON.
    func weightedTotal(stageId: String) -> Double {
        weightedTotalByStageId[stageId] ?? 0
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
                rebuildStageIndex()
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
            rebuildStageIndex()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Build per-stage lookups (deals + raw total + weighted total) so the
    /// body of DealKanbanView can read O(1) values instead of re-scanning
    /// the deals array twice per stage on every render.
    private func rebuildStageIndex() {
        var grouped: [String: [Deal]] = [:]
        var raw: [String: Double] = [:]
        var weighted: [String: Double] = [:]
        for d in deals {
            guard let sid = d.stageId else { continue }
            grouped[sid, default: []].append(d)
            let amount = d.amount ?? 0
            raw[sid, default: 0] += amount
            weighted[sid, default: 0] += amount * (d.winProbability ?? 0)
        }
        dealsByStageId = grouped
        rawTotalByStageId = raw
        weightedTotalByStageId = weighted
    }
}

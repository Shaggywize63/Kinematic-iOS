//
//  LeadAnalyticsViewModel.swift
//  Kinematic CRM
//
//  Drives the read-only Lead Analytics view. Fans out 6 parallel reads to
//  the analytics endpoints and surfaces per-endpoint state so the cards
//  can each render their own "no data yet" placeholder without dragging
//  the whole screen into an error state.
//

import Foundation
import Combine
import SwiftUI

@MainActor
final class LeadAnalyticsViewModel: ObservableObject {
    // Per-widget @Published state — keeps each card independently reactive.
    @Published var funnel: [FunnelStageMetric] = []
    @Published var velocity: [LeadVelocityPoint] = []
    @Published var lostReasons: [ReasonCount] = []
    @Published var stageConversion: [StageConversionRow] = []
    @Published var leadsAtRisk: [LeadAtRisk] = []
    @Published var leadSourceROI: [LeadSourceROIRow] = []

    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    private let api = CRMService.shared
    private let location = CRMLocationStore.shared
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Refetch every widget when the global CRM city picker changes.
        // Without this, switching the picker mid-session left every
        // analytics card showing the previous city's aggregate (the
        // initial `.task { refresh() }` only fires once on appear).
        location.$state.combineLatest(location.$city)
            .dropFirst()
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in Task { await self?.refresh() } }
            .store(in: &cancellables)
    }

    /// Parallel refresh of every widget. Each endpoint is wrapped in `try?`
    /// so one 500 doesn't blank the whole screen — empty arrays render the
    /// per-card placeholder instead.
    func refresh() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        async let funnelTask  = api.funnel()
        async let velTask     = api.leadVelocity(months: 6)
        async let lostTask    = api.lostReasons()
        async let stageTask   = api.stageConversion()
        async let riskTask    = api.leadsAtRisk()
        async let roiTask     = api.leadSourceRoi()

        self.funnel          = (try? await funnelTask) ?? []
        self.velocity        = (try? await velTask)    ?? []
        self.lostReasons     = (try? await lostTask)   ?? []
        self.stageConversion = (try? await stageTask)  ?? []
        self.leadsAtRisk     = (try? await riskTask)   ?? []
        self.leadSourceROI   = (try? await roiTask)    ?? []
    }
}

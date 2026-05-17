//
//  LeadAnalyticsModels.swift
//  Kinematic CRM
//
//  Response shapes for the 5 extended analytics endpoints surfaced on the
//  read-only Lead Analytics view. Mirrors the TypeScript types in the
//  dashboard (`src/lib/crmAnalyticsExtApi.ts`, `src/types/crm.ts`).
//
//  The pipeline-funnel endpoint reuses the existing `FunnelStageMetric`
//  from `AnalyticsSummary.swift` (kept in sync with `CRMService.funnel()`).
//

import Foundation

// MARK: - Lead Velocity (GET /api/v1/crm/analytics/lead-velocity)
/// One row per month with total + qualified lead counts and MoM growth.
struct LeadVelocityPoint: Codable, Identifiable, Hashable {
    var id: String { month }
    let month: String
    let total: Int
    let qualified: Int
    /// Server returns `null` for the first cohort — leave nullable.
    let momGrowthPct: Double?

    enum CodingKeys: String, CodingKey {
        case month, total, qualified
        case momGrowthPct = "mom_growth_pct"
    }
}

// MARK: - Lost Reasons (GET /api/v1/crm/analytics/lost-reasons)
/// Counts of reasons leads were marked Lost. Same shape is also used by
/// won-reasons + disqualification-reasons so we leave it generic.
struct ReasonCount: Codable, Identifiable, Hashable {
    var id: String { reason }
    let reason: String
    let count: Int
}

// MARK: - Stage Conversion (GET /api/v1/crm/analytics/stage-conversion)
/// Funnel-style adjacent-stage advance rate. `rate` is a percentage 0..100
/// (the server already multiplies). One row per consecutive stage pair.
struct StageConversionRow: Codable, Identifiable, Hashable {
    var id: String { "\(fromStage)→\(toStage)" }
    let fromStage: String
    let toStage: String
    let entered: Int
    let advanced: Int
    let rate: Double

    enum CodingKeys: String, CodingKey {
        case fromStage = "from_stage"
        case toStage   = "to_stage"
        case entered, advanced, rate
    }
}

// MARK: - Leads at Risk (GET /api/v1/crm/analytics/leads-at-risk)
/// High-score open leads that have gone quiet (score ≥ 60, idle ≥ 14d by
/// default). Used for the "big number + top-5" risk widget.
struct LeadAtRisk: Codable, Identifiable, Hashable {
    var id: String { leadId }
    let leadId: String
    let name: String
    let score: Double
    let ownerId: String?
    let daysIdle: Int

    enum CodingKeys: String, CodingKey {
        case leadId   = "lead_id"
        case name, score
        case ownerId  = "owner_id"
        case daysIdle = "days_idle"
    }
}

// MARK: - Lead Source ROI (GET /api/v1/crm/analytics/lead-source-roi)
/// Per-source revenue/cost/ROI breakdown. The backend tolerates two column
/// shapes (canonical and legacy MV); we accept both via fallback decoding
/// so the iOS client doesn't crash on a freshly-deployed server.
struct LeadSourceROIRow: Codable, Identifiable, Hashable {
    var id: String { source }
    let source: String
    let leads: Int
    let deals: Int
    let revenue: Double
    let cost: Double
    /// Decimal ratio (0.5 = +50%). UI multiplies by 100 for display.
    let roi: Double

    enum CodingKeys: String, CodingKey {
        case source, leads, deals, revenue, cost, roi
        // Legacy aliases the materialised view emits.
        case sourceName  = "source_name"
        case leadCount   = "lead_count"
        case convertedCount = "converted_count"
        case revenueWon  = "revenue_won"
        case totalCost   = "total_cost"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.source = (try? c.decode(String.self, forKey: .source))
            ?? (try? c.decode(String.self, forKey: .sourceName))
            ?? "Unspecified"
        self.leads = (try? c.decode(Int.self, forKey: .leads))
            ?? (try? c.decode(Int.self, forKey: .leadCount))
            ?? 0
        self.deals = (try? c.decode(Int.self, forKey: .deals))
            ?? (try? c.decode(Int.self, forKey: .convertedCount))
            ?? 0
        let rev = (try? c.decode(Double.self, forKey: .revenue))
            ?? (try? c.decode(Double.self, forKey: .revenueWon))
            ?? 0
        let cst = (try? c.decode(Double.self, forKey: .cost))
            ?? (try? c.decode(Double.self, forKey: .totalCost))
            ?? 0
        self.revenue = rev
        self.cost = cst
        if let r = try? c.decode(Double.self, forKey: .roi) {
            self.roi = r
        } else if cst > 0 {
            self.roi = (rev - cst) / cst
        } else {
            self.roi = rev > 0 ? 1 : 0
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(source,  forKey: .source)
        try c.encode(leads,   forKey: .leads)
        try c.encode(deals,   forKey: .deals)
        try c.encode(revenue, forKey: .revenue)
        try c.encode(cost,    forKey: .cost)
        try c.encode(roi,     forKey: .roi)
    }
}

import Foundation

/// Renamed to avoid collision with the existing `AnalyticsSummary` declared in
/// `KinematicApp.swift` (used for the field-rep TFF dashboard).
struct CRMAnalyticsSummary: Codable, Hashable {
    let totalLeads: Int?
    let newLeadsThisWeek: Int?
    let openDeals: Int?
    let openPipelineValue: Double?
    /// Open-pipeline tonnage in kg (web surfaces this as MT = kg / 1000).
    let openDealVolume: Double?
    let dealsWonThisMonth: Int?
    let revenueWonThisMonth: Double?
    let winRate: Double?
    let averageDealSize: Double?
    let activitiesToday: Int?
    let tasksDue: Int?

    // Keys must match the backend `dashboardSummary()` payload exactly. The
    // previous mapping (open_pipeline_value, win_rate, …) was stale and decoded
    // every money/rate tile to nil → the dashboard showed 0 for Pipeline, Win
    // Rate, Avg Deal, New Leads, Won and Activities.
    enum CodingKeys: String, CodingKey {
        case totalLeads = "total_leads"
        case newLeadsThisWeek = "new_leads_30d"
        case openDeals = "open_deals"
        case openPipelineValue = "open_deal_value"
        case openDealVolume = "open_deal_volume"
        case dealsWonThisMonth = "won_deals_30d"
        case revenueWonThisMonth = "won_revenue_30d"
        case winRate = "win_rate_30d"
        case averageDealSize = "avg_deal_size"
        case activitiesToday = "activities_7d"
        // Backend does not emit a tasks_due figure; leave nil → tile shows 0.
        case tasksDue = "tasks_due"
    }
}

/// A client an org-level admin can scope the CRM into via the dashboard
/// picker. Mirrors the web `ClientSelect` row shape (`{ id, name }`).
struct CRMClientOption: Codable, Identifiable, Hashable {
    let id: String
    let name: String
}

/// A lead source (web/referral/cold-call …) used by the leads-list source
/// filter. Mirrors the web `LeadSource` row shape (`{ id, name }`).
struct CRMLeadSource: Codable, Identifiable, Hashable {
    let id: String
    let name: String
}

struct FunnelStageMetric: Codable, Identifiable, Hashable {
    var id: String { stageName }
    let stageName: String
    let count: Int
    let value: Double?

    enum CodingKeys: String, CodingKey {
        case stageName = "stage_name"
        case count, value
    }
}

struct WinRateBucket: Codable, Identifiable, Hashable {
    var id: String { period }
    let period: String
    let won: Int
    let lost: Int
    let winRate: Double

    enum CodingKeys: String, CodingKey {
        case period, won, lost
        case winRate = "win_rate"
    }
}

struct ForecastPoint: Codable, Identifiable, Hashable {
    var id: String { period }
    let period: String
    let bestCase: Double?
    let commit: Double?
    let weighted: Double?

    enum CodingKeys: String, CodingKey {
        case period
        case bestCase = "best_case"
        case commit
        case weighted
    }
}

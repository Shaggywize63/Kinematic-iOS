import Foundation

/// Renamed to avoid collision with the existing `AnalyticsSummary` declared in
/// `KinematicApp.swift` (used for the field-rep TFF dashboard).
struct CRMAnalyticsSummary: Codable, Hashable {
    let totalLeads: Int?
    let newLeadsThisWeek: Int?
    let openDeals: Int?
    let openPipelineValue: Double?
    let dealsWonThisMonth: Int?
    let revenueWonThisMonth: Double?
    let winRate: Double?
    let averageDealSize: Double?
    let activitiesToday: Int?
    let tasksDue: Int?

    enum CodingKeys: String, CodingKey {
        case totalLeads = "total_leads"
        case newLeadsThisWeek = "new_leads_this_week"
        case openDeals = "open_deals"
        case openPipelineValue = "open_pipeline_value"
        case dealsWonThisMonth = "deals_won_this_month"
        case revenueWonThisMonth = "revenue_won_this_month"
        case winRate = "win_rate"
        case averageDealSize = "average_deal_size"
        case activitiesToday = "activities_today"
        case tasksDue = "tasks_due"
    }
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

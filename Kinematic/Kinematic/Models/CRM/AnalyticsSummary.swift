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
    /// Sum of `custom_fields.estimated_amount` across the rep's leads
    /// in scope. Powers the Champion "Total Estimates Raised" tile.
    let estimatesRaised: Double?
    /// TOTAL leads per lead type. Sent only for a client that named its lead types
    /// (`config.lead_form.segment_labels`); nil for everyone else, which keeps the dashboard as it was.
    let leadsBySegment: LeadsBySegment?

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
        case estimatesRaised = "estimates_raised"
        case leadsBySegment = "leads_by_segment"
        // Backend does not emit a tasks_due figure; leave nil → tile shows 0.
        case tasksDue = "tasks_due"
    }

    // Spelled out (instead of synthesized) for one reason: `leads_by_segment` is an optional extra, so a
    // malformed value must cost the dashboard that tile only — never every other number on the screen.
    // Every other field decodes exactly as the synthesized code did.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalLeads = try c.decodeIfPresent(Int.self, forKey: .totalLeads)
        newLeadsThisWeek = try c.decodeIfPresent(Int.self, forKey: .newLeadsThisWeek)
        openDeals = try c.decodeIfPresent(Int.self, forKey: .openDeals)
        openPipelineValue = try c.decodeIfPresent(Double.self, forKey: .openPipelineValue)
        openDealVolume = try c.decodeIfPresent(Double.self, forKey: .openDealVolume)
        dealsWonThisMonth = try c.decodeIfPresent(Int.self, forKey: .dealsWonThisMonth)
        revenueWonThisMonth = try c.decodeIfPresent(Double.self, forKey: .revenueWonThisMonth)
        winRate = try c.decodeIfPresent(Double.self, forKey: .winRate)
        averageDealSize = try c.decodeIfPresent(Double.self, forKey: .averageDealSize)
        activitiesToday = try c.decodeIfPresent(Int.self, forKey: .activitiesToday)
        tasksDue = try c.decodeIfPresent(Int.self, forKey: .tasksDue)
        estimatesRaised = try c.decodeIfPresent(Double.self, forKey: .estimatesRaised)
        leadsBySegment = (try? c.decodeIfPresent(LeadsBySegment.self, forKey: .leadsBySegment)) ?? nil
    }
}

/// Total leads split by lead type — `{ "b2b": 12, "b2c": 30 }`. A missing count reads as 0.
struct LeadsBySegment: Codable, Hashable {
    let b2b: Int
    let b2c: Int

    init(b2b: Int, b2c: Int) {
        self.b2b = b2b
        self.b2c = b2c
    }

    private enum CodingKeys: String, CodingKey { case b2b, b2c }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        b2b = try c.decodeIfPresent(Int.self, forKey: .b2b) ?? 0
        b2c = try c.decodeIfPresent(Int.self, forKey: .b2c) ?? 0
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

/// The signed-in FE's daily lead target + how many they've added today.
/// Drives the dashboard ticker and the lead-add "1/5" progress badge.
struct CRMTarget: Codable, Hashable {
    let metric: String?
    let period: String?
    let target: Int
    let achieved: Int
    var hasTarget: Bool { target > 0 }
}

/// An org hierarchy tier (e.g. Tata "Consumer Champion", "Area Sales Officer").
struct CRMHierarchyLevel: Codable, Identifiable, Hashable {
    let id: String
    let name: String
}

/// Manager view of configured targets — the per-level values + the fallback.
struct CRMLevelTarget: Codable, Hashable {
    let hierarchyLevelId: String
    let targetValue: Int
    enum CodingKeys: String, CodingKey { case hierarchyLevelId = "hierarchy_level_id"; case targetValue = "target_value" }
}
struct CRMTargetsAdmin: Codable, Hashable {
    let defaultTarget: Int
    let perLevel: [CRMLevelTarget]
    enum CodingKeys: String, CodingKey { case defaultTarget = "default_target"; case perLevel = "per_level" }
}

// MARK: Targets leaderboard
struct CRMLeaderboardPerson: Codable, Hashable {
    let name: String
    let leads: Int
}
struct CRMLeaderboardStats: Codable, Hashable {
    let participants: Int
    let totalLeads: Int
    let averageLeads: Double
    let meetingTarget: Int
    let targetParticipants: Int
    let topPerformer: CRMLeaderboardPerson?
    let lowestPerformer: CRMLeaderboardPerson?
    enum CodingKeys: String, CodingKey {
        case participants
        case totalLeads = "total_leads"
        case averageLeads = "average_leads"
        case meetingTarget = "meeting_target"
        case targetParticipants = "target_participants"
        case topPerformer = "top_performer"
        case lowestPerformer = "lowest_performer"
    }
}
struct CRMLeaderboardEntry: Codable, Identifiable, Hashable {
    let userId: String
    let name: String
    let city: String?
    let leads: Int
    let target: Int
    let pct: Int?
    var id: String { userId }
    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name, city, leads, target, pct
    }
}
struct CRMLeaderboard: Codable, Hashable {
    let stats: CRMLeaderboardStats
    let entries: [CRMLeaderboardEntry]
    let roleId: String?
    enum CodingKeys: String, CodingKey { case stats, entries; case roleId = "role_id" }
}

struct FunnelStageMetric: Codable, Identifiable, Hashable {
    var id: String { stageName }
    let stageName: String
    let count: Int
    let value: Double?

    // Backend's funnel response emits each row as `{ stage, count, value }`.
    // We were decoding `stage_name`, so iOS picked up an empty string and
    // the chart silently rendered every bar as "" (or fell back to a
    // generic placeholder upstream). Map to `stage` now.
    enum CodingKeys: String, CodingKey {
        case stageName = "stage"
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

import Foundation

struct NextBestAction: Codable, Hashable {
    let dealId: String?
    let action: String
    /// 1-2 sentence rationale (legacy field — keep for older payloads).
    let rationale: String?
    /// New 1-2 sentence rationale from the enriched backend payload.
    /// When present this should be preferred over `rationale`.
    let reason: String?
    /// "high" | "medium" | "med" | "low".
    let priority: String?
    /// "now" | "today" | "this_week" | "next_week".
    let suggestedWhen: String?
    let dueAt: String?
    let confidence: Double?
    let suggestedTemplate: String?
    /// Step-by-step breakdown of how the recommendation was reached.
    /// Present on the new `/ai/next-best-action` response; nil on older
    /// payloads.
    let methodology: NextBestActionMethodology?

    enum CodingKeys: String, CodingKey {
        case dealId = "deal_id"
        case action, rationale, reason, priority
        case suggestedWhen = "suggested_when"
        case dueAt = "due_at"
        case confidence
        case suggestedTemplate = "suggested_template"
        case methodology
    }
}

/// Deal signals the recommendation engine considered. Mirrors the
/// backend payload one-for-one; every field is optional so older or
/// short-circuit responses still decode cleanly.
struct NextBestActionMethodology: Codable, Hashable {
    let signals: NextBestActionSignals?
    let closingPlan: [NextBestActionPlanStep]?
    let reasoning: String?

    enum CodingKeys: String, CodingKey {
        case signals
        case closingPlan = "closing_plan"
        case reasoning
    }
}

struct NextBestActionSignals: Codable, Hashable {
    let stage: NextBestActionStageInfo?
    let daysInStage: Int?
    let dealAgeDays: Int?
    let winProbability: Int?
    let activities30dTotal: Int?
    let activities30dByType: [String: Int]?
    let lastActivityAt: String?
    let lastActivityType: String?
    let daysSinceLastTouch: Int?
    let stageTransitions: Int?

    enum CodingKeys: String, CodingKey {
        case stage
        case daysInStage          = "days_in_stage"
        case dealAgeDays          = "deal_age_days"
        case winProbability       = "win_probability"
        case activities30dTotal   = "activities_30d_total"
        case activities30dByType  = "activities_30d_by_type"
        case lastActivityAt       = "last_activity_at"
        case lastActivityType     = "last_activity_type"
        case daysSinceLastTouch   = "days_since_last_touch"
        case stageTransitions     = "stage_transitions"
    }
}

struct NextBestActionStageInfo: Codable, Hashable {
    let name: String?
    let type: String?           // open / won / lost
    let probability: Int?
}

struct NextBestActionPlanStep: Codable, Hashable, Identifiable {
    var id: Int { step }
    let step: Int
    let action: String
    let rationale: String?
    let when: String?
}

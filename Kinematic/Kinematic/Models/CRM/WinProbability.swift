import Foundation

struct WinProbability: Codable, Hashable {
    let dealId: String?
    /// 0..1 Double. The gauge multiplies this by 100 for display, so we
    /// normalize on decode — backend now returns 0..100 ints, legacy
    /// callers may still send fractional 0..1 values.
    let probability: Double
    /// Short English explanation rendered above the breakdown sheet.
    let reasoning: String?
    let band: String?           // legacy: low / medium / high
    let drivers: [WinProbabilityDriver]?
    let computedAt: String?
    /// Detailed walkthrough of how `probability` was computed. Present
    /// on the new `/ai/win-probability` response; nil on older payloads.
    let breakdown: WinProbabilityBreakdown?

    enum CodingKeys: String, CodingKey {
        case dealId = "deal_id"
        case probability
        case reasoning
        case band
        case drivers
        case computedAt = "computed_at"
        case breakdown
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.dealId      = try c.decodeIfPresent(String.self,  forKey: .dealId)
        self.reasoning   = try c.decodeIfPresent(String.self,  forKey: .reasoning)
        self.band        = try c.decodeIfPresent(String.self,  forKey: .band)
        self.drivers     = try c.decodeIfPresent([WinProbabilityDriver].self, forKey: .drivers)
        self.computedAt  = try c.decodeIfPresent(String.self,  forKey: .computedAt)
        self.breakdown   = try c.decodeIfPresent(WinProbabilityBreakdown.self, forKey: .breakdown)
        let raw = try c.decode(Double.self, forKey: .probability)
        // Backend started returning 0..100 ints; keep the Swift contract
        // at 0..1 so the existing gauge code stays correct.
        self.probability = raw > 1.0 ? raw / 100.0 : raw
    }

    // Memberwise init kept for tests / previews.
    init(dealId: String?, probability: Double, reasoning: String? = nil,
         band: String? = nil, drivers: [WinProbabilityDriver]? = nil,
         computedAt: String? = nil, breakdown: WinProbabilityBreakdown? = nil) {
        self.dealId = dealId
        self.probability = probability
        self.reasoning = reasoning
        self.band = band
        self.drivers = drivers
        self.computedAt = computedAt
        self.breakdown = breakdown
    }
}

struct WinProbabilityDriver: Codable, Hashable, Identifiable {
    var id: String { factor }
    let factor: String
    let impact: Double
    let direction: String?      // positive / negative
}

/// Step-by-step breakdown rendered inside the "How is this calculated?"
/// sheet. Mirrors the backend payload one-for-one; every field is
/// optional so older responses (or short-circuit Won/Lost rows where the
/// engine bypasses the math) still decode cleanly.
struct WinProbabilityBreakdown: Codable, Hashable {
    /// "won" | "lost" | nil. When set, the engine bypassed the formula
    /// because the deal is already closed and the gauge is locked.
    let shortCircuit: String?
    let shortCircuitMessage: String?
    let stageProbability: Int?
    let stageName: String?
    let ageDays: Int?
    let ageMultiplier: Double?
    let ageLabel: String?
    let activities30d: Int?
    let engagementMultiplier: Double?
    let engagementLabel: String?
    let formulaText: String?
    let finalProbability: Int?

    enum CodingKeys: String, CodingKey {
        case shortCircuit         = "short_circuit"
        case shortCircuitMessage  = "short_circuit_message"
        case stageProbability     = "stage_probability"
        case stageName            = "stage_name"
        case ageDays              = "age_days"
        case ageMultiplier        = "age_multiplier"
        case ageLabel             = "age_label"
        case activities30d        = "activities_30d"
        case engagementMultiplier = "engagement_multiplier"
        case engagementLabel      = "engagement_label"
        case formulaText          = "formula_text"
        case finalProbability     = "final_probability"
    }
}

import Foundation

struct LeadScore: Codable, Hashable {
    let leadId: String
    let score: Double
    let band: String?           // hot / warm / cold
    let breakdown: [ScoreBreakdown]?
    let computedAt: String?

    enum CodingKeys: String, CodingKey {
        case leadId = "lead_id"
        case score, band, breakdown
        case computedAt = "computed_at"
    }
}

struct LeadScoreHistoryEntry: Codable, Identifiable, Hashable {
    var id: String { computedAt ?? UUID().uuidString }
    let score: Double
    let band: String?
    let computedAt: String?

    enum CodingKeys: String, CodingKey {
        case score, band
        case computedAt = "computed_at"
    }
}

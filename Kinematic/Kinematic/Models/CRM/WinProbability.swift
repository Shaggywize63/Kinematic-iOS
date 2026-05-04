import Foundation

struct WinProbability: Codable, Hashable {
    let dealId: String?
    let probability: Double
    let band: String?           // low / medium / high
    let drivers: [WinProbabilityDriver]?
    let computedAt: String?

    enum CodingKeys: String, CodingKey {
        case dealId = "deal_id"
        case probability, band, drivers
        case computedAt = "computed_at"
    }
}

struct WinProbabilityDriver: Codable, Hashable, Identifiable {
    var id: String { factor }
    let factor: String
    let impact: Double
    let direction: String?      // positive / negative
}

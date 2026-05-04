import Foundation

struct ScoreBreakdown: Codable, Identifiable, Hashable {
    var id: String { factor }
    let factor: String
    let points: Double
    let rationale: String?
}

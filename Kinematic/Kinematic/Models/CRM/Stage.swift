import Foundation

struct Stage: Codable, Identifiable, Hashable {
    let id: String
    let pipelineId: String?
    let name: String
    let order: Int?
    let probability: Double?
    let isClosed: Bool?
    let isWon: Bool?
    let color: String?

    enum CodingKeys: String, CodingKey {
        case id
        case pipelineId = "pipeline_id"
        case name
        case order
        case probability
        case isClosed = "is_closed"
        case isWon = "is_won"
        case color
    }
}

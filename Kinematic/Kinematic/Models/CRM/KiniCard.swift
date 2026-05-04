import Foundation

/// Rich card emitted by KINI/AI tool-calls. The mobile UI renders these as
/// inline cards under the assistant bubble (deal preview, lead preview, etc.).
struct KiniCard: Codable, Identifiable, Hashable {
    var id: String { (kind ?? "card") + "_" + (title ?? UUID().uuidString) }
    let kind: String?              // "lead", "deal", "contact", "chart", "action"
    let title: String?
    let subtitle: String?
    let body: String?
    let entityId: String?
    let value: Double?
    let metric: String?
    let actions: [KiniCardAction]?

    enum CodingKeys: String, CodingKey {
        case kind, title, subtitle, body
        case entityId = "entity_id"
        case value, metric, actions
    }
}

struct KiniCardAction: Codable, Hashable, Identifiable {
    var id: String { label }
    let label: String
    let route: String?
    let payload: [String: AnyCodable]?
}

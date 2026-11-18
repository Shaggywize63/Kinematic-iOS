import Foundation

/// A co-owner (additional owner) of a lead / account / contact / deal. The record keeps its single primary
/// owner; co-owners are peers who also see it. Note the wire key is `user_id`.
struct CoOwner: Codable, Identifiable, Hashable {
    let userId: String
    let name: String?

    var id: String { userId }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case name
    }

    init(userId: String, name: String?) {
        self.userId = userId; self.name = name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = (try? c.decode(String.self, forKey: .userId)) ?? ""
        name = try? c.decodeIfPresent(String.self, forKey: .name)
    }
}

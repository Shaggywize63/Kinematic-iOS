import Foundation

struct Campaign: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let type: String?           // email / sms / event
    let status: String?         // draft / active / paused / done
    let startDate: String?
    let endDate: String?
    let budget: Double?
    let actualCost: Double?
    let expectedRevenue: Double?
    let actualRevenue: Double?
    let ownerId: String?

    enum CodingKeys: String, CodingKey {
        case id, name, type, status
        case startDate = "start_date"
        case endDate = "end_date"
        case budget
        case actualCost = "actual_cost"
        case expectedRevenue = "expected_revenue"
        case actualRevenue = "actual_revenue"
        case ownerId = "owner_id"
    }
}

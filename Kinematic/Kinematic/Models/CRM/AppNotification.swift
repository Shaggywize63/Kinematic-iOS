import Foundation

/// A backend notification row (public.notifications) — stagnant-lead nudges,
/// deal-closing reminders, task-overdue alerts, broadcasts, etc. Carries a
/// loose `data` payload that usually includes `lead_id` / `deal_id` for
/// deep-linking and `kind` for the icon.
struct CRMNotification: Codable, Identifiable {
    let id: String
    let title: String?
    let body: String?
    let data: [String: AnyCodable]?
    let isRead: Bool?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, body, data
        case isRead = "is_read"
        case createdAt = "created_at"
    }

    var leadId: String? { data?["lead_id"]?.value }
    var dealId: String? { data?["deal_id"]?.value }
    var kind: String? { data?["kind"]?.value }
}

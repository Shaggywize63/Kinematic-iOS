import Foundation

/// A single task assigned to the signed-in user, as returned by
/// `GET /api/v1/crm/my-tasks`. The endpoint returns ONLY the caller's own
/// tasks (open/upcoming by default) and denormalises the linked lead /
/// contact / account / company / deal names plus — crucially — **who
/// assigned the task** (`assigned_by` / `assigned_by_name`), which no other
/// CRM list surfaces.
///
/// Every string field is nullable on the wire; only `is_overdue` is a
/// guaranteed bool. Decoding is lenient (every key `decodeIfPresent`, a
/// missing `is_overdue` reads `false`) so an older/partial server row never
/// drops the whole list — the same contract the other CRM list models follow.
struct MyTask: Codable, Identifiable, Hashable {
    let id: String
    let type: String?
    let subject: String?
    let body: String?
    let status: String?
    let dueAt: String?
    let completedAt: String?
    let activityDate: String?
    let createdAt: String?
    let leadId: String?
    let leadName: String?
    let leadPhone: String?
    let contactId: String?
    let contactName: String?
    let accountId: String?
    let accountName: String?
    let companyId: String?
    let companyName: String?
    let dealId: String?
    let dealName: String?
    let ownerId: String?
    let ownerName: String?
    /// The person the task is assigned to (the caller) + their name.
    let assignedTo: String?
    let assignedToName: String?
    /// Who created / assigned this task to the caller + their name. Nil for
    /// self-created tasks — the row hides the "Assigned by …" line then.
    let assignedBy: String?
    let assignedByName: String?
    /// Server-computed: the task is open and past its due date. Never nil.
    let isOverdue: Bool

    enum CodingKeys: String, CodingKey {
        case id, type, subject, body, status
        case dueAt = "due_at"
        case completedAt = "completed_at"
        case activityDate = "activity_date"
        case createdAt = "created_at"
        case leadId = "lead_id"
        case leadName = "lead_name"
        case leadPhone = "lead_phone"
        case contactId = "contact_id"
        case contactName = "contact_name"
        case accountId = "account_id"
        case accountName = "account_name"
        case companyId = "company_id"
        case companyName = "company_name"
        case dealId = "deal_id"
        case dealName = "deal_name"
        case ownerId = "owner_id"
        case ownerName = "owner_name"
        case assignedTo = "assigned_to"
        case assignedToName = "assigned_to_name"
        case assignedBy = "assigned_by"
        case assignedByName = "assigned_by_name"
        case isOverdue = "is_overdue"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.type = try c.decodeIfPresent(String.self, forKey: .type)
        self.subject = try c.decodeIfPresent(String.self, forKey: .subject)
        self.body = try c.decodeIfPresent(String.self, forKey: .body)
        self.status = try c.decodeIfPresent(String.self, forKey: .status)
        self.dueAt = try c.decodeIfPresent(String.self, forKey: .dueAt)
        self.completedAt = try c.decodeIfPresent(String.self, forKey: .completedAt)
        self.activityDate = try c.decodeIfPresent(String.self, forKey: .activityDate)
        self.createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        self.leadId = try c.decodeIfPresent(String.self, forKey: .leadId)
        self.leadName = try c.decodeIfPresent(String.self, forKey: .leadName)
        self.leadPhone = try c.decodeIfPresent(String.self, forKey: .leadPhone)
        self.contactId = try c.decodeIfPresent(String.self, forKey: .contactId)
        self.contactName = try c.decodeIfPresent(String.self, forKey: .contactName)
        self.accountId = try c.decodeIfPresent(String.self, forKey: .accountId)
        self.accountName = try c.decodeIfPresent(String.self, forKey: .accountName)
        self.companyId = try c.decodeIfPresent(String.self, forKey: .companyId)
        self.companyName = try c.decodeIfPresent(String.self, forKey: .companyName)
        self.dealId = try c.decodeIfPresent(String.self, forKey: .dealId)
        self.dealName = try c.decodeIfPresent(String.self, forKey: .dealName)
        self.ownerId = try c.decodeIfPresent(String.self, forKey: .ownerId)
        self.ownerName = try c.decodeIfPresent(String.self, forKey: .ownerName)
        self.assignedTo = try c.decodeIfPresent(String.self, forKey: .assignedTo)
        self.assignedToName = try c.decodeIfPresent(String.self, forKey: .assignedToName)
        self.assignedBy = try c.decodeIfPresent(String.self, forKey: .assignedBy)
        self.assignedByName = try c.decodeIfPresent(String.self, forKey: .assignedByName)
        self.isOverdue = (try c.decodeIfPresent(Bool.self, forKey: .isOverdue)) ?? false
    }

    // MARK: Display helpers

    /// Row title: the subject, else a humanised activity type, else "Task".
    var displayTitle: String {
        if let s = subject?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty { return s }
        if let t = type?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            return t.replacingOccurrences(of: "_", with: " ").capitalized
        }
        return "Task"
    }

    /// The linked record's name for the row's subtitle — lead first, then
    /// account / company / contact / deal (the order the list prioritises
    /// context). Nil when the task is linked to nothing.
    var linkedName: String? {
        for candidate in [leadName, accountName, companyName, contactName, dealName] {
            if let v = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { return v }
        }
        return nil
    }

    /// Effective workflow state for the status pill: the stamped `status`,
    /// falling back to "completed" when only `completed_at` is set, else "open".
    var effectiveStatus: String {
        if let s = status?.trimmingCharacters(in: .whitespaces), !s.isEmpty { return s.lowercased() }
        return (completedAt?.isEmpty == false) ? "completed" : "open"
    }
}

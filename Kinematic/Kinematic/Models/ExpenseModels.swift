// ExpenseModels — wire types for /api/v1/expenses (Field Expense / Travel Claims).
//
// Property names are snake_case to match the JSON keys directly, because the
// shared decoder (see ExpensesAPI) uses no keyDecodingStrategy — same idiom as
// DistributionModels.

import Foundation

struct ExpensePolicy: Codable {
    let currency: String
    let mileage_rate: Double
    let auto_approve_under: Double?
    let escalate_over: Double?
    let require_receipt_over: Double
    let category_limits: [String: Double]?
    let is_active: Bool?
}

struct ExpenseFlag: Codable, Identifiable {
    var id: String { code + "|" + (detail ?? "") }
    let code: String
    let severity: String?
    let detail: String?
}

struct ExpenseClaimItem: Codable, Identifiable {
    let id: String
    let category: String
    let item_date: String?
    let description: String?
    let amount: Double
    let distance_km: Double?
    let from_location: String?
    let to_location: String?
    let merchant: String?
    let receipt_url: String?
    let flagged: Bool?
    let flag_reason: String?
}

struct ExpenseApproval: Codable, Identifiable {
    let id: String
    let level: Int
    let approver_id: String?
    let status: String?
    let note: String?
    let decided_at: String?
    let approver_name: String?
}

struct ExpenseClaim: Codable, Identifiable {
    let id: String
    let user_id: String?
    let claim_no: String?
    let title: String?
    let status: String?
    let currency: String
    let total_amount: Double
    let distance_km: Double?
    let gps_derived_km: Double?
    let approver_id: String?
    let current_level: Int?
    let submitted_at: String?
    let review_note: String?
    let ai_summary: String?
    let ai_flags: [ExpenseFlag]?
    let created_at: String?
    let user_name: String?
    let employee_id: String?
    let approver_name: String?
    let items: [ExpenseClaimItem]?
    let approvals: [ExpenseApproval]?

    var statusLabel: String { (status ?? "draft").capitalized }
}

struct ExpenseMileageResult: Codable {
    let distance_km: Double
    let points_used: Int?
    let points_excluded: Int?
    let segments_skipped: Int?
    let mileage_rate: Double
    let currency: String
    let suggested_amount: Double
}

struct ExpenseReceiptFields: Codable {
    let merchant: String?
    let txn_date: String?
    let amount: Double?
    let currency: String?
    let tax_amount: Double?
    let category: String?
}

// ── Request bodies ──────────────────────────────────────────────────────────
struct ExpenseClaimItemInput: Encodable {
    let category: String
    let item_date: String?
    let description: String?
    let amount: Double?
    let distance_km: Double?
    let from_location: String?
    let to_location: String?
    let merchant: String?
    let receipt_url: String?
}

struct ExpenseClaimInput: Encodable {
    let title: String?
    let items: [ExpenseClaimItemInput]
}

enum ExpenseCategory: String, CaseIterable, Identifiable {
    case mileage, travel, food, lodging, fuel, toll, misc
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

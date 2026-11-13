//
//  DeskCall.swift
//  Kinematic CRM
//
//  Models for the pharma "Calling Desk" — a daily tele-calling worklist for
//  Maa Mansha Pharma. A desk operator works a generated list of customers
//  (accounts / leads) and dispositions each call with one of three statuses;
//  "Order Taken" additionally captures an order value.
//
//  Mirrors the backend contract at /api/v1/crm/desk/* (see the Kinematic repo
//  and the web dashboard). All responses are the standard
//  `{ success, data }` envelope, decoded through `APIEnvelope<T>` by the
//  service layer, so these structs model only the `data` payloads.
//
//  The service's JSONDecoder has NO snake_case key strategy, so every struct
//  declares explicit snake_case `CodingKeys` (matching Lead / Deal / …).
//

import Foundation

/// One customer on the operator's daily call list.
struct DeskCallTask: Codable, Identifiable, Hashable {
    let id: String
    /// "YYYY-MM-DD" — the day this task belongs to.
    let callDate: String?
    /// "account" | "lead" — which CRM record this customer is.
    let customerType: String?
    /// The linked account / lead id.
    let customerId: String?
    let customerName: String?
    let customerPhone: String?
    /// User id of the operator this task is assigned to (nil = unassigned pool).
    let assignedOperator: String?
    /// "pending" | "order_taken" | "order_pending" | "no_order".
    let status: String?
    /// Captured only when `status == "order_taken"`.
    let orderValue: Double?
    let notes: String?
    /// ISO-8601 timestamp of when the call was dispositioned (nil until called).
    let calledAt: String?
    /// True once an "order_pending" follow-up has been resolved.
    let pendingResolved: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case callDate = "call_date"
        case customerType = "customer_type"
        case customerId = "customer_id"
        case customerName = "customer_name"
        case customerPhone = "customer_phone"
        case assignedOperator = "assigned_operator"
        case status
        case orderValue = "order_value"
        case notes
        case calledAt = "called_at"
        case pendingResolved = "pending_resolved"
    }

    /// The disposition as a typed enum (falls back to `.pending` for an unknown
    /// or absent server value so the row still renders).
    var dispositionStatus: DeskStatus {
        DeskStatus(rawValue: status ?? "pending") ?? .pending
    }

    /// True when this task has been worked (any disposition set).
    var isCalled: Bool { calledAt != nil || dispositionStatus != .pending }

    var displayName: String {
        let n = (customerName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Unknown customer" : n
    }
}

/// The disposition statuses an operator can set. The raw values are the API
/// keys; `label` is the exact client wording shown in the UI.
enum DeskStatus: String, CaseIterable, Hashable {
    case pending
    case orderTaken = "order_taken"
    case orderPending = "order_pending"
    case noOrder = "no_order"

    /// Exact client wording. "pending" is the pre-call state and is not an
    /// operator-selectable disposition, so it carries a neutral label.
    var label: String {
        switch self {
        case .pending:      return "Not Called Yet"
        case .orderTaken:   return "Call Connected – Order Taken"
        case .orderPending: return "Call Connected – Order Pending"
        case .noOrder:      return "No Order Today"
        }
    }

    /// Short badge text for dense list rows.
    var shortLabel: String {
        switch self {
        case .pending:      return "Pending"
        case .orderTaken:   return "Order Taken"
        case .orderPending: return "Order Pending"
        case .noOrder:      return "No Order"
        }
    }

    /// Only the three dispositions an operator sets (excludes `.pending`).
    static var dispositions: [DeskStatus] { [.orderTaken, .orderPending, .noOrder] }

    /// Order Taken is the only disposition that requires an order value.
    var requiresOrderValue: Bool { self == .orderTaken }
}

/// `data` of GET /api/v1/crm/desk/call-list.
struct DeskCallListPage: Codable {
    let rows: [DeskCallTask]
    let total: Int?
    let page: Int?
    let limit: Int?
    let date: String?

    enum CodingKeys: String, CodingKey {
        case rows, total, page, limit, date
    }
}

/// `data` of GET /api/v1/crm/desk/summary — the day's roll-up for the header.
struct DeskDaySummary: Codable, Hashable {
    let date: String?
    let assigned: Int?
    let pending: Int?
    let orderTaken: Int?
    let orderPending: Int?
    let noOrder: Int?
    let connected: Int?
    let ordersValue: Double?
    let called: Int?

    enum CodingKeys: String, CodingKey {
        case date, assigned, pending
        case orderTaken = "order_taken"
        case orderPending = "order_pending"
        case noOrder = "no_order"
        case connected
        case ordersValue = "orders_value"
        case called
    }
}

/// `data` of POST /api/v1/crm/desk/generate (admin only).
struct DeskGenerateResult: Codable {
    let date: String?
    let created: Int?
    let existing: Int?
    let customers: Int?
    let operators: Int?

    enum CodingKeys: String, CodingKey {
        case date, created, existing, customers, operators
    }
}

/// `data` of PATCH /api/v1/crm/desk/call-list/{id}. We only consume `task`;
/// `order` is any shape, kept optional so decoding never fails on it.
struct DeskPatchResult: Codable {
    let task: DeskCallTask
    let order: AnyCodable?

    enum CodingKeys: String, CodingKey {
        case task, order
    }
}

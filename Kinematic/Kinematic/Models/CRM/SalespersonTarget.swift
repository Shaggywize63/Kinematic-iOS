import Foundation

/// One salesperson's SALES-target drill-down for an IST month, from
/// `GET /api/v1/crm/targets/salesperson/:userId?month=YYYY-MM` (manager-gated).
/// `basis` is how achievement is measured — "won_deals" for an opted-in client
/// (e.g. Aadinath), "manual" (logged entries) otherwise. Money fields are rupees.
///
/// Decoding is lenient: a missing/garbled field falls back to a sane default so
/// one odd value never blanks the whole screen. `target`/`pending`/`pct` are
/// nullable (no target set, or the targets feature is off).
struct SalespersonTargetDetail: Codable, Hashable {
    var userId: String?
    var name: String?
    var basis: String?
    var periodStart: String?
    var periodEnd: String?
    var target: Double?
    var achieved: Double
    var pending: Double?
    var pct: Int?
    var daily: [SalesBucket]
    var weekly: [SalesBucket]
    var historical: [SalesHistoryPoint]
    var customers: [SalesCustomer]

    var isWonDealsBasis: Bool { basis == "won_deals" }

    enum CodingKeys: String, CodingKey {
        case userId = "user_id", name, basis
        case periodStart = "period_start", periodEnd = "period_end"
        case target, achieved, pending, pct, daily, weekly, historical, customers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try? c.decode(String.self, forKey: .userId)
        name = try? c.decode(String.self, forKey: .name)
        basis = try? c.decode(String.self, forKey: .basis)
        periodStart = try? c.decode(String.self, forKey: .periodStart)
        periodEnd = try? c.decode(String.self, forKey: .periodEnd)
        target = try? c.decode(Double.self, forKey: .target)
        achieved = (try? c.decode(Double.self, forKey: .achieved)) ?? 0
        pending = try? c.decode(Double.self, forKey: .pending)
        pct = try? c.decode(Int.self, forKey: .pct)
        daily = (try? c.decode([SalesBucket].self, forKey: .daily)) ?? []
        weekly = (try? c.decode([SalesBucket].self, forKey: .weekly)) ?? []
        historical = (try? c.decode([SalesHistoryPoint].self, forKey: .historical)) ?? []
        customers = (try? c.decode([SalesCustomer].self, forKey: .customers)) ?? []
    }
}

/// One daily (`date`) or weekly (`week_start`) progress bucket: ₹ value + record count.
struct SalesBucket: Codable, Hashable, Identifiable {
    var date: String?
    var weekStart: String?
    var value: Double
    var count: Int

    /// Stable id for ForEach — the day or the week start.
    var id: String { date ?? weekStart ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey { case date, weekStart = "week_start", value, count }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try? c.decode(String.self, forKey: .date)
        weekStart = try? c.decode(String.self, forKey: .weekStart)
        value = (try? c.decode(Double.self, forKey: .value)) ?? 0
        count = (try? c.decode(Int.self, forKey: .count)) ?? 0
    }
}

/// One month's target-vs-achieved point in the 6-month history.
struct SalesHistoryPoint: Codable, Hashable, Identifiable {
    var month: String?
    var target: Double?
    var achieved: Double
    var pct: Int?

    var id: String { month ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey { case month, target, achieved, pct }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        month = try? c.decode(String.self, forKey: .month)
        target = try? c.decode(Double.self, forKey: .target)
        achieved = (try? c.decode(Double.self, forKey: .achieved)) ?? 0
        pct = try? c.decode(Int.self, forKey: .pct)
    }
}

/// One customer/account contributing to this month's sales: ₹ value + order count.
struct SalesCustomer: Codable, Hashable, Identifiable {
    var name: String?
    var value: Double
    var count: Int

    var id: String { name ?? UUID().uuidString }

    enum CodingKeys: String, CodingKey { case name, value, count }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try? c.decode(String.self, forKey: .name)
        value = (try? c.decode(Double.self, forKey: .value)) ?? 0
        count = (try? c.decode(Int.self, forKey: .count)) ?? 0
    }
}

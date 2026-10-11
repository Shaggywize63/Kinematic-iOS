// SalesmanJSON — forgiving readers for the replies of the endpoints the Gomant field loop added:
//   GET /salesman/outlets, GET /salesman/outlets/{id}/outstanding, and the reply of POST /salesman/{orders,payments,returns}.
// Pure Foundation (reads through `AnyJSON`), so it is unit-tested (see KinematicTests/SalesmanJSONTests).
//
// Why by hand instead of `Codable` models: each reader accepts BOTH the usual `{ success, data: … }` envelope and the
// bare payload, tolerates a number sent as a string ("1,200.50"), and skips a single unreadable row instead of failing
// the whole list. Every function returns "nothing" (nil / empty) instead of throwing.

import Foundation

// MARK: - Models

/// One outlet the rep may sell to / collect from. Everything except `id` is optional.
struct SalesmanOutlet: Identifiable, Equatable {
    let id: String
    var name: String? = nil
    var code: String? = nil
    var address: String? = nil
    var city: String? = nil
    var phone: String? = nil
    var distributorId: String? = nil
    var distributorName: String? = nil
    /// nil when the server sent none.
    var outstandingBalance: Double? = nil
}

/// One unpaid invoice of an outlet. `balance` = total - paid.
struct OpenInvoice: Identifiable, Equatable {
    let invoiceId: String
    var invoiceNo: String? = nil
    var invoiceDate: String? = nil
    var dueDate: String? = nil
    var total: Double? = nil
    var paid: Double? = nil
    var balance: Double? = nil
    var id: String { invoiceId }
}

/// An outlet's balance and its open invoices, oldest first. `creditLimit` is nil when the outlet has none.
struct OutletOutstanding: Equatable {
    var outletId: String? = nil
    var outletName: String? = nil
    var balance: Double? = nil
    var creditLimit: Double? = nil
    var openInvoices: [OpenInvoice] = []
}

/// Result of an outlet search for the picker.
enum OutletSearchResult: Equatable {
    case found([SalesmanOutlet])
    /// No connection — the picker says so; it cannot search offline.
    case offline
    case failed(String)
}

/// Result of loading an outlet's outstanding balance (online only; never cached — money data must not be stale).
enum OutstandingResult: Equatable {
    case loaded(OutletOutstanding)
    /// No connection — shown as the muted "Outstanding unavailable offline".
    case offline
    /// The server could not provide it (error / unreadable) — shown as a muted "Outstanding unavailable".
    case unavailable

    var loadedValue: OutletOutstanding? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var isOffline: Bool {
        if case .offline = self { return true }
        return false
    }
}

/// What the payment reply says was done with the money.
struct PaymentReply: Equatable {
    var paymentNo: String? = nil
    var amount: Double? = nil
    /// nil when the reply has no `applied_to_invoices` list at all.
    var applied: [PaymentReplyLine]? = nil
}

struct PaymentReplyLine: Equatable {
    let invoiceId: String
    var invoiceNo: String? = nil
    let amount: Double
}

// MARK: - Readers

enum SalesmanJSON {

    // MARK: tolerant helpers

    /// The JSON tree of a reply body, or nil when it is empty or not JSON.
    static func tree(_ data: Data?) -> AnyJSON? {
        guard let data = data, !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(AnyJSON.self, from: data)
    }

    /// `data` of a `{ success, data }` envelope when there is a non-null one, else the element itself.
    static func unwrap(_ root: AnyJSON?) -> AnyJSON? {
        guard let root = root else { return nil }
        if case .null = root { return nil }
        if case .object(let fields) = root, let inner = fields["data"] {
            if case .null = inner { return root }
            return inner
        }
        return root
    }

    private static func object(_ value: AnyJSON?) -> [String: AnyJSON]? {
        if let value = value, case .object(let fields) = value { return fields }
        return nil
    }

    private static func array(_ value: AnyJSON?) -> [AnyJSON]? {
        if let value = value, case .array(let items) = value { return items }
        return nil
    }

    /// A non-blank string (numbers read as their text); nil for anything else.
    private static func text(_ value: AnyJSON?) -> String? {
        guard let value = value else { return nil }
        switch value {
        case .string(let s):
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case .number(let n):
            guard n.isFinite else { return nil }
            if n == n.rounded() && abs(n) < 1e15 { return String(Int64(n)) }
            return String(n)
        default:
            return nil
        }
    }

    /// A number, or a string holding one ("1200.50", "1,200"). Anything else (null, junk, NaN) is nil.
    private static func number(_ value: AnyJSON?) -> Double? {
        guard let value = value else { return nil }
        switch value {
        case .number(let n):
            return n.isFinite ? n : nil
        case .string(let s):
            let cleaned = s.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
            if let d = Double(cleaned), d.isFinite { return d }
            return nil
        default:
            return nil
        }
    }

    // MARK: GET /salesman/outlets

    static func outlets(fromData data: Data?) -> [SalesmanOutlet] { outlets(from: tree(data)) }

    /// The outlet list. A row without an `id` is skipped; anything unreadable → an empty list.
    static func outlets(from root: AnyJSON?) -> [SalesmanOutlet] {
        guard let payload = unwrap(root) else { return [] }
        let rows: [AnyJSON] = array(payload)
            ?? array(object(payload)?["outlets"])
            ?? array(object(payload)?["items"])
            ?? []
        var result: [SalesmanOutlet] = []
        for row in rows {
            guard let fields = object(row), let id = text(fields["id"]) else { continue }
            result.append(SalesmanOutlet(
                id: id,
                name: text(fields["name"]),
                code: text(fields["code"]),
                address: text(fields["address"]),
                city: text(fields["city"]),
                phone: text(fields["phone"]),
                distributorId: text(fields["distributor_id"]),
                distributorName: text(fields["distributor_name"]),
                outstandingBalance: number(fields["outstanding_balance"])
            ))
        }
        return result
    }

    // MARK: GET /salesman/outlets/{id}/outstanding

    static func outstanding(fromData data: Data?) -> OutletOutstanding? { outstanding(from: tree(data)) }

    /// The outlet's balance + open invoices; nil when the reply is not an object at all.
    static func outstanding(from root: AnyJSON?) -> OutletOutstanding? {
        guard let fields = object(unwrap(root)) else { return nil }
        var invoices: [OpenInvoice] = []
        for row in array(fields["open_invoices"]) ?? [] {
            guard let inv = object(row), let invoiceId = text(inv["invoice_id"]) ?? text(inv["id"]) else { continue }
            invoices.append(OpenInvoice(
                invoiceId: invoiceId,
                invoiceNo: text(inv["invoice_no"]),
                invoiceDate: text(inv["invoice_date"]),
                dueDate: text(inv["due_date"]),
                total: number(inv["total"]),
                paid: number(inv["paid"]),
                balance: number(inv["balance"])
            ))
        }
        return OutletOutstanding(
            outletId: text(fields["outlet_id"]),
            outletName: text(fields["outlet_name"]),
            balance: number(fields["balance"]),
            creditLimit: number(fields["credit_limit"]),
            openInvoices: invoices
        )
    }

    // MARK: replies of the three POSTs

    /// The order / payment / return number in a create reply (`{ data: { order_no | payment_no | return_no } }`),
    /// or nil when the reply is unreadable or carries none.
    static func reference(fromData data: Data?) -> String? {
        guard let fields = object(unwrap(tree(data))) else { return nil }
        for key in ["order_no", "payment_no", "return_no"] {
            if let value = text(fields[key]) { return value }
        }
        return nil
    }

    /// The payment created, as the server answered: its number, amount and where the amount was applied.
    static func paymentReply(fromData data: Data?) -> PaymentReply? {
        guard let fields = object(unwrap(tree(data))) else { return nil }
        var reply = PaymentReply()
        reply.paymentNo = text(fields["payment_no"])
        reply.amount = number(fields["amount"])
        if let rows = array(fields["applied_to_invoices"]) {
            var lines: [PaymentReplyLine] = []
            for row in rows {
                guard let entry = object(row), let invoiceId = text(entry["invoice_id"]),
                      let amount = number(entry["amount"]), amount > 0 else { continue }
                lines.append(PaymentReplyLine(invoiceId: invoiceId, invoiceNo: text(entry["invoice_no"]), amount: amount))
            }
            reply.applied = lines
        }
        return reply
    }
}

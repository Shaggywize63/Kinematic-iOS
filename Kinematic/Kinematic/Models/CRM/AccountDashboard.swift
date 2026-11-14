import Foundation

// Pure, UI-free logic behind the reworked account screens (mirrors web PR #668 + backend #676):
//   • the POST /crm/accounts 409 duplicate payload,
//   • the account-detail value stats + product rollup from the account's deals,
//   • the account-detail Leads card's display name / value.
// Kept here (no SwiftUI) so the forms and the detail dashboard bind to it and the tests drive it directly.

// MARK: - Duplicate account (POST /crm/accounts → 409)

/// The `existing` account carried by the backend's 409 duplicate response.
struct AccountDuplicateInfo: Codable, Equatable, Hashable, Identifiable {
    let id: String
    let name: String
}

/// Decodes the `POST /crm/accounts` 409 duplicate payload:
/// `{ success:false, error, code:"DUPLICATE_ACCOUNT", existing:{ id, name } }`.
/// Returns the existing account only when the code matches and an id is present, so a shape change
/// (or any other 4xx) can never be mistaken for a duplicate.
enum AccountDuplicate {
    static let code = "DUPLICATE_ACCOUNT"

    private struct Wire: Codable {
        let code: String?
        let existing: Existing?
        struct Existing: Codable {
            let id: String?
            let name: String?
        }
    }

    /// Parse the raw 409 body.
    static func parse(_ data: Data) -> AccountDuplicateInfo? {
        guard let wire = try? JSONDecoder().decode(Wire.self, from: data) else { return nil }
        return info(code: wire.code, id: wire.existing?.id, name: wire.existing?.name)
    }

    /// Pure gate (testable without JSON): a duplicate only when the code matches and a non-empty id is present.
    static func info(code: String?, id: String?, name: String?) -> AccountDuplicateInfo? {
        guard code == Self.code else { return nil }
        let trimmedId = (id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else { return nil }
        return AccountDuplicateInfo(id: trimmedId, name: (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// The inline message shown on the create form, falling back to the typed name when the server sent none.
    static func message(for info: AccountDuplicateInfo, fallbackName: String) -> String {
        let name = info.name.isEmpty ? fallbackName.trimmingCharacters(in: .whitespacesAndNewlines) : info.name
        return "An account named \"\(name)\" already exists."
    }
}

// MARK: - Account value stats + product rollup (from the account's deals)

struct AccountValueStats: Equatable {
    /// Every deal / quote under the account.
    let total: Double
    /// Open deals' pipeline value.
    let openPipeline: Double
    /// Realised value of won deals.
    let won: Double
}

struct AccountProductRow: Equatable, Identifiable {
    let name: String
    let value: Double
    var id: String { name }
}

enum AccountDealRollup {
    /// A deal's headline value: the quoted amount where one exists (connected-B2B rollup), else the plain amount.
    static func dealValue(_ d: Deal) -> Double { d.quotedAmount ?? d.amount ?? 0 }

    /// A won deal's realised value: what was ordered where that is filled, else the deal amount, else the quote.
    static func wonValue(_ d: Deal) -> Double { d.orderAmount ?? d.amount ?? d.quotedAmount ?? 0 }

    /// Total = every deal / quote; Open pipeline = open deals; Won = realised value of won deals.
    static func valueStats(_ deals: [Deal]) -> AccountValueStats {
        let total = deals.reduce(0.0) { $0 + dealValue($1) }
        let open = deals.filter { $0.status == "open" }.reduce(0.0) { $0 + dealValue($1) }
        let won = deals.filter { $0.status == "won" }.reduce(0.0) { $0 + wonValue($1) }
        return AccountValueStats(total: total, openPipeline: open, won: won)
    }

    /// Roll the account's deals up to one row per product with a summed value. Reads each deal's own basket
    /// (`custom_fields.product_lines`, the same source the deal detail uses) and the conversion-stamped
    /// `line_items` shape, resolving a product id to a catalogue name via `nameForProductId`. A deal with no
    /// product lines contributes nothing, so an account whose deals carry none rolls up to an empty list.
    static func products(_ deals: [Deal], nameForProductId: (String) -> String? = { _ in nil }) -> [AccountProductRow] {
        var totals: [String: Double] = [:]
        var order: [String] = []
        for d in deals {
            let cf = d.customFields?.compactMapValues { $0.raw?.any } ?? [:]
            let rows = (cf["product_lines"] as? [[String: Any]]) ?? (cf["line_items"] as? [[String: Any]]) ?? []
            for row in rows {
                guard let name = productName(row, nameForProductId: nameForProductId) else { continue }
                if totals[name] == nil { order.append(name) }
                totals[name, default: 0] += lineValue(row)
            }
        }
        return order
            .map { AccountProductRow(name: $0, value: paise(totals[$0] ?? 0)) }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.name < $1.name }
    }

    /// The row's product name: the stamped `product_name`, else the catalogue name for its id, else the raw id.
    private static func productName(_ row: [String: Any], nameForProductId: (String) -> String?) -> String? {
        if let n = trimmed(row["product_name"]) { return n }
        for idKey in ["product_id", "product_interested"] {
            if let pid = trimmed(row[idKey]) {
                if let resolved = nameForProductId(pid)?.trimmingCharacters(in: .whitespacesAndNewlines), !resolved.isEmpty {
                    return resolved
                }
                return pid
            }
        }
        return nil
    }

    /// The row's value: the ordered amount where present, else the estimated / quoted line amount.
    private static func lineValue(_ row: [String: Any]) -> Double {
        for key in ["order_value", "estimated_amount", "subtotal", "amount"] {
            if let v = number(row[key]) { return v }
        }
        return 0
    }

    /// Lenient numeric read: a value may arrive as a number or a string.
    static func number(_ any: Any?) -> Double? {
        switch any {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let s as String: return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    private static func trimmed(_ any: Any?) -> String? {
        guard let s = (any as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    private static func paise(_ v: Double) -> Double { (v * 100).rounded() / 100 }
}

// MARK: - Account-detail Leads card

enum AccountLeadDisplay {
    /// A linked lead's headline: first + last, else company, else email, else "Lead".
    static func name(_ l: Lead) -> String {
        let full = "\(l.firstName ?? "") \(l.lastName ?? "")".trimmingCharacters(in: .whitespaces)
        if !full.isEmpty { return full }
        if let c = l.company?.trimmingCharacters(in: .whitespaces), !c.isEmpty { return c }
        if let e = l.email?.trimmingCharacters(in: .whitespaces), !e.isEmpty { return e }
        return "Lead"
    }

    /// The row's secondary line: the company, else the status, else a dash.
    static func subtitle(_ l: Lead) -> String {
        if let c = l.company?.trimmingCharacters(in: .whitespaces), !c.isEmpty { return c }
        if let s = l.status?.trimmingCharacters(in: .whitespaces), !s.isEmpty { return s }
        return "—"
    }
}

enum AccountLeadValue {
    /// The custom-field keys a tenant may store a lead's value under (leads have no value column). Mirrors web.
    static let keys = ["deal_value", "value", "amount", "estimated_value", "budget"]

    /// A monetary value for a lead when one is stored on custom_fields. Never fabricated — nil when no
    /// recognisable, positive amount is present.
    static func value(_ l: Lead) -> Double? {
        guard let cf = l.customFields else { return nil }
        for key in keys {
            guard let box = cf[key] else { continue }
            let n: Double?
            switch box.raw {
            case .some(.number(let v)): n = v
            case .some(.string(let s)): n = Double(s.trimmingCharacters(in: .whitespaces))
            default: n = Double(box.value ?? "")
            }
            if let n, n.isFinite, n > 0 { return n }
        }
        return nil
    }
}

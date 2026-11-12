//
//  DealLineDetails.swift
//  Kinematic
//
//  Connected-B2B (Spark & Ray) deal lines: make, brand, product reference, quoted value, ORDER value and
//  the MAC funnel reference. Everything here is pure (no UI, no network) so it can be unit tested:
//  lenient decoding helpers, the make / brand option model, the MAC rule, the request-body builders,
//  the totals / header texts, the read-only detail rows and the "confirm the ordered value" step of the
//  Won flow.
//
//  Model: Account -> Lead -> several Deals -> product lines on each deal. Brand is NOT make (the
//  manufacturer); MAC, PHD, BEKO, PIAB... are brands.
//

import Foundation

// MARK: - Lenient decoding

/// Helpers for decoding a value that may arrive as a number or a numeric string (Postgres `numeric`
/// columns often travel as strings) without failing the whole row.
enum LenientDecode {
    static func string<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> String? {
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? c.decodeIfPresent(Int.self, forKey: key) { return String(i) }
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return String(d) }
        return nil
    }

    static func double<K: CodingKey>(_ c: KeyedDecodingContainer<K>, _ key: K) -> Double? {
        if let d = try? c.decodeIfPresent(Double.self, forKey: key) { return d.isFinite ? d : nil }
        if let s = try? c.decodeIfPresent(String.self, forKey: key) { return SparkJourney.parseNumber(s) }
        return nil
    }
}

/// A number that may be missing, a JSON number or a numeric string; anything else decodes to nil.
struct LenientDouble: Codable, Hashable {
    let value: Double?

    init(_ value: Double?) { self.value = value }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            value = nil
        } else if let d = try? c.decode(Double.self) {
            value = d.isFinite ? d : nil
        } else if let s = try? c.decode(String.self) {
            value = SparkJourney.parseNumber(s)
        } else {
            value = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(value)
    }
}

/// A list of strings that may be missing, an array (non-string elements are skipped) or one
/// comma-separated string; anything else decodes to an empty list.
struct LenientStringList: Codable, Hashable {
    let values: [String]

    init(_ values: [String]) { self.values = values }

    private struct Element: Decodable {
        let text: String?
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            text = try? c.decode(String.self)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            values = []
        } else if let elements = try? c.decode([Element].self) {
            values = elements.compactMap { $0.text }
        } else if let s = try? c.decode(String.self) {
            values = s.split(separator: ",").map { String($0) }
        } else {
            values = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(values)
    }
}

// MARK: - Make / brand options

/// A row of `GET /crm/makes?is_active=true` or `GET /crm/brands?is_active=true`.
struct LineOption: Codable, Identifiable, Hashable {
    let id: String
    let name: String

    enum CodingKeys: String, CodingKey { case id, name }

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = LenientDecode.string(c, .id) ?? ""
        name = LenientDecode.string(c, .name) ?? ""
    }
}

/// The manufacturer of a product.
typealias ProductMake = LineOption
/// MAC, PHD, BEKO, PIAB... (not the same thing as the make).
typealias ProductBrand = LineOption

// MARK: - Rules

enum DealLineRules {
    /// Server wording; the inline message uses the same text.
    static let macFunnelRequiredMessage = "MAC funnel reference is required for MAC products"

    /// True when the brand is MAC (trimmed, case-insensitive).
    static func isMacBrand(_ brandName: String?) -> Bool {
        guard let brandName else { return false }
        return brandName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "mac"
    }

    /// The funnel reference to send: trimmed, or nil when blank.
    static func cleanFunnelRef(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// The MAC rule: a MAC product needs a funnel reference; every other brand may leave it blank.
    static func funnelProblem(brandName: String?, funnelRef: String?) -> String? {
        if isMacBrand(brandName) && cleanFunnelRef(funnelRef) == nil { return macFunnelRequiredMessage }
        return nil
    }

    /// An ordered value is optional; when typed it must be a number >= 0.
    static func orderValue(from text: String) -> Double? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return nil }
        guard let v = SparkJourney.parseNumber(t), v >= 0 else { return nil }
        return v
    }

    /// False when the text is non-blank but not a number >= 0.
    static func orderValueTextIsValid(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return true }
        return orderValue(from: t) != nil
    }

    static let invalidOrderValueMessage = "Order value must be 0 or more."
}

// MARK: - Request bodies

/// PATCH body for `/crm/line-items/:id`.
enum DealLineBody {
    private static func normalised(_ id: String?) -> String? {
        guard let id else { return nil }
        let t = id.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// The value, or an explicit JSON null when it is nil (a cleared field).
    private static func jsonValue(_ value: Any?) -> Any {
        if let value { return value }
        return NSNull()
    }

    /// Only what changed against `original`: a new value is sent as is, a cleared one as an explicit
    /// null. An order value that is not a valid number counts as unchanged (the form blocks saving it).
    static func patch(
        original: DealLineItem,
        makeId: String?,
        brandId: String?,
        funnelRef: String,
        orderValueText: String
    ) -> [String: Any] {
        var body: [String: Any] = [:]

        let newMake = normalised(makeId)
        if newMake != normalised(original.makeId) {
            body["make_id"] = jsonValue(newMake)
        }
        let newBrand = normalised(brandId)
        if newBrand != normalised(original.brandId) {
            body["brand_id"] = jsonValue(newBrand)
        }
        let newRef = DealLineRules.cleanFunnelRef(funnelRef)
        if newRef != DealLineRules.cleanFunnelRef(original.funnelRef) {
            body["funnel_ref"] = jsonValue(newRef)
        }
        if DealLineRules.orderValueTextIsValid(orderValueText) {
            let newOrder = DealLineRules.orderValue(from: orderValueText)
            if newOrder != original.orderValue {
                body["order_value"] = jsonValue(newOrder)
            }
        }
        return body
    }
}

// MARK: - Totals and header texts

enum DealLineTotals {
    /// Sum of the quoted values, to 2 dp.
    static func quoted(_ values: [Double]) -> Double {
        SparkJourney.round2(values.reduce(0) { $0 + $1 })
    }

    /// Sum of the order values that are set; nil when no line has one.
    static func ordered(_ values: [Double?]) -> Double? {
        let set = values.compactMap { $0 }
        if set.isEmpty { return nil }
        return SparkJourney.round2(set.reduce(0) { $0 + $1 })
    }

    static func quotedText(_ value: Double) -> String {
        "Quoted \(CurrencyFormatter.formatINR(value))"
    }

    /// "Ordered ₹Y", or nil when there is no order value.
    static func orderedText(_ value: Double?) -> String? {
        guard let value else { return nil }
        return "Ordered \(CurrencyFormatter.formatINR(value))"
    }

    /// "Quoted ₹X" or "Quoted ₹X · Ordered ₹Y".
    static func summary(quoted: Double, ordered: Double?) -> String {
        if let o = orderedText(ordered) { return "\(quotedText(quoted)) · \(o)" }
        return quotedText(quoted)
    }
}

// MARK: - Detail rows

/// One "label: value" cell of a line on the deal detail.
struct LineDetailRow: Equatable {
    let label: String
    let value: String
}

extension DealLineItem {
    /// Quoted value: the server's line total, else quantity x unit price (with discount / tax when given).
    var quotedValue: Double {
        if let lineTotal { return lineTotal }
        let discount = discountPct ?? 0
        let tax = taxPct ?? 0
        return quantity * unitPrice * (1 - discount / 100) * (1 + tax / 100)
    }

    private static func clean(_ s: String?) -> String? {
        guard let s else { return nil }
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    /// The product reference: `reference`, else the sku.
    var displayReference: String? { Self.clean(reference) ?? Self.clean(sku) }

    /// Reference, Make, Brand and Funnel ref in that order; blank values are left out.
    var detailRows: [LineDetailRow] {
        var rows: [LineDetailRow] = []
        if let v = displayReference { rows.append(LineDetailRow(label: "Reference", value: v)) }
        if let v = Self.clean(makeName) { rows.append(LineDetailRow(label: "Make", value: v)) }
        if let v = Self.clean(brandName) { rows.append(LineDetailRow(label: "Brand", value: v)) }
        if let v = Self.clean(funnelRef) { rows.append(LineDetailRow(label: "Funnel ref", value: v)) }
        return rows
    }
}

enum DealLineItems {
    static func quotedTotal(_ items: [DealLineItem]) -> Double {
        DealLineTotals.quoted(items.map { $0.quotedValue })
    }

    static func orderedTotal(_ items: [DealLineItem]) -> Double? {
        DealLineTotals.ordered(items.map { $0.orderValue })
    }
}

// MARK: - Won flow: confirm the ordered value

/// A queued PATCH for one line.
struct LineOrderPatch {
    let lineId: String
    let body: [String: Any]
}

enum DealLineOrderConfirm {
    /// Lines that still lack an order value.
    static func pending(_ items: [DealLineItem]) -> [DealLineItem] {
        items.filter { $0.orderValue == nil }
    }

    /// Initial field text per pending line id: the quoted value.
    static func prefill(_ items: [DealLineItem]) -> [String: String] {
        var out: [String: String] = [:]
        for item in pending(items) {
            out[item.id] = SparkJourney.priceText(SparkJourney.round2(item.quotedValue))
        }
        return out
    }

    /// The first typed value that is not a number >= 0 (blank is fine: that line is left unconfirmed).
    static func problem(items: [DealLineItem], texts: [String: String]) -> String? {
        for item in pending(items) {
            let text = texts[item.id] ?? ""
            if !DealLineRules.orderValueTextIsValid(text) {
                let name = item.productName.isEmpty ? "A line" : item.productName
                return "\(name): \(DealLineRules.invalidOrderValueMessage)"
            }
        }
        return nil
    }

    /// One PATCH per pending line that has a usable value; blank fields send nothing.
    static func patches(items: [DealLineItem], texts: [String: String]) -> [LineOrderPatch] {
        var out: [LineOrderPatch] = []
        for item in pending(items) {
            guard let v = DealLineRules.orderValue(from: texts[item.id] ?? "") else { continue }
            out.append(LineOrderPatch(lineId: item.id, body: ["order_value": v]))
        }
        return out
    }
}

// MARK: - Lead detail: the deals card

enum LeadDealsSummary {
    static let emptyText = "No deals yet. Add one for each requirement."

    /// A deal's quoted amount: the server's `quoted_amount`, else the deal amount.
    static func quoted(_ deal: Deal) -> Double { deal.quotedAmount ?? deal.amount ?? 0 }

    static func quotedTotal(_ deals: [Deal]) -> Double {
        SparkJourney.round2(deals.reduce(0) { $0 + quoted($1) })
    }

    /// Sum of the deals' order amounts; nil when no deal has one.
    static func orderedTotal(_ deals: [Deal]) -> Double? {
        DealLineTotals.ordered(deals.map { $0.orderAmount })
    }

    /// "N deals · ₹quoted quoted · ₹ordered ordered" (the ordered part only when some deal has an
    /// order amount); nil when there are no deals.
    static func headerText(_ deals: [Deal]) -> String? {
        if deals.isEmpty { return nil }
        let count = deals.count == 1 ? "1 deal" : "\(deals.count) deals"
        var text = "\(count) · \(CurrencyFormatter.formatINR(quotedTotal(deals))) quoted"
        if let ordered = orderedTotal(deals) {
            text += " · \(CurrencyFormatter.formatINR(ordered)) ordered"
        }
        return text
    }

    /// The deal's brands for chips: trimmed, no blanks, no repeats (case-insensitive), order kept.
    static func brandChips(_ deal: Deal) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in deal.brands ?? [] {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            if seen.insert(t.lowercased()).inserted { out.append(t) }
        }
        return out
    }
}

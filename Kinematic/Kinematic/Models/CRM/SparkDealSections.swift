import Foundation

// Spark & Ray deal sections: the pure logic (no UI, no network) behind
//   - the deal's Quotation / Pricing / Product trial / Approvals sections, and the admin's
//     `config.deal_sections` (enabled / label / position) from /crm/settings,
//   - the request bodies the create / edit forms send for them.
//
// Everything built on this is shown / sent ONLY for the Spark & Ray client (`SparkJourney.isActive`);
// other tenants never see these controls and never send these keys.

// MARK: - Section config

/// The four deal sections an admin can manage, in their default order.
enum DealSectionKey: String, CaseIterable, Hashable {
    case quotation
    case pricing
    case productTrial = "product_trial"
    case approvals

    var defaultLabel: String {
        switch self {
        case .quotation: return "Quotation"
        case .pricing: return "Pricing"
        case .productTrial: return "Product trial"
        case .approvals: return "Approvals"
        }
    }

    /// Position in the default order (quotation, pricing, product trial, approvals).
    var defaultIndex: Int {
        DealSectionKey.allCases.firstIndex(of: self) ?? 0
    }
}

/// `config.deal_sections` from `GET /crm/settings`:
/// `{ quotation|pricing|product_trial|approvals: { enabled?, label?, position? } }`.
/// A missing key (or no config at all) means enabled, default label, default order.
struct DealSectionsConfig: Equatable {
    struct Entry: Equatable {
        var enabled: Bool?
        var label: String?
        var position: Int?
    }

    var entries: [DealSectionKey: Entry] = [:]

    /// Backend cap on a section label.
    static let maxLabelLength = 60

    /// Parse the `config` object of the settings reply (nil / no `deal_sections` / wrong shape = defaults).
    static func parse(_ cfg: [String: AnyJSON]?) -> DealSectionsConfig {
        guard let cfg, case let .object(sections)? = cfg["deal_sections"] else { return DealSectionsConfig() }
        var out = DealSectionsConfig()
        for key in DealSectionKey.allCases {
            guard case let .object(props)? = sections[key.rawValue] else { continue }
            var entry = Entry()
            if case let .bool(b)? = props["enabled"] { entry.enabled = b }
            if case let .string(s)? = props["label"] {
                let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty { entry.label = String(t.prefix(maxLabelLength)) }
            }
            if case let .number(n)? = props["position"], n.isFinite, abs(n) < 1_000_000 {
                entry.position = Int(n)
            }
            out.entries[key] = entry
        }
        return out
    }

    /// Parse the whole settings reply.
    static func parse(settings: CRMService.CRMSettingsRaw?) -> DealSectionsConfig {
        guard case let .object(cfg)? = settings?.config else { return DealSectionsConfig() }
        return parse(cfg)
    }

    func isEnabled(_ key: DealSectionKey) -> Bool {
        entries[key]?.enabled != false
    }

    func label(_ key: DealSectionKey) -> String {
        entries[key]?.label ?? key.defaultLabel
    }

    /// The enabled sections in display order: by `position` (a section without one sits at its default
    /// index), ties broken by the default order.
    var ordered: [DealSectionKey] {
        DealSectionKey.allCases
            .filter { isEnabled($0) }
            .sorted { a, b in
                let pa = entries[a]?.position ?? a.defaultIndex
                let pb = entries[b]?.position ?? b.defaultIndex
                if pa != pb { return pa < pb }
                return a.defaultIndex < b.defaultIndex
            }
    }
}

// MARK: - Pricing

enum SparkPricing {
    static let discountMessage = "Discount must be between 0 and 100."
    static let quotedMessage = "Quoted price must be a number of 0 or more."

    /// quoted x (1 - discount / 100), to 2 dp.
    static func finalPrice(quoted: Double, discountPct: Double) -> Double {
        SparkJourney.round2(quoted * (1 - discountPct / 100))
    }

    /// The live final price for what is typed: nil while the quoted price is blank or unusable, or the
    /// discount is typed but not within 0...100. A blank discount means 0.
    static func finalPrice(quotedText: String, discountText: String) -> Double? {
        guard validate(quotedText: quotedText, discountText: discountText) == nil,
              let quoted = SparkJourney.parseNumber(quotedText) else { return nil }
        let discount = SparkJourney.parseNumber(discountText) ?? 0
        return finalPrice(quoted: quoted, discountPct: discount)
    }

    /// An error for a typed quoted price that is not a number >= 0 or a discount outside 0...100; blank is fine.
    static func validate(quotedText: String, discountText: String) -> String? {
        let q = quotedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            guard let v = SparkJourney.parseNumber(q), v >= 0 else { return quotedMessage }
        }
        let d = discountText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !d.isEmpty {
            guard let v = SparkJourney.parseNumber(d), v >= 0, v <= 100 else { return discountMessage }
        }
        return nil
    }
}

// MARK: - Dates (YYYY-MM-DD, the wire format of `date` columns)

enum SparkDealDate {
    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone.current
        return c
    }

    /// "2026-11-05" (a longer timestamp is cut to its date part) -> that day at noon, local time. Nil when
    /// it is not a real date.
    static func parse(_ raw: String) -> Date? {
        let s = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(10))
        let parts = s.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { return nil }
        var comps = DateComponents()
        comps.year = y; comps.month = m; comps.day = d; comps.hour = 12
        guard let date = calendar.date(from: comps) else { return nil }
        // Reject overflow ("2026-02-31" would roll into March).
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        guard back.year == y, back.month == m, back.day == d else { return nil }
        return date
    }

    /// A day as "YYYY-MM-DD" (local calendar day).
    static func format(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(pad(c.year ?? 1970, 4))-\(pad(c.month ?? 1, 2))-\(pad(c.day ?? 1, 2))"
    }

    private static func pad(_ n: Int, _ width: Int) -> String {
        let s = String(n)
        return s.count >= width ? s : String(repeating: "0", count: width - s.count) + s
    }

    /// The date part of a stored value ("" when blank).
    static func normalized(_ raw: String?) -> String {
        guard let raw else { return "" }
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "" : String(t.prefix(10))
    }
}

// MARK: - Product trial

enum SparkTrialResult: String, CaseIterable, Hashable {
    case pending, successful, failed

    var label: String {
        switch self {
        case .pending: return "Pending"
        case .successful: return "Successful"
        case .failed: return "Failed"
        }
    }
}

enum SparkTrial {
    static let orderMessage = "Trial end date can't be before the start date."

    /// An error when both dates are set and the end is before the start. Blank dates are fine.
    static func validate(start: String, end: String) -> String? {
        guard let s = SparkDealDate.parse(start), let e = SparkDealDate.parse(end) else { return nil }
        let cal = Calendar(identifier: .gregorian)
        return cal.startOfDay(for: e) < cal.startOfDay(for: s) ? orderMessage : nil
    }
}

// MARK: - Draft (what the forms edit)

/// The Spark deal-section values a create / edit form is editing, as strings the controls bind to.
struct SparkDealSectionsDraft: Equatable {
    var quotationNo = ""
    // Pricing
    var quotedText = ""
    var discountText = ""
    var validTill = ""
    // Product trial (`trialRequired` nil = not answered yet)
    var trialRequired: Bool? = nil
    var trialStart = ""
    var trialEnd = ""
    /// "", or a `SparkTrialResult` raw value.
    var trialResult = ""
    var trialNotes = ""
    // People (user ids; "" = nobody)
    var technicalApprovalBy = ""
    var preparedBy = ""
    var checkedBy = ""
    var supervisorId = ""

    init() {}

    /// Seed from a stored deal (the edit form).
    init(deal: Deal) {
        quotationNo = deal.quotationNo ?? ""
        quotedText = deal.pricingQuoted.map { SparkJourney.priceText($0) } ?? ""
        discountText = deal.pricingDiscountPct.map { SparkJourney.priceText($0) } ?? ""
        validTill = SparkDealDate.normalized(deal.pricingValidTill)
        trialRequired = deal.trialRequired
        trialStart = SparkDealDate.normalized(deal.trialStart)
        trialEnd = SparkDealDate.normalized(deal.trialEnd)
        trialResult = (deal.trialResult ?? "").lowercased()
        trialNotes = deal.trialNotes ?? ""
        technicalApprovalBy = deal.technicalApprovalBy ?? ""
        preparedBy = deal.preparedBy ?? ""
        checkedBy = deal.checkedBy ?? ""
        supervisorId = deal.supervisorId ?? ""
    }

    /// id -> name for the people already on a deal (from the `*_name` fields the backend stamps), to label
    /// a picker whose user list does not contain them.
    static func knownNames(deal: Deal) -> [String: String] {
        var out: [String: String] = [:]
        let pairs: [(String?, String?)] = [
            (deal.technicalApprovalBy, deal.technicalApprovalByName),
            (deal.preparedBy, deal.preparedByName),
            (deal.checkedBy, deal.checkedByName),
            (deal.supervisorId, deal.supervisorIdName),
        ]
        for (id, name) in pairs {
            guard let id, !id.isEmpty, let name, !name.isEmpty else { continue }
            out[id] = name
        }
        return out
    }

    // MARK: Field keys (the override keys, `deal.<key>`, and the request keys)

    static let quotationKey = "quotation_no"
    static let pricingKeys = ["pricing_quoted", "pricing_discount_pct", "pricing_final", "pricing_valid_till"]
    static let trialKeys = ["trial_required", "trial_start", "trial_end", "trial_result", "trial_notes"]
    static let peopleKeys = ["technical_approval_by", "prepared_by", "checked_by", "supervisor_id"]

    /// Every built-in deal key these sections own.
    static var allKeys: [String] { [quotationKey] + pricingKeys + trialKeys + peopleKeys }

    /// The keys the admin hid (`isHidden` answers per key), so they are neither shown nor sent.
    static func hiddenKeys(_ isHidden: (String) -> Bool) -> Set<String> {
        Set(allKeys.filter { isHidden($0) })
    }

    // MARK: Derived values

    /// The live final price (nil while the quoted price is blank / invalid).
    var finalPrice: Double? {
        SparkPricing.finalPrice(quotedText: quotedText, discountText: discountText)
    }

    /// The trial result as sent: "pending" when the trial is on but no result was picked.
    var effectiveTrialResult: String {
        trialResult.isEmpty ? SparkTrialResult.pending.rawValue : trialResult
    }

    /// The first problem that should block Save, or nil. Only enabled, visible sections are checked.
    func validationError(config: DealSectionsConfig, hidden: Set<String> = []) -> String? {
        if config.isEnabled(.pricing),
           !hidden.contains("pricing_quoted") || !hidden.contains("pricing_discount_pct") {
            if let e = SparkPricing.validate(quotedText: quotedText, discountText: discountText) { return e }
        }
        if config.isEnabled(.productTrial), trialRequired == true,
           !hidden.contains("trial_start"), !hidden.contains("trial_end") {
            if let e = SparkTrial.validate(start: trialStart, end: trialEnd) { return e }
        }
        return nil
    }

    // MARK: Request body

    private static func put<T>(_ body: inout [String: Any], _ key: String, new: T?, old: T?, create: Bool) where T: Equatable {
        if create {
            if let new { body[key] = new }
            return
        }
        if new == old { return }
        if let new { body[key] = new } else { body[key] = NSNull() }
    }

    private static func text(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static func number(_ raw: String) -> Double? {
        SparkJourney.parseNumber(raw).map { SparkJourney.round2($0) }
    }

    /// Merge the enabled, visible sections into a deal POST / PATCH body.
    ///
    /// Create (`previous == nil`): the non-blank values only. Edit: only what differs from `previous`
    /// (a cleared value goes as null), so an untouched edit sends nothing. A disabled section, a key the
    /// admin hid and (with `includeQuotation == false`) the quotation number are never sent. While the
    /// trial is not "needed" its dates / result / notes are left alone. The final price is sent whenever
    /// the quoted price or discount changes, computed here the same way the server does.
    func apply(
        to body: inout [String: Any],
        config: DealSectionsConfig,
        hidden: Set<String> = [],
        previous: SparkDealSectionsDraft? = nil,
        includeQuotation: Bool = true
    ) {
        let create = previous == nil
        let old = previous ?? SparkDealSectionsDraft()
        func visible(_ key: String) -> Bool { !hidden.contains(key) }

        if includeQuotation, config.isEnabled(.quotation), visible(Self.quotationKey) {
            Self.put(&body, Self.quotationKey, new: Self.text(quotationNo), old: Self.text(old.quotationNo), create: create)
        }

        if config.isEnabled(.pricing) {
            if visible("pricing_quoted") {
                Self.put(&body, "pricing_quoted", new: Self.number(quotedText), old: Self.number(old.quotedText), create: create)
            }
            if visible("pricing_discount_pct") {
                Self.put(&body, "pricing_discount_pct", new: Self.number(discountText), old: Self.number(old.discountText), create: create)
            }
            if visible("pricing_final") {
                Self.put(&body, "pricing_final", new: finalPrice, old: old.finalPrice, create: create)
            }
            if visible("pricing_valid_till") {
                Self.put(&body, "pricing_valid_till", new: Self.text(validTill), old: Self.text(old.validTill), create: create)
            }
        }

        if config.isEnabled(.productTrial) {
            if visible("trial_required"), let required = trialRequired {
                Self.put(&body, "trial_required", new: required, old: old.trialRequired, create: create)
            }
            if trialRequired == true {
                if visible("trial_start") {
                    Self.put(&body, "trial_start", new: Self.text(trialStart), old: Self.text(old.trialStart), create: create)
                }
                if visible("trial_end") {
                    Self.put(&body, "trial_end", new: Self.text(trialEnd), old: Self.text(old.trialEnd), create: create)
                }
                if visible("trial_result") {
                    // The previous draft's result only counts when its trial was on too.
                    let oldResult: String? = old.trialRequired == true ? old.effectiveTrialResult : nil
                    Self.put(&body, "trial_result", new: effectiveTrialResult, old: oldResult, create: create)
                }
                if visible("trial_notes") {
                    Self.put(&body, "trial_notes", new: Self.text(trialNotes), old: Self.text(old.trialNotes), create: create)
                }
            }
        }

        if config.isEnabled(.approvals) {
            if visible("technical_approval_by") {
                Self.put(&body, "technical_approval_by", new: Self.text(technicalApprovalBy), old: Self.text(old.technicalApprovalBy), create: create)
            }
            if visible("prepared_by") {
                Self.put(&body, "prepared_by", new: Self.text(preparedBy), old: Self.text(old.preparedBy), create: create)
            }
            if visible("checked_by") {
                Self.put(&body, "checked_by", new: Self.text(checkedBy), old: Self.text(old.checkedBy), create: create)
            }
            if visible("supervisor_id") {
                Self.put(&body, "supervisor_id", new: Self.text(supervisorId), old: Self.text(old.supervisorId), create: create)
            }
        }
    }
}

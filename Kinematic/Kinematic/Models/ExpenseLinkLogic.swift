// ExpenseLinkLogic — the pure rules behind linking an expense claim to a CRM lead and deal (connected-B2B,
// Spark & Ray) and behind the "Expenses" card on a lead / deal. No UI, no networking: the editor, the detail
// screens and the tests all go through these functions.
//
// Contract with the backend: a claim body may carry `lead_id` / `deal_id` (string, or an explicit null to clear).
// The server derives the rest — a deal fills its lead, a lead fills its account — and answers 400 "That deal
// belongs to another lead" on a mismatch, so the editor keeps the two pickers consistent before it sends.

import Foundation

/// The ids of a claim's CRM links, with blanks normalised away.
struct ExpenseLinkSelection: Equatable {
    var leadId: String?
    var dealId: String?

    init(leadId: String? = nil, dealId: String? = nil) {
        self.leadId = ExpenseLinkLogic.clean(leadId)
        self.dealId = ExpenseLinkLogic.clean(dealId)
    }
}

/// What goes into a claim create / patch body for the two links.
struct ExpenseLinkBodyFields: Equatable {
    /// An id to send, or nil to omit the key.
    var leadId: String?
    var dealId: String?
    /// True: send an explicit `null` for the key (only when no id is sent).
    var clearLead: Bool
    var clearDeal: Bool

    static let untouched = ExpenseLinkBodyFields(leadId: nil, dealId: nil, clearLead: false, clearDeal: false)
}

/// The editor's lead + deal choice, with the names to show. Picking and clearing keep the two consistent:
/// picking a deal selects that deal's lead; picking a different lead drops a deal that belongs to another
/// lead; clearing the lead drops a deal that was tied to it.
struct ExpenseLinkState: Equatable {
    var leadId: String?
    var leadName: String?
    var dealId: String?
    var dealName: String?
    /// The lead the chosen deal belongs to, when that is known (nil: unknown, or the deal has no lead).
    var dealLeadId: String?

    init() {}

    /// Pre-fill from a claim being edited (nil for a new claim). The server fills a deal's lead, so a claim that
    /// has both links has a deal that belongs to that lead.
    init(claim: ExpenseClaim?) {
        leadId = ExpenseLinkLogic.clean(claim?.lead_id)
        leadName = ExpenseLinkLogic.clean(claim?.lead_name)
        dealId = ExpenseLinkLogic.clean(claim?.deal_id)
        dealName = ExpenseLinkLogic.clean(claim?.deal_name)
        dealLeadId = (dealId != nil) ? leadId : nil
    }

    var selection: ExpenseLinkSelection { ExpenseLinkSelection(leadId: leadId, dealId: dealId) }

    /// What the Lead row shows: the name, "Selected lead" when only the id is known, nil when nothing is picked.
    var leadDisplay: String? {
        guard leadId != nil else { return nil }
        return leadName ?? "Selected lead"
    }

    /// What the Deal row shows, the same way.
    var dealDisplay: String? {
        guard dealId != nil else { return nil }
        return dealName ?? "Selected deal"
    }

    mutating func pickLead(id: String, name: String?) {
        guard let id = ExpenseLinkLogic.clean(id) else { return }
        if dealId != nil, let owner = dealLeadId, owner != id { dropDeal() }
        leadId = id
        leadName = ExpenseLinkLogic.clean(name)
    }

    mutating func clearLead() {
        if dealId != nil, let owner = dealLeadId, owner == leadId { dropDeal() }
        leadId = nil
        leadName = nil
    }

    /// `ownerLeadId` / `ownerLeadName` are the picked deal's own lead (a deal row carries them).
    mutating func pickDeal(id: String, name: String?, ownerLeadId: String?, ownerLeadName: String?) {
        guard let id = ExpenseLinkLogic.clean(id) else { return }
        dealId = id
        dealName = ExpenseLinkLogic.clean(name)
        dealLeadId = ExpenseLinkLogic.clean(ownerLeadId)
        if let owner = dealLeadId {
            if leadId != owner {
                leadId = owner
                leadName = ExpenseLinkLogic.clean(ownerLeadName)
            } else if leadName == nil {
                leadName = ExpenseLinkLogic.clean(ownerLeadName)
            }
        }
    }

    mutating func clearDeal() { dropDeal() }

    private mutating func dropDeal() {
        dealId = nil
        dealName = nil
        dealLeadId = nil
    }
}

enum ExpenseLinkLogic {
    /// Trimmed, or nil when blank.
    static func clean(_ s: String?) -> String? {
        let t = (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    // MARK: Body fields

    /// The lead / deal part of a claim body.
    /// - Not a connected-B2B client: nothing is sent.
    /// - A new claim: the ids that are picked (nothing to clear).
    /// - An edit: only what changed against `baseline` (what the claim already had) — an id for a new choice,
    ///   an explicit null when a link was removed, nothing for an untouched one.
    static func bodyFields(isSpark: Bool, isEditing: Bool, current: ExpenseLinkSelection,
                           baseline: ExpenseLinkSelection) -> ExpenseLinkBodyFields {
        guard isSpark else { return .untouched }
        guard isEditing else {
            return ExpenseLinkBodyFields(leadId: current.leadId, dealId: current.dealId, clearLead: false, clearDeal: false)
        }
        var out = ExpenseLinkBodyFields.untouched
        if current.leadId != baseline.leadId {
            if let id = current.leadId { out.leadId = id } else { out.clearLead = true }
        }
        if current.dealId != baseline.dealId {
            if let id = current.dealId { out.dealId = id } else { out.clearDeal = true }
        }
        return out
    }

    // MARK: Deal picker

    /// The deals the picker offers: those of `leadId` when a lead is chosen (all deals otherwise), then narrowed
    /// by a case-insensitive name search. The deals endpoint has no search, so this runs on the device.
    static func dealOptions(_ deals: [Deal], leadId: String?, query: String) -> [Deal] {
        var narrowed = deals
        if let lead = clean(leadId) { narrowed = deals.filter { clean($0.leadId) == lead } }
        return ActivityLinkEditing.filter(narrowed, query: query) { $0.name }
    }

    // MARK: Claim captions

    /// "Lead: Acme Plant · Deal: Boiler retrofit" for a claim row; nil when it has neither link.
    static func linkCaption(leadName: String?, dealName: String?) -> String? {
        var parts: [String] = []
        if let l = clean(leadName) { parts.append("Lead: \(l)") }
        if let d = clean(dealName) { parts.append("Deal: \(d)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - Lead / deal "Expenses" card text

/// The wording of the Expenses card on a lead or deal, from the server's roll-up.
enum ExpenseRollupText {
    private static func money(_ v: Double, _ rollup: ExpenseRollup) -> String {
        ExpenseLogic.money(v, clean(rollup.currency) ?? "INR")
    }

    private static func clean(_ s: String?) -> String? { ExpenseLinkLogic.clean(s) }

    /// Nothing linked yet: no claims, no visits.
    static func isEmpty(_ r: ExpenseRollup) -> Bool {
        r.totals.claim_count == 0 && r.claims.isEmpty && r.visit_count == 0
    }

    /// "30%" / "12.5%" — whole numbers without a decimal.
    static func percent(_ p: Double) -> String {
        let s = String(format: "%.1f", p)
        return (s.hasSuffix(".0") ? String(s.dropLast(2)) : s) + "%"
    }

    /// "₹3,000 spent · 30% of ₹10,000". No share when the record has no value to compare to; "₹0 spent" when
    /// nothing has been spent.
    static func headline(_ r: ExpenseRollup) -> String {
        let spent = r.totals.spent_amount
        var text = "\(money(spent, r)) spent"
        guard spent > 0, let pct = r.spent_pct_of_value, pct.isFinite,
              let value = r.opportunity_value, value > 0 else { return text }
        text += " · \(percent(pct)) of \(money(value, r))"
        return text
    }

    /// "2 claims · 3 visits" (singular for one).
    static func counts(_ r: ExpenseRollup) -> String {
        let claims = r.totals.claim_count
        let visits = r.visit_count
        return "\(claims) \(claims == 1 ? "claim" : "claims") · \(visits) \(visits == 1 ? "visit" : "visits")"
    }

    /// The non-zero Pending / Draft / Rejected amounts, in that order, e.g. "Pending ₹500 · Rejected ₹200".
    /// nil when all three are zero.
    static func breakdown(_ r: ExpenseRollup) -> String? {
        var parts: [String] = []
        if r.totals.pending_amount > 0 { parts.append("Pending \(money(r.totals.pending_amount, r))") }
        if r.totals.draft_amount > 0 { parts.append("Draft \(money(r.totals.draft_amount, r))") }
        if r.totals.rejected_amount > 0 { parts.append("Rejected \(money(r.totals.rejected_amount, r))") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// A claim row's title: its title, else its number, else "Expense claim".
    static func claimTitle(_ c: ExpenseRollupClaim) -> String {
        clean(c.title) ?? clean(c.claim_no) ?? "Expense claim"
    }

    /// A claim row's second line: "EXP-0007 · Approved · Meera Rao · 2026-10-01" (number only when the title is
    /// shown, parts that are missing are skipped).
    static func claimSubtitle(_ c: ExpenseRollupClaim) -> String {
        var parts: [String] = []
        if clean(c.title) != nil, let no = clean(c.claim_no) { parts.append(no) }
        parts.append((c.status ?? "draft").capitalized)
        if let who = clean(c.user_name) { parts.append(who) }
        if let d = clean(c.created_at) { parts.append(String(d.prefix(10))) }
        return parts.joined(separator: " · ")
    }

    /// A claim row's amount in the roll-up's currency (the claim's own when it names one).
    static func claimAmount(_ c: ExpenseRollupClaim, in r: ExpenseRollup) -> String {
        ExpenseLogic.money(c.total_amount ?? 0, clean(c.currency) ?? clean(r.currency) ?? "INR")
    }
}

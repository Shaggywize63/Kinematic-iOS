// ExpenseLogic — the rules behind the expense screens, kept free of SwiftUI so
// they can be unit-tested (see KinematicTests/ExpenseLogicTests). The screens
// only render what these decide.

import Foundation

// MARK: - Errors

enum ExpenseErrors {
    /// The message inside an API error body: `{ "error": "..." }` or `{ "error": { "message": "..." } }`.
    static func serverMessage(in data: Data) -> String? {
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        if let s = obj["error"] as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : s }
        if let e = obj["error"] as? [String: Any], let m = e["message"] as? String, !m.isEmpty { return m }
        if let m = obj["message"] as? String, !m.isEmpty { return m }
        return nil
    }

    /// What to show: the server's own words (written for the user), else a plain line per status.
    static func message(serverMessage: String?, status: Int) -> String {
        if let m = serverMessage?.trimmingCharacters(in: .whitespacesAndNewlines), !m.isEmpty { return m }
        switch status {
        case 401: return "Your session has expired — sign in again."
        case 403: return "You don't have permission to do that."
        case 404: return "That claim could not be found."
        case 413: return "That file is too large (10 MB maximum)."
        case 500...599: return "The server had a problem. Try again in a moment."
        default: return "Request failed (\(status))"
        }
    }
}

// MARK: - Claims

enum ExpenseLogic {
    static let categories = ExpenseCategory.allCases.map { $0.rawValue }

    static func categoryLabel(_ c: String) -> String { c == "misc" ? "Other" : c.capitalized }

    /// Claims the owner may still change: before approval, or being fixed after a rejection.
    static func isEditable(_ status: String?) -> Bool {
        ["draft", "submitted", "rejected"].contains((status ?? "draft").lowercased())
    }

    /// Part of the claim was approved but not all of it.
    static func isPartlyApproved(_ c: ExpenseClaim) -> Bool {
        let s = (c.status ?? "").lowercased()
        guard let approved = c.approved_amount else { return false }
        return (s == "approved" || s == "reimbursed") && approved < c.total_amount - 0.005
    }

    /// What the claimant will actually be paid (the approved amount once decided, otherwise the claimed total).
    static func payable(_ c: ExpenseClaim) -> Double {
        let s = (c.status ?? "").lowercased()
        if let a = c.approved_amount, s == "approved" || s == "reimbursed" { return a }
        return c.total_amount
    }

    /// Plain-language names for the policy checks the server reports.
    static func flagLabel(_ code: String) -> String {
        switch code {
        case "category_not_allowed":    return "Not reimbursable"
        case "receipt_missing":         return "Receipt needed"
        case "over_category_limit":     return "Over daily limit"
        case "over_claim_category_limit": return "Over claim limit"
        case "over_month_limit":        return "Over monthly limit"
        case "over_claim_limit":        return "Over claim maximum"
        case "late_submission":         return "Submitted late"
        case "future_date":             return "Future date"
        default:
            let s = code.replacingOccurrences(of: "_", with: " ")
            return s.prefix(1).uppercased() + s.dropFirst()
        }
    }

    /// Flags that belong to the line at `index` of a policy check (unsaved lines are identified by position).
    static func flags(forLine index: Int, in flags: [ExpenseFlag]?) -> [ExpenseFlag] {
        (flags ?? []).filter { $0.item_id == String(index) }
    }

    /// Flags that are about the claim as a whole rather than one line.
    static func claimLevelFlags(_ flags: [ExpenseFlag]?) -> [ExpenseFlag] {
        (flags ?? []).filter { ($0.item_id ?? "").isEmpty || Int($0.item_id ?? "") == nil }
    }

    /// Whether a manager should be offered a one-tap approval — not when the policy flagged something serious.
    static func canQuickApprove(_ c: ExpenseClaim) -> Bool {
        !(c.ai_flags ?? []).contains { $0.severity == "high" }
    }

    /// Mirrors the backend's approver roles; a field executive (data scope "own") never approves.
    /// An unknown role keeps the entry, since the API is the authority.
    static func canApprove(role: String?, dataScope: String?) -> Bool {
        guard let role = role?.trimmingCharacters(in: .whitespaces).lowercased(), !role.isEmpty else { return true }
        if (dataScope ?? "").lowercased() == "own" { return false }
        let approverRoles: Set<String> = ["super_admin", "admin", "main_admin", "org_admin", "sub_admin", "client",
                                          "city_manager", "supervisor", "manager", "hr", "program_manager"]
        return approverRoles.contains(role)
    }

    static func money(_ v: Double, _ currency: String) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_IN")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 2
        f.minimumFractionDigits = 0
        let n = f.string(from: NSNumber(value: v)) ?? String(v)
        return currency == "INR" ? "₹\(n)" : "\(currency) \(n)"
    }

    /// "120", "99.5" — no trailing zeros, for putting a number back into a text field.
    static func trimNumber(_ v: Double) -> String {
        if v == v.rounded() { return String(Int(v)) }
        var s = String(format: "%.2f", v)
        while s.hasSuffix("0") { s.removeLast() }
        if s.hasSuffix(".") { s.removeLast() }
        return s
    }
}

// MARK: - Editing a claim

/// The values of one line in the editor, as plain data.
struct ExpenseLineFields: Equatable {
    var id: String? = nil
    var category: String = "food"
    var itemDate: String = ""          // yyyy-MM-dd
    var amount: String = ""
    var description: String = ""
    var merchant: String = ""
    var fromLocation: String = ""
    var toLocation: String = ""
    var distanceKm: String = ""
    /// The reference to store on the line (empty when there is no receipt).
    var receiptUrl: String = ""
    /// The line already had a receipt when the editor opened.
    var hadReceipt: Bool = false
    /// What OCR read from a receipt attached in this session.
    var ocr: ExpenseReceiptFields? = nil

    private static func positive(_ s: String) -> Double? {
        guard let v = Double(s.trimmingCharacters(in: .whitespaces)), v > 0 else { return nil }
        return v
    }

    /// Anything typed or attached — an untouched blank line is simply dropped on save.
    var isFilled: Bool {
        !amount.isEmpty || !distanceKm.isEmpty || !merchant.isEmpty || !description.isEmpty ||
            !receiptUrl.isEmpty || !fromLocation.isEmpty || !toLocation.isEmpty
    }

    /// A filled line can be saved when it has an amount (or, for mileage, a distance).
    var isValid: Bool {
        if category == "mileage" { return Self.positive(amount) != nil || Self.positive(distanceKm) != nil }
        return Self.positive(amount) != nil
    }

    /// The line's amount for the on-screen total; mileage with only a distance is priced at the policy rate.
    func effectiveAmount(mileageRate: Double) -> Double {
        if let a = Self.positive(amount) { return a }
        if category == "mileage", let km = Self.positive(distanceKm) { return (km * mileageRate * 100).rounded() / 100 }
        return 0
    }

    func toInput() -> ExpenseClaimItemInput {
        let mileage = category == "mileage"
        func nonEmpty(_ s: String) -> String? { let t = s.trimmingCharacters(in: .whitespaces); return t.isEmpty ? nil : t }
        // A receipt that is attached is sent; one that was removed is cleared with "" (nil is omitted,
        // and an omitted receipt means "keep what is on file").
        let receipt: String? = !receiptUrl.isEmpty ? receiptUrl : (hadReceipt ? "" : nil)
        return ExpenseClaimItemInput(
            id: id,
            category: category,
            item_date: itemDate.isEmpty ? nil : itemDate,
            description: nonEmpty(description),
            amount: Self.positive(amount),
            distance_km: mileage ? Self.positive(distanceKm) : nil,
            from_location: mileage ? nonEmpty(fromLocation) : nil,
            to_location: mileage ? nonEmpty(toLocation) : nil,
            merchant: mileage ? nil : nonEmpty(merchant),
            receipt_url: receipt,
            ai_extracted: ocr
        )
    }

    /// Fill what the receipt scan found into a line, never overwriting what the person already typed.
    func withScan(_ scan: ExpenseReceiptFields?, receiptUrl url: String) -> ExpenseLineFields {
        var out = self
        let fresh = amount.isEmpty && merchant.isEmpty
        out.receiptUrl = url
        if let scan = scan { out.ocr = scan }
        if amount.isEmpty, let a = scan?.amount { out.amount = ExpenseLogic.trimNumber(a) }
        if merchant.isEmpty, let m = scan?.merchant, !m.isEmpty { out.merchant = m }
        if fresh, let d = scan?.txn_date, !d.isEmpty { out.itemDate = String(d.prefix(10)) }
        if fresh, category != "mileage", let c = scan?.category, ExpenseLogic.categories.contains(c) { out.category = c }
        return out
    }
}

extension ExpenseClaimItem {
    func toFields() -> ExpenseLineFields {
        var f = ExpenseLineFields()
        f.id = id
        f.category = category
        f.itemDate = item_date ?? ""
        f.amount = amount != 0 ? ExpenseLogic.trimNumber(amount) : ""
        f.description = description ?? ""
        f.merchant = merchant ?? ""
        f.fromLocation = from_location ?? ""
        f.toLocation = to_location ?? ""
        f.distanceKm = distance_km.map { ExpenseLogic.trimNumber($0) } ?? ""
        f.receiptUrl = receipt_url ?? ""
        f.hadReceipt = !(receipt_url ?? "").isEmpty
        return f
    }
}

// MARK: - Reviewing a claim

/// One line's decision while an approver reviews it.
struct ExpenseLineReview: Equatable {
    var id: String
    var approved: Bool = true
    var note: String = ""
}

enum ExpenseReview {
    /// Which rejected lines still lack the remark the server will insist on.
    static func linesMissingRemark(_ reviews: [ExpenseLineReview]) -> [String] {
        reviews.filter { !$0.approved && $0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.map { $0.id }
    }

    /// What would be paid if the approver approves with these line decisions.
    static func approvedTotal(items: [ExpenseClaimItem], reviews: [ExpenseLineReview]) -> Double {
        let rejected = Set(reviews.filter { !$0.approved }.map { $0.id })
        return items.filter { !rejected.contains($0.id) }.reduce(0) { $0 + $1.amount }
    }

    /// The per-line part of an approve request: every line's decision, with its remark if rejected.
    static func body(_ reviews: [ExpenseLineReview]) -> [ExpenseLineDecisionInput] {
        reviews.map {
            let note = $0.note.trimmingCharacters(in: .whitespacesAndNewlines)
            return ExpenseLineDecisionInput(id: $0.id, decision: $0.approved ? "approved" : "rejected",
                                            note: ($0.approved || note.isEmpty) ? nil : note)
        }
    }

    /// For rejecting the whole claim: only lines where the reviewer already wrote their own remark need to be sent.
    static func ownRemarks(_ reviews: [ExpenseLineReview]) -> [ExpenseLineDecisionInput] {
        reviews.compactMap {
            let note = $0.note.trimmingCharacters(in: .whitespacesAndNewlines)
            return (!$0.approved && !note.isEmpty) ? ExpenseLineDecisionInput(id: $0.id, decision: "rejected", note: note) : nil
        }
    }
}

// MARK: - History

enum ExpenseStepTone { case done, bad, waiting, info }

struct ExpenseTimelineStep: Equatable {
    var title: String
    var date: String? = nil
    var tone: ExpenseStepTone = .info
    /// The approver's remark on this decision.
    var remark: String? = nil
    /// Rejected lines in this decision, each with its own remark.
    var rejectedLines: [String] = []
}

/// The claim's story: created, each submission, each decision with its remark, reimbursement.
func expenseTimeline(_ c: ExpenseClaim) -> [ExpenseTimelineStep] {
    var out = [ExpenseTimelineStep(title: "Claim created", date: c.created_at.map { String($0.prefix(10)) })]
    let approvals = c.approvals ?? []
    var rounds: [Int] = []
    for a in approvals { let r = a.round ?? 1; if !rounds.contains(r) { rounds.append(r) } }
    let multi = rounds.count > 1 || (c.submit_count ?? 1) > 1
    var last = 0

    func lineText(_ d: ExpenseItemDecision) -> String {
        var s = "\(ExpenseLogic.categoryLabel(d.category ?? "misc")) · \(ExpenseLogic.money(d.amount ?? 0, c.currency))"
        if let n = d.note, !n.isEmpty { s += " — \(n)" }
        return s
    }

    for a in approvals {
        let r = a.round ?? 1
        if r != last {
            last = r
            let title = multi ? "Submitted\(r > 1 ? " again" : "") (attempt \(r))" : "Submitted for approval"
            out.append(ExpenseTimelineStep(title: title, date: r == rounds.last ? c.submitted_at.map { String($0.prefix(10)) } : nil))
        }
        let who = a.approver_name ?? "approver"
        let level = a.level > 1 ? " (level \(a.level))" : ""
        let rejected = (a.item_decisions ?? []).filter { $0.decision == "rejected" }
        let remark = (a.note ?? "").isEmpty ? nil : a.note
        let date = a.decided_at.map { String($0.prefix(10)) }
        switch a.status {
        case "pending":
            out.append(ExpenseTimelineStep(title: "Waiting for \(who)\(level)", tone: .waiting))
        case "approved":
            out.append(ExpenseTimelineStep(title: "\(rejected.isEmpty ? "Approved" : "Partly approved") by \(who)\(level)", date: date,
                                           tone: .done, remark: remark, rejectedLines: rejected.map(lineText)))
        default:
            out.append(ExpenseTimelineStep(title: "Rejected by \(who)\(level)", date: date, tone: .bad, remark: remark,
                                           rejectedLines: rejected.filter { !($0.note ?? "").isEmpty }.map(lineText)))
        }
    }
    if c.auto_approved == true {
        out.append(ExpenseTimelineStep(title: "Approved automatically under the policy", date: c.reviewed_at.map { String($0.prefix(10)) }, tone: .done))
    }
    if (c.status ?? "") == "cancelled" { out.append(ExpenseTimelineStep(title: "Cancelled")) }
    if let paid = c.reimbursed_at, !paid.isEmpty {
        let ref = (c.reimbursed_ref ?? "").isEmpty ? "" : " · ref \(c.reimbursed_ref ?? "")"
        out.append(ExpenseTimelineStep(title: "Reimbursed\(ref)", date: String(paid.prefix(10)), tone: .done))
    }
    return out
}

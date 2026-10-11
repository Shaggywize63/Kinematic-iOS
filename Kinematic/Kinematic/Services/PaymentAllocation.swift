// PaymentAllocation — how a collected payment is applied to the outlet's invoices, and the checks around the
// Collect Payment form, as pure functions so they are unit-tested (see KinematicTests/PaymentAllocationTests).
// Mirrors the Android `PaymentAllocation`.
//
// Two choices, as the backend contract defines them:
//  * `.autoAllocate` (the default): send `auto_allocate = true` and NO `applied_to_invoices`; the server allocates
//    oldest-first across the outlet's open invoices up to the amount, and whatever is left stays on account.
//  * `.onAccount`: send `auto_allocate = false` and NO `applied_to_invoices`; the whole amount stays on account.
// A manual allocation (an explicit `applied_to_invoices` list) is still honoured when given, and then
// `auto_allocate` is not sent at all — the server validates it.
//
// A queued payment row stores the whole `PaymentInput`, so the choice rides in the row (`auto_allocate` /
// `applied_to_invoices`); rows queued by older builds simply have neither key and are sent as they always were.

import Foundation

enum PaymentAllocation {

    /// The server's per-payment ceiling (`z.number().positive().max(100000000)`).
    static let maxAmount: Double = 100_000_000

    enum Choice: Equatable {
        case autoAllocate
        case onAccount
    }

    /// The two payment fields a choice controls.
    struct Payload: Equatable {
        var autoAllocate: Bool?
        var applied: [AppliedInvoice]?
    }

    /// The payload for `choice`; a non-empty valid `manual` list wins and suppresses `auto_allocate`.
    static func payload(choice: Choice, manual: [AppliedInvoice]? = nil) -> Payload {
        let clean: [AppliedInvoice] = (manual ?? []).filter { (entry: AppliedInvoice) -> Bool in
            !entry.invoice_id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && entry.amount > 0
        }
        if !clean.isEmpty { return Payload(autoAllocate: nil, applied: clean) }
        switch choice {
        case .autoAllocate: return Payload(autoAllocate: true, applied: nil)
        case .onAccount:    return Payload(autoAllocate: false, applied: nil)
        }
    }

    /// `base` with the allocation fields set from `payload`.
    static func applyTo(_ base: PaymentInput, payload: Payload) -> PaymentInput {
        PaymentInput(outlet_id: base.outlet_id, mode: base.mode, amount: base.amount, reference: base.reference,
                     cheque_bank: base.cheque_bank, cheque_date: base.cheque_date,
                     cheque_image_url: base.cheque_image_url, applied_to_invoices: payload.applied,
                     gps: base.gps, auto_allocate: payload.autoAllocate)
    }

    // MARK: - The amount

    /// The amount typed, to the paisa; nil when it is empty, not a number, <= 0 or above `maxAmount`.
    static func parseAmount(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed), value.isFinite else { return nil }
        if value > maxAmount * 2 { return nil }                 // far out of range: never do arithmetic on it
        let paise = (value * 100).rounded()
        if paise <= 0 { return nil }
        let rounded = paise / 100
        return rounded <= maxAmount ? rounded : nil
    }

    /// The message to show for a bad amount, or nil when it is fine.
    static func amountError(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(trimmed), value.isFinite else { return "Enter a valid amount" }
        if value <= 0 || (value * 100).rounded() <= 0 { return "Amount must be more than zero" }
        if value > maxAmount * 2 || (value * 100).rounded() / 100 > maxAmount { return "Amount is too large" }
        return nil
    }

    /// The first problem that blocks submitting, or nil. A cheque payment needs its photo (the bank is optional).
    /// No network is needed to pass this.
    static func validate(outletId: String?, amountText: String, mode: String, hasChequeImage: Bool) -> String? {
        if (outletId ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Choose an outlet first" }
        if let problem = amountError(amountText) { return problem }
        if mode == "cheque" && !hasChequeImage { return "Cheque image is required" }
        return nil
    }

    /// Keeps what a person typed into the amount box to digits and ONE decimal point (a comma, which some keyboards
    /// use as the decimal mark, counts as the point).
    static func sanitizeAmountInput(_ text: String) -> String {
        var out = ""
        var seenPoint = false
        for ch in text {
            if ch.isASCII && ch.isNumber {
                out.append(ch)
            } else if (ch == "." || ch == ",") && !seenPoint {
                out.append(".")
                seenPoint = true
            }
        }
        return out
    }

    // MARK: - The "where will it go" estimate (the server decides; this is only an estimate)

    struct Line: Equatable {
        let invoiceId: String
        let invoiceNo: String?
        let amount: Double
    }

    /// `lines` = what lands on each invoice, oldest first; `onAccount` = what is left over.
    struct Preview: Equatable {
        let lines: [Line]
        let onAccount: Double
    }

    /// Oldest-first allocation of `amount` across `invoices` (each up to its balance), to the paisa. Invoices
    /// without a positive balance are skipped. Mirrors the server's auto-allocation so the rep sees roughly where
    /// the money goes before submitting; the server's answer is the truth.
    static func preview(amount: Double, invoices: [OpenInvoice]) -> Preview {
        guard amount.isFinite else { return Preview(lines: [], onAccount: 0) }
        var remaining = (amount * 100).rounded()                // paise, held as a whole-number Double
        if remaining <= 0 { return Preview(lines: [], onAccount: 0) }
        let order: [Int] = Array(invoices.indices).sorted { (i: Int, j: Int) -> Bool in
            let di = invoices[i].invoiceDate ?? "9999-99-99"
            let dj = invoices[j].invoiceDate ?? "9999-99-99"
            if di != dj { return di < dj }
            return i < j
        }
        var lines: [Line] = []
        for index in order {
            if remaining <= 0 { break }
            let invoice = invoices[index]
            let balance = ((invoice.balance ?? 0) * 100).rounded()
            if !(balance > 0) { continue }
            let take = min(balance, remaining)
            lines.append(Line(invoiceId: invoice.invoiceId, invoiceNo: invoice.invoiceNo, amount: take / 100))
            remaining -= take
        }
        return Preview(lines: lines, onAccount: remaining / 100)
    }

    // MARK: - What the server did (read from the reply)

    /// "₹300.00 → INV-1 · ₹200.00 on account" from the payment reply, or nil when the reply carries no allocation
    /// list (an older server, or an unreadable body).
    static func summary(fromReplyData data: Data?) -> String? {
        guard let reply = SalesmanJSON.paymentReply(fromData: data), let applied = reply.applied else { return nil }
        var parts: [String] = []
        var allocated: Double = 0
        for line in applied {
            parts.append(DistributionMoney.rupees(line.amount) + " → " + (line.invoiceNo ?? String(line.invoiceId.prefix(8))))
            allocated += line.amount
        }
        if let total = reply.amount {
            let rest = ((total - allocated) * 100).rounded() / 100
            if rest > 0 { parts.append(DistributionMoney.rupees(rest) + " on account") }
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Rupee amounts for the distribution screens: always "₹", Indian digit grouping (12,34,567), deterministic
/// (no locale), optionally without the paise.
enum DistributionMoney {
    static func rupees(_ value: Double?, decimals: Bool = true) -> String {
        guard let v = value, v.isFinite else { return decimals ? "₹0.00" : "₹0" }
        let capped = min(abs(v), 1_000_000_000_000)
        let totalPaise: Int = decimals ? Int((capped * 100).rounded()) : Int(capped.rounded()) * 100
        let whole = totalPaise / 100
        let fraction = totalPaise % 100
        let negative = v < 0 && totalPaise > 0
        var text = (negative ? "-" : "") + "₹" + groupIndian(String(whole))
        if decimals { text += "." + (fraction < 10 ? "0" : "") + String(fraction) }
        return text
    }

    /// "1234567" → "12,34,567".
    static func groupIndian(_ digits: String) -> String {
        if digits.count <= 3 { return digits }
        let lastThree = String(digits.suffix(3))
        var rest = String(digits.dropLast(3))
        var groups: [String] = []
        while rest.count > 2 {
            groups.insert(String(rest.suffix(2)), at: 0)
            rest = String(rest.dropLast(2))
        }
        if !rest.isEmpty { groups.insert(rest, at: 0) }
        groups.append(lastThree)
        return groups.joined(separator: ",")
    }
}

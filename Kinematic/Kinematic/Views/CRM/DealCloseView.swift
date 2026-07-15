import SwiftUI

/// Sheet that closes a deal as Won or Lost. Mirrors the modal on the web
/// dashboard so the lifecycle (open → won/lost) is reachable from iOS too.
/// Backend exposes dedicated `/win` and `/lose` endpoints that also write
/// to `crm_deal_history`; the plain PATCH path would skip that audit row.
struct DealCloseView: View {
    let deal: Deal
    let onClosed: (Deal) -> Void
    @Environment(\.dismiss) private var dismiss

    /// Keep these lists in sync with `LOST_REASONS` / `WON_REASONS` in
    /// the web dashboard's `deals/[id]/page.tsx` — analytics groups on
    /// the resulting string, so any drift between platforms shows up as
    /// duplicated buckets on the win-loss reports.
    private static let lostReasons: [String] = [
        "Price too high",
        "Lost to competitor",
        "No budget / budget cut",
        "No decision maker reached",
        "Bad timing / not ready",
        "Product doesn't fit needs",
        "No response from prospect",
        "Stayed with current solution",
        "Missing features",
        "Project cancelled",
        "Lost on payment terms",
        "Lost on delivery / lead time",
        "Lost on quality / spec mismatch",
        "Internal champion left",
        "Procurement / vendor not approved",
        "Wrong contact / no authority",
        "Duplicate / merged with another deal",
        "Other",
    ]

    private static let wonReasons: [String] = [
        "Competitive pricing",
        "Better product fit",
        "Strong relationship / trust",
        "Faster delivery / availability",
        "Better quality / spec match",
        "Better payment / credit terms",
        "Existing vendor expansion",
        "Referral / word of mouth",
        "Bundled deal / cross-sell",
        "Replaced competitor solution",
        "Superior demo / POC result",
        "Better support / SLA",
        "Other",
    ]

    @State private var outcome: Outcome = .won
    @State private var winReason: String = ""
    @State private var wonOther: String = ""
    @State private var lostReason: String = ""
    @State private var lostOther: String = ""
    /// Closed (realised) amount, prefilled with the deal amount. Entering
    /// a lower value marks a partial close — the win posts that amount and
    /// (optionally) asks the backend to create a balance deal for the rest.
    @State private var closedAmountText: String
    @State private var createBalance = true
    @State private var saving = false
    @State private var errorMessage: String?

    init(deal: Deal, onClosed: @escaping (Deal) -> Void) {
        self.deal = deal
        self.onClosed = onClosed
        _closedAmountText = State(initialValue: Self.plainAmount(deal.amount))
    }

    enum Outcome: String, CaseIterable, Identifiable {
        case won, lost
        var id: String { rawValue }
        var label: String { self == .won ? "Won" : "Lost" }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Outcome", selection: $outcome) {
                        ForEach(Outcome.allCases) { o in
                            Text(o.label).tag(o)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Outcome")
                } footer: {
                    Text("Won/Lost is final but reversible — you can re-open the deal later from the deal detail screen.")
                        .font(.caption2)
                }

                if outcome == .lost {
                    Section("Lost reason") {
                        Picker("Reason", selection: $lostReason) {
                            Text("— Select a reason —").tag("")
                            ForEach(Self.lostReasons, id: \.self) { r in
                                Text(r).tag(r)
                            }
                        }
                        if lostReason == "Other" {
                            TextField("Describe the reason", text: $lostOther, axis: .vertical)
                                .lineLimit(2...4)
                        }
                    }
                } else {
                    // Win reason switched from free-text to a curated
                    // dropdown so analytics doesn't get polluted with
                    // one-off spellings ("comp prc", "competetive pricing"…).
                    // Required on submit, mirrors web dashboard PR #70.
                    Section("Win reason") {
                        Picker("Reason", selection: $winReason) {
                            Text("— Select a reason —").tag("")
                            ForEach(Self.wonReasons, id: \.self) { r in
                                Text(r).tag(r)
                            }
                        }
                        if winReason == "Other" {
                            TextField("Describe the reason", text: $wonOther, axis: .vertical)
                                .lineLimit(2...4)
                        }
                    }

                    // Closed amount — deals are price-locked after creation,
                    // so the win call is the one place the realised amount is
                    // captured. Entering less than the deal amount is a
                    // partial close; the backend can spin up an open
                    // "(Balance)" deal for whatever remains.
                    Section {
                        TextField("Closed amount (₹)", text: $closedAmountText)
                            .keyboardType(.decimalPad)
                        if let balance = balanceRemaining {
                            Label(
                                "Balance \(CurrencyFormatter.formatINR(balance)) will remain",
                                systemImage: "info.circle"
                            )
                            .font(.caption)
                            .foregroundColor(.orange)
                            Toggle("Create balance deal for the remainder", isOn: $createBalance)
                        }
                    } header: {
                        Text("Closed amount (₹)")
                    } footer: {
                        Text("Prefilled with the deal amount. Enter a lower value for a partial close.")
                            .font(.caption2)
                    }
                }

                Section {
                    summaryRow("Deal", deal.name)
                    summaryRow("Amount", formattedAmount)
                    if let stage = deal.stageName { summaryRow("Current stage", stage) }
                }
            }
            .navigationTitle("Close deal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if saving { ProgressView() }
                        else { Text(outcome == .won ? "Close as Won" : "Close as Lost").bold() }
                    }
                    .disabled(saving || !canSubmit)
                }
            }
            .alert("Close failed",
                   isPresented: .init(get: { errorMessage != nil },
                                      set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private var canSubmit: Bool {
        switch outcome {
        case .won:
            guard !winReason.isEmpty else { return false }
            if winReason == "Other",
               wonOther.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return false
            }
            // A non-empty amount must parse to a positive number. Empty is
            // fine — the backend computes from closed quantities / falls
            // back to the deal amount.
            let raw = closedAmountText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !raw.isEmpty {
                guard let n = enteredAmount, n > 0 else { return false }
            }
            return true
        case .lost:
            guard !lostReason.isEmpty else { return false }
            if lostReason == "Other" {
                return !lostOther.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return true
        }
    }

    /// Parsed closed-amount input. Tolerates grouping commas ("1,25,000").
    private var enteredAmount: Double? {
        let raw = closedAmountText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
        guard !raw.isEmpty else { return nil }
        return Double(raw)
    }

    /// Remainder when the entered amount is a valid partial close
    /// (0 < entered < deal amount); nil otherwise.
    private var balanceRemaining: Double? {
        guard let entered = enteredAmount, entered > 0,
              let full = deal.amount, entered < full else { return nil }
        return full - entered
    }

    /// Plain editable representation of the deal amount ("125000" /
    /// "125000.50") — no currency symbol or grouping so the decimal pad
    /// can round-trip it.
    private static func plainAmount(_ v: Double?) -> String {
        guard let v, v > 0 else { return "" }
        if v == v.rounded() { return String(Int(v)) }
        return String(format: "%.2f", v)
    }

    private var formattedAmount: String {
        guard let amount = deal.amount else { return "—" }
        if (deal.currency ?? "INR").uppercased() == "INR" {
            return CurrencyFormatter.formatINR(amount)
        }
        // Kinematic is INR-only; never let a missing deal.currency
        // fall through to the OS locale default (which renders $ for
        // most US-locale devices). Honour the deal row when set,
        // default to INR otherwise.
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = deal.currency ?? "INR"
        return f.string(from: NSNumber(value: amount)) ?? "\(amount)"
    }

    private func summaryRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundColor(.secondary)
            Spacer()
            Text(value).foregroundColor(.primary)
        }
        .font(.system(size: 13))
    }

    private func submit() async {
        saving = true
        defer { saving = false }
        do {
            let updated: Deal
            switch outcome {
            case .won:
                let reason = winReason == "Other"
                    ? wonOther.trimmingCharacters(in: .whitespacesAndNewlines)
                    : winReason
                // Only send create_balance_deal on a genuine partial close —
                // it's meaningless (and ignored) for a full-amount win.
                let isPartial = balanceRemaining != nil
                updated = try await CRMService.shared.winDeal(
                    id: deal.id,
                    amount: enteredAmount,
                    reason: reason.isEmpty ? nil : reason,
                    createBalanceDeal: isPartial ? createBalance : nil
                )
            case .lost:
                let reason = lostReason == "Other"
                    ? lostOther.trimmingCharacters(in: .whitespacesAndNewlines)
                    : lostReason
                updated = try await CRMService.shared.loseDeal(id: deal.id, reason: reason)
            }
            onClosed(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

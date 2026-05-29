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
    @State private var saving = false
    @State private var errorMessage: String?

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
            if winReason == "Other" {
                return !wonOther.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
                updated = try await CRMService.shared.winDeal(
                    id: deal.id,
                    amount: nil,
                    reason: reason.isEmpty ? nil : reason
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

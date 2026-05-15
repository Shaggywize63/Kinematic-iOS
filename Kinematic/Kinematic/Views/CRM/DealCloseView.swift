import SwiftUI

/// Sheet that closes a deal as Won or Lost. Mirrors the modal on the web
/// dashboard so the lifecycle (open → won/lost) is reachable from iOS too.
/// Backend exposes dedicated `/win` and `/lose` endpoints that also write
/// to `crm_deal_history`; the plain PATCH path would skip that audit row.
struct DealCloseView: View {
    let deal: Deal
    let onClosed: (Deal) -> Void
    @Environment(\.dismiss) private var dismiss

    /// Keep this list in sync with `LOST_REASONS` in the web dashboard's
    /// `deals/[id]/page.tsx` — reports group on the resulting string.
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
        "Other",
    ]

    @State private var outcome: Outcome = .won
    @State private var winReason: String = ""
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
                    Section("Win reason (optional)") {
                        TextField("e.g. Competitive pricing, great demo, referral",
                                  text: $winReason,
                                  axis: .vertical)
                            .lineLimit(2...4)
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
        case .won: return true
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
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = deal.currency ?? "USD"
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
                let trimmed = winReason.trimmingCharacters(in: .whitespacesAndNewlines)
                updated = try await CRMService.shared.winDeal(
                    id: deal.id,
                    amount: nil,
                    reason: trimmed.isEmpty ? nil : trimmed
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

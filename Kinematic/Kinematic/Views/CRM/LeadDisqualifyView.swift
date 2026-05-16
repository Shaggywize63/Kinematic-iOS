import SwiftUI

/// Sheet that disqualifies a lead as Unqualified or Lost. Mirrors
/// `DealCloseView` but for the lead lifecycle (step 2 of the plan).
///
/// The backend exposes no dedicated `/disqualify` endpoint — the plain
/// PATCH /leads/:id with `{ status, lost_reason }` is what triggers the
/// server to stamp `disqualified_at` and write the `crm_lead_history`
/// audit row. Re-open uses POST /leads/:id/reopen instead so the history
/// row distinguishes the two transitions.
struct LeadDisqualifyView: View {
    let lead: Lead
    let defaultOutcome: Outcome
    let onDisqualified: (Lead) -> Void
    @Environment(\.dismiss) private var dismiss

    /// Keep these lists in sync with the dashboard's disqualify modal —
    /// reports group on the resulting string so any divergence shows up
    /// as a new bucket in the win/loss/disqualify breakdown.
    private static let unqualifiedReasons: [String] = [
        "Not ready to buy",
        "No budget",
        "Wrong contact",
        "Needs revisit later",
        "Other",
    ]
    private static let lostReasons: [String] = [
        "Lost to competitor",
        "No response",
        "Junk / spam",
        "Wrong fit",
        "Duplicate",
        "Other",
    ]

    @State private var outcome: Outcome
    @State private var reason: String = ""
    @State private var other: String = ""
    @State private var saving = false
    @State private var errorMessage: String?

    init(lead: Lead, defaultOutcome: Outcome = .unqualified, onDisqualified: @escaping (Lead) -> Void) {
        self.lead = lead
        self.defaultOutcome = defaultOutcome
        self.onDisqualified = onDisqualified
        _outcome = State(initialValue: defaultOutcome)
    }

    enum Outcome: String, CaseIterable, Identifiable {
        case unqualified, lost
        var id: String { rawValue }
        var label: String { self == .unqualified ? "Unqualified" : "Lost" }
        var title: String { self == .unqualified ? "Disqualify Lead" : "Mark Lost" }
        var ctaLabel: String { self == .unqualified ? "Mark Unqualified" : "Mark Lost" }
    }

    private var reasonOptions: [String] {
        outcome == .unqualified ? Self.unqualifiedReasons : Self.lostReasons
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
                    .onChange(of: outcome) { _, _ in
                        // Reset reason when the option list changes so we
                        // never leave an unqualified-only reason selected
                        // after the rep flips to Lost.
                        reason = ""
                        other = ""
                    }
                } header: {
                    Text("Outcome")
                } footer: {
                    Text("You can re-open the lead later from the detail screen — disqualifying is reversible.")
                        .font(.caption2)
                }

                Section("Reason") {
                    Picker("Reason", selection: $reason) {
                        Text("— Select a reason —").tag("")
                        ForEach(reasonOptions, id: \.self) { r in
                            Text(r).tag(r)
                        }
                    }
                    if reason == "Other" {
                        TextField("Describe the reason", text: $other, axis: .vertical)
                            .lineLimit(2...4)
                    }
                }

                Section {
                    summaryRow("Lead", lead.displayName)
                    if let email = lead.email, !email.isEmpty {
                        summaryRow("Email", email)
                    }
                    if let status = lead.status, !status.isEmpty {
                        summaryRow("Current status", status.capitalized)
                    }
                }
            }
            .navigationTitle(outcome.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(saving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await submit() }
                    } label: {
                        if saving { ProgressView() }
                        else { Text(outcome.ctaLabel).bold() }
                    }
                    .disabled(saving || !canSubmit)
                }
            }
            .alert("Disqualify failed",
                   isPresented: .init(get: { errorMessage != nil },
                                      set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(errorMessage ?? "") }
        }
    }

    private var canSubmit: Bool {
        guard !reason.isEmpty else { return false }
        if reason == "Other" {
            return !other.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
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
        let finalReason = reason == "Other"
            ? other.trimmingCharacters(in: .whitespacesAndNewlines)
            : reason
        do {
            let updated = try await CRMService.shared.disqualifyLead(
                id: lead.id,
                status: outcome.rawValue,
                lostReason: finalReason
            )
            onDisqualified(updated)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

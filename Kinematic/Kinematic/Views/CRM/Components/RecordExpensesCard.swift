import SwiftUI

/// "Expenses" card on a lead or deal (connected-B2B / Spark & Ray only — the caller gates it on
/// `SparkJourney.isActive`): what was spent on the record, the visits, and the spend as a share of its value.
/// Fed by `GET /crm/leads/:id/expenses` or `GET /crm/deals/:id/expenses`; the wording is `ExpenseRollupText`.
struct RecordExpensesCard: View {
    enum Kind { case lead, deal }

    let kind: Kind
    let recordId: String

    private enum LoadState {
        case loading
        case failed
        case loaded(ExpenseRollup)
    }

    @State private var state: LoadState = .loading

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EXPENSES")
                .font(.system(size: 11, weight: .black))
                .tracking(0.8)
                .foregroundColor(Brand.red)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground)))
        .task(id: recordId) { await load() }
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                Text("Loading expenses…").font(.caption).foregroundColor(.secondary)
            }
        case .failed:
            VStack(alignment: .leading, spacing: 6) {
                Text("Couldn't load expenses").font(.subheadline).foregroundColor(.secondary)
                Button("Try again") { Task { await load() } }
                    .font(.caption.bold())
                    .tint(Brand.red)
            }
        case .loaded(let rollup):
            if ExpenseRollupText.isEmpty(rollup) {
                Text("No expenses linked yet").font(.subheadline).foregroundColor(.secondary)
            } else {
                loadedBody(rollup)
            }
        }
    }

    private func loadedBody(_ r: ExpenseRollup) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ExpenseRollupText.headline(r))
                .font(.system(size: 16, weight: .bold))
            Text(ExpenseRollupText.counts(r))
                .font(.caption).foregroundColor(.secondary)
            if let split = ExpenseRollupText.breakdown(r) {
                Text(split).font(.caption).foregroundColor(.secondary)
            }
            if !r.claims.isEmpty {
                VStack(spacing: 8) {
                    ForEach(r.claims) { c in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ExpenseRollupText.claimTitle(c)).font(.system(size: 14, weight: .semibold))
                                Text(ExpenseRollupText.claimSubtitle(c)).font(.caption2).foregroundColor(.secondary)
                                // On a lead, the deal a claim belongs to (the deal's own card is already that deal).
                                if kind == .lead, let deal = ExpenseLinkLogic.clean(c.deal_name) {
                                    Text("Deal: \(deal)").font(.caption2).foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Text(ExpenseRollupText.claimAmount(c, in: r))
                                .font(.system(size: 14, weight: .bold))
                        }
                        .padding(10)
                        .background(Color(uiColor: .tertiarySystemBackground))
                        .cornerRadius(10)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func load() async {
        state = .loading
        do {
            let rollup: ExpenseRollup
            switch kind {
            case .lead: rollup = try await CRMService.shared.leadExpenses(id: recordId)
            case .deal: rollup = try await CRMService.shared.dealExpenses(id: recordId)
            }
            if Task.isCancelled { return }
            state = .loaded(rollup)
        } catch {
            if Task.isCancelled { return }
            state = .failed
        }
    }
}

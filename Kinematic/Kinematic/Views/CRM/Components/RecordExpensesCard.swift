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
    @State private var showLink = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("EXPENSES")
                .font(.system(size: 11, weight: .black))
                .tracking(0.8)
                .foregroundColor(Brand.red)
            content
            // Attach an expense the rep already filed (even an approved / reimbursed one) to this record.
            if case .loaded = state {
                Button { showLink = true } label: {
                    Label("Link an existing expense", systemImage: "plus")
                        .font(.caption.bold())
                }
                .tint(Brand.red)
                .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground)))
        .task(id: recordId) { await load() }
        .sheet(isPresented: $showLink) {
            LinkExpenseSheet(kind: kind, recordId: recordId, onLinked: { Task { await load() } })
        }
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
            // Spend split by expense type (travel / food / lodging …).
            let byType = ExpenseRollupText.categoryLines(r)
            if !byType.isEmpty {
                Text("BY TYPE").font(.caption2.weight(.semibold)).foregroundColor(.secondary).padding(.top, 4)
                ForEach(Array(byType.enumerated()), id: \.offset) { _, row in
                    HStack {
                        Text(row.label).font(.caption).foregroundColor(.secondary)
                        Spacer()
                        Text(row.amount).font(.caption.weight(.semibold))
                    }
                }
            }
            if !r.claims.isEmpty {
                Text("BY TRIP").font(.caption2.weight(.semibold)).foregroundColor(.secondary).padding(.top, 4)
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

/// Picker to attach one of the signed-in rep's own expense claims to this lead / deal. Lists their claims
/// (via `GET /expenses/claims`), hides any already on this record, marks one sitting elsewhere, and on a pick
/// calls `PATCH /expenses/claims/:id/link` — allowed even for an approved / reimbursed claim — then asks the
/// card to reload.
private struct LinkExpenseSheet: View {
    let kind: RecordExpensesCard.Kind
    let recordId: String
    let onLinked: () -> Void
    @Environment(\.dismiss) private var dismiss

    private enum SheetState { case loading, failed, loaded([ExpenseClaim]) }
    @State private var state: SheetState = .loading
    @State private var linkingId: String?
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .loading:
                    ProgressView("Loading your expenses…")
                case .failed:
                    VStack(spacing: 12) {
                        Text("Couldn't load your expenses").foregroundColor(.secondary)
                        Button("Try again") { Task { await load() } }.tint(Brand.red)
                    }
                case .loaded(let claims):
                    let linkable = claims.filter { kind == .lead ? $0.lead_id != recordId : $0.deal_id != recordId }
                    if linkable.isEmpty {
                        VStack(spacing: 8) {
                            Text("No other expenses to link").font(.headline)
                            Text("Create one from the Expenses tab, choosing this \(kind == .lead ? "lead" : "deal") as what it was spent on.")
                                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                        }
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            if let errorText {
                                Text(errorText).font(.caption).foregroundColor(.red)
                            }
                            ForEach(linkable) { c in
                                Button { link(c) } label: { row(c) }
                                    .disabled(linkingId != nil)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Link an expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task { await load() }
        }
    }

    @ViewBuilder private func row(_ c: ExpenseClaim) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(c.title ?? c.claim_no ?? "Expense claim")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                let otherLink = (kind == .lead ? c.lead_name : c.deal_name).flatMap { $0.isEmpty ? nil : $0 }
                Text([c.statusLabel, otherLink.map { "on \($0)" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            if linkingId == c.id {
                ProgressView()
            } else {
                Text(ExpenseLogic.money(c.total_amount, c.currency))
                    .font(.system(size: 15, weight: .bold))
            }
        }
    }

    private func load() async {
        state = .loading
        do {
            let claims = try await ExpensesAPI.shared.myClaims()
            if Task.isCancelled { return }
            state = .loaded(claims)
        } catch {
            if !Task.isCancelled { state = .failed }
        }
    }

    private func link(_ c: ExpenseClaim) {
        Task {
            linkingId = c.id
            errorText = nil
            do {
                _ = try await ExpensesAPI.shared.linkClaim(
                    id: c.id,
                    leadId: kind == .lead ? recordId : nil,
                    dealId: kind == .deal ? recordId : nil,
                )
                onLinked()
                dismiss()
            } catch {
                linkingId = nil
                errorText = (error as? LocalizedError)?.errorDescription ?? "Couldn't link that expense"
            }
        }
    }
}

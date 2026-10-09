import SwiftUI

/// One claim in full: lines with receipts, the policy checks, every decision with its remark, and the
/// history. For the claimant it offers Edit / Submit / Fix and resubmit / Withdraw. For an approver
/// looking at a claim awaiting them it becomes the review: approve or reject each line (a rejected
/// line needs a remark), then approve the claim or reject it (also with a remark).
struct ExpenseClaimDetailView: View {
    let claimId: String
    var startEditing: Bool = false
    @ObservedObject var listVM: ExpensesViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var claim: ExpenseClaim?
    @State private var loadError: String?
    @State private var busy = false
    @State private var notice: String?
    @State private var editing = false
    @State private var autoOpened = false
    @State private var confirmWithdraw = false
    @State private var viewing: ReceiptRef?

    private var me: User? { Session.currentUser }
    private var isMine: Bool { claim?.user_id != nil && claim?.user_id == me?.id }
    private var status: String { (claim?.status ?? "").lowercased() }
    private var canApprove: Bool { ExpenseLogic.canApprove(role: me?.role, dataScope: me?.orgRoleDataScope) }
    private var reviewing: Bool { claim != nil && status == "submitted" && canApprove && !isMine && me != nil }
    /// The policy's own names for the categories (e.g. mileage → "Travel"); nil = the built-in names.
    private var categoryLabels: [String: String]? { listVM.policy?.rules?.category_labels }

    var body: some View {
        Group {
            if let c = claim {
                List {
                    Section { header(c) }
                    if (c.status ?? "") == "rejected" { Section { ExpenseRejectionBanner(claim: c).listRowInsets(EdgeInsets()) } }
                    if ExpenseLogic.isPartlyApproved(c) {
                        Section {
                            Text("\(expenseMoney(c.approved_amount ?? 0, c.currency)) of \(expenseMoney(c.total_amount, c.currency)) approved. The rejected lines are marked with the reviewer's remark.")
                                .font(.subheadline)
                        }
                    }
                    if isMine { Section { ownerActions(c) } }

                    if reviewing {
                        ExpenseReviewSection(claim: c, busy: busy, categoryLabels: categoryLabels, onViewReceipt: { viewing = ReceiptRef(url: $0) }) { decision, note, items in
                            await decide(c, decision: decision, note: note, items: items)
                        }
                    } else {
                        Section("Expenses") {
                            if (c.items ?? []).isEmpty { Text("This claim has no lines.").foregroundColor(.secondary) }
                            ForEach(c.items ?? []) { item in
                                ExpenseLineView(item: item, currency: c.currency, categoryLabels: categoryLabels) { viewing = ReceiptRef(url: $0) }
                            }
                        }
                    }

                    if let flags = c.ai_flags, !flags.isEmpty {
                        Section("Policy checks") {
                            if let s = c.ai_summary, !s.isEmpty { Text(s).font(.caption).foregroundColor(.secondary) }
                            ExpenseFindingsList(flags: flags)
                        }
                    }
                    Section("Details") { details(c) }
                    Section("History") { ExpenseTimelineView(claim: c, categoryLabels: categoryLabels) }
                }
                .refreshable { await load(silent: true) }
                .overlay(alignment: .top) { if busy { ProgressView().padding(.top, 8) } }
            } else if let err = loadError {
                ContentUnavailableView {
                    Label("Couldn't open the claim", systemImage: "exclamationmark.triangle")
                } description: { Text(err) } actions: { Button("Try again") { Task { await load() } } }
            } else {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(claim?.claim_no ?? "Claim")
        .navigationBarTitleDisplayMode(.inline)
        .task { await listVM.loadPolicy(); await load() }
        .sheet(isPresented: $editing) {
            if let c = claim {
                ExpenseClaimEditorView(vm: listVM, claim: c) { _, _ in
                    editing = false
                    Task { await load(silent: true); await listVM.loadClaims() }
                }
            }
        }
        .sheet(item: $viewing) { ReceiptViewerSheet(url: $0.url) }
        .alert(status == "draft" ? "Delete this draft?" : "Withdraw this claim?", isPresented: $confirmWithdraw) {
            Button(status == "draft" ? "Delete draft" : "Withdraw", role: .destructive) { Task { await withdraw() } }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text(status == "draft" ? "The draft and its receipts will be discarded." : "It leaves the approval queue. You can't reopen it, but you can file a new claim.")
        }
        .alert("Claim", isPresented: Binding(get: { notice != nil }, set: { if !$0 { notice = nil } })) {
            Button("OK", role: .cancel) { notice = nil }
        } message: { Text(notice ?? "") }
    }

    // ── pieces ──────────────────────────────────────────────────────────────

    private func header(_ c: ExpenseClaim) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(c.title ?? c.claim_no ?? "Expense claim").font(.title3).bold()
            if !isMine {
                Text((c.user_name ?? "Team member") + (c.employee_id.map { " (\($0))" } ?? "")).font(.subheadline).foregroundColor(.secondary)
            }
            HStack(spacing: 10) {
                ExpenseStatusChip(claim: c)
                Text(expenseMoney(ExpenseLogic.payable(c), c.currency)).font(.headline)
                if ExpenseLogic.isPartlyApproved(c) {
                    Text(expenseMoney(c.total_amount, c.currency)).font(.caption).strikethrough().foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder private func ownerActions(_ c: ExpenseClaim) -> some View {
        switch status {
        case "draft":
            HStack {
                Button("Submit for approval") { Task { await submit(c) } }.buttonStyle(.borderedProminent).disabled(busy)
                Button("Edit") { editing = true }.buttonStyle(.bordered).disabled(busy)
            }
        case "rejected":
            Button("Fix and resubmit") { editing = true }.buttonStyle(.borderedProminent).disabled(busy)
        case "submitted":
            Button("Edit") { editing = true }.buttonStyle(.bordered).disabled(busy)
        default:
            EmptyView()
        }
        if ExpenseLogic.isEditable(c.status) {
            Button(status == "draft" ? "Delete draft" : "Withdraw this claim", role: .destructive) { confirmWithdraw = true }
                .buttonStyle(.borderless).disabled(busy)
        }
    }

    private func detailRows(_ c: ExpenseClaim) -> [(String, String)] {
        var rows: [(String, String)] = []
        if let d = c.submitted_at { rows.append(("Submitted", String(d.prefix(10)))) }
        if let p = c.policy_name { rows.append(("Policy", p)) }
        rows.append(("Claimed", expenseMoney(c.total_amount, c.currency)))
        if let a = c.approved_amount, (c.status ?? "") != "rejected" { rows.append(("Approved", expenseMoney(a, c.currency))) }
        if (c.status ?? "") == "submitted", let w = c.approver_name {
            let level = c.current_level ?? 1
            rows.append(("With", level > 1 ? "\(w) (level \(level))" : w))
        }
        if let km = c.distance_km { rows.append(("\(ExpenseLogic.categoryLabel("mileage", labels: categoryLabels)) claimed", "\(ExpenseLogic.trimNumber(km)) km")) }
        if let km = c.gps_derived_km { rows.append(("GPS trail", "\(ExpenseLogic.trimNumber(km)) km")) }
        if let paid = c.reimbursed_at {
            let ref = (c.reimbursed_ref ?? "").isEmpty ? "" : " · \(c.reimbursed_ref ?? "")"
            rows.append(("Reimbursed", String(paid.prefix(10)) + ref))
        }
        return rows
    }

    @ViewBuilder private func details(_ c: ExpenseClaim) -> some View {
        ForEach(Array(detailRows(c).enumerated()), id: \.offset) { _, row in
            HStack(alignment: .top) {
                Text(row.0).foregroundColor(.secondary)
                Spacer()
                Text(row.1).multilineTextAlignment(.trailing)
            }
            .font(.subheadline)
        }
    }

    // ── actions ─────────────────────────────────────────────────────────────

    private func load(silent: Bool = false) async {
        do {
            let c = try await listVM.claim(id: claimId)
            claim = c
            loadError = nil
            // Arriving from "Fix and resubmit" opens the editor straight away, once the claim has loaded.
            if startEditing && !autoOpened && c.user_id == me?.id && ExpenseLogic.isEditable(c.status) { autoOpened = true; editing = true }
        } catch {
            if claim == nil { loadError = error.localizedDescription } else if !silent { notice = error.localizedDescription }
        }
    }

    private func submit(_ c: ExpenseClaim) async {
        busy = true; defer { busy = false }
        await listVM.submit(id: c.id)
        notice = listVM.notice; listVM.notice = nil
        await load(silent: true)
    }

    private func withdraw() async {
        busy = true; defer { busy = false }
        if await listVM.cancel(id: claimId) { dismiss() } else { notice = listVM.notice; listVM.notice = nil }
    }

    private func decide(_ c: ExpenseClaim, decision: String, note: String?, items: [ExpenseLineDecisionInput]?) async {
        busy = true; defer { busy = false }
        if await listVM.decide(id: c.id, decision: decision, note: note, items: items) != nil {
            notice = listVM.notice; listVM.notice = nil
            await load(silent: true)
        } else {
            notice = listVM.notice; listVM.notice = nil
        }
    }
}

// MARK: - The approver's review

private struct ExpenseReviewSection: View {
    let claim: ExpenseClaim
    let busy: Bool
    let categoryLabels: [String: String]?
    let onViewReceipt: (String) -> Void
    let onDecide: (_ decision: String, _ note: String?, _ items: [ExpenseLineDecisionInput]?) async -> Void

    @State private var reviews: [ExpenseLineReview]
    @State private var note = ""
    @State private var showErrors = false
    @State private var rejecting = false

    init(claim: ExpenseClaim, busy: Bool, categoryLabels: [String: String]?, onViewReceipt: @escaping (String) -> Void,
         onDecide: @escaping (_ decision: String, _ note: String?, _ items: [ExpenseLineDecisionInput]?) async -> Void) {
        self.claim = claim; self.busy = busy; self.categoryLabels = categoryLabels
        self.onViewReceipt = onViewReceipt; self.onDecide = onDecide
        _reviews = State(initialValue: (claim.items ?? []).map { ExpenseLineReview(id: $0.id) })
    }

    private var items: [ExpenseClaimItem] { claim.items ?? [] }
    private var rejectedCount: Int { reviews.filter { !$0.approved }.count }
    private var allRejected: Bool { !items.isEmpty && rejectedCount == items.count }
    private var partial: Bool { rejectedCount > 0 && !allRejected }
    private var total: Double { ExpenseReview.approvedTotal(items: items, reviews: reviews) }

    var body: some View {
        Group {
        Section("Review") {
            ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                VStack(alignment: .leading, spacing: 8) {
                    ExpenseLineView(item: item, currency: claim.currency, categoryLabels: categoryLabels, onViewReceipt: onViewReceipt)
                    if reviews.indices.contains(i) {
                        Picker("Decision", selection: Binding(get: { reviews[i].approved }, set: { reviews[i].approved = $0 })) {
                            Text("Approve").tag(true)
                            Text("Reject").tag(false)
                        }
                        .pickerStyle(.segmented)
                        if !reviews[i].approved {
                            TextField("Why is this line rejected? (required)", text: Binding(get: { reviews[i].note }, set: { reviews[i].note = String($0.prefix(1000)) }), axis: .vertical)
                                .lineLimit(2...4)
                            if showErrors && reviews[i].note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("A remark is needed to reject this line").font(.caption).foregroundColor(.red)
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
        }
        Section {
            TextField("Note to the claimant (optional)", text: $note, axis: .vertical).lineLimit(2...4)
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(partial ? "You will approve" : "Claimed").font(.caption2).foregroundColor(.secondary)
                    Text(expenseMoney(partial ? total : claim.total_amount, claim.currency) + (partial ? " of \(expenseMoney(claim.total_amount, claim.currency))" : ""))
                        .font(.headline)
                }
                Spacer()
            }
            HStack {
                Button("Reject claim", role: .destructive) { rejecting = true }.buttonStyle(.bordered).disabled(busy)
                Spacer()
                Button(partial ? "Approve selected" : "Approve") {
                    if !ExpenseReview.linesMissingRemark(reviews).isEmpty { showErrors = true; return }
                    let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task { await onDecide("approved", trimmed.isEmpty ? nil : trimmed, ExpenseReview.body(reviews)) }
                }
                .buttonStyle(.borderedProminent).tint(.green).disabled(busy || allRejected)
            }
            if allRejected { Text("Every line is rejected — use “Reject claim” and explain why.").font(.caption).foregroundColor(.secondary) }
        }
        }
        .sheet(isPresented: $rejecting) {
            ExpenseRemarkSheet(title: "Reject this claim",
                               message: "\(claim.user_name ?? "The claimant") will see this remark in their app and can fix the claim and resubmit it.",
                               confirmLabel: "Reject") { remark in
                let own = ExpenseReview.ownRemarks(reviews)
                Task { await onDecide("rejected", remark, own.isEmpty ? nil : own) }
            }
        }
    }
}

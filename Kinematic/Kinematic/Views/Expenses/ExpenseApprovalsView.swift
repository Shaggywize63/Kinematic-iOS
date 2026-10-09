import SwiftUI

/// Manager approvals for expense claims — what is waiting on you. Tap a claim to review it line by line
/// (with its receipts); or approve it in one tap, or reject it with the remark the claimant will see.
/// Rejecting always needs a remark. A claim the policy flagged as a serious breach can't be approved from
/// the queue — open it and review the flagged lines. High-value claims escalate to the next manager on
/// approval (server-side). Mirrors LeaveApprovalsView.
struct ExpenseApprovalsView: View {
    @StateObject private var vm = ExpensesViewModel()
    @State private var rejectTarget: ExpenseClaim?
    @State private var openClaimId: String?

    /// The policy's own name for mileage (e.g. "Travel"); the built-in name otherwise.
    private var mileageName: String { ExpenseLogic.categoryLabel("mileage", labels: vm.policy?.rules?.category_labels) }

    var body: some View {
        Group {
            if !vm.didLoad {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = vm.loadError, vm.pending.isEmpty {
                ContentUnavailableView {
                    Label("Couldn't load the queue", systemImage: "exclamationmark.triangle")
                } description: { Text(err) } actions: {
                    Button("Try again") { Task { await vm.loadPending() } }
                }
            } else if vm.pending.isEmpty {
                ContentUnavailableView("Nothing is waiting for you", systemImage: "checkmark.seal",
                                       description: Text("Claims routed to you will appear here."))
            } else {
                List {
                    Section("Awaiting your approval") {
                        ForEach(vm.pending) { claim in
                            row(claim)
                                .contentShape(Rectangle())
                                .onTapGesture { openClaimId = claim.id }
                        }
                    }
                }
            }
        }
        .navigationTitle("Expense Approvals")
        .navigationBarTitleDisplayMode(.inline)
        // The queue first; the policy (only for its category names) follows without holding the list up.
        .task { if !vm.didLoad { await vm.loadPending() }; await vm.loadPolicy() }
        .refreshable { await vm.loadPending() }
        .background(
            NavigationLink(isActive: Binding(get: { openClaimId != nil }, set: { if !$0 { openClaimId = nil; Task { await vm.loadPending() } } })) {
                if let id = openClaimId { ExpenseClaimDetailView(claimId: id, listVM: vm) }
            } label: { EmptyView() }
        )
        .sheet(item: $rejectTarget) { claim in
            ExpenseRemarkSheet(title: "Reject this claim",
                               message: "\(claim.user_name ?? "The claimant") will see this remark in their app and can fix the claim and resubmit it.",
                               confirmLabel: "Reject") { remark in
                Task { await vm.decide(id: claim.id, decision: "rejected", note: remark) }
            }
        }
        .alert("Expense approvals", isPresented: Binding(get: { vm.notice != nil }, set: { if !$0 { vm.notice = nil } })) {
            Button("OK", role: .cancel) { vm.notice = nil }
        } message: { Text(vm.notice ?? "") }
    }

    private func row(_ claim: ExpenseClaim) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(claim.user_name ?? "Team member").font(.subheadline).bold()
                    Text(rowSubtitle(claim)).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Text(expenseMoney(claim.total_amount, claim.currency)).font(.subheadline).bold()
            }
            if let s = claim.ai_summary, !s.isEmpty { Text(s).font(.caption).foregroundColor(.secondary) }
            if let flags = claim.ai_flags, !flags.isEmpty {
                ExpenseFindingsList(flags: Array(flags.prefix(3)))
            } else {
                Text("Within policy").font(.caption2).bold().padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.green.opacity(0.15)).foregroundColor(.green).clipShape(Capsule())
            }
            if let km = claim.distance_km {
                Text("\(mileageName) claimed \(ExpenseLogic.trimNumber(km)) km" + (claim.gps_derived_km.map { " · GPS \(ExpenseLogic.trimNumber($0)) km" } ?? ""))
                    .font(.caption2).foregroundColor(.secondary)
            }
            HStack {
                Spacer()
                if vm.busyIds.contains(claim.id) {
                    ProgressView()
                } else {
                    Button("Reject", role: .destructive) { rejectTarget = claim }
                        .buttonStyle(.bordered).controlSize(.small)
                    if ExpenseLogic.canQuickApprove(claim) {
                        Button("Approve") { Task { await vm.decide(id: claim.id, decision: "approved", note: nil) } }
                            .buttonStyle(.borderedProminent).controlSize(.small).tint(.green)
                    } else {
                        Button("Review") { openClaimId = claim.id }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func rowSubtitle(_ claim: ExpenseClaim) -> String {
        var s = (claim.title ?? claim.claim_no ?? "Expense claim") + " · " + String((claim.submitted_at ?? "").prefix(10))
        let level = claim.current_level ?? 1
        if level > 1 { s += " · level \(level)" }
        return s
    }
}

import SwiftUI
import UIKit
// Combine is not re-exported by SwiftUI on the Xcode 26 toolchain.
import Combine

// MARK: - View model (shared by the claims, detail, editor and approvals screens)

@MainActor
final class ExpensesViewModel: ObservableObject {
    @Published var policy: ExpensePolicy?
    @Published var claims: [ExpenseClaim] = []
    @Published var pending: [ExpenseClaim] = []
    @Published var didLoad = false
    @Published var busyIds: Set<String> = []
    /// Set when a list could not be loaded (shown instead of an empty list).
    @Published var loadError: String?
    /// One-off message, success or failure.
    @Published var notice: String?

    private let api = ExpensesAPI.shared

    // ── My claims ────────────────────────────────────────────────────────────
    func loadClaims() async {
        loadError = nil
        if policy == nil { policy = try? await api.policy() }
        do { claims = try await api.myClaims() }
        catch { loadError = error.localizedDescription }
        didLoad = true
    }

    func loadPolicy() async { if policy == nil { policy = try? await api.policy() } }

    func claim(id: String) async throws -> ExpenseClaim { try await api.claim(id: id) }

    func submit(id: String) async {
        busyIds.insert(id); defer { busyIds.remove(id) }
        do { _ = try await api.submit(id: id); notice = "Submitted for approval"; await loadClaims() }
        catch { notice = error.localizedDescription }
    }

    func cancel(id: String) async -> Bool {
        busyIds.insert(id); defer { busyIds.remove(id) }
        do { try await api.cancel(id: id); await loadClaims(); return true }
        catch { notice = error.localizedDescription; return false }
    }

    // ── Editor ───────────────────────────────────────────────────────────────
    struct SaveOutcome { let savedId: String?; let submitted: Bool; let error: String? }

    /// Save the lines as a new draft (`claimId` nil) or onto an existing claim, and optionally submit it.
    /// If saving works but submitting is refused (a "block" policy, say), the outcome still carries the
    /// saved id so the editor keeps working on that claim instead of creating a duplicate.
    func save(claimId: String?, title: String?, items: [ExpenseClaimItemInput], submit: Bool) async -> SaveOutcome {
        let input = ExpenseClaimInput(title: title, items: items)
        var id = claimId
        do {
            if let existing = claimId { _ = try await api.updateClaim(id: existing, input) }
            else { id = try await api.createClaim(input).id }
        } catch { return SaveOutcome(savedId: claimId, submitted: false, error: error.localizedDescription) }
        guard submit, let savedId = id else { return SaveOutcome(savedId: id, submitted: false, error: nil) }
        do { _ = try await api.submit(id: savedId); return SaveOutcome(savedId: savedId, submitted: true, error: nil) }
        catch { return SaveOutcome(savedId: savedId, submitted: false, error: error.localizedDescription) }
    }

    func uploadReceipt(data: Data, filename: String, mime: String) async -> (ExpenseUploadedReceipt?, String?) {
        do { return (try await api.uploadReceipt(data: data, filename: filename, mime: mime), nil) }
        catch { return (nil, error.localizedDescription) }
    }

    /// Ask the server what the policy thinks of these unsaved lines. Best effort: a failure just means no warnings.
    func check(items: [ExpenseClaimItemInput], claimId: String?) async -> ExpenseClaimCheck? {
        try? await api.check(items: items, claimId: claimId)
    }

    func mileage(fromISO: String, toISO: String) async -> (ExpenseMileageResult?, String?) {
        do { return (try await api.mileage(fromISO: fromISO, toISO: toISO), nil) }
        catch { return (nil, error.localizedDescription) }
    }

    // ── Approvals ────────────────────────────────────────────────────────────
    func loadPending() async {
        loadError = nil
        do { pending = try await api.pendingClaims() }
        catch { loadError = error.localizedDescription }
        didLoad = true
    }

    /// Approve (optionally line by line) or reject with the remark the server requires.
    /// Returns the result, or nil with `notice` set to the server's message.
    @discardableResult
    func decide(id: String, decision: String, note: String?, items: [ExpenseLineDecisionInput]? = nil) async -> ExpenseDecisionResult? {
        busyIds.insert(id); defer { busyIds.remove(id) }
        do {
            let r = try await api.decide(id: id, decision: decision, note: note, items: items)
            pending.removeAll { $0.id == id }
            if decision == "rejected" { notice = "Rejected — your remark has been sent to the claimant" }
            else if r.escalated == true { notice = "Approved — sent to the next manager for sign-off" }
            else if (r.rejected_lines ?? 0) > 0 { notice = "Partly approved" }
            else { notice = "Claim approved" }
            return r
        } catch { notice = error.localizedDescription; return nil }
    }
}

// MARK: - Claims list

struct ExpenseClaimsView: View {
    private enum Filter: String, CaseIterable, Identifiable {
        case all = "All", needsYou = "Needs you", waiting = "Awaiting approval", approved = "Approved", paid = "Reimbursed"
        var id: String { rawValue }
        func matches(_ c: ExpenseClaim) -> Bool {
            let s = (c.status ?? "draft").lowercased()
            switch self {
            case .all:      return s != "cancelled"
            case .needsYou: return s == "rejected" || s == "draft"
            case .waiting:  return s == "submitted"
            case .approved: return s == "approved"
            case .paid:     return s == "reimbursed"
            }
        }
    }

    @StateObject private var vm = ExpensesViewModel()
    @ObservedObject private var appState = KiniAppState.shared
    @State private var showCreate = false
    @State private var filter: Filter = .all
    /// The claim to open (from a tapped row, "Fix and resubmit", or an expense push).
    @State private var openClaimId: String?
    @State private var openInEditor = false

    private var shown: [ExpenseClaim] { vm.claims.filter { filter.matches($0) } }
    private var canApprove: Bool {
        ExpenseLogic.canApprove(role: Session.currentUser?.role, dataScope: Session.currentUser?.orgRoleDataScope)
    }

    var body: some View {
        Group {
            if !vm.didLoad {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = vm.loadError, vm.claims.isEmpty {
                ContentUnavailableView {
                    Label("Couldn't load your claims", systemImage: "exclamationmark.triangle")
                } description: { Text(err) } actions: {
                    Button("Try again") { Task { await vm.loadClaims() } }
                }
            } else {
                List {
                    Section { summary }
                    Section {
                        Picker("Show", selection: $filter) { ForEach(Filter.allCases) { Text($0.rawValue).tag($0) } }
                            .pickerStyle(.menu)
                    }
                    if shown.isEmpty {
                        Section {
                            Text(vm.claims.isEmpty ? "No claims yet. Tap + to add your expenses with a photo of each receipt." : "Nothing in this view.")
                                .font(.subheadline).foregroundColor(.secondary)
                        }
                    } else {
                        Section("My claims") {
                            ForEach(shown) { claim in
                                // The row opens the claim; the bordered buttons inside it act on their own.
                                ClaimRow(claim: claim, busy: vm.busyIds.contains(claim.id),
                                         onFix: { openClaimId = claim.id; openInEditor = true },
                                         onSubmit: { Task { await vm.submit(id: claim.id) } })
                                    .contentShape(Rectangle())
                                    .onTapGesture { openClaimId = claim.id; openInEditor = false }
                            }
                        }
                    }
                }
                .refreshable { await vm.loadClaims() }
            }
        }
        .navigationTitle("Expenses")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    if canApprove {
                        NavigationLink { ExpenseApprovalsView() } label: { Image(systemName: "checkmark.seal") }
                            .accessibilityLabel("Approvals")
                    }
                    Button { showCreate = true } label: { Image(systemName: "plus") }.accessibilityLabel("New claim")
                }
            }
        }
        .background(
            NavigationLink(isActive: Binding(get: { openClaimId != nil }, set: { if !$0 { openClaimId = nil } })) {
                if let id = openClaimId { ExpenseClaimDetailView(claimId: id, startEditing: openInEditor, listVM: vm) }
            } label: { EmptyView() }
        )
        .task {
            if !vm.didLoad { await vm.loadClaims() }
            consumePushTarget()
        }
        .onChange(of: appState.pendingExpenseClaimId) { _, _ in consumePushTarget() }
        .sheet(isPresented: $showCreate) {
            ExpenseClaimEditorView(vm: vm, claim: nil) { id, _ in
                showCreate = false
                openInEditor = false
                openClaimId = id          // land on the claim so the person sees it was recorded
                Task { await vm.loadClaims() }
            }
        }
        .alert("Expenses", isPresented: Binding(get: { vm.notice != nil }, set: { if !$0 { vm.notice = nil } })) {
            Button("OK", role: .cancel) { vm.notice = nil }
        } message: { Text(vm.notice ?? "") }
    }

    /// A tapped expense push opens its claim.
    private func consumePushTarget() {
        guard let id = appState.pendingExpenseClaimId, !id.isEmpty else { return }
        appState.pendingExpenseClaimId = nil
        openInEditor = false
        openClaimId = id
    }

    private var summary: some View {
        let live = vm.claims.filter { ($0.status ?? "") != "cancelled" }
        let currency = live.first?.currency ?? "INR"
        let waiting = live.filter { $0.status == "submitted" }
        let toPay = live.filter { $0.status == "approved" }
        let rejected = live.filter { $0.status == "rejected" }.count
        return HStack(alignment: .top) {
            summaryCell("Awaiting", expenseMoney(waiting.reduce(0) { $0 + ExpenseLogic.payable($1) }, currency), waiting.isEmpty ? .primary : .orange)
            Spacer()
            summaryCell("To be paid", expenseMoney(toPay.reduce(0) { $0 + ExpenseLogic.payable($1) }, currency), toPay.isEmpty ? .primary : .green)
            Spacer()
            summaryCell("Sent back", String(rejected), rejected == 0 ? .primary : .red)
        }
    }

    private func summaryCell(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.headline).foregroundColor(color)
        }
    }
}

private struct ClaimRow: View {
    let claim: ExpenseClaim
    let busy: Bool
    let onFix: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        let status = (claim.status ?? "draft").lowercased()
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(claim.title ?? claim.claim_no ?? "Expense claim").font(.subheadline).bold()
                    Text(subtitle(status)).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(expenseMoney(ExpenseLogic.payable(claim), claim.currency)).font(.subheadline).bold()
                    if ExpenseLogic.isPartlyApproved(claim) {
                        Text(expenseMoney(claim.total_amount, claim.currency)).font(.caption2).strikethrough().foregroundColor(.secondary)
                    }
                }
            }
            HStack(spacing: 6) {
                ExpenseStatusChip(claim: claim)
                if status == "submitted", let n = claim.ai_flags?.count, n > 0 {
                    Text("\(n) flagged").font(.caption2).bold().padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15)).foregroundColor(.orange).clipShape(Capsule())
                }
            }
            if status == "rejected" {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rejected" + (claim.reviewer_name.map { " by \($0)" } ?? "")).font(.caption).bold().foregroundColor(.red)
                    Text((claim.review_note ?? "").isEmpty ? "No remark was left." : (claim.review_note ?? "")).font(.subheadline)
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.10)).clipShape(RoundedRectangle(cornerRadius: 8))
            }
            if ExpenseLogic.isPartlyApproved(claim) {
                Text("Some lines were rejected — open the claim to see why.").font(.caption).foregroundColor(.orange)
            }
            if status == "rejected" {
                Button("Fix and resubmit", action: onFix).buttonStyle(.borderedProminent).controlSize(.small)
            } else if status == "draft" {
                HStack {
                    Button("Submit", action: onSubmit).buttonStyle(.borderedProminent).controlSize(.small).disabled(busy)
                    Button("Edit", action: onFix).buttonStyle(.bordered).controlSize(.small).disabled(busy)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func subtitle(_ status: String) -> String {
        var s = status == "draft" ? "Started " : "Submitted "
        s += String((status == "draft" ? claim.created_at : (claim.submitted_at ?? claim.created_at))?.prefix(10) ?? "—")
        if status == "submitted", let ap = claim.approver_name { s += " · with \(ap)" }
        return s
    }
}

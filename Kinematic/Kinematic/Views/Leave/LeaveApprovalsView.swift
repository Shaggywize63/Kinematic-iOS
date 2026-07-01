import SwiftUI

/// Manager view: pending leave requests + pending attendance regularizations,
/// each with Approve / Reject (and an optional note). Backed by
/// GET /leave/requests/pending, GET /leave/regularizations/pending and the
/// two /decision PATCH routes.
///
/// Visibility is decided by the caller (only supervisors/admins see the entry
/// point). If a non-manager reaches it anyway the API 403s and we render an
/// empty state rather than crashing.
struct LeaveApprovalsView: View {
    @State private var pendingLeave: [LeaveRequest] = []
    @State private var pendingRegs: [Regularization] = []
    @State private var isLoading = true
    @State private var didLoad = false
    @State private var tab = 0

    // Decision-note sheet state.
    @State private var noteContext: DecisionContext?

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("Leave (\(pendingLeave.count))").tag(0)
                Text("Regularization (\(pendingRegs.count))").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            if isLoading && !didLoad {
                ProgressView().tint(Brand.red).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        if tab == 0 {
                            if pendingLeave.isEmpty {
                                emptyState("No pending leave requests")
                            } else {
                                ForEach(pendingLeave) { req in
                                    ApprovalLeaveCard(request: req) { decision in
                                        noteContext = DecisionContext(kind: .leave, id: req.id, decision: decision)
                                    }
                                }
                            }
                        } else {
                            if pendingRegs.isEmpty {
                                emptyState("No pending regularizations")
                            } else {
                                ForEach(pendingRegs) { reg in
                                    ApprovalRegCard(item: reg) { decision in
                                        noteContext = DecisionContext(kind: .regularization, id: reg.id, decision: decision)
                                    }
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Approvals")
        .navigationBarTitleDisplayMode(.inline)
        .background(Color(uiColor: .systemGroupedBackground).ignoresSafeArea())
        .sheet(item: $noteContext) { ctx in
            DecisionNoteSheet(context: ctx) { await decide(ctx, note: $0) }
        }
        .task {
            guard !didLoad else { return }
            await load()
        }
        .refreshable { await load() }
    }

    private func emptyState(_ text: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal").font(.system(size: 44)).foregroundColor(.gray.opacity(0.4))
            Text(text).font(.subheadline).foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
    }

    private func load() async {
        await MainActor.run { isLoading = true }
        async let l = KinematicRepository.shared.fetchPendingLeaveRequests()
        async let r = KinematicRepository.shared.fetchPendingRegularizations()
        let (leave, regs) = await (l, r)
        await MainActor.run {
            self.pendingLeave = leave
            self.pendingRegs = regs
            self.isLoading = false
            self.didLoad = true
        }
    }

    private func decide(_ ctx: DecisionContext, note: String?) async {
        let ok: Bool
        switch ctx.kind {
        case .leave:
            ok = await KinematicRepository.shared.decideLeaveRequest(id: ctx.id, decision: ctx.decision, note: note)
        case .regularization:
            ok = await KinematicRepository.shared.decideRegularization(id: ctx.id, decision: ctx.decision, note: note)
        }
        if ok { await load() }
    }
}

// MARK: - Decision context

private struct DecisionContext: Identifiable {
    enum Kind { case leave, regularization }
    let id: String
    let kind: Kind
    let decision: String   // "approved" | "rejected"

    init(kind: Kind, id: String, decision: String) {
        self.kind = kind
        self.id = id
        self.decision = decision
    }
}

// MARK: - Approve/Reject buttons

private struct ApproveRejectBar: View {
    let onDecision: (String) -> Void
    var body: some View {
        HStack(spacing: 10) {
            Button {
                onDecision("rejected")
            } label: {
                Text("Reject").fontWeight(.semibold).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Brand.red)

            Button {
                onDecision("approved")
            } label: {
                Text("Approve").fontWeight(.semibold).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Brand.success)
        }
        .padding(.top, 4)
    }
}

// MARK: - Cards

private struct ApprovalLeaveCard: View {
    let request: LeaveRequest
    let onDecision: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(request.userName ?? "Team member")
                    .font(.subheadline).fontWeight(.bold)
                Spacer()
                if let name = request.leaveTypeName {
                    Text(name).font(.caption).foregroundColor(.secondary)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "calendar").font(.caption2).foregroundColor(.secondary)
                Text("\(LeaveUI.prettyDate(request.fromDate)) – \(LeaveUI.prettyDate(request.toDate))")
                    .font(.caption).foregroundColor(.secondary)
                if let days = request.days {
                    Text("· \(days.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(days)) : String(format: "%.1f", days))d")
                        .font(.caption).foregroundColor(.secondary)
                }
            }
            if let reason = request.reason, !reason.isEmpty {
                Text(reason).font(.caption2).foregroundColor(.secondary).lineLimit(3)
            }
            ApproveRejectBar(onDecision: onDecision)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }
}

private struct ApprovalRegCard: View {
    let item: Regularization
    let onDecision: (String) -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.userName ?? "Team member")
                    .font(.subheadline).fontWeight(.bold)
                Spacer()
                Text(RegularizationType.label(for: item.type))
                    .font(.caption).foregroundColor(.secondary)
            }
            HStack(spacing: 6) {
                Image(systemName: "calendar").font(.caption2).foregroundColor(.secondary)
                Text(LeaveUI.prettyDate(item.attDate)).font(.caption).foregroundColor(.secondary)
            }
            if let reason = item.reason, !reason.isEmpty {
                Text(reason).font(.caption2).foregroundColor(.secondary).lineLimit(3)
            }
            ApproveRejectBar(onDecision: onDecision)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemGroupedBackground)))
    }
}

// MARK: - Decision-note sheet

private struct DecisionNoteSheet: View {
    let context: DecisionContext
    let onConfirm: (String?) async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var isSubmitting = false

    private var isApprove: Bool { context.decision == "approved" }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Note (optional)")) {
                    TextEditor(text: $note).frame(minHeight: 100)
                }
                Section {
                    Button {
                        Task {
                            isSubmitting = true
                            await onConfirm(note.isEmpty ? nil : note)
                            isSubmitting = false
                            dismiss()
                        }
                    } label: {
                        HStack {
                            if isSubmitting { ProgressView().tint(.white) }
                            Text(isSubmitting ? "Saving…" : (isApprove ? "Confirm Approve" : "Confirm Reject"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(isApprove ? Brand.success : Brand.red)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                    }
                    .disabled(isSubmitting)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle(isApprove ? "Approve" : "Reject")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

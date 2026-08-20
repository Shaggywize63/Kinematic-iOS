import SwiftUI

/// Manager approvals for expense claims — pending claims routed up the reporting
/// line, with Approve / Reject (+ optional note). High-value claims escalate to
/// the next manager on approval (server-side). Mirrors LeaveApprovalsView.
struct ExpenseApprovalsView: View {
    @StateObject private var vm = ExpensesViewModel()
    @State private var rejectTarget: String?
    @State private var rejectNote = ""

    var body: some View {
        Group {
            if !vm.didLoad {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.pending.isEmpty {
                ContentUnavailableView("Nothing awaiting approval", systemImage: "checkmark.seal",
                                       description: Text("Claims routed to you will appear here."))
            } else {
                List {
                    if let err = vm.errorMsg { Section { Text(err).font(.caption).foregroundColor(.red) } }
                    Section("Awaiting your approval") {
                        ForEach(vm.pending) { claim in row(claim) }
                    }
                }
            }
        }
        .navigationTitle("Expense Approvals")
        .navigationBarTitleDisplayMode(.inline)
        .task { if !vm.didLoad { await vm.loadPending() } }
        .refreshable { await vm.loadPending() }
        .alert("Reject claim", isPresented: Binding(get: { rejectTarget != nil }, set: { if !$0 { rejectTarget = nil } })) {
            TextField("Note (optional)", text: $rejectNote)
            Button("Reject", role: .destructive) {
                if let id = rejectTarget {
                    let note = rejectNote.isEmpty ? nil : rejectNote
                    Task { await vm.decide(id: id, decision: "rejected", note: note) }
                }
                rejectNote = ""; rejectTarget = nil
            }
            Button("Cancel", role: .cancel) { rejectTarget = nil }
        }
    }

    private func row(_ claim: ExpenseClaim) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(claim.user_name ?? "Team member").font(.subheadline).bold()
            Text(expenseMoney(claim.total_amount, claim.currency) + " · " + (claim.claim_no ?? String((claim.submitted_at ?? "").prefix(10)))
                 + ((claim.current_level ?? 1) > 1 ? " · level \(claim.current_level!)" : ""))
                .font(.caption).foregroundColor(.secondary)
            if let s = claim.ai_summary, !s.isEmpty { Text("🧠 \(s)").font(.caption2).foregroundColor(.secondary) }
            if let flags = claim.ai_flags, !flags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(flags.prefix(4)) { f in
                        Text(f.code.replacingOccurrences(of: "_", with: " "))
                            .font(.caption2).bold()
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .overlay(Capsule().stroke(flagColor(f.severity), lineWidth: 1))
                            .foregroundColor(flagColor(f.severity))
                    }
                }
            }
            if let km = claim.distance_km {
                Text("Mileage claimed \(fmtKm(km)) km" + (claim.gps_derived_km.map { " · GPS \(fmtKm($0)) km" } ?? ""))
                    .font(.caption2).foregroundColor(.secondary)
            }
            HStack {
                Spacer()
                if vm.busyIds.contains(claim.id) {
                    ProgressView()
                } else {
                    Button("Reject", role: .destructive) { rejectTarget = claim.id }
                        .buttonStyle(.bordered).controlSize(.small)
                    Button("Approve") { Task { await vm.decide(id: claim.id, decision: "approved", note: nil) } }
                        .buttonStyle(.borderedProminent).controlSize(.small).tint(.green)
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func flagColor(_ severity: String?) -> Color {
        switch severity { case "high": return .red; case "warn": return .orange; default: return .blue }
    }
    private func fmtKm(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
}

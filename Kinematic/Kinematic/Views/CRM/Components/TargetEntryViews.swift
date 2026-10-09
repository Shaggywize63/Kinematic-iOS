import SwiftUI
import Combine

// MARK: - Log a sale / collection

/// "Log sale" / "Log collection": the amount (required), an optional lead and an optional note. Posts one entry.
/// A broken connection says so and keeps the sheet open — nothing is queued offline. Submitting can't be done twice.
struct LogTargetEntrySheet: View {
    let type: RupeeTargetType
    /// Called once the entry is saved, just before the sheet closes.
    let onLogged: (RupeeTargetType) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var amountText = ""
    @State private var note = ""
    @State private var lead: Lead?
    @State private var showLeadPicker = false
    @State private var submitting = false
    @State private var errorText: String?
    /// One per opened sheet; with the entry's own fields it makes the idempotency key of a retry.
    @State private var attempt = UUID().uuidString
    @FocusState private var amountFocused: Bool

    private var check: RupeeTargets.AmountCheck { RupeeTargets.parseAmount(amountText) }
    private var canSubmit: Bool {
        if case .ok = check { return !submitting }
        return false
    }
    private var title: String { RupeeTargets.logButtonTitle(key: type.key, label: type.label) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 6) {
                        Text("₹").foregroundColor(.secondary)
                        TextField("Amount", text: $amountText)
                            .keyboardType(.decimalPad)
                            .focused($amountFocused)
                            .disabled(submitting)
                    }
                } header: {
                    Text("\(type.label) amount")
                } footer: {
                    // Say what's wrong only once something has been typed.
                    if !amountText.isEmpty, let m = RupeeTargets.message(for: check) {
                        Text(m).foregroundColor(.red)
                    } else if case .ok(let v) = check {
                        Text(RupeeTargets.inr(v))
                    }
                }

                Section("Linked lead (optional)") {
                    Button { showLeadPicker = true } label: {
                        HStack {
                            if let l = lead {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(l.displayName).foregroundColor(.primary)
                                    if let phone = l.phone, !phone.isEmpty {
                                        Text(phone).font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            } else {
                                Text("Choose a lead").foregroundColor(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .disabled(submitting)
                    if lead != nil {
                        Button("Remove lead", role: .destructive) { lead = nil }.disabled(submitting)
                    }
                }

                Section {
                    TextField("Add a note", text: $note, axis: .vertical)
                        .lineLimit(2...5)
                        .disabled(submitting)
                } header: {
                    Text("Note (optional)")
                } footer: {
                    Text("\(note.count)/\(RupeeTargets.maxNoteLength)").frame(maxWidth: .infinity, alignment: .trailing)
                }

                if let e = errorText {
                    Section { Text(e).font(.footnote).foregroundColor(.red) }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(submitting) }
                ToolbarItem(placement: .confirmationAction) {
                    if submitting {
                        ProgressView()
                    } else {
                        Button("Save") { Task { await submit() } }.disabled(!canSubmit)
                    }
                }
            }
            .onChange(of: note) { _, new in
                if new.count > RupeeTargets.maxNoteLength { note = String(new.prefix(RupeeTargets.maxNoteLength)) }
            }
            .onChange(of: amountText) { _, _ in errorText = nil }
            .sheet(isPresented: $showLeadPicker) {
                LeadSearchPickerSheet { picked in lead = picked }
            }
            .interactiveDismissDisabled(submitting)
            .onAppear { amountFocused = true }
        }
    }

    private func submit() async {
        guard !submitting else { return }            // never twice
        guard case .ok(let amount) = check else {
            errorText = RupeeTargets.message(for: check)
            return
        }
        submitting = true
        errorText = nil
        defer { submitting = false }
        let cleaned = RupeeTargets.cleanNote(note)
        let key = RupeeTargets.idempotencyKey(attempt: attempt, kind: type.key, amount: amount, leadId: lead?.id, note: cleaned)
        do {
            try await CRMService.shared.createRupeeTargetEntry(kind: type.key, amount: amount, leadId: lead?.id,
                                                               note: cleaned, idempotencyKey: key)
            onLogged(type)
            dismiss()
        } catch {
            errorText = RupeeTargets.failureMessage(for: error, fallback: "Couldn't save this. Please try again.")
        }
    }
}

// MARK: - Targets history

@MainActor
final class TargetsHistoryViewModel: ObservableObject {
    @Published private(set) var entries: [RupeeTargetEntry] = []
    @Published private(set) var loaded = false
    @Published private(set) var loadError: String?
    /// A failed delete.
    @Published var notice: String?

    func load(from: String?, to: String?) async {
        do {
            let rows = try await CRMService.shared.listRupeeTargetEntries(from: from, to: to, limit: 50)
            if Task.isCancelled { return }
            entries = rows
            loadError = nil
        } catch {
            if Task.isCancelled { return }
            loadError = RupeeTargets.failureMessage(for: error, fallback: "Couldn't load your entries.")
        }
        loaded = true
    }

    /// Returns true when the entry is gone.
    func delete(_ entry: RupeeTargetEntry) async -> Bool {
        do {
            try await CRMService.shared.deleteRupeeTargetEntry(id: entry.id)
            entries.removeAll { $0.id == entry.id }
            return true
        } catch {
            if case CRMServiceError.badResponse(403) = error {
                notice = RupeeTargets.deleteRefused
            } else {
                notice = RupeeTargets.failureMessage(for: error, fallback: "Couldn't delete this entry.")
            }
            return false
        }
    }
}

/// This month's entries: date, kind, amount, lead and note, newest first. Pull to refresh. An entry can be deleted
/// (swipe, then confirm) by the person who logged it, for 24 hours.
struct TargetsHistoryView: View {
    let types: [RupeeTargetType]
    let periodStart: String?
    let periodEnd: String?
    let monthTitle: String?
    /// Something was deleted: the card's figures are out of date.
    let onChanged: () -> Void

    @StateObject private var vm = TargetsHistoryViewModel()
    @State private var pendingDelete: RupeeTargetEntry?

    private var me: String? { Session.currentUser?.id }

    var body: some View {
        Group {
            if !vm.loaded {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let err = vm.loadError, vm.entries.isEmpty {
                ContentUnavailableView {
                    Label("Couldn't load your entries", systemImage: "exclamationmark.triangle")
                } description: { Text(err) } actions: {
                    Button("Try again") { Task { await reload() } }
                }
            } else if vm.entries.isEmpty {
                // In a ScrollView so pulling down still refreshes an empty month.
                ScrollView {
                    ContentUnavailableView("No entries yet", systemImage: "indianrupeesign.circle",
                                           description: Text("What you log this month shows up here."))
                        .frame(maxWidth: .infinity, minHeight: 320)
                }
            } else {
                List {
                    Section {
                        ForEach(vm.entries) { entry in row(entry) }
                    } header: {
                        if let m = monthTitle { Text(m) }
                    } footer: {
                        Text("You can delete an entry within 24 hours of logging it — swipe it left.")
                    }
                }
            }
        }
        .navigationTitle("Targets history")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
        .confirmationDialog("Delete this entry?", isPresented: Binding(get: { pendingDelete != nil },
                                                                       set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { entry in
            Button("Delete", role: .destructive) {
                Task { if await vm.delete(entry) { onChanged() } }
            }
            Button("Keep it", role: .cancel) {}
        } message: { entry in
            Text("\(RupeeTargets.inr(entry.amount)) \(kindName(entry).lowercased()) will be removed from your totals.")
        }
        .alert("Targets", isPresented: Binding(get: { vm.notice != nil }, set: { if !$0 { vm.notice = nil } })) {
            Button("OK", role: .cancel) { vm.notice = nil }
        } message: { Text(vm.notice ?? "") }
    }

    private func reload() async { await vm.load(from: periodStart, to: periodEnd) }

    private func kindName(_ e: RupeeTargetEntry) -> String {
        types.first { $0.key == e.kind }?.label ?? RupeeTargets.defaultLabel(for: e.kind)
    }

    private func row(_ e: RupeeTargetEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(RupeeTargets.inr(e.amount)).font(.headline)
                Spacer()
                Text(kindName(e)).font(.caption2.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Brand.red.opacity(0.12)).foregroundColor(Brand.red).clipShape(Capsule())
            }
            Text(ExpenseLogic.shortDate(e.entryDate) ?? "—").font(.caption).foregroundColor(.secondary)
            if let name = e.leadName, !name.isEmpty {
                Label(name, systemImage: "person.fill").font(.subheadline).foregroundColor(.secondary)
            }
            if let n = e.note, !n.isEmpty {
                Text(n).font(.subheadline)
            }
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if RupeeTargets.canDelete(createdAt: e.createdAt, entryUserId: e.userId, currentUserId: me, now: Date()) {
                Button(role: .destructive) { pendingDelete = e } label: { Label("Delete", systemImage: "trash") }
            }
        }
    }
}

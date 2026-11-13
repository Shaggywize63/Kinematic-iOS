import SwiftUI

/// "My Tasks" — the signed-in user's own assigned tasks, grouped into
/// Overdue / Today / Upcoming / No date (soonest-due first), each row showing
/// who assigned it. Core CRM for ALL tenants (not feature-gated). Consumes
/// `GET /api/v1/crm/my-tasks`.
struct MyTasksView: View {
    @StateObject private var vm = MyTasksViewModel()

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            content
        }
        .navigationTitle("My Tasks")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            // Load once; the controls drive their own refetch on change.
            if !vm.didLoad { await vm.refresh() }
        }
    }

    // MARK: Filter controls

    private var controls: some View {
        VStack(spacing: 10) {
            Picker("Status", selection: Binding(
                get: { vm.statusFilter },
                set: { choice in Task { await vm.setStatus(choice) } }
            )) {
                ForEach(MyTasksStatusFilter.allCases) { f in
                    Text(f.title).tag(f)
                }
            }
            .pickerStyle(.segmented)

            Toggle(isOn: Binding(
                get: { vm.overdueOnly },
                set: { on in Task { await vm.setOverdueOnly(on) } }
            )) {
                Label("Overdue only", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
            }
            .tint(Brand.red)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: Body states

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && vm.tasks.isEmpty {
            loadingState
        } else if let message = vm.errorMessage, vm.tasks.isEmpty {
            errorState(message)
        } else if vm.tasks.isEmpty {
            emptyState
        } else {
            list
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
            Text("Loading your tasks…")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 34))
                .foregroundColor(Brand.caution)
            Text("Couldn't load your tasks")
                .font(.system(size: 16, weight: .semibold))
            Text(message)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Try again") { Task { await vm.refresh() } }
                .buttonStyle(.borderedProminent)
                .tint(Brand.red)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 40))
                .foregroundColor(Brand.success)
            Text("You're all caught up")
                .font(.system(size: 16, weight: .semibold))
            Text(vm.overdueOnly
                 ? "No overdue tasks assigned to you."
                 : "No tasks match this filter right now.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var list: some View {
        List {
            ForEach(vm.sections) { group in
                Section {
                    ForEach(group.tasks) { task in
                        MyTaskRow(task: task)
                    }
                } header: {
                    HStack {
                        Text(group.title.uppercased())
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(group.section == .overdue ? Brand.red : .secondary)
                        Spacer()
                        Text("\(group.tasks.count)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable { await vm.refresh() }
    }
}

/// One task row. Navigates to the linked lead when there is one; otherwise it
/// is a plain, non-tappable row (the task may link only a contact / deal).
private struct MyTaskRow: View {
    let task: MyTask

    var body: some View {
        if let leadId = task.leadId, !leadId.isEmpty {
            NavigationLink(destination: LeadDetailView(leadId: leadId)) {
                rowBody
            }
        } else {
            rowBody
        }
    }

    private var rowBody: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(task.displayTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(2)
                Spacer(minLength: 8)
                statusPill
            }

            if let linked = task.linkedName {
                Label(linked, systemImage: "person.crop.circle")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 10) {
                if let due = dueText {
                    Label(due, systemImage: "calendar")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(task.isOverdue ? Brand.red : .secondary)
                }
                if let assignedBy = MyTasksLogic.assignedByDisplay(task) {
                    Label(assignedBy, systemImage: "person.badge.shield.checkmark")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: Status pill

    private var statusPill: some View {
        Text(statusLabel)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(statusColor.opacity(0.16))
            .foregroundColor(statusColor)
            .clipShape(Capsule())
    }

    private var statusLabel: String {
        if task.isOverdue { return "OVERDUE" }
        switch task.effectiveStatus {
        case "in_progress": return "IN PROGRESS"
        case "completed":   return "COMPLETED"
        case "cancelled", "canceled": return "CANCELLED"
        default:            return "OPEN"
        }
    }

    private var statusColor: Color {
        if task.isOverdue { return Brand.red }
        switch task.effectiveStatus {
        case "in_progress": return Brand.info
        case "completed":   return Brand.success
        case "cancelled", "canceled": return .secondary
        default:            return Brand.caution
        }
    }

    // MARK: Due date text

    private var dueText: String? {
        guard let date = MyTasksLogic.dueDate(task) else { return nil }
        let df = DateFormatter()
        df.dateFormat = Calendar.current.isDateInToday(date) ? "'Today' h:mm a" : "d MMM, h:mm a"
        return df.string(from: date)
    }
}

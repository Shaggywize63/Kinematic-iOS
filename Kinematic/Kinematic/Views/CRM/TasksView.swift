import SwiftUI
import Combine

/// Tasks inbox grouped by urgency. Replaces the older wrapper that just
/// delegated to ActivitiesView with a type filter — that gave a flat list
/// with no notion of overdue / today / this-week, which is what reps
/// actually need to triage their day.
struct TasksView: View {
    @StateObject private var vm = TasksInboxViewModel()
    @State private var showCompleted = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if vm.isLoading && vm.tasks.isEmpty {
                    ProgressView().padding(.top, 80).frame(maxWidth: .infinity)
                } else if vm.tasks.isEmpty {
                    emptyState
                } else {
                    let groups = vm.grouped
                    section("Overdue", tasks: groups.overdue, accent: .red)
                    section("Today", tasks: groups.today, accent: .blue)
                    section("This week", tasks: groups.thisWeek, accent: .teal)
                    section("Later", tasks: groups.later, accent: .gray)

                    if !groups.completed.isEmpty {
                        Button(action: { withAnimation { showCompleted.toggle() } }) {
                            HStack {
                                Text("Completed (\(groups.completed.count))")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.gray)
                                Spacer()
                                Text(showCompleted ? "Hide" : "Show")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(.blue)
                            }
                            .padding(.horizontal, 4)
                        }
                        .padding(.top, 4)
                        if showCompleted {
                            ForEach(groups.completed) { t in TaskRow(task: t, accent: .gray, onToggle: { Task { await vm.toggle(t) } }) }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Tasks")
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    private func section(_ label: String, tasks: [CRMTask], accent: Color) -> some View {
        Group {
            if !tasks.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Circle().fill(accent).frame(width: 8, height: 8)
                        Text(label.uppercased()).font(.system(size: 11, weight: .black)).tracking(1)
                        Text("\(tasks.count)").font(.system(size: 11, weight: .heavy)).foregroundColor(.secondary)
                        Spacer()
                    }
                    ForEach(tasks) { t in TaskRow(task: t, accent: accent, onToggle: { Task { await vm.toggle(t) } }) }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist").font(.system(size: 40)).foregroundColor(.gray.opacity(0.4))
            Text("Inbox zero").font(.headline)
            Text("Tasks added against leads or deals will show up here.")
                .font(.caption).foregroundColor(.gray).multilineTextAlignment(.center)
        }
        .padding(.top, 60)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Row

private struct TaskRow: View {
    let task: CRMTask
    let accent: Color
    let onToggle: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundColor(task.isDone ? accent : .gray)
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.subject ?? "Untitled task")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(task.isDone ? .secondary : Color(uiColor: .label))
                    .strikethrough(task.isDone)
                HStack(spacing: 8) {
                    if let due = task.dueAt {
                        Text(humanizeDue(due))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(isOverdue(due) && !task.isDone ? .red : .secondary)
                    }
                    if let (icon, label) = parentBadge(task) {
                        HStack(spacing: 3) {
                            Image(systemName: icon).font(.system(size: 10))
                            Text(label).font(.system(size: 11))
                        }
                        .foregroundColor(.secondary)
                    }
                    Spacer()
                    if task.priority == "high" || task.priority == "urgent" {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
    }
}

// MARK: - VM

@MainActor
final class TasksInboxViewModel: ObservableObject {
    @Published var tasks: [CRMTask] = []
    @Published var isLoading = false
    private let api = CRMService.shared

    struct Groups {
        let overdue: [CRMTask]
        let today: [CRMTask]
        let thisWeek: [CRMTask]
        let later: [CRMTask]
        let completed: [CRMTask]
    }

    var grouped: Groups {
        let today = Calendar.current.startOfDay(for: Date())
        let endOfWeek = Calendar.current.date(byAdding: .day, value: 7, to: today) ?? today
        var overdue: [CRMTask] = []
        var now: [CRMTask] = []
        var week: [CRMTask] = []
        var later: [CRMTask] = []
        var done: [CRMTask] = []
        for t in tasks {
            if t.isDone { done.append(t); continue }
            guard let dueStr = t.dueAt, let due = parseDate(dueStr) else { later.append(t); continue }
            let dueDay = Calendar.current.startOfDay(for: due)
            if dueDay < today { overdue.append(t) }
            else if dueDay == today { now.append(t) }
            else if dueDay < endOfWeek { week.append(t) }
            else { later.append(t) }
        }
        return Groups(
            overdue: overdue.sorted { ($0.dueAt ?? "") < ($1.dueAt ?? "") },
            today: now.sorted { ($0.dueAt ?? "") < ($1.dueAt ?? "") },
            thisWeek: week.sorted { ($0.dueAt ?? "") < ($1.dueAt ?? "") },
            later: later.sorted { ($0.dueAt ?? "9999") < ($1.dueAt ?? "9999") },
            completed: done.sorted { ($0.completedAt ?? $0.dueAt ?? "") > ($1.completedAt ?? $1.dueAt ?? "") }
        )
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do { tasks = try await api.listTasks() } catch { tasks = [] }
    }

    func toggle(_ task: CRMTask) async {
        let next = task.isDone ? "open" : "done"
        guard let updated = try? await api.setTaskStatus(id: task.id, status: next) else { return }
        if let i = tasks.firstIndex(where: { $0.id == task.id }) { tasks[i] = updated }
    }
}

// MARK: - Helpers

private func parseDate(_ iso: String) -> Date? {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = f.date(from: iso) { return d }
    f.formatOptions = [.withInternetDateTime]
    return f.date(from: iso)
}

private func isOverdue(_ iso: String) -> Bool {
    guard let d = parseDate(iso) else { return false }
    return Calendar.current.startOfDay(for: d) < Calendar.current.startOfDay(for: Date())
}

private func humanizeDue(_ iso: String) -> String {
    guard let d = parseDate(iso) else { return iso }
    let cal = Calendar.current
    let dueDay = cal.startOfDay(for: d)
    let today = cal.startOfDay(for: Date())
    let days = cal.dateComponents([.day], from: today, to: dueDay).day ?? 0
    if days < 0 {
        let abs = -days
        return abs == 1 ? "Yesterday" : "\(abs)d overdue"
    }
    if days == 0 { return "Today" }
    if days == 1 { return "Tomorrow" }
    let df = DateFormatter(); df.dateFormat = "d MMM"
    return df.string(from: d)
}

private func parentBadge(_ t: CRMTask) -> (String, String)? {
    if (t.dealId ?? "").isEmpty == false { return ("briefcase.fill", "Deal") }
    if (t.leadId ?? "").isEmpty == false { return ("person.fill.badge.plus", "Lead") }
    if (t.contactId ?? "").isEmpty == false { return ("person.fill", "Contact") }
    if (t.accountId ?? "").isEmpty == false { return ("building.2.fill", "Account") }
    return nil
}

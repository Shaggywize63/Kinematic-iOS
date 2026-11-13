import Foundation

/// The four buckets the "My Tasks" screen groups rows into, in render order.
enum MyTaskSection: String, CaseIterable, Hashable {
    case overdue
    case today
    case upcoming
    case noDate

    var title: String {
        switch self {
        case .overdue:  return "Overdue"
        case .today:    return "Today"
        case .upcoming: return "Upcoming"
        case .noDate:   return "No date"
        }
    }
}

/// One rendered section: its bucket + the tasks in it (already sorted).
struct MyTaskSectionGroup: Identifiable, Hashable {
    let section: MyTaskSection
    let tasks: [MyTask]
    var id: String { section.rawValue }
    var title: String { section.title }
}

/// Pure, test-covered logic for the My Tasks screen: which section a task
/// lands in (from `due_at` + `is_overdue`), the within-section sort (soonest
/// due first), the "Assigned by …" display rule, and the query params sent to
/// `/crm/my-tasks`. Kept free of SwiftUI / networking so it can be unit-tested
/// against fixed clocks and fixtures.
enum MyTasksLogic {

    // MARK: Date parsing

    /// `due_at` / `created_at` arrive as ISO-8601, with or without fractional
    /// seconds, so try both — the same tolerance the activities timeline uses.
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let isoPlain = ISO8601DateFormatter()

    static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return isoFractional.date(from: raw) ?? isoPlain.date(from: raw)
    }

    static func dueDate(_ task: MyTask) -> Date? { parseDate(task.dueAt) }

    // MARK: Section assignment

    /// Which bucket a task belongs to.
    ///
    /// Rule (deterministic, and trusts the server's `is_overdue` first):
    /// - no / unparseable `due_at`            → **No date**
    /// - `is_overdue` true                    → **Overdue**
    /// - due date before the start of today   → **Overdue**
    /// - due date falls on today              → **Today**
    /// - due date after today                 → **Upcoming**
    static func section(for task: MyTask, now: Date = Date(), calendar: Calendar = .current) -> MyTaskSection {
        guard let due = dueDate(task) else { return .noDate }
        if task.isOverdue { return .overdue }
        let startOfToday = calendar.startOfDay(for: now)
        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
            return .upcoming
        }
        if due < startOfToday { return .overdue }
        if due < startOfTomorrow { return .today }
        return .upcoming
    }

    // MARK: Grouping + sort

    /// Group tasks into the non-empty sections, in fixed render order, each
    /// sorted soonest-due first. Dated sections sort ascending by `due_at`
    /// (earliest / most-overdue at the top); the No-date section sorts
    /// newest-created first. Ties break on `id` for a stable order.
    static func grouped(_ tasks: [MyTask], now: Date = Date(), calendar: Calendar = .current) -> [MyTaskSectionGroup] {
        var buckets: [MyTaskSection: [MyTask]] = [:]
        for task in tasks {
            buckets[section(for: task, now: now, calendar: calendar), default: []].append(task)
        }
        return MyTaskSection.allCases.compactMap { sec in
            guard let rows = buckets[sec], !rows.isEmpty else { return nil }
            let sorted = rows.sorted { a, b in
                if sec == .noDate {
                    // Newest-created first; no due date to order by.
                    let da = parseDate(a.createdAt) ?? .distantPast
                    let db = parseDate(b.createdAt) ?? .distantPast
                    if da != db { return da > db }
                    return a.id < b.id
                }
                let da = dueDate(a) ?? .distantFuture
                let db = dueDate(b) ?? .distantFuture
                if da != db { return da < db }
                return a.id < b.id
            }
            return MyTaskSectionGroup(section: sec, tasks: sorted)
        }
    }

    // MARK: "Assigned by …" display rule

    /// The "Assigned by {name}" line for a row, or nil when there is no
    /// assigner name (self-created tasks) so the row hides the line.
    static func assignedByDisplay(_ task: MyTask) -> String? {
        guard let name = task.assignedByName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty else { return nil }
        return "Assigned by \(name)"
    }

    // MARK: Query params

    /// Build the `/crm/my-tasks` query string from the screen's controls.
    /// `status` is dropped when nil / empty / "all"; `overdue` only sent when
    /// true; `from` / `to` only when non-empty. `page` / `limit` optional.
    static func queryParams(status: String? = nil,
                            overdue: Bool = false,
                            from: String? = nil,
                            to: String? = nil,
                            page: Int? = nil,
                            limit: Int? = nil) -> [String: String] {
        var q: [String: String] = [:]
        if let s = status?.trimmingCharacters(in: .whitespacesAndNewlines),
           !s.isEmpty, s.lowercased() != "all" {
            q["status"] = s
        }
        if overdue { q["overdue"] = "true" }
        if let from = from?.trimmingCharacters(in: .whitespacesAndNewlines), !from.isEmpty { q["from"] = from }
        if let to = to?.trimmingCharacters(in: .whitespacesAndNewlines), !to.isEmpty { q["to"] = to }
        if let page { q["page"] = String(page) }
        if let limit { q["limit"] = String(limit) }
        return q
    }
}

/// The status filter the screen offers (All / Open / In progress / Completed).
/// `apiValue` maps each choice to the `status` query value (nil = All).
enum MyTasksStatusFilter: String, CaseIterable, Identifiable {
    case all
    case open
    case inProgress
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:        return "All"
        case .open:       return "Open"
        case .inProgress: return "In progress"
        case .completed:  return "Completed"
        }
    }

    /// The `status` query value for this choice; nil for All.
    var apiValue: String? {
        switch self {
        case .all:        return nil
        case .open:       return "open"
        case .inProgress: return "in_progress"
        case .completed:  return "completed"
        }
    }
}

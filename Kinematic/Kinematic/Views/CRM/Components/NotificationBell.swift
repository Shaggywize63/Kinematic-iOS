import SwiftUI

/// Reusable notification bell for the CRM module.
/// Polls `/api/v1/crm/activities/calendar` (±7 days) every 60 seconds for
/// incomplete activities with a due date — matches dashboard NotificationBell.tsx.
///
/// Badge is red if any activity is overdue, blue otherwise. Tap presents a
/// sheet with the upcoming activity list.
struct NotificationBell: View {
    @State private var activities: [Activity] = []
    @State private var showList = false
    @State private var pollTask: Task<Void, Never>?

    private var unread: [Activity] {
        activities
            .filter { $0.completedAt == nil && $0.dueAt != nil }
            .sorted { ($0.dueAt ?? "") < ($1.dueAt ?? "") }
    }

    private var overdueCount: Int {
        unread.filter { isOverdue($0.dueAt) }.count
    }

    var body: some View {
        Button { showList = true } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(uiColor: .label))
                if !unread.isEmpty {
                    Text("\(min(unread.count, 99))")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(overdueCount > 0 ? Color.red : Brand.red)
                        .clipShape(Capsule())
                        .offset(x: 8, y: -6)
                }
            }
            .frame(width: 32, height: 32)
        }
        .sheet(isPresented: $showList) {
            NotificationListSheet(activities: unread, reload: load)
        }
        .task { startPolling() }
        .onDisappear { pollTask?.cancel() }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            await load()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                await load()
            }
        }
    }

    private func load() async {
        let f = ISO8601DateFormatter()
        let from = f.string(from: Date().addingTimeInterval(-7 * 86400))
        let to   = f.string(from: Date().addingTimeInterval( 7 * 86400))
        if let list = try? await CRMService.shared.activitiesCalendar(from: from, to: to) {
            await MainActor.run { activities = list }
        }
    }

    private func isOverdue(_ iso: String?) -> Bool {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return false }
        return d.timeIntervalSinceNow < 0
    }
}

private struct NotificationListSheet: View {
    let activities: [Activity]
    let reload: () async -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if activities.isEmpty {
                    Text("No upcoming activities.").foregroundColor(.secondary).font(.caption)
                } else {
                    ForEach(activities, id: \.id) { a in
                        NotificationActivityRow(activity: a)
                    }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
                }
            }
            .refreshable { await reload() }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct NotificationActivityRow: View {
    let activity: Activity

    var body: some View {
        HStack(spacing: 10) {
            if activity.type == "whatsapp" {
                // Render the brand SVG instead of an emoji — the
                // previous 💚 heart was the wrong glyph and users
                // have flagged it multiple times.
                WhatsAppLogo(size: 20)
            } else {
                Text(emoji(for: activity.type))
                    .font(.system(size: 22))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(activity.subject ?? activity.type?.capitalized ?? "Activity")
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                if let body = activity.description, !body.isEmpty {
                    Text(body).font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text(relativeDue(activity.dueAt))
                .font(.caption2).fontWeight(.bold)
                .foregroundColor(isOverdue(activity.dueAt) ? .red : Brand.red)
        }
        .padding(.vertical, 4)
    }

    private func emoji(for type: String?) -> String {
        switch type ?? "" {
        case "call":     return "📞"
        case "email":    return "✉️"
        case "meeting":  return "📅"
        case "task":     return "✅"
        case "note":     return "📝"
        case "sms":      return "💬"
        // whatsapp is rendered via WhatsAppLogo, not an emoji.
        default:         return "🔔"
        }
    }

    private func isOverdue(_ iso: String?) -> Bool {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return false }
        return d.timeIntervalSinceNow < 0
    }

    private func relativeDue(_ iso: String?) -> String {
        guard let iso, let d = ISO8601DateFormatter().date(from: iso) else { return "" }
        let delta = d.timeIntervalSinceNow
        let abs = Swift.abs(delta)
        let label: String
        if abs < 3600 { label = "\(Int(abs / 60))m" }
        else if abs < 86400 { label = "\(Int(abs / 3600))h" }
        else { label = "\(Int(abs / 86400))d" }
        return delta < 0 ? "\(label) overdue" : "in \(label)"
    }
}

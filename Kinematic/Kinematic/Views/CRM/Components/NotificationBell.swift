import SwiftUI

/// Notification bell → in-app Notification Center. Reads the backend
/// notification feed (`/api/v1/notifications`): stagnant-lead nudges, deals
/// closing, tasks overdue, broadcasts. The badge shows the unread count; the
/// sheet lists each notification with its full detail, and tapping one opens
/// the related lead (deep-link) and marks it read.
struct NotificationBell: View {
    @State private var notifications: [CRMNotification] = []
    @State private var showList = false
    @State private var pollTask: Task<Void, Never>?

    private var unreadCount: Int { notifications.filter { !($0.isRead ?? false) }.count }

    var body: some View {
        Button { showList = true } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(Color(uiColor: .label))
                if unreadCount > 0 {
                    Text("\(min(unreadCount, 99))")
                        .font(.system(size: 10, weight: .black))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .background(Color.red)
                        .clipShape(Capsule())
                        .offset(x: 8, y: -6)
                }
            }
            .frame(width: 32, height: 32)
        }
        .sheet(isPresented: $showList) {
            NotificationCenterView(notifications: notifications, reload: load, onRead: markRead, onClearAll: clearAll)
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
        if let list = try? await CRMService.shared.listNotifications() {
            await MainActor.run { notifications = list }
        }
    }

    private func markRead(_ id: String) {
        // Optimistic local update + fire the PATCH.
        if let i = notifications.firstIndex(where: { $0.id == id }) {
            let n = notifications[i]
            notifications[i] = CRMNotification(id: n.id, title: n.title, body: n.body, data: n.data, isRead: true, createdAt: n.createdAt)
        }
        Task { await CRMService.shared.markNotificationRead(id: id) }
    }

    /// "Clear all" empties the entire list (deletes every notification),
    /// not just marks them read.
    private func clearAll() {
        notifications = []
        Task { await CRMService.shared.clearNotifications() }
    }
}

private struct NotificationCenterView: View {
    let notifications: [CRMNotification]
    let reload: () async -> Void
    let onRead: (String) -> Void
    let onClearAll: () -> Void
    @Environment(\.dismiss) private var dismiss

    private var hasUnread: Bool { notifications.contains { !($0.isRead ?? false) } }

    var body: some View {
        NavigationStack {
            List {
                if notifications.isEmpty {
                    Text("You're all caught up — no notifications.").foregroundColor(.secondary).font(.caption)
                } else {
                    ForEach(notifications) { n in
                        // Lead notifications take precedence — most CRM
                        // nudges (stagnant lead, lead assigned) point at
                        // a lead. Fall through to dealId for deal-side
                        // events (closing-soon, overdue). Notifications
                        // without either id just mark themselves read on
                        // tap (broadcasts, system messages).
                        if let leadId = n.leadId {
                            NavigationLink(destination: LeadDetailView(leadId: leadId)) {
                                NotificationRow(n: n)
                            }
                            .simultaneousGesture(TapGesture().onEnded { onRead(n.id) })
                        } else if let dealId = n.dealId {
                            NavigationLink(destination: DealDetailView(dealId: dealId)) {
                                NotificationRow(n: n)
                            }
                            .simultaneousGesture(TapGesture().onEnded { onRead(n.id) })
                        } else {
                            NotificationRow(n: n)
                                .contentShape(Rectangle())
                                .onTapGesture { onRead(n.id) }
                        }
                    }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 14) {
                        if !notifications.isEmpty {
                            Button("Clear all") { onClearAll() }
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Button { Task { await reload() } } label: { Image(systemName: "arrow.clockwise") }
                    }
                }
            }
            .refreshable { await reload() }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct NotificationRow: View {
    let n: CRMNotification

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill((n.isRead ?? false ? Color.gray : Brand.red).opacity(0.15)).frame(width: 36, height: 36)
                Image(systemName: icon(for: n.kind)).foregroundColor(n.isRead ?? false ? .gray : Brand.red).font(.system(size: 15))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(n.title ?? "Notification")
                    .font(.system(size: 14, weight: (n.isRead ?? false) ? .regular : .bold))
                    .lineLimit(2)
                if let body = n.body, !body.isEmpty {
                    Text(body).font(.caption).foregroundColor(.secondary).lineLimit(3)
                }
            }
            Spacer()
            if !(n.isRead ?? false) {
                Circle().fill(Brand.red).frame(width: 8, height: 8)
            }
        }
        .padding(.vertical, 4)
    }

    private func icon(for kind: String?) -> String {
        switch kind ?? "" {
        case "crm_lead_stagnant", "crm_lead_stagnant_escalation": return "person.fill.questionmark"
        case "crm_deal_closing_soon": return "calendar.badge.clock"
        case "crm_deal_overdue":      return "exclamationmark.triangle.fill"
        case "crm_task_overdue":      return "checklist"
        default:                       return "bell.fill"
        }
    }
}

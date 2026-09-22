//
//  KinematicLeadWidget.swift
//  KinematicWidget
//
//  "Leads" home-screen widget — new/unworked count, my open pipeline,
//  follow-ups due today, and the latest few leads. Reads the shared
//  App Group cache that the host app refreshes from
//  GET /api/v1/crm/widgets/lead-summary. Tapping opens the app to the
//  Leads tab; the small size carries a quick "Add lead" action.
//
//  Read-only in the extension: the app fetches + writes the cache, the
//  widget only renders it (no auth token lives in the widget).
//

import WidgetKit
import SwiftUI

// MARK: - Timeline data

struct LeadWidgetEntry: TimelineEntry {
    let date: Date
    let newCount: Int
    let openCount: Int
    let followupsDueToday: Int
    let recent: [RecentLead]
    let refreshedAt: Date?

    struct RecentLead: Identifiable {
        let id: String
        let name: String
        let status: String?
    }

    static let placeholder = LeadWidgetEntry(
        date: Date(), newCount: 8, openCount: 42, followupsDueToday: 5,
        recent: [
            .init(id: "1", name: "Acme Steel", status: "new"),
            .init(id: "2", name: "Ravi Sharma", status: "working"),
            .init(id: "3", name: "BuildCo", status: "qualified"),
        ],
        refreshedAt: Date()
    )
    static let empty = LeadWidgetEntry(
        date: Date(), newCount: 0, openCount: 0, followupsDueToday: 0, recent: [], refreshedAt: nil
    )
}

// MARK: - Shared cache (App Group)

enum LeadWidgetCache {
    static let appGroup = "group.com.shaggywize63.kinematic"
    static let key = "kinematic_widget_lead_v1"

    static func read() -> LeadWidgetEntry? {
        guard let store = UserDefaults(suiteName: appGroup),
              let data = store.data(forKey: key),
              let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        let recentRaw = (raw["recent"] as? [[String: Any]]) ?? []
        let recent = recentRaw.prefix(5).map { r in
            LeadWidgetEntry.RecentLead(
                id: (r["id"] as? String) ?? UUID().uuidString,
                name: (r["name"] as? String) ?? "Lead",
                status: r["status"] as? String
            )
        }
        let ts = raw["refreshed_at"] as? TimeInterval
        return LeadWidgetEntry(
            date: Date(),
            newCount: (raw["new_count"] as? Int) ?? 0,
            openCount: (raw["open_count"] as? Int) ?? 0,
            followupsDueToday: (raw["followups_due_today"] as? Int) ?? 0,
            recent: Array(recent),
            refreshedAt: ts.map { Date(timeIntervalSince1970: $0) }
        )
    }
}

// MARK: - Provider

struct LeadWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> LeadWidgetEntry { .placeholder }
    func getSnapshot(in context: Context, completion: @escaping (LeadWidgetEntry) -> Void) {
        completion(LeadWidgetCache.read() ?? .placeholder)
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<LeadWidgetEntry>) -> Void) {
        let entry = LeadWidgetCache.read() ?? .empty
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Widget

struct KinematicLeadWidget: Widget {
    let kind = "KinematicLeadWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: LeadWidgetProvider()) { entry in
            LeadWidgetView(entry: entry)
        }
        .configurationDisplayName("Kinematic Leads")
        .description("New leads, your open pipeline, follow-ups due today, and the latest leads.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Views

struct LeadWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: LeadWidgetEntry
    var body: some View {
        Group {
            switch family {
            case .systemSmall: LeadWidgetSmall(entry: entry)
            default:           LeadWidgetMedium(entry: entry)
            }
        }
        .kinematicWidgetChrome()
    }
}

private struct LeadWidgetSmall: View {
    let entry: LeadWidgetEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            BrandPill(markOnly: true)
            Spacer(minLength: 2)
            Text("New leads")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            Text(lfmt(entry.newCount))
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .minimumScaleFactor(0.5)
            Spacer(minLength: 2)
            // Quick action — opens the app to the lead-create form.
            Link(destination: URL(string: "kinematic://new-lead")!) {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add lead").font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(.white)
                .padding(.vertical, 5).padding(.horizontal, 9)
                .background(Color.white.opacity(0.18), in: Capsule())
            }
        }
        .padding(14)
        .widgetURL(URL(string: "kinematic://leads"))
    }
}

private struct LeadWidgetMedium: View {
    let entry: LeadWidgetEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                BrandPill()
                Spacer()
                Text(lupdated(entry.refreshedAt))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }
            HStack(spacing: 14) {
                LeadStat(label: "New", value: lfmt(entry.newCount))
                LeadStat(label: "Open", value: lfmt(entry.openCount))
                LeadStat(label: "Due today", value: lfmt(entry.followupsDueToday))
            }
            if entry.recent.isEmpty {
                Spacer(minLength: 0)
                Text("No recent leads")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(entry.recent.prefix(3)) { l in
                        Link(destination: URL(string: "kinematic://lead?id=\(l.id)")!) {
                            HStack(spacing: 6) {
                                Circle().fill(Color.white.opacity(0.8)).frame(width: 5, height: 5)
                                Text(l.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                                    .foregroundColor(.white)
                                Spacer(minLength: 4)
                                if let s = l.status, !s.isEmpty {
                                    Text(s.capitalized).font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white.opacity(0.7))
                                }
                            }
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .widgetURL(URL(string: "kinematic://leads"))
    }
}

private struct LeadStat: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold)).tracking(0.6)
                .foregroundColor(.white.opacity(0.6))
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(.white).minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Local formatters (file-private; the base widget's are private too)

private func lfmt(_ n: Int) -> String {
    if n >= 100_000 { return String(format: "%.1fL", Double(n) / 100_000.0) }
    return NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal)
}
private func lupdated(_ at: Date?) -> String {
    guard let at = at else { return "" }
    let mins = Int(Date().timeIntervalSince(at) / 60)
    if mins < 1 { return "Just now" }
    if mins < 60 { return "\(mins)m ago" }
    if mins < 1440 { return "\(mins / 60)h ago" }
    return "\(mins / 1440)d ago"
}

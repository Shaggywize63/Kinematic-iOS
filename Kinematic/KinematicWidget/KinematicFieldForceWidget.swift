//
//  KinematicFieldForceWidget.swift
//  KinematicWidget
//
//  "Field Force" home-screen widget. Role-aware from the cached payload:
//  a field executive sees "My Day" (check-in status, visited vs planned,
//  working minutes) with a quick Check-in action; a manager sees the
//  team snapshot (checked-in / active / TFF / SOS). Reads the shared App
//  Group cache the host app refreshes from /analytics/mobile-home (FE)
//  and /misc/dashboard-summary (manager).
//

import WidgetKit
import SwiftUI

// MARK: - Timeline data

struct FieldForceEntry: TimelineEntry {
    let date: Date
    let isManager: Bool
    // FE ("My Day")
    let checkedIn: Bool
    let workingMinutes: Int
    let visited: Int
    let planned: Int
    // Manager ("Team")
    let teamCheckedIn: Int
    let teamActive: Int
    let teamTff: Int
    let sosAlerts: Int
    let refreshedAt: Date?

    static let placeholderFE = FieldForceEntry(
        date: Date(), isManager: false, checkedIn: true, workingMinutes: 214,
        visited: 4, planned: 7, teamCheckedIn: 0, teamActive: 0, teamTff: 0, sosAlerts: 0,
        refreshedAt: Date()
    )
    static let placeholderMgr = FieldForceEntry(
        date: Date(), isManager: true, checkedIn: false, workingMinutes: 0,
        visited: 0, planned: 0, teamCheckedIn: 28, teamActive: 22, teamTff: 143, sosAlerts: 1,
        refreshedAt: Date()
    )
    static let empty = FieldForceEntry(
        date: Date(), isManager: false, checkedIn: false, workingMinutes: 0,
        visited: 0, planned: 0, teamCheckedIn: 0, teamActive: 0, teamTff: 0, sosAlerts: 0,
        refreshedAt: nil
    )
}

// MARK: - Shared cache (App Group)

enum FieldForceWidgetCache {
    static let appGroup = "group.com.shaggywize63.kinematic"
    static let key = "kinematic_widget_ff_v1"

    static func read() -> FieldForceEntry? {
        guard let store = UserDefaults(suiteName: appGroup),
              let data = store.data(forKey: key),
              let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        let ts = raw["refreshed_at"] as? TimeInterval
        return FieldForceEntry(
            date: Date(),
            isManager: (raw["is_manager"] as? Bool) ?? false,
            checkedIn: (raw["checked_in"] as? Bool) ?? false,
            workingMinutes: (raw["working_minutes"] as? Int) ?? 0,
            visited: (raw["visited"] as? Int) ?? 0,
            planned: (raw["planned"] as? Int) ?? 0,
            teamCheckedIn: (raw["team_checked_in"] as? Int) ?? 0,
            teamActive: (raw["team_active"] as? Int) ?? 0,
            teamTff: (raw["team_tff"] as? Int) ?? 0,
            sosAlerts: (raw["sos_alerts"] as? Int) ?? 0,
            refreshedAt: ts.map { Date(timeIntervalSince1970: $0) }
        )
    }
}

// MARK: - Provider

struct FieldForceProvider: TimelineProvider {
    func placeholder(in context: Context) -> FieldForceEntry { .placeholderFE }
    func getSnapshot(in context: Context, completion: @escaping (FieldForceEntry) -> Void) {
        completion(FieldForceWidgetCache.read() ?? .placeholderFE)
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FieldForceEntry>) -> Void) {
        let entry = FieldForceWidgetCache.read() ?? .empty
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Widget

struct KinematicFieldForceWidget: Widget {
    let kind = "KinematicFieldForceWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FieldForceProvider()) { entry in
            FieldForceWidgetView(entry: entry)
        }
        .configurationDisplayName("Kinematic Field Force")
        .description("Your day at a glance — check-in, visits vs plan, working hours. Managers see the team snapshot.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Views

struct FieldForceWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: FieldForceEntry
    var body: some View {
        ZStack {
            BrandGradient()
            if entry.isManager {
                FFTeamView(entry: entry, compact: family == .systemSmall)
            } else {
                FFMyDayView(entry: entry, compact: family == .systemSmall)
            }
        }
        .containerBackground(for: .widget) { BrandGradient() }
    }
}

private struct FFMyDayView: View {
    let entry: FieldForceEntry
    let compact: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                BrandPill()
                Spacer()
                if !compact {
                    Text(ffUpdated(entry.refreshedAt))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            HStack(spacing: 6) {
                Circle().fill(entry.checkedIn ? Color.green : Color.white.opacity(0.5))
                    .frame(width: 8, height: 8)
                Text(entry.checkedIn ? "Checked in" : "Not checked in")
                    .font(.system(size: 12, weight: .bold)).foregroundColor(.white)
            }
            Text("\(entry.visited)/\(entry.planned) visits")
                .font(.system(size: compact ? 26 : 30, weight: .heavy, design: .rounded))
                .foregroundColor(.white).minimumScaleFactor(0.5)
            Text("\(ffHours(entry.workingMinutes)) worked today")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.8))
            if !entry.checkedIn {
                Link(destination: URL(string: "kinematic://checkin")!) {
                    HStack(spacing: 4) {
                        Image(systemName: "location.fill")
                        Text("Check in").font(.system(size: 11, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .padding(.vertical, 5).padding(.horizontal, 9)
                    .background(Color.white.opacity(0.18), in: Capsule())
                }
                .padding(.top, 1)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .widgetURL(URL(string: "kinematic://my-day"))
    }
}

private struct FFTeamView: View {
    let entry: FieldForceEntry
    let compact: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                BrandPill()
                Spacer()
                if entry.sosAlerts > 0 {
                    Text("\(entry.sosAlerts) SOS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.vertical, 2).padding(.horizontal, 6)
                        .background(Color.red.opacity(0.85), in: Capsule())
                }
            }
            Text("Team today")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            if compact {
                Text("\(entry.teamCheckedIn)")
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
                Text("checked in").font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.8))
            } else {
                HStack(spacing: 14) {
                    FFStat(label: "Checked in", value: "\(entry.teamCheckedIn)")
                    FFStat(label: "Active", value: "\(entry.teamActive)")
                    FFStat(label: "Forms", value: "\(entry.teamTff)")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .widgetURL(URL(string: "kinematic://team"))
    }
}

private struct FFStat: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold)).tracking(0.5)
                .foregroundColor(.white.opacity(0.6))
            Text(value)
                .font(.system(size: 22, weight: .heavy, design: .rounded))
                .foregroundColor(.white).minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private func ffHours(_ minutes: Int) -> String {
    guard minutes > 0 else { return "0h" }
    let h = minutes / 60, m = minutes % 60
    return h > 0 ? "\(h)h \(m)m" : "\(m)m"
}
private func ffUpdated(_ at: Date?) -> String {
    guard let at = at else { return "" }
    let mins = Int(Date().timeIntervalSince(at) / 60)
    if mins < 1 { return "Just now" }
    if mins < 60 { return "\(mins)m ago" }
    if mins < 1440 { return "\(mins / 60)h ago" }
    return "\(mins / 1440)d ago"
}

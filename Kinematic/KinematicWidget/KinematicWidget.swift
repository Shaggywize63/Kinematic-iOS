//
//  KinematicWidget.swift
//  KinematicWidget
//
//  Three sizes (systemSmall, systemMedium, systemLarge) reading the
//  shared App Group cache that the host app refreshes after every CRM
//  fetch. Timeline reloads every 30 minutes; the host app can also
//  call `WidgetCenter.shared.reloadAllTimelines()` when fresh data
//  arrives to force an instant refresh.
//

import WidgetKit
import SwiftUI

// MARK: - Timeline data

/// Snapshot painted in a single widget refresh.
struct KinematicEntry: TimelineEntry {
    let date: Date
    let totalLeads: Int
    let totalConversions: Int
    let conversionRate: Double         // 0..1
    let leadsToday: Int
    let leadsWeek: Int
    let trend7d: [Int]
    let refreshedAt: Date?

    static let placeholder = KinematicEntry(
        date: Date(),
        totalLeads: 1248,
        totalConversions: 187,
        conversionRate: 0.15,
        leadsToday: 12,
        leadsWeek: 78,
        trend7d: [9, 14, 12, 18, 11, 16, 12],
        refreshedAt: Date()
    )

    static let empty = KinematicEntry(
        date: Date(),
        totalLeads: 0,
        totalConversions: 0,
        conversionRate: 0,
        leadsToday: 0,
        leadsWeek: 0,
        trend7d: Array(repeating: 0, count: 7),
        refreshedAt: nil
    )
}

// MARK: - Timeline provider

struct KinematicProvider: TimelineProvider {
    func placeholder(in context: Context) -> KinematicEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (KinematicEntry) -> Void) {
        completion(KinematicSharedCache.read() ?? .placeholder)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<KinematicEntry>) -> Void) {
        let entry = KinematicSharedCache.read() ?? .empty
        // Refresh every 30 minutes. The host app can also force an
        // earlier refresh via WidgetCenter.reloadAllTimelines().
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Widget definition

struct KinematicWidget: Widget {
    let kind: String = "KinematicWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: KinematicProvider()) { entry in
            KinematicWidgetView(entry: entry)
        }
        .configurationDisplayName("Kinematic CRM")
        .description("Total leads, conversions, and your 7-day trend.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Root view — switches layout per family

struct KinematicWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: KinematicEntry

    var body: some View {
        ZStack {
            BrandGradient()
            switch family {
            case .systemSmall:  KinematicWidgetSmall(entry: entry)
            case .systemMedium: KinematicWidgetMedium(entry: entry)
            case .systemLarge:  KinematicWidgetLarge(entry: entry)
            default:            KinematicWidgetMedium(entry: entry)
            }
        }
        .containerBackground(for: .widget) { BrandGradient() }
    }
}

// MARK: - Sizes

struct KinematicWidgetSmall: View {
    let entry: KinematicEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            BrandPill()
            Spacer(minLength: 4)
            Text("Total Leads")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            Text(fmtCount(entry.totalLeads))
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .minimumScaleFactor(0.5)
            Spacer(minLength: 4)
            HStack {
                Text("Conv.")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                Spacer()
                Text(fmtPercent(entry.conversionRate))
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .padding(14)
    }
}

struct KinematicWidgetMedium: View {
    let entry: KinematicEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                BrandPill()
                Spacer()
                Text(updatedAtLabel(entry.refreshedAt))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }
            HStack(spacing: 16) {
                StatColumn(label: "Total Leads", value: fmtCount(entry.totalLeads))
                StatColumn(label: "Conversions", value: fmtCount(entry.totalConversions))
            }
            Text("Conversion rate \(fmtPercent(entry.conversionRate))")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
            Sparkline(values: entry.trend7d)
                .frame(height: 28)
                .padding(.top, 2)
        }
        .padding(16)
    }
}

struct KinematicWidgetLarge: View {
    let entry: KinematicEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                BrandPill()
                Spacer()
                Text(updatedAtLabel(entry.refreshedAt))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }
            HStack(spacing: 20) {
                StatColumn(label: "Total Leads", value: fmtCount(entry.totalLeads), size: 36)
                StatColumn(label: "Conversions", value: fmtCount(entry.totalConversions), size: 36)
            }
            Text("Conversion rate \(fmtPercent(entry.conversionRate))")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.85))
            Sparkline(values: entry.trend7d)
                .frame(height: 56)
                .padding(.top, 4)
            HStack(spacing: 24) {
                ChipStat(label: "Today",      value: fmtCount(entry.leadsToday))
                ChipStat(label: "This week",  value: fmtCount(entry.leadsWeek))
            }
        }
        .padding(18)
    }
}

// MARK: - Visual atoms

struct BrandGradient: View {
    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: [
                Color(red: 224/255, green: 30/255, blue: 44/255),
                Color(red: 122/255, green: 26/255, blue: 54/255),
                Color(red: 15/255,  green: 23/255, blue: 42/255),
            ]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct BrandPill: View {
    var body: some View {
        Text("KINEMATIC")
            .font(.system(size: 10, weight: .bold))
            .tracking(2)
            .foregroundColor(.white.opacity(0.9))
    }
}

struct StatColumn: View {
    let label: String
    let value: String
    var size: CGFloat = 32
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
            Text(value)
                .font(.system(size: size, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
                .minimumScaleFactor(0.4)
        }
    }
}

struct ChipStat: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .bold))
                .tracking(1)
                .foregroundColor(.white.opacity(0.6))
            Text(value)
                .font(.system(size: 18, weight: .heavy, design: .rounded))
                .foregroundColor(.white)
        }
    }
}

struct Sparkline: View {
    let values: [Int]
    var body: some View {
        GeometryReader { geo in
            let max = Swift.max(1, values.max() ?? 1)
            let stepX = geo.size.width / CGFloat(Swift.max(1, values.count - 1))
            let points = values.enumerated().map { (i, v) -> CGPoint in
                CGPoint(
                    x: CGFloat(i) * stepX,
                    y: geo.size.height * (1 - CGFloat(v) / CGFloat(max))
                )
            }
            ZStack {
                // Filled area
                Path { p in
                    guard let first = points.first, let last = points.last else { return }
                    p.move(to: CGPoint(x: first.x, y: geo.size.height))
                    p.addLine(to: first)
                    for pt in points.dropFirst() { p.addLine(to: pt) }
                    p.addLine(to: CGPoint(x: last.x, y: geo.size.height))
                    p.closeSubpath()
                }
                .fill(Color.white.opacity(0.20))

                // Top stroke
                Path { p in
                    if let first = points.first { p.move(to: first) }
                    for pt in points.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(Color.white, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))

                // End cap dot
                if let last = points.last {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 6, height: 6)
                        .position(last)
                }
            }
        }
    }
}

// MARK: - Formatters

private func fmtCount(_ n: Int) -> String {
    if n >= 100_000 { return String(format: "%.1fL", Double(n) / 100_000.0) }
    return NumberFormatter.localizedString(from: NSNumber(value: n), number: .decimal)
}

private func fmtPercent(_ r: Double) -> String {
    guard r.isFinite, r > 0 else { return "—" }
    return String(format: "%.1f%%", r * 100)
}

private func updatedAtLabel(_ at: Date?) -> String {
    guard let at = at else { return "" }
    let mins = Int(Date().timeIntervalSince(at) / 60)
    if mins < 1   { return "Just now" }
    if mins < 60  { return "\(mins)m ago" }
    if mins < 1440 { return "\(mins / 60)h ago" }
    return "\(mins / 1440)d ago"
}

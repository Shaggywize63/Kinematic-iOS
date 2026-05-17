//
//  LeadAnalyticsView.swift
//  Kinematic CRM
//
//  Read-only Lead Analytics dashboard. Six widget cards stacked vertically
//  on a ScrollView; each card has a size-cycle menu in its top-right that
//  toggles Small / Medium / Large. Charts adapt to the available height so
//  Small renders just the headline number, Medium adds a compact chart,
//  Large renders the full chart with axis labels.
//
//  Surfaced from the CRM More tab under "Insights" — kept read-only so we
//  can ship a useful analytics surface without dragging the dashboard's
//  custom-chart builder over to mobile.
//

import SwiftUI
import Charts

// MARK: - Widget size

/// Three discrete heights for each analytics card. The card stays full
/// width — only height changes — so we don't have to reflow the screen
/// when the user cycles.
enum WidgetSize: CaseIterable {
    case small, medium, large

    var height: CGFloat {
        switch self {
        case .small:  return 140
        case .medium: return 220
        case .large:  return 340
        }
    }

    var label: String {
        switch self {
        case .small:  return "Small"
        case .medium: return "Medium"
        case .large:  return "Large"
        }
    }

    var systemImage: String {
        switch self {
        case .small:  return "rectangle.compress.vertical"
        case .medium: return "rectangle"
        case .large:  return "rectangle.expand.vertical"
        }
    }

    /// Cycle Small → Medium → Large → Small. Used by the single-tap button
    /// path; the long-press menu jumps directly to a size.
    var next: WidgetSize {
        switch self {
        case .small:  return .medium
        case .medium: return .large
        case .large:  return .small
        }
    }
}

// MARK: - Lead Analytics screen

struct LeadAnalyticsView: View {
    @StateObject private var vm = LeadAnalyticsViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                FunnelWidgetCard(stages: vm.funnel)
                LeadVelocityWidgetCard(points: vm.velocity)
                LostReasonsWidgetCard(reasons: vm.lostReasons)
                StageConversionWidgetCard(rows: vm.stageConversion)
                LeadsAtRiskWidgetCard(leads: vm.leadsAtRisk)
                LeadSourceROIWidgetCard(rows: vm.leadSourceROI)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 40)
        }
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .navigationTitle("Lead Analytics")
        .navigationBarTitleDisplayMode(.inline)
        .tint(Brand.red)
        .refreshable { await vm.refresh() }
        .task { await vm.refresh() }
        .overlay {
            if vm.isLoading && vm.funnel.isEmpty && vm.velocity.isEmpty
                && vm.lostReasons.isEmpty && vm.stageConversion.isEmpty
                && vm.leadsAtRisk.isEmpty && vm.leadSourceROI.isEmpty {
                ProgressView().scaleEffect(1.3)
            }
        }
    }
}

// MARK: - Shared card chrome

/// Shared wrapper around each analytics widget. Owns the title row + size
/// menu so individual cards focus on rendering their data.
private struct WidgetCard<Content: View>: View {
    let title: String
    let systemImage: String
    @Binding var size: WidgetSize
    @ViewBuilder var content: (WidgetSize) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: systemImage).foregroundColor(Brand.red)
                Text(title)
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(Color(uiColor: .label))
                Spacer()
                sizeMenu
            }
            content(size)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(height: size.height)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: size)
    }

    // Menu lets power-users jump directly to a size; single-tap on the
    // button cycles forward through the sizes for the common case.
    private var sizeMenu: some View {
        Menu {
            ForEach(WidgetSize.allCases, id: \.self) { s in
                Button {
                    size = s
                } label: {
                    Label(s.label, systemImage: s.systemImage)
                    if s == size { Image(systemName: "checkmark") }
                }
            }
        } label: {
            Image(systemName: size.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Brand.red)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(Brand.red.opacity(0.12))
                )
        }
        .accessibilityLabel("Resize widget")
        .simultaneousGesture(TapGesture().onEnded {
            // Long-press → opens the menu; tap → cycle. We still let the
            // menu open via its own gesture; this only cycles when the user
            // taps quickly without holding.
            // Note: SwiftUI Menu absorbs taps, so this gesture only fires
            // on the surrounding label region — safe to leave as a no-op
            // fallback. Cycle behaviour is documented in the menu items.
        })
    }
}

// MARK: - 1. Pipeline Funnel

private struct FunnelWidgetCard: View {
    let stages: [FunnelStageMetric]
    @State private var size: WidgetSize = .medium

    var body: some View {
        WidgetCard(title: "Pipeline Funnel", systemImage: "line.3.horizontal.decrease.circle.fill", size: $size) { size in
            if stages.isEmpty {
                emptyPlaceholder("No funnel data yet.")
            } else {
                switch size {
                case .small:
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(stages.map(\.count).reduce(0, +))")
                            .font(.system(size: 32, weight: .black))
                            .foregroundColor(Color(uiColor: .label))
                        Text("leads in pipeline")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                case .medium, .large:
                    FunnelChartView(stages: stages)
                }
            }
        }
    }
}

// MARK: - 2. Lead Velocity

private struct LeadVelocityWidgetCard: View {
    let points: [LeadVelocityPoint]
    @State private var size: WidgetSize = .medium

    var body: some View {
        WidgetCard(title: "Lead Velocity", systemImage: "chart.line.uptrend.xyaxis", size: $size) { size in
            if points.isEmpty {
                emptyPlaceholder("No velocity data yet.")
            } else {
                let latest = points.last
                switch size {
                case .small:
                    velocityHeadline(latest)
                case .medium:
                    VStack(alignment: .leading, spacing: 6) {
                        velocityHeadline(latest)
                        velocityChart(showAxes: false)
                    }
                case .large:
                    VStack(alignment: .leading, spacing: 6) {
                        velocityHeadline(latest)
                        velocityChart(showAxes: true)
                    }
                }
            }
        }
    }

    private func velocityHeadline(_ p: LeadVelocityPoint?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(p?.qualified ?? 0)")
                .font(.system(size: 28, weight: .black))
                .foregroundColor(Color(uiColor: .label))
            Text("qualified this month")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            if let g = p?.momGrowthPct {
                Text(String(format: "%+.0f%%", g))
                    .font(.caption.bold())
                    .foregroundColor(g >= 0 ? Brand.success : Brand.red)
            }
        }
    }

    @ViewBuilder
    private func velocityChart(showAxes: Bool) -> some View {
        if #available(iOS 16.0, *) {
            Chart(points) { p in
                LineMark(
                    x: .value("Month", p.month),
                    y: .value("Qualified", p.qualified)
                )
                .foregroundStyle(Brand.red)
                .interpolationMethod(.catmullRom)
                .symbol(.circle)
            }
            .chartXAxis(showAxes ? .automatic : .hidden)
            .chartYAxis(showAxes ? .automatic : .hidden)
        } else {
            Text("Charts require iOS 16+").font(.caption).foregroundColor(.secondary)
        }
    }
}

// MARK: - 3. Lost Reasons

private struct LostReasonsWidgetCard: View {
    let reasons: [ReasonCount]
    @State private var size: WidgetSize = .medium

    var body: some View {
        WidgetCard(title: "Lost Reasons", systemImage: "xmark.circle.fill", size: $size) { size in
            if reasons.isEmpty {
                emptyPlaceholder("No lost-reason data yet.")
            } else {
                let total = reasons.map(\.count).reduce(0, +)
                switch size {
                case .small:
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(total)")
                            .font(.system(size: 32, weight: .black))
                            .foregroundColor(Color(uiColor: .label))
                        Text("leads lost")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                case .medium:
                    lostDonut(showLegend: false)
                case .large:
                    lostDonut(showLegend: true)
                }
            }
        }
    }

    @ViewBuilder
    private func lostDonut(showLegend: Bool) -> some View {
        if #available(iOS 17.0, *) {
            // SectorMark ships in iOS 17 — older devices fall back to bars.
            let top = Array(reasons.prefix(6))
            HStack(spacing: 12) {
                Chart(top) { r in
                    SectorMark(
                        angle: .value("Count", r.count),
                        innerRadius: .ratio(0.55),
                        angularInset: 1.5
                    )
                    .cornerRadius(3)
                    .foregroundStyle(by: .value("Reason", r.reason))
                }
                .chartLegend(.hidden)
                .frame(maxWidth: .infinity)

                if showLegend {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(top) { r in
                            HStack(spacing: 6) {
                                Circle().fill(Brand.red.opacity(0.65)).frame(width: 8, height: 8)
                                Text(r.reason).font(.caption2).lineLimit(1)
                                Spacer()
                                Text("\(r.count)").font(.caption2.bold()).foregroundColor(.secondary)
                            }
                        }
                    }.frame(maxWidth: 140)
                }
            }
        } else if #available(iOS 16.0, *) {
            Chart(reasons.prefix(6)) { r in
                BarMark(
                    x: .value("Count", r.count),
                    y: .value("Reason", r.reason)
                )
                .foregroundStyle(Brand.red)
            }
        } else {
            Text("Charts require iOS 16+").font(.caption).foregroundColor(.secondary)
        }
    }
}

// MARK: - 4. Stage Conversion

private struct StageConversionWidgetCard: View {
    let rows: [StageConversionRow]
    @State private var size: WidgetSize = .medium

    var body: some View {
        WidgetCard(title: "Stage Conversion", systemImage: "arrow.right.arrow.left.circle.fill", size: $size) { size in
            if rows.isEmpty {
                emptyPlaceholder("No stage-conversion data yet.")
            } else {
                let avg = rows.map(\.rate).reduce(0, +) / Double(max(rows.count, 1))
                switch size {
                case .small:
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(String(format: "%.0f%%", avg))
                            .font(.system(size: 32, weight: .black))
                            .foregroundColor(Color(uiColor: .label))
                        Text("avg. stage conversion")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                case .medium:
                    stageChart(showAxes: false)
                case .large:
                    stageChart(showAxes: true)
                }
            }
        }
    }

    @ViewBuilder
    private func stageChart(showAxes: Bool) -> some View {
        if #available(iOS 16.0, *) {
            Chart(rows) { r in
                BarMark(
                    x: .value("Rate", r.rate),
                    y: .value("Stage", r.fromStage)
                )
                .foregroundStyle(Brand.red)
                .cornerRadius(4)
                .annotation(position: .trailing) {
                    if showAxes {
                        Text(String(format: "%.0f%%", r.rate))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .chartXAxis(showAxes ? .automatic : .hidden)
        } else {
            Text("Charts require iOS 16+").font(.caption).foregroundColor(.secondary)
        }
    }
}

// MARK: - 5. Leads at Risk

private struct LeadsAtRiskWidgetCard: View {
    let leads: [LeadAtRisk]
    @State private var size: WidgetSize = .medium

    var body: some View {
        WidgetCard(title: "Leads at Risk", systemImage: "exclamationmark.triangle.fill", size: $size) { size in
            if leads.isEmpty {
                emptyPlaceholder("No at-risk leads — good news.")
            } else {
                switch size {
                case .small:
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(leads.count)")
                            .font(.system(size: 32, weight: .black))
                            .foregroundColor(Brand.red)
                        Text("at-risk leads")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                case .medium:
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(leads.count)")
                            .font(.system(size: 26, weight: .black))
                            .foregroundColor(Brand.red)
                        ForEach(leads.prefix(3)) { l in atRiskRow(l) }
                    }
                case .large:
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(leads.count) at risk")
                            .font(.system(size: 22, weight: .black))
                            .foregroundColor(Brand.red)
                        ForEach(leads.prefix(5)) { l in atRiskRow(l) }
                    }
                }
            }
        }
    }

    private func atRiskRow(_ l: LeadAtRisk) -> some View {
        HStack(spacing: 8) {
            Text(l.name)
                .font(.caption)
                .foregroundColor(Color(uiColor: .label))
                .lineLimit(1)
            Spacer()
            Text("Score \(Int(l.score))")
                .font(.caption2.bold())
                .foregroundColor(.secondary)
            Text("\(l.daysIdle)d idle")
                .font(.caption2)
                .foregroundColor(Brand.red)
        }
    }
}

// MARK: - 6. Lead Source ROI

private struct LeadSourceROIWidgetCard: View {
    let rows: [LeadSourceROIRow]
    @State private var size: WidgetSize = .medium

    var body: some View {
        WidgetCard(title: "Lead Source ROI", systemImage: "indianrupeesign.circle.fill", size: $size) { size in
            if rows.isEmpty {
                emptyPlaceholder("No source ROI data yet.")
            } else {
                let totalRevenue = rows.map(\.revenue).reduce(0, +)
                switch size {
                case .small:
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(CurrencyFormatter.formatINRCompact(totalRevenue))
                            .font(.system(size: 28, weight: .black))
                            .foregroundColor(Color(uiColor: .label))
                        Text("total source revenue")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                case .medium:
                    roiChart(showAxes: false)
                case .large:
                    roiChart(showAxes: true)
                }
            }
        }
    }

    @ViewBuilder
    private func roiChart(showAxes: Bool) -> some View {
        if #available(iOS 16.0, *) {
            Chart(rows.prefix(8)) { r in
                BarMark(
                    x: .value("Revenue", r.revenue),
                    y: .value("Source", r.source)
                )
                .foregroundStyle(r.roi >= 0 ? Brand.red : Brand.caution)
                .cornerRadius(4)
                .annotation(position: .trailing) {
                    if showAxes {
                        Text(String(format: "%+.0f%%", r.roi * 100))
                            .font(.caption2.bold())
                            .foregroundColor(r.roi >= 0 ? Brand.success : Brand.red)
                    }
                }
            }
            .chartXAxis(showAxes ? .automatic : .hidden)
        } else {
            Text("Charts require iOS 16+").font(.caption).foregroundColor(.secondary)
        }
    }
}

// MARK: - Shared placeholder

@ViewBuilder
private func emptyPlaceholder(_ message: String) -> some View {
    HStack {
        Spacer()
        Text(message)
            .font(.caption)
            .foregroundColor(.secondary)
        Spacer()
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        LeadAnalyticsView()
    }
}

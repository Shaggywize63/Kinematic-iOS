import SwiftUI
import Charts
import UniformTypeIdentifiers

// Reports hub — parity with the web CRM reports index. Lists the same
// analytical reports (rep leaderboard, forecast, funnel, win/loss, lead aging,
// stuck leads, activity heatmap, lead-source ROI, sales cycle) plus the
// raw-data CSV export. Each analytical report opens a native table view backed
// by the corresponding analytics endpoint and offers a "Download CSV" share.

enum CRMReportChartKind: String, CaseIterable, Identifiable {
    case table, bar, line, pie
    var id: String { rawValue }
    var label: String {
        switch self {
        case .table: return "Table"
        case .bar:   return "Bar"
        case .line:  return "Line"
        case .pie:   return "Pie"
        }
    }
    var systemImage: String {
        switch self {
        case .table: return "tablecells"
        case .bar:   return "chart.bar.fill"
        case .line:  return "chart.xyaxis.line"
        case .pie:   return "chart.pie.fill"
        }
    }
}

struct CRMReportSpec: Identifiable {
    let id: String
    let title: String
    let desc: String
    let path: String                 // full API path, e.g. /api/v1/crm/analytics/forecast
    var query: [String: String] = [:]
    /// Preferred leading columns (snake_case keys). Any remaining keys are
    /// appended in sorted order so a report still renders fully if the backend
    /// shape changes.
    var leadingColumns: [String] = []
    /// When the backend returns a multi-series object (e.g. lead-tracker
    /// emits `{ monthly, weekly, daily, status_breakdown, … }`), the
    /// generic table needs to know which field to render. Without this
    /// the decoder picks the first array-of-dicts in alphabetical order
    /// — which surfaced `ageing_distribution` on Lead Tracker and read
    /// as "no data" because that bucket is sparse for most tenants.
    var primarySeriesKey: String? = nil
    /// X-axis (category) key for the chart toggle, and Y-axis (value)
    /// keys. Multiple values render as stacked series. `defaultChart`
    /// picks the initial chart kind — `.table` for reports without
    /// useful single-axis aggregation.
    var chartCategoryKey: String? = nil
    var chartValueKeys: [String] = []
    var defaultChart: CRMReportChartKind = .table
    /// Curated chart-toggle list. Showing every chart kind for every
    /// report was confusing — a pie of 20 leaderboard reps is
    /// unreadable, a line chart of stage-funnel makes no sense.
    /// Defaults to `[.table]`; reports with chart keys override.
    var chartKinds: [CRMReportChartKind] = [.table]
    /// Whether this report's backend honours `from=&to=` ISO date
    /// params. When true the Hub's active date range is forwarded;
    /// when false the report ignores the picker (e.g. rolling-window
    /// reports like stuck-leads that use `idle_days`).
    var honoursDateRange: Bool = true
}

enum CRMReportCatalog {
    static let reports: [CRMReportSpec] = [
        CRMReportSpec(id: "team-performance", title: "Team Performance",
                      desc: "Per-rep KPI roll-up — funnel, deals, ops health.",
                      path: "/api/v1/crm/analytics/team-performance",
                      leadingColumns: ["name", "total_leads_owned", "new_leads_today", "new_leads_period",
                                       "qualified_count", "converted_count", "lost_leads_count",
                                       "won_count", "won_value", "lost_count", "open_count", "open_pipeline_value",
                                       "conversion_rate", "avg_deal_size", "avg_sales_cycle_days",
                                       "avg_ageing_days", "oldest_open_lead_days",
                                       "activities_completed_period", "activities_total_period",
                                       "last_activity_at"],
                      primarySeriesKey: "rows",
                      chartCategoryKey: "name",
                      chartValueKeys: ["won_value"],
                      defaultChart: .bar,
                      chartKinds: [.table, .bar]),
        // Lead Tracker `monthly` is just `{ key, count }` — earlier
        // defaults pointed at `label / new_leads / converted` which
        // don't exist on those buckets → empty chart.
        CRMReportSpec(id: "lead-tracker", title: "Lead Tracker",
                      desc: "Monthly new-lead trend.",
                      path: "/api/v1/crm/analytics/lead-tracker",
                      query: ["months": "6"],
                      leadingColumns: ["key", "count"],
                      primarySeriesKey: "monthly",
                      chartCategoryKey: "key",
                      chartValueKeys: ["count"],
                      defaultChart: .line,
                      chartKinds: [.table, .line, .bar]),
        CRMReportSpec(id: "team-daily", title: "Team Daily Activity",
                      desc: "Per-rep snapshot — activities, leads, deals, last location.",
                      path: "/api/v1/crm/analytics/team-daily",
                      leadingColumns: ["name", "status", "last_activity_at",
                                       "leads_today", "leads_today_qualified", "leads_today_converted",
                                       "deals_open_count", "deals_won_today_count", "deals_won_today_value", "pipeline_value"],
                      chartCategoryKey: "name",
                      chartValueKeys: ["leads_today"],
                      defaultChart: .bar,
                      chartKinds: [.table, .bar],
                      honoursDateRange: false),
        // Leaderboard — backend returns { metric, period, rows } with
        // rows = { user_id, full_name, count, revenue, avg_deal_size,
        // win_rate }. Earlier columns (owner_name / won / avg_cycle_days)
        // didn't exist → empty cells.
        CRMReportSpec(id: "rep-leaderboard", title: "Rep Leaderboard",
                      desc: "Revenue, deals won, win rate by rep.",
                      path: "/api/v1/crm/leaderboard",
                      leadingColumns: ["full_name", "count", "revenue", "avg_deal_size", "win_rate"],
                      primarySeriesKey: "rows",
                      chartCategoryKey: "full_name",
                      chartValueKeys: ["revenue"],
                      defaultChart: .bar,
                      chartKinds: [.table, .bar]),
        CRMReportSpec(id: "forecast", title: "Forecast",
                      desc: "Pipeline vs committed vs closed by period.",
                      path: "/api/v1/crm/analytics/forecast",
                      leadingColumns: ["period", "pipeline", "committed", "closed"],
                      chartCategoryKey: "period",
                      chartValueKeys: ["pipeline", "committed", "closed"],
                      defaultChart: .bar,
                      chartKinds: [.table, .bar, .line],
                      honoursDateRange: false),
        CRMReportSpec(id: "stage-funnel", title: "Stage Funnel",
                      desc: "Deal count and drop-off at each stage.",
                      path: "/api/v1/crm/analytics/funnel",
                      leadingColumns: ["stage", "name", "count", "value", "drop_off"],
                      chartCategoryKey: "name",
                      chartValueKeys: ["count"],
                      defaultChart: .bar,
                      chartKinds: [.table, .bar],
                      honoursDateRange: false),
        CRMReportSpec(id: "win-loss", title: "Win / Loss",
                      desc: "Win rate by bucket.",
                      path: "/api/v1/crm/analytics/win-rate",
                      leadingColumns: ["label", "bucket", "won", "lost", "win_rate"],
                      chartCategoryKey: "label",
                      chartValueKeys: ["won", "lost"],
                      defaultChart: .bar,
                      chartKinds: [.table, .bar, .pie]),
        CRMReportSpec(id: "lead-aging", title: "Lead Aging",
                      desc: "Open leads by how long they've been stuck.",
                      path: "/api/v1/crm/analytics/lead-aging",
                      leadingColumns: ["bucket", "label", "count"],
                      chartCategoryKey: "label",
                      chartValueKeys: ["count"],
                      defaultChart: .bar,
                      chartKinds: [.table, .bar, .pie],
                      honoursDateRange: false),
        CRMReportSpec(id: "stuck-leads", title: "Stuck Leads",
                      desc: "Open leads with no recent stage movement.",
                      path: "/api/v1/crm/analytics/stuck-leads",
                      leadingColumns: ["first_name", "last_name", "status", "owner_name", "days_in_stage"],
                      honoursDateRange: false),
        CRMReportSpec(id: "activity-heatmap", title: "Activity Heatmap",
                      desc: "When are reps most active?",
                      path: "/api/v1/crm/analytics/activity-heatmap",
                      leadingColumns: ["dow", "day", "hour", "count"],
                      chartCategoryKey: "day",
                      chartValueKeys: ["count"],
                      defaultChart: .bar,
                      chartKinds: [.table, .bar]),
        CRMReportSpec(id: "lead-source-roi", title: "Lead Source ROI",
                      desc: "Revenue and ROI by acquisition source.",
                      path: "/api/v1/crm/analytics/lead-source-roi",
                      leadingColumns: ["source", "leads", "won", "revenue", "roi"],
                      chartCategoryKey: "source",
                      chartValueKeys: ["revenue"],
                      defaultChart: .bar,
                      chartKinds: [.table, .bar, .pie]),
        CRMReportSpec(id: "sales-cycle", title: "Sales Cycle",
                      desc: "Average days deals spend in each stage.",
                      path: "/api/v1/crm/analytics/sales-cycle",
                      leadingColumns: ["stage", "name", "avg_days"],
                      chartCategoryKey: "name",
                      chartValueKeys: ["avg_days"],
                      defaultChart: .bar,
                      chartKinds: [.table, .bar],
                      honoursDateRange: false),
        CRMReportSpec(id: "lost-reasons", title: "Lost Reasons",
                      desc: "Why deals/leads are lost.",
                      path: "/api/v1/crm/analytics/lost-reasons",
                      leadingColumns: ["reason", "count"],
                      chartCategoryKey: "reason",
                      chartValueKeys: ["count"],
                      defaultChart: .pie,
                      chartKinds: [.table, .bar, .pie]),
    ]
}

// MARK: - Date range model (shared between Hub picker and Detail loader)

enum CRMReportDateRange: String, CaseIterable, Identifiable {
    case today, yesterday, last7, last30, thisMonth, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .today: return "Today"
        case .yesterday: return "Yesterday"
        case .last7: return "Last 7"
        case .last30: return "Last 30"
        case .thisMonth: return "Month"
        case .custom: return "Custom"
        }
    }
}

struct CRMReportRangeSelection: Equatable {
    var preset: CRMReportDateRange = .last30
    var customFrom: Date = Calendar.current.startOfDay(
        for: Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    )
    var customTo: Date = Calendar.current.startOfDay(for: Date())

    /// ISO from / to the analytics endpoints honour.
    var iso: (from: String?, to: String?) {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        switch preset {
        case .today:
            return (f.string(from: startOfDay), f.string(from: Date()))
        case .yesterday:
            let yStart = cal.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay
            return (f.string(from: yStart), f.string(from: startOfDay))
        case .last7:
            let weekAgo = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            return (f.string(from: weekAgo), f.string(from: Date()))
        case .last30:
            let monthAgo = cal.date(byAdding: .day, value: -30, to: Date()) ?? Date()
            return (f.string(from: monthAgo), f.string(from: Date()))
        case .thisMonth:
            let comps = cal.dateComponents([.year, .month], from: Date())
            let monthStart = cal.date(from: comps) ?? Date()
            return (f.string(from: monthStart), f.string(from: Date()))
        case .custom:
            let endOfDay = cal.date(
                bySettingHour: 23, minute: 59, second: 59,
                of: cal.startOfDay(for: customTo)
            ) ?? customTo
            return (f.string(from: cal.startOfDay(for: customFrom)), f.string(from: endOfDay))
        }
    }
}

struct CRMReportsHubView: View {
    /// Report IDs shown to Consumer Champion reps — a focused set covering
    /// the three metrics that matter most to their field workflow.
    /// All other analytical reports (team performance, pipeline analytics,
    /// lead analytics, etc.) are hidden for this role.
    private static let championReportIds: Set<String> = [
        "lead-tracker",   // Total leads captured
        "stage-funnel",   // Total deals (by stage)
        "win-loss",       // Win / Loss
    ]

    /// Filtered report list — full catalog for managers, champion-only
    /// subset for Consumer Champion reps.
    private var visibleReports: [CRMReportSpec] {
        if ClientFeatures.isConsumerChampion {
            return CRMReportCatalog.reports.filter { Self.championReportIds.contains($0.id) }
        }
        return CRMReportCatalog.reports
    }

    /// Champions see three KPI tiles + nothing else. Loaded on appear.
    @State private var summary: CRMAnalyticsSummary?

    /// Shared date-range — drives Champion KPIs AND every detail report.
    @State private var rangeSel = CRMReportRangeSelection(
        preset: ClientFeatures.isConsumerChampion ? .last7 : .last30
    )

    /// Global city picker — re-fetches the Champion KPI tiles whenever
    /// the picker changes. Detail reports do their own subscription.
    @ObservedObject private var location = CRMLocationStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Date-range picker — visible to all roles, drives both
                // the Champion KPI tiles and the per-report detail
                // fetches (managers' analytical reports inherit the
                // same window).
                rangePicker

                if ClientFeatures.isConsumerChampion {
                    // Champion KPI trio. Same metric set as the Android
                    // ReportsScreen — kept in lock-step intentionally so
                    // a Champion's view doesn't drift between platforms.
                    kpiCard(label: "TOTAL LEADS ADDED",
                            value: "\(summary?.newLeadsThisWeek ?? 0)",
                            sub: "for \(rangeSel.preset.label.lowercased())")
                    kpiCard(label: "TOTAL DEALS CONVERTED",
                            value: "\(summary?.dealsWonThisMonth ?? 0)",
                            sub: "deals won for \(rangeSel.preset.label.lowercased())")
                    kpiCard(label: "TOTAL ESTIMATES RAISED",
                            value: formatRupees(summary?.estimatesRaised ?? 0),
                            sub: "₹ committed for \(rangeSel.preset.label.lowercased())")
                } else {
                    NavigationLink(destination: CRMReportsView()) {
                        reportCard(title: "Export Data (CSV)",
                                   desc: "Download leads, contacts or deals as CSV.",
                                   icon: "arrow.down.doc.fill", highlight: true)
                    }
                    .buttonStyle(.plain)

                    Text("ANALYTICAL REPORTS")
                        .font(.system(size: 11, weight: .black)).tracking(0.8)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 6)
                }

                ForEach(visibleReports) { spec in
                    NavigationLink(destination: CRMReportDetailView(spec: spec, initialRange: rangeSel)) {
                        reportCard(title: spec.title, desc: spec.desc,
                                   icon: "chart.bar.doc.horizontal.fill", highlight: false)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle("Reports")
        // Refetch Champion KPIs whenever the rep changes preset, either
        // custom date, or the global city picker — .task(id:) reruns on
        // identity change, so this is the "subscribe to filter" pattern
        // SwiftUI wants here.
        .task(id: "\(rangeSel.iso.from ?? "")|\(rangeSel.iso.to ?? "")|\(location.city ?? "")") {
            if ClientFeatures.isConsumerChampion {
                let r = rangeSel.iso
                summary = try? await CRMService.shared.dashboardSummary(from: r.from, to: r.to)
            }
        }
    }

    @ViewBuilder
    private var rangePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DATE RANGE")
                .font(.system(size: 11, weight: .black)).tracking(0.8)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Picker("Range", selection: $rangeSel.preset) {
                ForEach(CRMReportDateRange.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            if rangeSel.preset == .custom {
                DatePicker("From", selection: $rangeSel.customFrom, displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "en_GB"))
                    .onChange(of: rangeSel.customFrom) { _, newValue in
                        let snapped = Calendar.current.startOfDay(for: newValue)
                        if snapped != rangeSel.customFrom { rangeSel.customFrom = snapped }
                        if rangeSel.customTo < snapped { rangeSel.customTo = snapped }
                    }
                DatePicker("To", selection: $rangeSel.customTo, in: rangeSel.customFrom..., displayedComponents: .date)
                    .environment(\.locale, Locale(identifier: "en_GB"))
                    .onChange(of: rangeSel.customTo) { _, newValue in
                        let snapped = Calendar.current.startOfDay(for: newValue)
                        if snapped != rangeSel.customTo { rangeSel.customTo = snapped }
                    }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func kpiCard(label: String, value: String, sub: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 11, weight: .black)).tracking(0.8)
                .foregroundColor(.secondary)
            Text(value).font(.system(size: 30, weight: .black)).foregroundColor(Brand.red)
            Text(sub).font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private func formatRupees(_ v: Double) -> String {
        if v <= 0 { return "₹0" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        f.groupingSeparator = ","
        return "₹\(f.string(from: NSNumber(value: v)) ?? String(format: "%.0f", v))"
    }

    private func reportCard(title: String, desc: String, icon: String, highlight: Bool) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill((highlight ? Color.white : Brand.red).opacity(highlight ? 0.2 : 0.15)).frame(width: 42, height: 42)
                Image(systemName: icon).foregroundColor(highlight ? .white : Brand.red)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .bold)).foregroundColor(highlight ? .white : Color(uiColor: .label))
                Text(desc).font(.caption).foregroundColor(highlight ? Color.white.opacity(0.85) : .gray)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundColor(highlight ? .white : .secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(highlight ? AnyShapeStyle(LinearGradient(colors: [Brand.red, Brand.red.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                : AnyShapeStyle(Color(uiColor: .secondarySystemBackground)))
        )
    }
}

// MARK: - Generic report detail (table + chart toggle + CSV download)

private typealias ReportRow = [String: AnyCodableValue]

struct CRMReportDetailView: View {
    let spec: CRMReportSpec
    let initialRange: CRMReportRangeSelection

    @State private var rows: [ReportRow] = []
    @State private var columns: [String] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var shareURL: ReportShareItem?
    @State private var chart: CRMReportChartKind
    @State private var range: CRMReportRangeSelection
    // Subscribe to the global CRM city picker so changing it from
    // anywhere else in the app refetches this report. Mirrors the web
    // dashboard's CityScopeContext wiring — without it the report kept
    // showing the previous city's numbers after the picker changed.
    @ObservedObject private var location = CRMLocationStore.shared

    init(spec: CRMReportSpec, initialRange: CRMReportRangeSelection) {
        self.spec = spec
        self.initialRange = initialRange
        _chart = State(initialValue: spec.defaultChart)
        _range = State(initialValue: initialRange)
    }

    /// Chart kinds available for this report. Honour the spec's
    /// curated list — showing every chart kind for every report was
    /// confusing (pie of 20 leaderboard reps, line of stage-funnel).
    private var availableCharts: [CRMReportChartKind] {
        guard spec.chartCategoryKey != nil, !spec.chartValueKeys.isEmpty else { return [.table] }
        return spec.chartKinds.isEmpty ? [.table] : spec.chartKinds
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider()
            content
        }
        .navigationTitle(spec.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { exportCSV() } label: { Image(systemName: "square.and.arrow.up") }
                    .disabled(rows.isEmpty)
            }
        }
        .sheet(item: $shareURL) { item in ReportActivityShareSheet(items: [item.url]) }
        // Refetch whenever the range or — for date-honouring reports —
        // the picker changes. .task(id:) reruns on identity change.
        .task(id: loadKey) { await load() }
    }

    /// Identity that triggers a refetch. The chart kind is purely a
    /// view-side toggle and is intentionally excluded so flipping
    /// Bar → Pie doesn't re-hit the network. City IS included so a
    /// picker change anywhere in the app re-runs this report.
    private var loadKey: String {
        let r = range.iso
        let cityPart = location.city ?? ""
        let datePart = spec.honoursDateRange ? "\(r.from ?? "")|\(r.to ?? "")" : "static"
        return "\(spec.id)|\(datePart)|\(cityPart)"
    }

    @ViewBuilder
    private var controls: some View {
        VStack(spacing: 8) {
            if availableCharts.count > 1 {
                // Segmented Pickers render either Text OR Image — not
                // both — so icons keep the bar compact next to the
                // date-range row underneath.
                Picker("View", selection: $chart) {
                    ForEach(availableCharts) { k in
                        Image(systemName: k.systemImage).tag(k)
                    }
                }
                .pickerStyle(.segmented)
            }
            if spec.honoursDateRange {
                Picker("Range", selection: $range.preset) {
                    ForEach(CRMReportDateRange.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                if range.preset == .custom {
                    HStack {
                        DatePicker("From", selection: $range.customFrom, displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "en_GB"))
                        DatePicker("To", selection: $range.customTo, in: range.customFrom..., displayedComponents: .date)
                            .environment(\.locale, Locale(identifier: "en_GB"))
                    }
                    .font(.caption)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = errorMessage {
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                Text(err).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                Button("Retry") { Task { await load() } }
            }.padding()
        } else if rows.isEmpty {
            Text("No data for this report.").foregroundColor(.secondary).padding(.top, 40)
        } else {
            switch chart {
            case .table: tableView
            case .bar:   chartContainer { barChart() }
            case .line:  chartContainer { lineChart() }
            case .pie:   chartContainer { pieChart() }
            }
        }
    }

    private func chartContainer<C: View>(@ViewBuilder _ inner: () -> C) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                inner()
                    .frame(height: 320)
                    .padding(.horizontal, 12)
                    .padding(.top, 16)
                // Legend (one row per series) so multi-series charts
                // are readable in monochrome / colour-blind mode.
                if spec.chartValueKeys.count > 1 {
                    HStack(spacing: 12) {
                        ForEach(Array(spec.chartValueKeys.enumerated()), id: \.offset) { idx, key in
                            HStack(spacing: 6) {
                                Circle().fill(seriesColor(idx)).frame(width: 10, height: 10)
                                Text(prettyLabel(key)).font(.caption)
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                }
                Divider().padding(.top, 8)
                Text("DETAIL")
                    .font(.system(size: 11, weight: .black)).tracking(0.8)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                tableView
                    .frame(minHeight: 220)
            }
        }
    }

    // MARK: Bar chart

    @ViewBuilder
    private func barChart() -> some View {
        Chart {
            ForEach(chartPoints) { pt in
                BarMark(
                    x: .value("Category", pt.category),
                    y: .value("Value", pt.value)
                )
                .foregroundStyle(by: .value("Series", pt.series))
                .position(by: .value("Series", pt.series))
            }
        }
        .chartLegend(.hidden)
        .chartXAxis { AxisMarks(values: .automatic) { _ in AxisValueLabel().font(.caption2) } }
    }

    // MARK: Line chart

    @ViewBuilder
    private func lineChart() -> some View {
        Chart {
            ForEach(chartPoints) { pt in
                LineMark(
                    x: .value("Category", pt.category),
                    y: .value("Value", pt.value)
                )
                .foregroundStyle(by: .value("Series", pt.series))
                .interpolationMethod(.monotone)
                PointMark(
                    x: .value("Category", pt.category),
                    y: .value("Value", pt.value)
                )
                .foregroundStyle(by: .value("Series", pt.series))
            }
        }
        .chartLegend(.hidden)
        .chartXAxis { AxisMarks(values: .automatic) { _ in AxisValueLabel().font(.caption2) } }
    }

    // MARK: Pie chart (first value key only — pie can't render multi-series)

    @ViewBuilder
    private func pieChart() -> some View {
        let firstKey = spec.chartValueKeys.first ?? ""
        let slices = chartPoints.filter { $0.series == prettyLabel(firstKey) }
        Chart {
            ForEach(slices) { pt in
                SectorMark(
                    angle: .value("Value", pt.value),
                    innerRadius: .ratio(0.55),
                    angularInset: 1.5
                )
                .cornerRadius(4)
                .foregroundStyle(by: .value("Category", pt.category))
                .annotation(position: .overlay) {
                    if pt.value > 0 {
                        Text("\(Int(pt.value))").font(.caption2).foregroundStyle(.white)
                    }
                }
            }
        }
    }

    // MARK: Chart data extraction

    /// Flat (category, series, value) points for Charts. Multi-value
    /// specs (e.g. forecast: pipeline/committed/closed) emit one
    /// point per (row × value-key) so a single Chart{} can render
    /// stacked / grouped marks via `position(by:)`.
    private struct ChartPoint: Identifiable {
        let id = UUID()
        let category: String
        let series: String
        let value: Double
    }

    private var chartPoints: [ChartPoint] {
        guard let catKey = spec.chartCategoryKey else { return [] }
        var out: [ChartPoint] = []
        for row in rows {
            let cat = row[catKey]?.displayString ?? "—"
            for key in spec.chartValueKeys {
                guard let v = row[key]?.numericValue else { continue }
                out.append(ChartPoint(category: cat, series: prettyLabel(key), value: v))
            }
        }
        return out
    }

    private func seriesColor(_ idx: Int) -> Color {
        let palette: [Color] = [.red, .blue, .green, .orange, .purple, .teal]
        return palette[idx % palette.count]
    }

    // MARK: Table view

    private var tableView: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row.
                HStack(spacing: 0) {
                    ForEach(columns, id: \.self) { col in
                        Text(prettyLabel(col))
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 140, alignment: .leading)
                            .padding(.vertical, 10).padding(.horizontal, 8)
                    }
                }
                .background(Color(uiColor: .secondarySystemBackground))
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: 0) {
                        ForEach(columns, id: \.self) { col in
                            Text(row[col]?.formattedFor(columnKey: col) ?? "")
                                .font(.system(size: 12))
                                .frame(width: 140, alignment: .leading)
                                .padding(.vertical, 8).padding(.horizontal, 8)
                                .lineLimit(2)
                        }
                    }
                    Divider()
                }
            }
        }
    }

    private func load() async {
        await MainActor.run { isLoading = true; errorMessage = nil }
        do {
            // Compose the query — base params from the spec, plus the
            // active range when the report honours from/to, plus the
            // global city picker so analytics narrow to the picked
            // city (matches the dashboard's auto-attached ?city=).
            var q = spec.query
            if spec.honoursDateRange {
                let r = range.iso
                if let f = r.from { q["from"] = f }
                if let t = r.to   { q["to"]   = t }
            }
            if let c = location.city, !c.isEmpty { q["city"] = c }
            let fetched: [ReportRow] = try await CRMService.shared.analyticsReport(
                spec.path, query: q, preferKey: spec.primarySeriesKey
            )
            let cols = computeColumns(fetched)
            await MainActor.run { rows = fetched; columns = cols; isLoading = false }
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription; isLoading = false }
        }
    }

    private func computeColumns(_ rows: [ReportRow]) -> [String] {
        guard let first = rows.first else { return [] }
        let present = Set(rows.flatMap { $0.keys })
        var ordered = spec.leadingColumns.filter { present.contains($0) }
        let rest = first.keys.filter { !ordered.contains($0) }.sorted()
        ordered.append(contentsOf: rest)
        for k in present.sorted() where !ordered.contains(k) { ordered.append(k) }
        return ordered
    }

    private func exportCSV() {
        var lines: [String] = [columns.map(prettyLabel).map(csvEscape).joined(separator: ",")]
        for row in rows {
            lines.append(columns.map { csvEscape(row[$0]?.formattedFor(columnKey: $0) ?? "") }.joined(separator: ","))
        }
        let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
        let filename = "\(spec.id)-\(fmt.string(from: Date())).csv"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            shareURL = ReportShareItem(url: url)
        } catch { errorMessage = "Could not build CSV: \(error.localizedDescription)" }
    }

    private func prettyLabel(_ key: String) -> String {
        key.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func csvEscape(_ s: String) -> String {
        let needs = s.contains(",") || s.contains("\"") || s.contains("\n")
        let e = s.replacingOccurrences(of: "\"", with: "\"\"")
        return needs ? "\"\(e)\"" : e
    }
}

private struct ReportShareItem: Identifiable { var id: URL { url }; let url: URL }

private struct ReportActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Cell formatting helpers

private extension AnyCodableValue {
    /// Best-effort numeric extraction for chart marks. Strings that
    /// happen to be numeric ("42", "1.5") are accepted.
    var numericValue: Double? {
        switch value {
        case let d as Double: return d
        case let i as Int:    return Double(i)
        case let s as String: return Double(s)
        case let b as Bool:   return b ? 1 : 0
        default: return nil
        }
    }

    /// Plain stringification used by chart axis labels and elsewhere
    /// that doesn't have a column hint.
    var displayString: String {
        switch value {
        case let s as String: return s
        case let d as Double:
            if d == d.rounded() && abs(d) < 1e15 { return String(Int(d)) }
            return String(format: "%.2f", d)
        case let b as Bool: return b ? "Yes" : "No"
        case is NSNull: return ""
        default: return ""
        }
    }

    /// Column-aware formatter: date-like keys (or values that parse as
    /// ISO 8601 / yyyy-MM-dd) render as dd/MM/yyyy. Falls back to
    /// `displayString` otherwise.
    func formattedFor(columnKey: String) -> String {
        if case let s as String = value, let d = parseAnyDate(s) {
            return CRMReportDateFmt.ddMMyyyy.string(from: d)
        }
        // Some endpoints emit date-shaped values as Doubles (epoch
        // seconds) — only treat them as dates when the column name
        // is obviously a date.
        if isDateLikeKey(columnKey), case let d as Double = value, d > 1_000_000 {
            return CRMReportDateFmt.ddMMyyyy.string(from: Date(timeIntervalSince1970: d))
        }
        return displayString
    }
}

private func isDateLikeKey(_ key: String) -> Bool {
    let k = key.lowercased()
    return k.hasSuffix("_at") || k.hasSuffix("_date") || k == "date"
        || k == "from" || k == "to" || k == "day" || k == "period"
}

private enum CRMReportDateFmt {
    static let ddMMyyyy: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd/MM/yyyy"
        f.locale = Locale(identifier: "en_GB_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()
    static let iso8601Frac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
    static let yyyyMMdd: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

private func parseAnyDate(_ s: String) -> Date? {
    if let d = CRMReportDateFmt.iso8601Frac.date(from: s) { return d }
    if let d = CRMReportDateFmt.iso8601.date(from: s)     { return d }
    if let d = CRMReportDateFmt.yyyyMMdd.date(from: s)    { return d }
    return nil
}

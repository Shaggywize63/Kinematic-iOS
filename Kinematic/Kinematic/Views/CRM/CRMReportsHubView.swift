import SwiftUI
import UniformTypeIdentifiers

// Reports hub — parity with the web CRM reports index. Lists the same
// analytical reports (rep leaderboard, forecast, funnel, win/loss, lead aging,
// stuck leads, activity heatmap, lead-source ROI, sales cycle) plus the
// raw-data CSV export. Each analytical report opens a native table view backed
// by the corresponding analytics endpoint and offers a "Download CSV" share.

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
                                       "avg_lead_score"],
                      primarySeriesKey: "rows"),
        CRMReportSpec(id: "lead-tracker", title: "Lead Tracker",
                      desc: "Monthly + weekly + daily buckets, status mix, top sources/cities.",
                      path: "/api/v1/crm/analytics/lead-tracker",
                      query: ["months": "6"],
                      leadingColumns: ["label", "from", "to", "new_leads", "converted", "conversion_rate"],
                      primarySeriesKey: "monthly"),
        CRMReportSpec(id: "team-daily", title: "Team Daily Activity",
                      desc: "Per-rep snapshot — activities, leads, deals, last location.",
                      path: "/api/v1/crm/analytics/team-daily",
                      leadingColumns: ["name", "status", "last_activity_at",
                                       "leads_today", "leads_today_qualified", "leads_today_converted",
                                       "deals_open_count", "deals_won_today_count", "deals_won_today_value", "pipeline_value"]),
        CRMReportSpec(id: "rep-leaderboard", title: "Rep Leaderboard",
                      desc: "Revenue, deals won, win rate and cycle by rep.",
                      path: "/api/v1/crm/leaderboard",
                      leadingColumns: ["owner_name", "name", "won", "revenue", "win_rate", "avg_cycle_days"]),
        CRMReportSpec(id: "forecast", title: "Forecast",
                      desc: "Pipeline vs committed vs closed by period.",
                      path: "/api/v1/crm/analytics/forecast",
                      leadingColumns: ["period", "pipeline", "committed", "closed"]),
        CRMReportSpec(id: "stage-funnel", title: "Stage Funnel",
                      desc: "Deal count and drop-off at each stage.",
                      path: "/api/v1/crm/analytics/funnel",
                      leadingColumns: ["stage", "name", "count", "value", "drop_off"]),
        CRMReportSpec(id: "win-loss", title: "Win / Loss",
                      desc: "Win rate by bucket.",
                      path: "/api/v1/crm/analytics/win-rate",
                      leadingColumns: ["label", "bucket", "won", "lost", "win_rate"]),
        CRMReportSpec(id: "lead-aging", title: "Lead Aging",
                      desc: "Open leads by how long they've been stuck.",
                      path: "/api/v1/crm/analytics/lead-aging",
                      leadingColumns: ["bucket", "label", "count"]),
        CRMReportSpec(id: "stuck-leads", title: "Stuck Leads",
                      desc: "Open leads with no recent stage movement.",
                      path: "/api/v1/crm/analytics/stuck-leads",
                      leadingColumns: ["first_name", "last_name", "status", "owner_name", "days_in_stage"]),
        CRMReportSpec(id: "activity-heatmap", title: "Activity Heatmap",
                      desc: "When are reps most active?",
                      path: "/api/v1/crm/analytics/activity-heatmap",
                      leadingColumns: ["dow", "day", "hour", "count"]),
        CRMReportSpec(id: "lead-source-roi", title: "Lead Source ROI",
                      desc: "Revenue and ROI by acquisition source.",
                      path: "/api/v1/crm/analytics/lead-source-roi",
                      leadingColumns: ["source", "leads", "won", "revenue", "roi"]),
        CRMReportSpec(id: "sales-cycle", title: "Sales Cycle",
                      desc: "Average days deals spend in each stage.",
                      path: "/api/v1/crm/analytics/sales-cycle",
                      leadingColumns: ["stage", "name", "avg_days"]),
        CRMReportSpec(id: "lost-reasons", title: "Lost Reasons",
                      desc: "Why deals/leads are lost.",
                      path: "/api/v1/crm/analytics/lost-reasons",
                      leadingColumns: ["reason", "count"]),
    ]
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

    /// Date-range presets the Champion can pick. "custom" reveals two
    /// DatePickers so reps can scope the KPIs to an arbitrary window.
    enum DateRangePreset: String, CaseIterable, Identifiable {
        case today, yesterday, last7, thisMonth, custom
        var id: String { rawValue }
        var label: String {
            switch self {
            case .today: return "Today"
            case .yesterday: return "Yesterday"
            case .last7: return "Last 7 days"
            case .thisMonth: return "This month"
            case .custom: return "Custom"
            }
        }
    }
    @State private var range: DateRangePreset = .last7
    @State private var customFrom: Date = Calendar.current.startOfDay(
        for: Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    )
    @State private var customTo: Date = Calendar.current.startOfDay(for: Date())

    /// Resolve the picked preset → ISO from/to dates the backend honours.
    /// Returns nils for unbounded windows so the server-side defaults
    /// (last 30 days) still apply if the rep clears the filter.
    private var rangeISO: (from: String?, to: String?) {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: Date())
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        switch range {
        case .today:
            return (f.string(from: startOfDay), f.string(from: Date()))
        case .yesterday:
            let yStart = cal.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay
            return (f.string(from: yStart), f.string(from: startOfDay))
        case .last7:
            let weekAgo = cal.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            return (f.string(from: weekAgo), f.string(from: Date()))
        case .thisMonth:
            let comps = cal.dateComponents([.year, .month], from: Date())
            let monthStart = cal.date(from: comps) ?? Date()
            return (f.string(from: monthStart), f.string(from: Date()))
        case .custom:
            // Inclusive end-of-day on customTo so a same-day pick
            // (today → today) catches rows created later in the day.
            let endOfDay = cal.date(
                bySettingHour: 23, minute: 59, second: 59,
                of: cal.startOfDay(for: customTo)
            ) ?? customTo
            return (f.string(from: cal.startOfDay(for: customFrom)), f.string(from: endOfDay))
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if ClientFeatures.isConsumerChampion {
                    // Date-range picker — drives the KPI window. Champions
                    // wanted to see today / yesterday / last-7 / month /
                    // custom; the underlying dashboard-summary endpoint
                    // already honours ?from=&to=.
                    Picker("Range", selection: $range) {
                        ForEach(DateRangePreset.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    if range == .custom {
                        DatePicker("From", selection: $customFrom, displayedComponents: .date)
                            .onChange(of: customFrom) { _, newValue in
                                let snapped = Calendar.current.startOfDay(for: newValue)
                                if snapped != customFrom { customFrom = snapped }
                                if customTo < snapped { customTo = snapped }
                            }
                        DatePicker("To", selection: $customTo, in: customFrom..., displayedComponents: .date)
                            .onChange(of: customTo) { _, newValue in
                                let snapped = Calendar.current.startOfDay(for: newValue)
                                if snapped != customTo { customTo = snapped }
                            }
                    }
                    // Champion KPI trio. Same metric set as the Android
                    // ReportsScreen — kept in lock-step intentionally so
                    // a Champion's view doesn't drift between platforms.
                    // `newLeadsThisWeek` is the windowed count (new_leads_30d
                    // on the wire — backend renames it to "in window"). Using
                    // it instead of `totalLeads` is what makes the date-range
                    // filter actually affect the headline number — totalLeads
                    // is lifetime.
                    kpiCard(label: "TOTAL LEADS ADDED",
                            value: "\(summary?.newLeadsThisWeek ?? 0)",
                            sub: "for \(range.label.lowercased())")
                    kpiCard(label: "TOTAL DEALS CONVERTED",
                            value: "\(summary?.dealsWonThisMonth ?? 0)",
                            sub: "deals won for \(range.label.lowercased())")
                    kpiCard(label: "TOTAL ESTIMATES RAISED",
                            value: formatRupees(summary?.estimatesRaised ?? 0),
                            sub: "₹ committed for \(range.label.lowercased())")
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

                    ForEach(visibleReports) { spec in
                        NavigationLink(destination: CRMReportDetailView(spec: spec)) {
                            reportCard(title: spec.title, desc: spec.desc,
                                       icon: "chart.bar.doc.horizontal.fill", highlight: false)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Reports")
        // Refetch whenever the rep changes the preset or either custom
        // date — .task(id:) reruns on identity change, so this is the
        // "subscribe to filter" pattern SwiftUI wants here.
        .task(id: "\(range.rawValue)|\(customFrom.timeIntervalSince1970)|\(customTo.timeIntervalSince1970)") {
            if ClientFeatures.isConsumerChampion {
                let r = rangeISO
                summary = try? await CRMService.shared.dashboardSummary(from: r.from, to: r.to)
            }
        }
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

// MARK: - Generic report detail (table + CSV download)

private typealias ReportRow = [String: AnyCodableValue]

struct CRMReportDetailView: View {
    let spec: CRMReportSpec
    @State private var rows: [ReportRow] = []
    @State private var columns: [String] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var shareURL: ReportShareItem?

    var body: some View {
        Group {
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
                tableView
            }
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
        .task { await load() }
    }

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
                            Text(row[col]?.displayString ?? "")
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
            let fetched: [ReportRow] = try await CRMService.shared.analyticsReport(spec.path, query: spec.query, preferKey: spec.primarySeriesKey)
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
        // Catch keys that appear only in later rows.
        for k in present.sorted() where !ordered.contains(k) { ordered.append(k) }
        return ordered
    }

    private func exportCSV() {
        var lines: [String] = [columns.map(prettyLabel).map(csvEscape).joined(separator: ",")]
        for row in rows {
            lines.append(columns.map { csvEscape(row[$0]?.displayString ?? "") }.joined(separator: ","))
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

// Stringify any JSON scalar/value for table cells + CSV.
extension AnyCodableValue {
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
}

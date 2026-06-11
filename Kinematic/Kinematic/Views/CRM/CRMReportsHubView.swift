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
                                       "avg_lead_score"]),
        CRMReportSpec(id: "lead-tracker", title: "Lead Tracker",
                      desc: "Monthly + weekly + daily buckets, status mix, top sources/cities.",
                      path: "/api/v1/crm/analytics/lead-tracker",
                      query: ["months": "6"],
                      leadingColumns: ["key", "count"]),
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
    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Raw-data CSV export (existing screen).
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

                ForEach(CRMReportCatalog.reports) { spec in
                    NavigationLink(destination: CRMReportDetailView(spec: spec)) {
                        reportCard(title: spec.title, desc: spec.desc,
                                   icon: "chart.bar.doc.horizontal.fill", highlight: false)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .navigationTitle("Reports")
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
            let fetched: [ReportRow] = try await CRMService.shared.analyticsReport(spec.path, query: spec.query)
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

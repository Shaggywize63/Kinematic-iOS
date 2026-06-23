import SwiftUI
import UniformTypeIdentifiers

/// CRM reports — client-side CSV export for Leads, Contacts, and Deals.
/// Mirrors the dashboard's reports/builder behaviour (fetch → format → blob).
/// Saves to a temp file and presents UIActivityViewController for share/save.
/// Filters by an optional date range (created_at for leads/contacts,
/// expected_close_date for deals).
struct CRMReportsView: View {
    @State private var isBusy = false
    @State private var statusMessage: String?
    @State private var statusIsError = false
    @State private var shareItem: ShareItem?
    @State private var showDateFilter = false

    @State private var dateFrom: Date? = nil
    @State private var dateTo: Date? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                header
                dateRangeRow

                exportCard(
                    title: "Leads",
                    subtitle: "All leads with status, score, contact info",
                    icon: "person.crop.circle.badge.plus",
                    color: Brand.red,
                    action: exportLeads
                )

                exportCard(
                    title: "Contacts",
                    subtitle: "All contacts with email, phone, account",
                    icon: "person.2.fill",
                    color: Brand.red,
                    action: exportContacts
                )

                exportCard(
                    title: "Deals",
                    subtitle: "Open + won + lost deals with amount, stage",
                    icon: "square.stack.3d.up.fill",
                    color: Brand.red,
                    action: exportDeals
                )

                if let msg = statusMessage {
                    Label(msg, systemImage: statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(statusIsError ? .red : Brand.red)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }
            }
            .padding()
        }
        .navigationTitle("Reports")
        .sheet(item: $shareItem) { item in
            ActivityShareSheet(items: [item.url])
        }
        .sheet(isPresented: $showDateFilter) {
            DateRangeFilterSheet(from: $dateFrom, to: $dateTo, label: "Report date range") {
                // No reload needed — date is applied at export-time.
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Export CRM data").font(.headline)
            Text("Download leads, contacts, or deals as a CSV. The location filter (top of CRM) and the date range below are both applied.")
                .font(.caption).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private var dateRangeRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .foregroundColor(dateFrom != nil || dateTo != nil ? Brand.red : .secondary)
            Text(dateRangeLabel)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(dateFrom != nil || dateTo != nil ? Brand.red : .secondary)
            Spacer()
            if dateFrom != nil || dateTo != nil {
                Button {
                    dateFrom = nil; dateTo = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.red)
                }
            }
            Button("Change") { showDateFilter = true }
                .font(.system(size: 13, weight: .bold))
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Brand.red)
                .foregroundColor(.white)
                .clipShape(Capsule())
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
    }

    private var dateRangeLabel: String {
        let fmt = DateFormatter(); fmt.dateFormat = "MMM d, yyyy"
        switch (dateFrom, dateTo) {
        case (nil, nil): return "All dates"
        case (let f?, nil): return "From \(fmt.string(from: f))"
        case (nil, let t?): return "Up to \(fmt.string(from: t))"
        case (let f?, let t?): return "\(fmt.string(from: f)) → \(fmt.string(from: t))"
        }
    }

    private func exportCard(title: String, subtitle: String, icon: String, color: Color, action: @escaping () async -> Void) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(color.opacity(0.15)).frame(width: 44, height: 44)
                    Image(systemName: icon).foregroundColor(color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 15, weight: .bold)).foregroundColor(Color(uiColor: .label))
                    Text(subtitle).font(.caption).foregroundColor(.gray)
                }
                Spacer()
                if isBusy {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.down.doc.fill").foregroundColor(color)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
    }

    // MARK: Export logic

    private static let isoFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f
    }()

    private var isoFrom: String? { dateFrom.map { Self.isoFmt.string(from: $0) } }
    private var isoTo: String? { dateTo.map { Self.isoFmt.string(from: $0) } }

    private func exportLeads() async {
        await runExport(filenamePrefix: "leads") {
            // The header claims "the location filter (top of CRM)" is
            // applied — actually apply it. Pulls the global picker out
            // of CRMLocationStore so the CSV honours the chosen city /
            // state instead of dumping every assigned region.
            let loc = CRMLocationStore.shared
            let rows = try await CRMService.shared.listLeads(
                city: loc.city, state: loc.state,
                from: self.isoFrom, to: self.isoTo
            )
            let headers = ["id","first_name","last_name","email","phone","company","title","status","score","city","state","is_b2c","created_at"]
            var lines: [String] = [headers.joined(separator: ",")]
            for l in rows {
                lines.append([
                    l.id, l.firstName ?? "", l.lastName ?? "", l.email ?? "", l.phone ?? "",
                    l.company ?? "", l.title ?? "", l.status ?? "", String(l.score ?? 0),
                    l.city ?? "", l.state ?? "", String(l.isB2c ?? false), l.createdAt ?? "",
                ].map(self.escape).joined(separator: ","))
            }
            return (lines.joined(separator: "\n"), rows.count)
        }
    }

    private func exportContacts() async {
        await runExport(filenamePrefix: "contacts") {
            let rows = try await CRMService.shared.listContacts()
            let filtered = self.filterByCreatedAt(rows: rows, getDate: { $0.createdAt })
            let headers = ["id","first_name","last_name","email","phone","account_name","title","city","created_at"]
            var lines: [String] = [headers.joined(separator: ",")]
            for c in filtered {
                lines.append([
                    c.id, c.firstName ?? "", c.lastName ?? "", c.email ?? "", c.phone ?? "",
                    c.accountName ?? "", c.title ?? "", c.city ?? "", c.createdAt ?? "",
                ].map(self.escape).joined(separator: ","))
            }
            return (lines.joined(separator: "\n"), filtered.count)
        }
    }

    private func exportDeals() async {
        await runExport(filenamePrefix: "deals") {
            let rows = try await CRMService.shared.listDeals(from: self.isoFrom, to: self.isoTo)
            let headers = ["id","name","amount","currency","status","stage_id","win_probability","expected_close_date","account_id","created_at"]
            var lines: [String] = [headers.joined(separator: ",")]
            for d in rows {
                lines.append([
                    d.id, d.name, String(d.amount ?? 0), d.currency ?? "INR",
                    d.status ?? "", d.stageId ?? "", String(d.winProbability ?? 0),
                    d.expectedCloseDate ?? "", d.accountId ?? "", d.createdAt ?? "",
                ].map(self.escape).joined(separator: ","))
            }
            return (lines.joined(separator: "\n"), rows.count)
        }
    }

    /// CRM contacts endpoint doesn't accept from/to params, so we filter
    /// client-side on the `created_at` ISO timestamp.
    private func filterByCreatedAt<T>(rows: [T], getDate: (T) -> String?) -> [T] {
        if dateFrom == nil && dateTo == nil { return rows }
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let alt = ISO8601DateFormatter()
        return rows.filter { row in
            guard let s = getDate(row), let d = parser.date(from: s) ?? alt.date(from: s) else { return false }
            if let f = dateFrom, d < Calendar.current.startOfDay(for: f) { return false }
            if let t = dateTo {
                let endOfT = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: t)) ?? t
                if d >= endOfT { return false }
            }
            return true
        }
    }

    private func runExport(filenamePrefix: String, build: () async throws -> (csv: String, count: Int)) async {
        await MainActor.run {
            isBusy = true
            statusMessage = nil
        }
        defer { Task { @MainActor in isBusy = false } }
        do {
            let (csv, count) = try await build()
            let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
            let filename = "\(filenamePrefix)-\(fmt.string(from: Date())).csv"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
            try csv.write(to: url, atomically: true, encoding: .utf8)
            // Small delay so isBusy=false animation lands before the sheet pops.
            try? await Task.sleep(nanoseconds: 200_000_000)
            await MainActor.run {
                statusIsError = false
                statusMessage = "Exported \(count) rows → \(filename)"
                shareItem = ShareItem(url: url)
            }
        } catch {
            await MainActor.run {
                statusIsError = true
                statusMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func escape(_ s: String) -> String {
        let needsQuoting = s.contains(",") || s.contains("\"") || s.contains("\n")
        let escaped = s.replacingOccurrences(of: "\"", with: "\"\"")
        return needsQuoting ? "\"\(escaped)\"" : escaped
    }
}

/// Identifiable wrapper whose id is the file URL itself (stable across reads).
/// The previous implementation used `let id = UUID()` which generated a fresh
/// identity on every Binding `get`, confusing SwiftUI's sheet(item:) tracking
/// and preventing the share sheet from appearing.
private struct ShareItem: Identifiable {
    var id: URL { url }
    let url: URL
}

private struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

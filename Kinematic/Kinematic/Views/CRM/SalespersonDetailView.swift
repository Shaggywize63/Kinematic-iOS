import SwiftUI

/// Per-salesperson sales & target drill-down (mirrors the web dashboard).
/// Reached from the Reports → "Salesperson Sales" picker, or by tapping a rep
/// on the Targets leaderboard. Shows, for a selected IST month: the monthly
/// sales target (target / achieved / pending / progress + achievement basis),
/// the customers contributing this month, daily & weekly progress, a 6-month
/// target-vs-achieved history, and the leads assigned to the rep (each links to
/// its detail, whose Recent Updates timeline is the follow-up history).
struct SalespersonDetailView: View {
    @StateObject private var vm: SalespersonDetailViewModel

    init(userId: String) {
        _vm = StateObject(wrappedValue: SalespersonDetailViewModel(userId: userId))
    }

    private var countLabel: String { (vm.detail?.isWonDealsBasis ?? true) ? "orders" : "entries" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                monthHeader
                targetCard
                if let d = vm.detail {
                    customersCard(d)
                    progressCard(title: "Daily progress",
                                 rows: d.daily.map { ProgressDatum(id: $0.id, label: Self.dayLabel($0.date), value: $0.value, count: $0.count) },
                                 empty: "No daily sales this month.")
                    progressCard(title: "Weekly progress",
                                 rows: d.weekly.map { ProgressDatum(id: $0.id, label: "Week of " + Self.dayLabel($0.weekStart), value: $0.value, count: $0.count) },
                                 empty: "No weekly sales this month.")
                    historyCard(d)
                }
                leadsSection
            }
            .padding()
        }
        .navigationTitle(vm.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.start() }
    }

    // MARK: Month header + basis badge
    private var monthHeader: some View {
        HStack(spacing: 12) {
            Button { vm.prevMonth() } label: { Image(systemName: "chevron.left") }
            Text(Self.monthLabel(vm.month)).font(.system(size: 16, weight: .semibold))
            Button { vm.nextMonth() } label: { Image(systemName: "chevron.right") }
                .disabled(!vm.canGoNext)
                .foregroundColor(vm.canGoNext ? Brand.red : .secondary)
            Spacer()
            if let b = vm.detail?.basis { basisBadge(b) }
        }
        .foregroundColor(Brand.red)
    }

    private func basisBadge(_ basis: String) -> some View {
        let won = basis == "won_deals"
        let tone = won ? Brand.success : Color.secondary
        return Text(won ? "From won deals" : "From logged entries")
            .font(.system(size: 10, weight: .bold))
            .foregroundColor(tone)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(tone.opacity(0.12))
            .clipShape(Capsule())
    }

    // MARK: Target card
    private var targetCard: some View {
        card("Monthly sales target") {
            if vm.loadingDetail && vm.detail == nil {
                Text("Loading…").font(.caption).foregroundColor(.secondary)
            } else if let d = vm.detail {
                let cols = [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: cols, spacing: 10) {
                    kpi("Target", d.target.map { CurrencyFormatter.formatINRCompact($0) } ?? "—")
                    kpi("Achieved", CurrencyFormatter.formatINRCompact(d.achieved), strong: true)
                    kpi("Pending", d.pending.map { CurrencyFormatter.formatINRCompact($0) } ?? "—")
                    kpi("Progress", d.pct.map { "\($0)%" } ?? "—")
                }
            } else {
                Text("No target data available for this salesperson.")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
    }

    // MARK: Customers
    private func customersCard(_ d: SalespersonTargetDetail) -> some View {
        card("Customers this month (\(d.customers.count))") {
            if d.customers.isEmpty {
                Text("No sales recorded in this month.").font(.caption).foregroundColor(.secondary)
            } else {
                let top = d.customers.first?.value ?? 0
                VStack(spacing: 10) {
                    ForEach(d.customers) { c in
                        progressRow(label: c.name ?? "Unknown",
                                    value: CurrencyFormatter.formatINRCompact(c.value),
                                    sub: "\(c.count) \(countLabel)",
                                    frac: top > 0 ? c.value / top : 0)
                    }
                }
            }
        }
    }

    // MARK: Daily / weekly progress
    private struct ProgressDatum: Identifiable { let id: String; let label: String; let value: Double; let count: Int }
    private func progressCard(title: String, rows: [ProgressDatum], empty: String) -> some View {
        card(title) {
            if rows.isEmpty {
                Text(empty).font(.caption).foregroundColor(.secondary)
            } else {
                let top = rows.map(\.value).max() ?? 0
                VStack(spacing: 10) {
                    ForEach(rows) { r in
                        progressRow(label: r.label,
                                    value: CurrencyFormatter.formatINRCompact(r.value),
                                    sub: "\(r.count) \(countLabel)",
                                    frac: top > 0 ? r.value / top : 0)
                    }
                }
            }
        }
    }

    // MARK: 6-month history
    private func historyCard(_ d: SalespersonTargetDetail) -> some View {
        card("Target vs achieved — last 6 months") {
            VStack(spacing: 10) {
                ForEach(d.historical) { h in
                    let frac = Double(min(max(h.pct ?? 0, 0), 100)) / 100.0
                    progressRow(label: Self.monthLabel(h.month),
                                value: CurrencyFormatter.formatINRCompact(h.achieved),
                                sub: (h.target.map { "of " + CurrencyFormatter.formatINRCompact($0) } ?? "no target")
                                    + (h.pct.map { " · \($0)%" } ?? ""),
                                frac: frac,
                                color: (h.pct ?? 0) >= 100 ? Brand.success : Brand.red)
                }
            }
        }
    }

    // MARK: Leads
    private var leadsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Leads (\(vm.shownLeads.count))").font(.system(size: 16, weight: .semibold))
                Spacer()
                if !vm.leadStatuses.isEmpty {
                    Menu {
                        Button("All statuses") { vm.statusFilter = nil }
                        ForEach(vm.leadStatuses, id: \.self) { s in Button(s) { vm.statusFilter = s } }
                    } label: {
                        HStack(spacing: 4) {
                            Text(vm.statusFilter ?? "All statuses")
                            Image(systemName: "chevron.down").font(.caption2)
                        }
                        .font(.system(size: 13, weight: .semibold)).foregroundColor(Brand.red)
                    }
                }
            }
            if vm.shownLeads.isEmpty {
                Text("No leads assigned.").font(.caption).foregroundColor(.secondary).padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(vm.shownLeads.enumerated()), id: \.element.id) { idx, lead in
                        NavigationLink(destination: LeadDetailView(leadId: lead.id)) {
                            HStack {
                                Text(Self.leadName(lead)).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                                    .foregroundColor(.primary)
                                Spacer()
                                statusPill(lead.status)
                                Image(systemName: "chevron.right").font(.caption2).foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12).padding(.vertical, 12)
                        }
                        if idx < vm.shownLeads.count - 1 { Divider() }
                    }
                }
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(12)
            }
        }
    }

    // MARK: Reusable pieces
    @ViewBuilder
    private func card<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 15, weight: .semibold))
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(14)
    }

    private func kpi(_ label: String, _ value: String, strong: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
            Text(value).font(.system(size: strong ? 18 : 16, weight: strong ? .heavy : .bold)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(uiColor: .tertiarySystemBackground))
        .cornerRadius(10)
    }

    private func progressRow(label: String, value: String, sub: String, frac: Double, color: Color = Brand.red) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.system(size: 13)).lineLimit(1)
                Spacer()
                Text(value).font(.system(size: 13, weight: .semibold))
            }
            ProgressView(value: min(max(frac, 0), 1)).tint(color)
            Text(sub).font(.system(size: 11)).foregroundColor(.secondary)
        }
    }

    private func statusPill(_ status: String?) -> some View {
        let s = status ?? "—"
        let tone: Color
        switch s {
        case "converted", "won": tone = Brand.success
        case "lost", "unqualified": tone = Brand.red
        case "working", "negotiation": tone = .orange
        default: tone = .secondary
        }
        return Text(s.capitalized)
            .font(.system(size: 11, weight: .bold)).foregroundColor(tone)
            .padding(.horizontal, 8).padding(.vertical, 2)
            .overlay(Capsule().stroke(tone, lineWidth: 1))
    }

    // MARK: Formatting helpers
    private static let MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

    static func leadName(_ l: Lead) -> String {
        let n = [l.firstName, l.lastName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        if !n.isEmpty { return n }
        if let c = l.company, !c.isEmpty { return c }
        return "Lead"
    }
    /// "YYYY-MM" → "Nov 2026".
    static func monthLabel(_ ym: String?) -> String {
        let p = (ym ?? "").split(separator: "-")
        guard p.count == 2, let y = Int(p[0]), let m = Int(p[1]), (1...12).contains(m) else { return ym ?? "—" }
        return "\(MONTHS[m - 1]) \(y)"
    }
    /// "YYYY-MM-DD" → "12 Nov".
    static func dayLabel(_ d: String?) -> String {
        let p = (d ?? "").split(separator: "-")
        guard p.count == 3, let m = Int(p[1]), let day = Int(p[2]), (1...12).contains(m) else { return d ?? "—" }
        return "\(day) \(MONTHS[m - 1])"
    }
}

import SwiftUI

/// Rep-facing "My Incentives" — the signed-in salesman's own earnings for the
/// chosen window, plus the recent accrual lines behind them. Reads only
/// `/distribution/incentives/me`, which the backend force-scopes to the caller,
/// so a rep never sees another rep's figures (the manager dashboard and the
/// leaderboard live on the web). Gated on the `distribution_incentives` module.
///
/// Periods resolve on the IST calendar server-side (the same `today / week /
/// month / all` the web page uses), so a month never rolls over at the server's
/// midnight.
struct MyIncentivesView: View {
    @State private var period = "month"
    @State private var data: MyIncentives?
    @State private var loading = true
    @State private var failed = false

    private let periods = ["today", "week", "month", "all"]
    private func periodLabel(_ p: String) -> String {
        switch p {
        case "today": return "Today"
        case "week":  return "This week"
        case "all":   return "All time"
        default:      return "This month"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Period", selection: $period) {
                    ForEach(periods, id: \.self) { Text(periodLabel($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: period) { _ in Task { await load() } }

                if loading {
                    HStack { Spacer(); ProgressView().padding(.top, 40); Spacer() }
                } else if let d = data {
                    summaryCards(d)
                    entriesSection(d)
                } else if failed {
                    emptyState("Couldn't load your incentives.",
                               "Pull to refresh, or try again in a moment.")
                }
            }
            .padding()
        }
        .navigationTitle("My Incentives")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    // ── Summary ──────────────────────────────────────────────────────────────
    @ViewBuilder
    private func summaryCards(_ d: MyIncentives) -> some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible())]
        LazyVGrid(columns: cols, spacing: 10) {
            card("Payable now", rupees(d.payable_amount),
                 "\(d.order_count) order\(d.order_count == 1 ? "" : "s")", Brand.success)
            card("Already paid", rupees(d.paid_amount), "settled", .secondary)
            card("Reversed", rupees(d.reversed_amount), "cancelled orders", Brand.red)
            card("Earned", rupees(d.earned_amount), d.period, .primary)
        }
    }

    private func card(_ label: String, _ value: String, _ sub: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
            Text(value).font(.system(size: 18, weight: .bold)).foregroundColor(tint).lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(sub).font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }

    // ── Ledger ───────────────────────────────────────────────────────────────
    @ViewBuilder
    private func entriesSection(_ d: MyIncentives) -> some View {
        Text("Recent orders").font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
            .padding(.top, 6)
        if d.entries.isEmpty {
            emptyState("Nothing yet for \(d.period.lowercased()).",
                       "When one of your orders is approved, your 2% shows up here.")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(d.entries.enumerated()), id: \.element.id) { idx, e in
                    entryRow(e)
                    if idx < d.entries.count - 1 { Divider() }
                }
            }
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(12)
        }
    }

    private func entryRow(_ e: IncentiveEntry) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(rupees(e.amount)).font(.system(size: 15, weight: .bold))
                    .foregroundColor(e.status == "reversed" ? Brand.red : .primary)
                    .strikethrough(e.status == "reversed", color: Brand.red)
                Text("\(ratePct(e.rate_pct)) of \(rupees(e.basis_amount)) · \(basisLabel(e.basis))")
                    .font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
                if e.status == "reversed", let reason = e.reversal_reason, !reason.isEmpty {
                    Text(reason).font(.system(size: 10)).foregroundColor(Brand.red).lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                statusPill(e.status)
                Text(shortDate(e.earned_at)).font(.system(size: 11)).foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private func statusPill(_ status: String) -> some View {
        let (text, color): (String, Color) = {
            switch status {
            case "paid":     return ("Paid", .secondary)
            case "reversed": return ("Reversed", Brand.red)
            default:          return ("Payable", Brand.success)
            }
        }()
        return Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundColor(color)
            .cornerRadius(6)
    }

    private func emptyState(_ title: String, _ sub: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "indianrupeesign.circle")
                .font(.system(size: 40)).foregroundColor(.secondary)
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(sub).font(.system(size: 12)).foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 28)
    }

    // ── Formatting ───────────────────────────────────────────────────────────
    private func rupees(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = v.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 2
        f.locale = Locale(identifier: "en_IN")
        return "₹" + (f.string(from: NSNumber(value: v)) ?? String(format: "%.0f", v))
    }
    private func ratePct(_ v: Double) -> String {
        v.truncatingRemainder(dividingBy: 1) == 0 ? "\(Int(v))%" : String(format: "%.2f%%", v)
    }
    private func basisLabel(_ basis: String) -> String {
        basis == "grand_total" ? "incl. GST" : "net"
    }
    /// The API's `earned_at` is an ISO-8601 timestamp; show just the day.
    private func shortDate(_ iso: String) -> String {
        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = parser.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)
        guard let d = date else { return String(iso.prefix(10)) }
        let out = DateFormatter()
        out.dateFormat = "d MMM"
        out.locale = Locale(identifier: "en_IN")
        return out.string(from: d)
    }

    private func load() async {
        loading = data == nil
        failed = false
        if let d = await DistributionAPI.shared.myIncentives(period: period) {
            data = d
        } else {
            failed = true
        }
        loading = false
    }
}

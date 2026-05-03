import SwiftUI
import Charts

struct CRMDashboardView: View {
    @StateObject var vm = CRMDashboardViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                kpiGrid
                funnelCard
                winRateCard
                forecastCard
                aiBanner
            }
            .padding(.horizontal)
            .padding(.bottom, 40)
        }
        .navigationTitle("CRM")
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .refreshable { await vm.refresh() }
        .task { await vm.refresh() }
        .overlay {
            if vm.isLoading && vm.summary == nil {
                ProgressView().scaleEffect(1.3)
            }
        }
    }

    private var kpiGrid: some View {
        let s = vm.summary
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            kpi("Total Leads", value: "\(s?.totalLeads ?? 0)", icon: "person.2.fill", color: .blue)
            kpi("Open Deals", value: "\(s?.openDeals ?? 0)", icon: "square.stack.3d.up.fill", color: .indigo)
            kpi("Pipeline", value: shortMoney(s?.openPipelineValue ?? 0), icon: "dollarsign.circle.fill", color: .green)
            kpi("Win Rate", value: "\(Int((s?.winRate ?? 0) * 100))%", icon: "trophy.fill", color: .orange)
            kpi("Won — Mo.", value: "\(s?.dealsWonThisMonth ?? 0)", icon: "checkmark.seal.fill", color: .green)
            kpi("Tasks Due", value: "\(s?.tasksDue ?? 0)", icon: "checklist", color: .red)
        }
    }

    private func kpi(_ title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundColor(color)
            Text(value)
                .font(.system(size: 22, weight: .black))
                .foregroundColor(Color(uiColor: .label))
            Text(title.uppercased())
                .font(.system(size: 10, weight: .black))
                .tracking(0.5)
                .foregroundColor(.gray)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private var funnelCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Pipeline Funnel", systemImage: "line.3.horizontal.decrease.circle.fill")
            if vm.funnel.isEmpty {
                Text("No funnel data yet.").font(.caption).foregroundColor(.gray)
            } else {
                FunnelChartView(stages: vm.funnel)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private var winRateCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Win / Loss", systemImage: "chart.bar.xaxis")
            if vm.winRate.isEmpty {
                Text("No win/loss data yet.").font(.caption).foregroundColor(.gray)
            } else {
                PipelineBarChartView(buckets: vm.winRate)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private var forecastCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Forecast", systemImage: "chart.line.uptrend.xyaxis")
            if vm.forecast.isEmpty {
                Text("No forecast available.").font(.caption).foregroundColor(.gray)
            } else if #available(iOS 16.0, *) {
                Chart(vm.forecast) { p in
                    if let weighted = p.weighted {
                        LineMark(x: .value("Period", p.period), y: .value("Weighted", weighted))
                            .foregroundStyle(.indigo)
                    }
                    if let bestCase = p.bestCase {
                        LineMark(x: .value("Period", p.period), y: .value("Best", bestCase))
                            .foregroundStyle(.green.opacity(0.7))
                    }
                }
                .frame(height: 180)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground))
        )
    }

    private var aiBanner: some View {
        NavigationLink {
            KiniChatView()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [.purple, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 44, height: 44)
                    Image(systemName: "sparkles").foregroundColor(.white)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ask KINI")
                        .font(.headline)
                        .foregroundColor(Color(uiColor: .label))
                    Text("Score a lead, draft a follow-up, or surface deals at risk.")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundColor(.gray)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color.indigo.opacity(0.08))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.indigo.opacity(0.25), lineWidth: 1))
            )
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).foregroundColor(.indigo)
            Text(title).font(.system(size: 14, weight: .black))
            Spacer()
        }
    }

    private func shortMoney(_ v: Double) -> String {
        if v >= 1_000_000 { return String(format: "$%.1fM", v / 1_000_000) }
        if v >= 1_000 { return String(format: "$%.1fk", v / 1_000) }
        return "$\(Int(v))"
    }
}

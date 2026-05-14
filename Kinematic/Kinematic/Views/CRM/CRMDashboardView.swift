import SwiftUI
import Charts

struct CRMDashboardView: View {
    @StateObject var vm = CRMDashboardViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                // Kinematic brand mark at the top so the product identity
                // reads even when CRM is the whole app (CRM-only clients).
                HStack(spacing: 10) {
                    Image("KinematicMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 36, height: 36)
                    Text("Kinematic CRM")
                        .font(.title3.bold())
                    Spacer()
                }
                .padding(.top, 4)

                kpiGrid
                funnelCard
                winRateCard
                forecastCard
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        .navigationTitle("CRM")
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    NotificationBell()
                    NavigationLink(destination: CRMReportsView()) {
                        Image(systemName: "square.and.arrow.down.on.square")
                    }
                }
            }
        }
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
            // All KPI tile accents standardised to Brand.red per the
            // single-accent product directive. Previously each tile carried
            // its own colour (blue/indigo/green/orange) which clashed with
            // the brand palette.
            NavigationLink(destination: LeadsListView()) {
                kpiTile("Total Leads", value: "\(s?.totalLeads ?? 0)", icon: "person.2.fill", color: Brand.red)
            }.buttonStyle(.plain)
            NavigationLink(destination: DealsListView()) {
                kpiTile("Open Deals", value: "\(s?.openDeals ?? 0)", icon: "square.stack.3d.up.fill", color: Brand.red)
            }.buttonStyle(.plain)
            NavigationLink(destination: DealKanbanView()) {
                kpiTile("Pipeline", value: CurrencyFormatter.formatINRCompact(s?.openPipelineValue ?? 0), icon: "indianrupeesign.circle.fill", color: Brand.red)
            }.buttonStyle(.plain)
            NavigationLink(destination: DealsListView()) {
                kpiTile("Win Rate", value: "\(Int((s?.winRate ?? 0) * 100))%", icon: "trophy.fill", color: Brand.red)
            }.buttonStyle(.plain)
            NavigationLink(destination: DealsListView()) {
                kpiTile("Won — Mo.", value: "\(s?.dealsWonThisMonth ?? 0)", icon: "checkmark.seal.fill", color: Brand.red)
            }.buttonStyle(.plain)
            NavigationLink(destination: TasksView()) {
                kpiTile("Tasks Due", value: "\(s?.tasksDue ?? 0)", icon: "checklist", color: Brand.red)
            }.buttonStyle(.plain)
        }
    }

    private func kpiTile(_ title: String, value: String, icon: String, color: Color) -> some View {
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
                            .foregroundStyle(Brand.red)
                    }
                    if let bestCase = p.bestCase {
                        LineMark(x: .value("Period", p.period), y: .value("Best", bestCase))
                            .foregroundStyle(Brand.red.opacity(0.45))
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

    private func sectionHeader(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage).foregroundColor(Brand.red)
            Text(title).font(.system(size: 14, weight: .black))
            Spacer()
        }
    }

}

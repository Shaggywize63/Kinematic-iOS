import SwiftUI

/// Reports is a thin wrapper around the dashboard analytics. The web app has
/// custom report builders — mobile parity surface a curated set of charts.
struct ReportsView: View {
    @StateObject var vm = CRMDashboardViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if vm.summary == nil && vm.isLoading { ProgressView().padding(.top, 40) }

                Group {
                    sectionCard("Funnel") { FunnelChartView(stages: vm.funnel) }
                    sectionCard("Win / Loss") { PipelineBarChartView(buckets: vm.winRate) }
                }
            }
            .padding()
        }
        .navigationTitle("Reports")
        .task { await vm.refresh() }
    }

    private func sectionCard<V: View>(_ title: String, @ViewBuilder content: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color(uiColor: .secondarySystemBackground)))
    }
}

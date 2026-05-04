import SwiftUI

struct CampaignsView: View {
    @StateObject var vm = CampaignsViewModel()

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                if vm.campaigns.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "megaphone.fill").font(.system(size: 40)).foregroundColor(.gray.opacity(0.4))
                        Text("No campaigns yet.").foregroundColor(.gray)
                        Text("Create campaigns from the web console for now.")
                            .font(.caption2).foregroundColor(.gray)
                    }
                    .padding(.top, 60)
                } else {
                    ForEach(vm.campaigns) { c in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(c.name).font(.headline)
                                Spacer()
                                if let status = c.status {
                                    Text(status.uppercased()).font(.system(size: 9, weight: .black))
                                        .padding(.horizontal, 6).padding(.vertical, 2)
                                        .background(Color.orange.opacity(0.15)).foregroundColor(.orange).cornerRadius(4)
                                }
                            }
                            HStack(spacing: 16) {
                                if let b = c.budget { Label("$\(Int(b))", systemImage: "dollarsign.circle").font(.caption).foregroundColor(.secondary) }
                                if let r = c.actualRevenue { Label("Rev $\(Int(r))", systemImage: "chart.line.uptrend.xyaxis").font(.caption).foregroundColor(.green) }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color(uiColor: .secondarySystemBackground)))
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Campaigns")
        .refreshable { await vm.refresh() }
        .task { await vm.refresh() }
    }
}

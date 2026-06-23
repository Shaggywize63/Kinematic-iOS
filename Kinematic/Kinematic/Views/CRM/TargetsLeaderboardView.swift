import SwiftUI

/// Manager-facing Targets leaderboard — who entered the most leads, who's
/// behind, average per person, and target attainment, for the chosen window.
/// Scoped to one hierarchy role (e.g. Consumer Champion), configurable here.
/// Mirrors the web Lead Analytics "Targets Leaderboard" widget.
struct TargetsLeaderboardView: View {
    @State private var period = "today"
    @State private var board: CRMLeaderboard?
    @State private var levels: [CRMHierarchyLevel] = []
    @State private var roleId: String?
    @State private var loading = true
    // Global CRM city picker — refetch the board when the picker
    // changes. `/leaderboard` is in the city-aware whitelist, so the
    // request itself already carries the city; this just rebinds the
    // `.task` so a new fetch fires.
    @ObservedObject private var location = CRMLocationStore.shared

    private let periods = ["today", "week", "month"]
    private func periodLabel(_ p: String) -> String {
        switch p { case "week": return "This week"; case "month": return "This month"; default: return "Today" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("Period", selection: $period) {
                    ForEach(periods, id: \.self) { Text(periodLabel($0)).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: period) { _ in Task { await loadBoard() } }

                if !levels.isEmpty {
                    Menu {
                        Button("All field force") { Task { await setRole(nil) } }
                        ForEach(levels) { l in
                            Button(l.name) { Task { await setRole(l.id) } }
                        }
                    } label: {
                        HStack {
                            Image(systemName: "person.3")
                            Text(roleId.flatMap { id in levels.first { $0.id == id }?.name } ?? "All field force")
                            Image(systemName: "chevron.down").font(.caption)
                        }
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Brand.red)
                    }
                }

                if loading {
                    HStack { Spacer(); ProgressView().padding(.top, 40); Spacer() }
                } else if let b = board {
                    statCards(b.stats)
                    if b.entries.isEmpty {
                        Text("No leads entered in this period yet.")
                            .font(.caption).foregroundColor(.secondary).padding(.top, 8)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(b.entries.enumerated()), id: \.element.id) { idx, e in
                                rankRow(rank: idx + 1, entry: e)
                                if idx < b.entries.count - 1 { Divider() }
                            }
                        }
                        .background(Color(uiColor: .secondarySystemBackground))
                        .cornerRadius(12)
                    }
                } else {
                    Text("Couldn't load the leaderboard.")
                        .font(.caption).foregroundColor(.secondary).padding(.top, 8)
                }
            }
            .padding()
        }
        .navigationTitle("Leaderboard")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadAll() }
        .task(id: location.city ?? "") { await loadBoard() }
    }

    @ViewBuilder
    private func statCards(_ s: CRMLeaderboardStats) -> some View {
        let cols = [GridItem(.flexible()), GridItem(.flexible())]
        LazyVGrid(columns: cols, spacing: 10) {
            statCard("🏆 Top performer", s.topPerformer?.name ?? "—",
                     s.topPerformer.map { "\($0.leads) leads" } ?? "No leads yet")
            statCard("📉 Needs a nudge", s.lowestPerformer?.name ?? "—",
                     s.lowestPerformer.map { "\($0.leads) leads" } ?? "—")
            statCard("Avg / person", String(format: "%.1f", s.averageLeads), "\(s.totalLeads) total")
            statCard("Meeting target", "\(s.meetingTarget)/\(s.targetParticipants)", "\(s.participants) on board")
        }
    }

    private func statCard(_ label: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
            Text(value).font(.system(size: 16, weight: .bold)).lineLimit(1)
            Text(sub).font(.system(size: 11)).foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }

    private func rankRow(rank: Int, entry e: CRMLeaderboardEntry) -> some View {
        let medal = rank == 1 ? "🥇" : rank == 2 ? "🥈" : rank == 3 ? "🥉" : "\(rank)"
        let hit = e.target > 0 && e.leads >= e.target
        let pctColor: Color = e.target == 0 ? .secondary : (hit ? Brand.success : (e.pct ?? 0) >= 60 ? .orange : Brand.red)
        return HStack(spacing: 12) {
            Text(medal).font(.system(size: 15, weight: .bold)).frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(e.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                Text(e.city ?? "—").font(.system(size: 11)).foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(e.leads)").font(.system(size: 15, weight: .bold))
                Text(e.target > 0 ? "of \(e.target)" : "—").font(.system(size: 11)).foregroundColor(.secondary)
            }
            Text(e.pct.map { "\($0)%" } ?? "—")
                .font(.system(size: 12, weight: .bold)).foregroundColor(pctColor)
                .frame(width: 44, alignment: .trailing)
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private func loadAll() async {
        levels = await CRMService.shared.listHierarchyLevels()
        roleId = await CRMService.shared.getLeaderboardRole()
        await loadBoard()
    }
    private func loadBoard() async {
        loading = true
        board = await CRMService.shared.leaderboard(period: period)
        roleId = board?.roleId ?? roleId
        loading = false
    }
    private func setRole(_ id: String?) async {
        _ = await CRMService.shared.setLeaderboardRole(id)
        roleId = id
        await loadBoard()
    }
}

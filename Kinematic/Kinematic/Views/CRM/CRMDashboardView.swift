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
                    KinematicBrandMark(size: 36)
                    Text("Kinematic CRM")
                        .font(.title3.bold())
                    Spacer()
                }
                .padding(.top, 4)

                if vm.canSwitchClient { clientScopePicker }

                // Date-range filter — drives every analytics card below
                // (kpi / funnel / win-rate). Default is "Last 7 days"
                // per the user's "show each data by default for 7 days".
                Picker("Range", selection: $vm.range) {
                    ForEach(CRMDashboardViewModel.DateRangePreset.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                if vm.range == .custom {
                    DatePicker("From", selection: $vm.customFrom, displayedComponents: .date)
                    DatePicker("To", selection: $vm.customTo, displayedComponents: .date)
                }

                if let t = vm.target, t.hasTarget { targetTicker(t) }

                kpiGrid
                DashboardLeadsMapCard()
                funnelCard
                winRateCard
                // Forecast (Quarter) card removed at the user's request — its
                // rolling-quarter window didn't line up with the date filter
                // and was confusing reps. The detail report stays reachable
                // through the Reports hub.
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 40)
        }
        // No navigationTitle — the "Kinematic CRM" mark + wordmark inside
        // the scroll content is the single source of identity. Setting a
        // navigationTitle here would render a second "CRM" header above it.
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .background(Color(uiColor: .systemBackground).ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    // Chat sits adjacent to the notification bell, matching
                    // the dashboard's header placement. CRMTabView wraps this
                    // view in a NavigationStack so this push lands inside the
                    // active tab — no full-screen cover needed.
                    NavigationLink(destination: ChatListView()) {
                        Image(systemName: "bubble.left.and.bubble.right")
                    }
                    NotificationBell()
                    NavigationLink(destination: CRMReportsHubView()) {
                        Image(systemName: "square.and.arrow.down.on.square")
                    }
                }
            }
        }
        .refreshable { await vm.refresh() }
        // .task(id:) re-fires the refresh when the rep picks a new
        // preset or moves a custom date, so the dashboard reactively
        // re-pulls every analytics endpoint with the new window.
        .task(id: "\(vm.range.rawValue)|\(vm.customFrom.timeIntervalSince1970)|\(vm.customTo.timeIntervalSince1970)") {
            await vm.refresh()
        }
        .task { await vm.loadClientsIfNeeded() }
        .overlay {
            if vm.isLoading && vm.summary == nil {
                ProgressView().scaleEffect(1.3)
            }
        }
    }

    /// Org-level admin client filter. Picking a client stamps X-Client-Id on
    /// every CRM call and re-pulls the dashboard scoped to that client; "All
    /// Clients" clears the scope back to the org-wide view. Mirrors the web
    /// ClientSelect + CrmScopeBadge behaviour.
    private var clientScopePicker: some View {
        Menu {
            Button {
                Task { await vm.selectClient(nil) }
            } label: {
                Label("All Clients", systemImage: vm.selectedClientId == nil ? "checkmark" : "globe")
            }
            Divider()
            ForEach(vm.clients) { c in
                Button {
                    Task { await vm.selectClient(c.id) }
                } label: {
                    Label(c.name, systemImage: vm.selectedClientId == c.id ? "checkmark" : "building.2")
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: vm.selectedClientId == nil ? "globe" : "building.2.fill")
                    .foregroundColor(Brand.red)
                VStack(alignment: .leading, spacing: 1) {
                    Text(vm.selectedClientId == nil ? "ORG-WIDE VIEW" : "VIEWING CLIENT")
                        .font(.system(size: 9, weight: .black)).tracking(0.6)
                        .foregroundColor(.gray)
                    Text(vm.selectedClientName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(uiColor: .label))
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.gray)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemBackground)))
        }
    }

    /// Today's lead-target ticker for field executives. Shows progress toward
    /// the daily target set by their manager (Settings → Targets).
    private func targetTicker(_ t: CRMTarget) -> some View {
        let pct = t.target > 0 ? min(Double(t.achieved) / Double(t.target), 1.0) : 0
        let done = t.achieved >= t.target
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: done ? "checkmark.seal.fill" : "target")
                    .foregroundColor(done ? Brand.success : Brand.red)
                Text("TODAY'S TARGET")
                    .font(.system(size: 11, weight: .black)).tracking(0.8).foregroundColor(.gray)
                Spacer()
                Text("\(t.achieved)/\(t.target) leads")
                    .font(.system(size: 14, weight: .black))
                    .foregroundColor(done ? Brand.success : Color(uiColor: .label))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(uiColor: .tertiarySystemFill)).frame(height: 8)
                    Capsule().fill(done ? Brand.success : Brand.red)
                        .frame(width: max(geo.size.width * pct, pct > 0 ? 8 : 0), height: 8)
                }
            }
            .frame(height: 8)
            Text(done ? "Target reached — nice work." : "\(max(t.target - t.achieved, 0)) more to hit today's goal")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(uiColor: .secondarySystemBackground)))
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
                kpiTile("Won — 30d", value: "\(s?.dealsWonThisMonth ?? 0)", icon: "checkmark.seal.fill", color: Brand.red)
            }.buttonStyle(.plain)
            NavigationLink(destination: DealKanbanView()) {
                kpiTile("Open Volume", value: formattedVolumeMT(s?.openDealVolume), icon: "shippingbox.fill", color: Brand.red)
            }.buttonStyle(.plain)
            NavigationLink(destination: DealsListView()) {
                kpiTile("Avg Deal", value: CurrencyFormatter.formatINRCompact(s?.averageDealSize ?? 0), icon: "chart.bar.fill", color: Brand.red)
            }.buttonStyle(.plain)
            NavigationLink(destination: LeadsListView()) {
                kpiTile("New Leads — 30d", value: "\(s?.newLeadsThisWeek ?? 0)", icon: "sparkles", color: Brand.red)
            }.buttonStyle(.plain)
            NavigationLink(destination: ActivitiesView()) {
                kpiTile("Activities — 7d", value: "\(s?.activitiesToday ?? 0)", icon: "bolt.fill", color: Brand.red)
            }.buttonStyle(.plain)
        }
    }

    /// Open-pipeline tonnage arrives in kg; the dashboard surfaces it as MT
    /// (metric tonnes) to match the web KPI. Compact so the value never
    /// overflows the small tile (e.g. "1.2K MT", "850 MT").
    private func formattedVolumeMT(_ kg: Double?) -> String {
        let mt = (kg ?? 0) / 1000.0
        if mt <= 0 { return "0 MT" }
        if mt >= 1000 { return String(format: "%.1fK MT", mt / 1000.0) }
        if mt >= 100 { return String(format: "%.0f MT", mt) }
        return String(format: "%.1f MT", mt)
    }

    private func kpiTile(_ title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).foregroundColor(color)
            Text(value)
                .font(.system(size: 22, weight: .black))
                .foregroundColor(Color(uiColor: .label))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(title.uppercased())
                .font(.system(size: 10, weight: .black))
                .tracking(0.5)
                .foregroundColor(.gray)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
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

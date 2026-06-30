import SwiftUI

extension Notification.Name {
    /// Posted by the lead-create form when a lead lands in the offline
    /// queue instead of hitting the network. The list screen shows a
    /// transient toast in response.
    static let kmLeadSavedOffline = Notification.Name("KMLeadSavedOffline")
}

struct LeadsListView: View {
    @StateObject var vm = LeadsViewModel()
    @StateObject private var queue = OfflineLeadQueue.shared
    @State private var showCreate = false
    @State private var showScanCard = false
    @State private var showImport = false
    @State private var showDateFilter = false
    @State private var showFilters = false
    @State private var offlineToast = false

    let statusOptions = ["all", "new", "contacted", "qualified", "unqualified", "converted"]

    // (label, sort key, ascending). "recent" = backend default order.
    private let sortOptions: [(String, String, Bool)] = [
        ("Most recent activity", "recent", false),
        ("Date added (newest)", "created", false),
        ("Date added (oldest)", "created", true),
        ("Name (A–Z)", "name", true),
        ("Name (Z–A)", "name", false),
        ("Company (A–Z)", "company", true),
        ("Score (high–low)", "score", false),
        ("Score (low–high)", "score", true),
        ("Last updated", "updated", false),
    ]

    private var sortMenu: some View {
        Menu {
            ForEach(sortOptions, id: \.0) { opt in
                Button {
                    vm.sortKey = opt.1
                    vm.sortAscending = opt.2
                    Task { await vm.refresh() }
                } label: {
                    Label(opt.0, systemImage:
                            (vm.sortKey == opt.1 && (opt.1 == "recent" || vm.sortAscending == opt.2)) ? "checkmark" : "")
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
                .foregroundColor(vm.sortKey == "recent" ? .secondary : Brand.red)
        }
    }

    /// Shared lead-submission handler used by both the manual create sheet
    /// and the "Scan business card" flow, so a scanned lead saves through
    /// the identical online / offline-queue path.
    private func submitLead(_ body: [String: Any]) async -> Bool {
        let outcome = await vm.create(body: body)
        switch outcome {
        case .online:
            return true
        case .offline:
            // Defer to the toast — UI presents this via the viewmodel's
            // errorMessage / OfflineLeadQueue.pendingCount observer below.
            // Dismiss the form so the rep can move on; the queued lead
            // syncs in the bg.
            NotificationCenter.default.post(name: .kmLeadSavedOffline, object: nil)
            return true
        case .error:
            // Keep the form open so the rep can fix + retry — the alert
            // inside LeadCreateView surfaces the failure.
            return false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if queue.pendingCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "icloud.slash")
                        .foregroundColor(.orange)
                    Text("\(queue.pendingCount) lead\(queue.pendingCount == 1 ? "" : "s") waiting to sync")
                        .font(.caption.bold())
                        .foregroundColor(.primary)
                    Spacer()
                    Button("Retry") { queue.drain() }
                        .font(.caption.bold())
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.12))
            }
            if offlineToast {
                HStack {
                    Image(systemName: "icloud.and.arrow.up").foregroundColor(.green)
                    Text("Saved offline — will sync when online")
                        .font(.caption.bold())
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(Color.green.opacity(0.12))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.gray)
                TextField("Search leads…", text: $vm.search)
                    .textFieldStyle(.plain)
                    .autocapitalization(.none)
                if vm.dateFrom != nil || vm.dateTo != nil {
                    Button { vm.dateFrom = nil; vm.dateTo = nil; Task { await vm.refresh() } } label: {
                        Image(systemName: "calendar.badge.minus").foregroundColor(Brand.red)
                    }
                }
                Button { showFilters = true } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .foregroundColor(vm.activeFilterCount > 0 ? Brand.red : .secondary)
                        if vm.activeFilterCount > 0 {
                            Text("\(vm.activeFilterCount)")
                                .font(.system(size: 9, weight: .black)).foregroundColor(.white)
                                .frame(width: 14, height: 14).background(Brand.red).clipShape(Circle())
                                .offset(x: 6, y: -6)
                        }
                    }
                }
                sortMenu
            }
            .padding(10)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(10)
            .padding(.horizontal)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(statusOptions, id: \.self) { s in
                        Button {
                            vm.statusFilter = s
                            Task { await vm.refresh() }
                        } label: {
                            Text(s.uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .padding(.horizontal, 12).padding(.vertical, 6)
                                .background(vm.statusFilter == s ? Brand.red : Color(uiColor: .secondarySystemBackground))
                                .foregroundColor(vm.statusFilter == s ? .white : .secondary)
                                .cornerRadius(8)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            // Total count — server-reported across all pages.
            if vm.total > 0 {
                HStack {
                    Text(vm.leads.count >= vm.total
                         ? "\(vm.total) lead\(vm.total == 1 ? "" : "s")"
                         : "Showing \(vm.leads.count) of \(vm.total) leads")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal).padding(.bottom, 4)
            }

            ScrollView {
                LazyVStack(spacing: 10) {
                    if vm.isLoading && vm.leads.isEmpty {
                        ProgressView().tint(Brand.red).padding(.top, 40)
                    } else if let err = vm.errorMessage, vm.leads.isEmpty {
                        // Surface fetch failures (most often 401 from a
                        // stale token) instead of falling through to the
                        // "No leads yet" empty state — the silent failure
                        // was the bug Hemanth ran into when his session
                        // expired and the list looked empty.
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 36))
                                .foregroundColor(Brand.red)
                            Text("Couldn't load leads")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(Color(uiColor: .label))
                            Text(err)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                            Button {
                                Task { await vm.refresh() }
                            } label: {
                                Text("Retry")
                                    .font(.system(size: 13, weight: .bold))
                                    .padding(.horizontal, 18).padding(.vertical, 10)
                                    .background(Brand.red)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                            Text("If this keeps happening, sign out and back in.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        }
                        .padding(.top, 60)
                    } else if vm.filtered.isEmpty {
                        // Real empty state — auth + fetch worked, the
                        // client just has no leads matching the current
                        // filters.
                        VStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.badge.plus")
                                .font(.system(size: 40))
                                .foregroundColor(Brand.red.opacity(0.5))
                            Text(vm.statusFilter == "all" && vm.search.isEmpty
                                 ? "No leads yet."
                                 : "No leads match your filters.")
                                .foregroundColor(.secondary)
                            Button("Create lead") { showCreate = true }
                                .buttonStyle(.borderedProminent)
                                .tint(Brand.red)
                        }
                        .padding(.top, 60)
                    } else {
                        ForEach(vm.filtered) { lead in
                            NavigationLink(destination: LeadDetailView(leadId: lead.id)) {
                                LeadRow(lead: lead)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                // Infinite scroll — load the next page as the
                                // last row appears so the whole book is reachable.
                                if lead.id == vm.leads.last?.id {
                                    Task { await vm.loadMoreIfNeeded() }
                                }
                            }
                        }
                        if vm.isLoadingMore {
                            ProgressView().tint(Brand.red).padding(.vertical, 12)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 4)
                .padding(.bottom, 40)
            }
            .refreshable { await vm.refresh() }
        }
        // Floating "+" CTA — always visible regardless of screen size.
        // The toolbar's plus button stays for muscle-memory on big phones,
        // but on a 4.7" device it shares the trailing navbar slot with the
        // chat-bubble icon and can get cramped or partially clipped. The
        // FAB guarantees the primary action is always one tap away and
        // matches the Android Compose app's existing FAB pattern on the
        // same screen.
        .overlay(alignment: .bottomTrailing) {
            Button {
                showCreate = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(Brand.red))
                    .shadow(color: Brand.red.opacity(0.4), radius: 12, x: 0, y: 6)
                    .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
            }
            .accessibilityLabel("New lead")
            .padding(.trailing, 18)
            .padding(.bottom, 22)
        }
        .navigationTitle("Leads")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink(destination: ChatListView()) {
                    Image(systemName: "bubble.left.and.bubble.right")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showScanCard = true } label: {
                    Image(systemName: "doc.viewfinder")
                }
                .accessibilityLabel("Scan business card")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add lead")
            }
        }
        .sheet(isPresented: $showCreate) {
            LeadCreateView { body in await submitLead(body) }
        }
        .sheet(isPresented: $showScanCard) {
            LeadScanCardView { body in await submitLead(body) }
        }
        .sheet(isPresented: $showImport) {
            LeadImportView()
        }
        .sheet(isPresented: $showFilters) {
            LeadsFilterSheet(vm: vm)
        }
        .sheet(isPresented: $showDateFilter) {
            DateRangeFilterSheet(from: $vm.dateFrom, to: $vm.dateTo, label: "Created date") {
                Task { await vm.refresh() }
            }
        }
        .task {
            // Try to drain any queued offline leads on first appearance —
            // network might already be back from a previous offline burst.
            queue.drain()
            await vm.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .kmLeadSavedOffline)) { _ in
            withAnimation { offlineToast = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                withAnimation { offlineToast = false }
            }
        }
        .onChange(of: queue.pendingCount) { _, newCount in
            // Once the queue drains down to 0 in the background, surface
            // a quick "synced" hint via the list refresh so the rep sees
            // their real leads pop in.
            if newCount == 0 {
                Task { await vm.refresh() }
            }
        }
        .onChange(of: vm.search) { _, _ in
            Task { await vm.refresh() }
        }
    }
}

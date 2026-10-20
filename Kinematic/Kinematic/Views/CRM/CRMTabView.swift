import SwiftUI

/// The CRM module's dedicated tab shell. Mirrors the dashboard's CRM-section
/// IA so a sales rep entering CRM sees the same five workspaces on mobile.
///
/// - For CRM-only clients (Tata Tiscon-style) `CRMTabView` is the whole app.
/// - For full-access clients it's presented as a fullScreenCover when the
///   user opens CRM from the side menu — the "Switch to Field Force" row in
///   the More tab dismisses back to the main app via `onExit`.
///
/// Uses iOS 26 `Tab(value:)` + `.tabBarMinimizeBehavior(.onScrollDown)` so we
/// get the native Liquid Glass tab bar treatment for free.
struct CRMTabView: View {
    /// Optional callback for full-access deployments — provides a way out of
    /// the CRM shell back to the main field-ops app. Nil hides the row.
    var onExit: (() -> Void)? = nil

    @EnvironmentObject var appState: KiniAppState
    @State private var selectedTab: Int = 0
    // KINI floats inside the CRM module only — it used to live at the
    // ContentView root, which meant the assistant appeared over the
    // Field Force tabs too. Moved here so reps doing route visits
    // aren't distracted by it.
    @State private var showKini: Bool = false
    @State private var kiniUsage: KiniUsage? = nil
    // First-launch guided tour. `crm.tour.seen` persists across launches so the
    // tour auto-shows exactly once (on the first authenticated load of the CRM
    // shell); it can always be replayed from More → Guided Tour.
    @AppStorage("crm.tour.seen") private var tourSeen: Bool = false
    @State private var showTour: Bool = false
    // Interactive spotlight tour — a coach-mark overlay that dims the Leads
    // screen and highlights one real control at a time. Owned here and injected
    // so the Leads screen (anchors + overlay) and the guided-tour hub (replay)
    // both reach it.
    @StateObject private var spotlight = SpotlightModel()
    // Home-screen widget taps route here (leads / new-lead / lead / my-day
    // / checkin / team) → select the matching bottom tab.
    @ObservedObject private var widgetLink = WidgetDeepLink.shared

    private var canShowKiniFab: Bool {
        Session.currentUser?.hasCrm ?? false
    }

    /// Map a widget route to a CRM tab. Home=0, Dashboard=1, Leads=2,
    /// Deals=3, More=4. Clears the pending route after applying.
    private func applyWidgetRoute(_ route: WidgetRoute?) {
        guard let route else { return }
        switch route {
        // A tab the client's modules do not include is not there to select: the route lands on Home instead.
        case .leads, .newLead, .lead:  selectedTab = ClientFeatures.showsCrmLeadsTab ? 2 : 0
        case .myDay, .checkIn:          selectedTab = 0
        case .team:                     selectedTab = ClientFeatures.showsCrmDashboardTab ? 1 : 0
        }
        widgetLink.pendingRoute = nil
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                // Home — the lead-management mission-control landing
                // (target ring, next-best-actions, closest-to-closing,
                // today's activity, playbook). Restored to the first tab
                // at the user's request so reps land on their day, not the
                // KPI dashboard.
                Tab("Home", systemImage: "house.fill", value: 0) {
                    NavigationStack { CrmHomeMissionView() }
                }
                // Dashboard / Leads / Deals are not in app_ui_config, so each is gated by its module here: under
                // `entitlements_strict` an un-ticked module's tab is not shown (always shown otherwise). Home and More are essential.
                if ClientFeatures.showsCrmDashboardTab {
                    Tab("Dashboard", systemImage: "chart.bar.fill", value: 1) {
                        NavigationStack { CRMDashboardView() }
                    }
                }
                if ClientFeatures.showsCrmLeadsTab {
                    Tab("Leads", systemImage: "person.crop.circle.badge.plus", value: 2) {
                        NavigationStack { LeadsListView() }
                    }
                }
                // Deals is the higher-frequency surface (list view, search,
                // close actions) so it gets the bottom slot. Pipeline (the
                // kanban view) moved into the More menu — same kanban,
                // just one tap deeper.
                if ClientFeatures.showsCrmDealsTab {
                    Tab("Deals", systemImage: "indianrupeesign.circle.fill", value: 3) {
                        NavigationStack { DealsListView() }
                    }
                }
                // Activities moved into More at the user's request — it's a
                // lower-frequency surface than Home/Leads/Deals for most reps.
                Tab("More", systemImage: "ellipsis.circle", value: 4) {
                    NavigationStack { CRMMoreMenu(onExit: onExit) }
                }
            }
            .tint(Brand.red)
            .tabBarMinimizeOnScrollIfAvailable()

            if canShowKiniFab {
                KiniFAB(usage: kiniUsage) { showKini = true }
                    .padding(.trailing, 16)
                    .padding(.bottom, 88)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .fullScreenCover(isPresented: $showKini, onDismiss: {
            Task { kiniUsage = await AIChatService.shared.fetchUsage() ?? kiniUsage }
        }) {
            KiniChatView(onClose: { showKini = false })
        }
        // First-login guided tour (Lead Management). Marked seen the moment it
        // opens so it never re-appears automatically; replay from More.
        .fullScreenCover(isPresented: $showTour) {
            GuidedTourView(tour: .leadManagement) { showTour = false }
        }
        .task {
            // The tour points at controls on the Leads screen, so it waits for a client that has the Leads tab.
            if !tourSeen && ClientFeatures.showsCrmLeadsTab {
                tourSeen = true
                // Switch to the Leads tab so its anchors (search / add / a row)
                // are laid out, then run the interactive spotlight.
                selectedTab = 2
                spotlight.start(SpotlightStep.leadManagement)
            }
            guard canShowKiniFab else { return }
            kiniUsage = await AIChatService.shared.fetchUsage()
        }
        // Re-assert the chosen theme at the CRM module root. The app root also
        // sets this, but if the CRM shell is ever presented in a context that
        // doesn't inherit the root's colorScheme, this guarantees the Light/
        // Dark/System pick in More actually takes effect here.
        .preferredColorScheme(appState.theme == .system ? nil : (appState.theme == .dark ? .dark : .light))
        // Make the spotlight model available (as an optional environment value)
        // to the Leads screen (anchors + overlay) and the guided-tour hub
        // (replay). Optional so LeadsListView never crashes when reached from
        // another entry point that doesn't own a tour.
        .environment(\.spotlightModel, spotlight)
        // Replay from the hub: it flips replayRequested and pops back; relaunch
        // the tour from the Leads tab.
        .onChange(of: spotlight.replayRequested) { _, requested in
            if requested {
                spotlight.replayRequested = false
                if ClientFeatures.showsCrmLeadsTab {
                    selectedTab = 2
                    spotlight.start(SpotlightStep.leadManagement)
                }
            }
        }
        // Consume any widget route that arrived before this shell mounted,
        // then react to taps while it's on screen.
        .onAppear { applyWidgetRoute(widgetLink.pendingRoute) }
        .onChange(of: widgetLink.pendingRoute) { _, route in applyWidgetRoute(route) }
    }
}

/// The "More" tab — collects the lower-frequency CRM destinations that don't
/// fit in the bottom-tab budget. Mirrors the dashboard's CRM sidebar.
struct CRMMoreMenu: View {
    var onExit: (() -> Void)? = nil
    @EnvironmentObject var appState: KiniAppState
    @State private var showLogoutConfirm: Bool = false

    /// Field executives see their own target ticker; everyone above them can
    /// set targets, so the Targets admin row is gated to non-FE roles.
    private var isManager: Bool {
        let r = (Session.currentUser?.role ?? "").lowercased()
        return r != "executive" && r != "field_executive"
    }

    /// "1.0.0 (123)" — marketing version (CFBundleShortVersionString) +
    /// build number (CFBundleVersion). Pulled at render time so every
    /// build that bumps either value reflects automatically in the
    /// More-tab footer.
    private var appVersionDisplay: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let v = (info["CFBundleShortVersionString"] as? String) ?? "?"
        let b = (info["CFBundleVersion"] as? String) ?? "?"
        return "\(v) (\(b))"
    }

    /// The user's actual display picture (or initials fallback) so the More
    /// tab surfaces the photo, not a generic glyph.
    @ViewBuilder private var profileAvatar: some View {
        let initials = String((Session.currentUser?.name ?? "U").prefix(1)).uppercased()
        ZStack {
            Circle().fill(Brand.red.opacity(0.15))
            if let s = Session.currentUser?.avatarUrl, !s.isEmpty {
                SignedAsyncImage(urlString: s) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default: Text(initials).font(.system(size: 18, weight: .black)).foregroundColor(Brand.red)
                    }
                }
            } else {
                Text(initials).font(.system(size: 18, weight: .black)).foregroundColor(Brand.red)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(Circle())
    }

    var body: some View {
        List {
            // Account sits at the top so the user has a one-tap way into
            // their profile (photo) and password from the CRM module without
            // having to bounce through the side menu (which CRM-only
            // deployments don't show).
            //
            // Both rows are PUSHED onto this tab's NavigationStack rather than
            // opened through `appState.activeSecondaryRoute`: that cover hangs
            // off ContentView, and when this shell is itself a fullScreenCover
            // (full-access clients: side menu → CRM) a second cover can't be
            // presented on top of it (the same limitation StoreVisitView
            // documents), so the Profile row couldn't open there. A push works
            // in every shell. The NavigationLink supplies its own chevron.
            Section {
                NavigationLink {
                    ProfileView()
                } label: {
                    HStack(spacing: 12) {
                        profileAvatar
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Session.currentUser?.name ?? "My Profile")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.primary)
                            Text((Session.currentUser?.role ?? "Tap to edit your photo")
                                    .replacingOccurrences(of: "_", with: " ").capitalized)
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                NavigationLink {
                    ChangePasswordView()
                } label: { MoreRow(icon: "key.fill", title: "Change password", tint: Brand.red) }
            }

            // Activities — the rep's scheduled calls / meetings / tasks.
            // Moved here from the bottom tab at the user's request; same
            // ActivitiesView, now one tap into More.
            // Activities has no app_ui_config switch, so it is gated by its module here (crm_activities, under
            // `entitlements_strict`; always shown otherwise).
            if ClientFeatures.showsCrmActivities {
                Section("Work") {
                    NavigationLink {
                        ActivitiesView()
                    } label: { MoreRow(icon: "checkmark.square.fill", title: "Activities", tint: Brand.red) }
                }
            }

            // CRM module surfaces only what's actually available on the
            // dashboard. Email Templates was removed from web; CRM Settings
            // is intentionally a web-console-only control. Keep the mobile
            // CRM More menu lean — Accounts / Contacts / Products / Reports.
            // The sections below are drawn in the built-in order unless the admin arranged this menu in Client Management
            // (app_ui_config.layout.crm_more): a section moves as a unit to where its earliest listed row sits, and its rows
            // follow the list too. Hide flags and each row's own rules still decide what is shown at all.
            ForEach(CRMMoreLayout.ordered(listed: ClientFeatures.layoutOrder("crm_more"), isShown: moreRowShown), id: \.id) { section in
                Section(moreSectionTitle(section.id)) {
                    ForEach(section.rows, id: \.self) { row in
                        moreRow(row)
                    }
                }
            }
            // Targets removed from mobile entirely — the manager-tier
            // hierarchy admin lives on the web console; reps see their
            // own target as a dashboard ticker without needing the
            // settings row here.
            // Help & lifecycle — single-tap onboarding so any new rep can
            // understand how a Lead → Contact → Deal flows through the CRM
            // without needing a training session.
            Section("Learn") {
                NavigationLink {
                    GuidedToursListView()
                } label: { MoreRow(icon: "figure.walk.motion", title: "Guided Tour", tint: Brand.red) }
                NavigationLink {
                    CRMHelpView()
                } label: { MoreRow(icon: "books.vertical.fill", title: "How CRM works", tint: Brand.red) }
            }
            // Appearance — light/dark/system picker. CRM-only deployments
            // never reach the field-force SettingsView where the global
            // theme toggle lives, so we re-host it here so every CRM user
            // has one-tap access to a theme switch.
            Section("Appearance") {
                themeRow("System", appTheme: .system, icon: "circle.lefthalf.filled")
                themeRow("Light",  appTheme: .light,  icon: "sun.max.fill")
                themeRow("Dark",   appTheme: .dark,   icon: "moon.stars.fill")
            }
            if let onExit, ClientFeatures.crmMoreVisible("switch_ff") {
                Section {
                    Button(action: onExit) {
                        HStack {
                            MoreRow(icon: "arrow.uturn.left", title: ClientFeatures.labelFor("crm_more", "switch_ff", default: "Switch to Field Force"), tint: .red)
                            Spacer()
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            // Sign out — always visible. CRM-only clients (Tata Tiscon-style)
            // have no other way to leave the CRM shell, so this is required.
            Section {
                Button {
                    showLogoutConfirm = true
                } label: {
                    HStack {
                        MoreRow(icon: "rectangle.portrait.and.arrow.right", title: "Sign Out", tint: .red)
                        Spacer()
                    }
                }
                .foregroundColor(.red)
            }

            // App version footer — pulled from the bundle so it
            // auto-updates whenever Xcode bumps CFBundleShortVersionString
            // (the marketing version, e.g. "1.0.0") or CFBundleVersion
            // (the build number, monotonically increasing per build).
            // Section { ... } with `.listRowBackground(Color.clear)`
            // renders as plain footer text under the last cell.
            Section {
                HStack {
                    Spacer()
                    Text("Kinematic v\(appVersionDisplay)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("More")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Sign out?", isPresented: $showLogoutConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Sign Out", role: .destructive) { appState.logout() }
        } message: {
            Text("You'll need to sign back in to access your CRM data.")
        }
    }

    private func moreSectionTitle(_ id: String) -> String {
        switch id {
        case "records":      return "Records"
        case "field_visits": return "Field Visits"
        case "field":        return "Field"
        case "workplace":    return "Workplace"
        case "expenses":     return "Expenses"
        default:             return "Insights"
        }
    }

    /// Is this More row shown? The rules each row has always had, plus its hide flag.
    private func moreRowShown(_ id: String) -> Bool {
        switch id {
        // Accounts is hidden for Consumer Champions and Tata Tiscon (their
        // workflow is lead/deal-centric — account management lives with
        // admins). Contacts is hidden for Consumer Champions only.
        case "accounts":          return !ClientFeatures.isConsumerChampion && ClientFeatures.showsAccounts && ClientFeatures.crmMoreVisible("accounts")
        case "pipeline":          return ClientFeatures.crmMoreVisible("pipeline")
        case "products":          return ClientFeatures.crmMoreVisible("products")
        case "custom_objects":    return ClientFeatures.showsCustomObjects && ClientFeatures.crmMoreVisible("custom_objects")
        // Marketing Visit (Rajkamal) — ad-hoc GPS Start → End tied to a
        // lead. Gated strictly on the client id so no other tenant sees it;
        // admins can still hide/relabel it via App Customization.
        case "marketing_visit":   return ClientFeatures.isRajkamal && ClientFeatures.crmMoreVisible("marketing_visit")
        case "nearest_leads":     return ClientFeatures.crmMoreVisible("nearest_leads")
        // Workplace — leave balances / requests + attendance regularization.
        // Hidden for SRS TATA Steel AND for every CRM-only tenant (BMW, new
        // lean-CRM clients, the parent Kinematic tenant): the "People &
        // Support" surface was dropped from the CRM-only build. Only full
        // field-force tenants still see it here.
        case "leave":             return ClientFeatures.showsLeave && ClientFeatures.crmMoreVisible("leave")
        // Field Expenses — module-gated (field_expenses), independent of
        // Leave, and shown on the CRM-only build.
        case "expenses":          return ClientFeatures.showsExpenses && ClientFeatures.crmMoreVisible("expenses")
        // Only people who can approve see it (an unknown role keeps it — the API is the authority).
        case "expense_approvals": return ClientFeatures.showsExpenses && ClientFeatures.crmMoreVisible("expenses")
                                    && ExpenseLogic.canApprove(role: Session.currentUser?.role, dataScope: Session.currentUser?.orgRoleDataScope)
        // Insights is split for Consumer Champion reps —
        // they still get a slimmed-down Reports view (3 KPI tiles)
        // but Dashboard + Lead Analytics are manager-tier surfaces
        // and stay hidden for FE-tier nav clarity.
        case "dashboard":         return !ClientFeatures.isConsumerChampion && ClientFeatures.crmMoreVisible("dashboard")
        case "reports":           return ClientFeatures.crmMoreVisible("reports")
        case "lead_analytics":    return !ClientFeatures.isConsumerChampion && ClientFeatures.crmMoreVisible("lead_analytics")
        default:                  return false
        }
    }

    @ViewBuilder
    private func moreRow(_ id: String) -> some View {
        switch id {
        case "accounts":
            NavigationLink {
                AccountsListView()
            } label: { MoreRow(icon: "building.2.fill", title: ClientFeatures.labelFor("crm_more", "accounts", default: "Accounts"), tint: Brand.red) }
        // Contacts hidden from mobile entirely — Tata's intake
        // flow doesn't surface contacts; reinstate this row if a
        // future tenant ever needs the contacts surface here.
        // Pipeline (kanban) — moved here from the bottom tab in
        // favour of the higher-frequency Deals list. Same view,
        // one tap deeper.
        case "pipeline":
            NavigationLink {
                DealKanbanView()
            } label: { MoreRow(icon: "square.stack.3d.up.fill", title: ClientFeatures.labelFor("crm_more", "pipeline", default: "Pipeline"), tint: Brand.red) }
        case "products":
            NavigationLink {
                ProductsListView()
            } label: { MoreRow(icon: "shippingbox.fill", title: ClientFeatures.labelFor("crm_more", "products", default: "Products"), tint: Brand.red) }
        case "custom_objects":
            NavigationLink {
                CustomObjectsListView()
            } label: { MoreRow(icon: "square.grid.2x2.fill", title: ClientFeatures.labelFor("crm_more", "custom_objects", default: "Custom Objects"), tint: Brand.red) }
        case "marketing_visit":
            NavigationLink {
                MarketingVisitView()
            } label: { MoreRow(icon: "figure.walk.motion", title: ClientFeatures.labelFor("crm_more", "marketing_visit", default: "Marketing Visit"), tint: Brand.red) }
        // Field tools that ride on the rep's current location. Distinct
        // from "Records" because reps think of these as "where am I
        // going next?" — not a directory.
        case "nearest_leads":
            NavigationLink {
                NearbyLeadsView()
            } label: { MoreRow(icon: "location.north.line.fill", title: ClientFeatures.labelFor("crm_more", "nearest_leads", default: "Nearest Leads"), tint: Brand.red) }
        case "leave":
            NavigationLink {
                LeaveHomeView()
            } label: { MoreRow(icon: "calendar.badge.clock", title: ClientFeatures.labelFor("crm_more", "leave", default: "Leave"), tint: Brand.red) }
        // Rep files claims (mileage auto-priced from GPS, receipts AI-OCR'd); managers approve.
        case "expenses":
            NavigationLink {
                ExpenseClaimsView()
            } label: { MoreRow(icon: "doc.text.magnifyingglass", title: ClientFeatures.labelFor("crm_more", "expenses", default: "Expense Claims"), tint: Brand.red) }
        case "expense_approvals":
            NavigationLink {
                ExpenseApprovalsView()
            } label: { MoreRow(icon: "checkmark.seal", title: "Expense Approvals", tint: Brand.red) }
        case "dashboard":
            NavigationLink {
                CRMDashboardView()
            } label: { MoreRow(icon: "chart.bar.fill", title: ClientFeatures.labelFor("crm_more", "dashboard", default: "Dashboard"), tint: Brand.red) }
        case "reports":
            NavigationLink {
                CRMReportsHubView()
            } label: { MoreRow(icon: "chart.pie.fill", title: ClientFeatures.labelFor("crm_more", "reports", default: "Reports"), tint: Brand.red) }
        case "lead_analytics":
            NavigationLink {
                CustomLeadAnalyticsView()
            } label: { MoreRow(icon: "chart.line.uptrend.xyaxis", title: ClientFeatures.labelFor("crm_more", "lead_analytics", default: "Lead Analytics"), tint: Brand.red) }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func themeRow(_ label: String, appTheme: AppTheme, icon: String) -> some View {
        Button {
            appState.theme = appTheme
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Brand.red.opacity(0.18))
                        .frame(width: 32, height: 32)
                    Image(systemName: icon)
                        .foregroundColor(Brand.red)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(label)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.primary)
                Spacer()
                if appState.theme == appTheme {
                    Image(systemName: "checkmark")
                        .foregroundColor(Brand.red)
                        .fontWeight(.bold)
                }
            }
        }
    }
}

private struct MoreRow: View {
    let icon: String
    let title: String
    let tint: Color
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(tint.opacity(0.18))
                    .frame(width: 32, height: 32)
                Image(systemName: icon).foregroundColor(tint).font(.system(size: 14, weight: .semibold))
            }
            Text(title)
                .font(.system(size: 15, weight: .medium))
        }
    }
}

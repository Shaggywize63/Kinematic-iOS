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

    private var canShowKiniFab: Bool {
        Session.currentUser?.hasCrm ?? false
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            TabView(selection: $selectedTab) {
                // First tab is the analytics Dashboard for every tenant.
                // The "Home" mission-control surface (CrmHomeMissionView)
                // is still reachable from More → Insights → Dashboard if
                // anyone needs it, but the daily-mission home was removed
                // from the bottom bar at the user's request — reps land
                // straight on the KPI tiles + date picker.
                Tab("Dashboard", systemImage: "chart.bar.fill", value: 0) {
                    NavigationStack { CRMDashboardView() }
                }
                Tab("Leads", systemImage: "person.crop.circle.badge.plus", value: 1) {
                    NavigationStack { LeadsListView() }
                }
                // Deals is the higher-frequency surface (list view, search,
                // close actions) so it gets the bottom slot. Pipeline (the
                // kanban view) moved into the More menu — same kanban,
                // just one tap deeper.
                Tab("Deals", systemImage: "indianrupeesign.circle.fill", value: 2) {
                    NavigationStack { DealsListView() }
                }
                Tab("Activities", systemImage: "checkmark.square.fill", value: 3) {
                    NavigationStack { ActivitiesView() }
                }
                Tab("More", systemImage: "ellipsis.circle", value: 4) {
                    NavigationStack { CRMMoreMenu(onExit: onExit) }
                }
            }
            .tint(Brand.red)
            .tabBarMinimizeBehavior(.onScrollDown)

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
        .task {
            guard canShowKiniFab else { return }
            kiniUsage = await AIChatService.shared.fetchUsage()
        }
        // Re-assert the chosen theme at the CRM module root. The app root also
        // sets this, but if the CRM shell is ever presented in a context that
        // doesn't inherit the root's colorScheme, this guarantees the Light/
        // Dark/System pick in More actually takes effect here.
        .preferredColorScheme(appState.theme == .system ? nil : (appState.theme == .dark ? .dark : .light))
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
            if let s = Session.currentUser?.avatarUrl, let url = URL(string: s), !s.isEmpty {
                AsyncImage(url: url) { phase in
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
            // Profile sits at the top so the user has a one-tap way into
            // their account from the CRM module without having to bounce
            // through the side menu (which CRM-only deployments don't show).
            Section {
                Button {
                    appState.activeSecondaryRoute = ModalRoute(route: .profile)
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
                        Spacer()
                        Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)
                    }
                }
                .foregroundColor(.primary)
            }

            // CRM module surfaces only what's actually available on the
            // dashboard. Email Templates was removed from web; CRM Settings
            // is intentionally a web-console-only control. Keep the mobile
            // CRM More menu lean — Accounts / Contacts / Products / Reports.
            // Accounts is hidden for Consumer Champions and Tata Tiscon (their
            // workflow is lead/deal-centric — account management lives with
            // admins). Contacts is hidden for Consumer Champions only.
            Section("Records") {
                if !ClientFeatures.isConsumerChampion && !ClientFeatures.isTataTiscon {
                    NavigationLink {
                        AccountsListView()
                    } label: { MoreRow(icon: "building.2.fill", title: "Accounts", tint: Brand.red) }
                }
                // Contacts hidden from mobile entirely — Tata's intake
                // flow doesn't surface contacts; reinstate this row if a
                // future tenant ever needs the contacts surface here.
                // Pipeline (kanban) — moved here from the bottom tab in
                // favour of the higher-frequency Deals list. Same view,
                // one tap deeper.
                NavigationLink {
                    DealKanbanView()
                } label: { MoreRow(icon: "square.stack.3d.up.fill", title: "Pipeline", tint: Brand.red) }
                NavigationLink {
                    ProductsListView()
                } label: { MoreRow(icon: "shippingbox.fill", title: "Products", tint: Brand.red) }
            }
            // Field tools that ride on the rep's current location. Distinct
            // from "Records" because reps think of these as "where am I
            // going next?" — not a directory.
            Section("Field") {
                NavigationLink {
                    NearbyLeadsView()
                } label: { MoreRow(icon: "location.north.line.fill", title: "Nearest Leads", tint: Brand.red) }
            }
            // Insights section is split for Consumer Champion reps —
            // they still get a slimmed-down Reports view (3 KPI tiles)
            // but Dashboard + Lead Analytics are manager-tier surfaces
            // and stay hidden for FE-tier nav clarity.
            Section("Insights") {
                if !ClientFeatures.isConsumerChampion {
                    NavigationLink {
                        CRMDashboardView()
                    } label: { MoreRow(icon: "chart.bar.fill", title: "Dashboard", tint: Brand.red) }
                }
                NavigationLink {
                    CRMReportsHubView()
                } label: { MoreRow(icon: "chart.pie.fill", title: "Reports", tint: Brand.red) }
                if !ClientFeatures.isConsumerChampion {
                    NavigationLink {
                        CustomLeadAnalyticsView()
                    } label: { MoreRow(icon: "chart.line.uptrend.xyaxis", title: "Lead Analytics", tint: Brand.red) }
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
            if let onExit {
                Section {
                    Button(action: onExit) {
                        HStack {
                            MoreRow(icon: "arrow.uturn.left", title: "Switch to Field Force", tint: .red)
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

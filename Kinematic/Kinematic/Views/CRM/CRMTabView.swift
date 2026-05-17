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

    @State private var selectedTab: Int = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Dashboard", systemImage: "chart.bar.fill", value: 0) {
                NavigationStack { CRMDashboardView() }
            }
            Tab("Leads", systemImage: "person.crop.circle.badge.plus", value: 1) {
                NavigationStack { LeadsListView() }
            }
            Tab("Pipeline", systemImage: "square.stack.3d.up.fill", value: 2) {
                NavigationStack { DealKanbanView() }
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
    }
}

/// The "More" tab — collects the lower-frequency CRM destinations that don't
/// fit in the bottom-tab budget. Mirrors the dashboard's CRM sidebar.
struct CRMMoreMenu: View {
    var onExit: (() -> Void)? = nil
    @EnvironmentObject var appState: KiniAppState
    @State private var showLogoutConfirm: Bool = false

    var body: some View {
        List {
            // Profile sits at the top so the user has a one-tap way into
            // their account from the CRM module without having to bounce
            // through the side menu (which CRM-only deployments don't show).
            Section {
                Button {
                    appState.activeSecondaryRoute = ModalRoute(route: .profile)
                } label: {
                    HStack {
                        MoreRow(icon: "person.crop.circle.fill", title: Session.currentUser?.name ?? "Profile", tint: Brand.red)
                        Spacer()
                    }
                }
                .foregroundColor(.primary)
            }

            // CRM module surfaces only what's actually available on the
            // dashboard. Email Templates was removed from web; CRM Settings
            // is intentionally a web-console-only control. Keep the mobile
            // CRM More menu lean — Accounts / Contacts / Products / Reports.
            Section("Records") {
                NavigationLink {
                    AccountsListView()
                } label: { MoreRow(icon: "building.2.fill", title: "Accounts", tint: Brand.red) }
                NavigationLink {
                    ContactsListView()
                } label: { MoreRow(icon: "person.2.fill", title: "Contacts", tint: Brand.red) }
                NavigationLink {
                    ProductsListView()
                } label: { MoreRow(icon: "shippingbox.fill", title: "Products", tint: Brand.red) }
            }
            Section("Insights") {
                NavigationLink {
                    CRMReportsView()
                } label: { MoreRow(icon: "chart.pie.fill", title: "Reports", tint: Brand.red) }
                // Read-only Lead Analytics surface — six widget cards with a
                // per-card size cycle. Mirrors the dashboard's
                // /dashboard/crm/analytics screen, scoped down to mobile.
                NavigationLink {
                    LeadAnalyticsView()
                } label: { MoreRow(icon: "chart.line.uptrend.xyaxis", title: "Lead Analytics", tint: Brand.red) }
            }
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

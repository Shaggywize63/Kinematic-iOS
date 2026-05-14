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
        .tint(.indigo)
        .tabBarMinimizeBehavior(.onScrollDown)
    }
}

/// The "More" tab — collects the lower-frequency CRM destinations that don't
/// fit in the bottom-tab budget. Mirrors the dashboard's CRM sidebar.
struct CRMMoreMenu: View {
    var onExit: (() -> Void)? = nil

    var body: some View {
        List {
            // CRM module surfaces only what's actually available on the
            // dashboard. Email Templates was removed from web; CRM Settings
            // is intentionally a web-console-only control. Keep the mobile
            // CRM More menu lean — Accounts / Contacts / Products / Reports.
            Section("Records") {
                NavigationLink {
                    AccountsListView()
                } label: { MoreRow(icon: "building.2.fill", title: "Accounts", tint: .teal) }
                NavigationLink {
                    ContactsListView()
                } label: { MoreRow(icon: "person.2.fill", title: "Contacts", tint: .purple) }
                NavigationLink {
                    ProductsListView()
                } label: { MoreRow(icon: "shippingbox.fill", title: "Products", tint: .brown) }
            }
            Section("Insights") {
                NavigationLink {
                    CRMReportsView()
                } label: { MoreRow(icon: "chart.pie.fill", title: "Reports", tint: .purple) }
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
        }
        .listStyle(.insetGrouped)
        .navigationTitle("More")
        .navigationBarTitleDisplayMode(.inline)
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

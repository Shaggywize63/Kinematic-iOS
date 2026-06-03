import SwiftUI

/// Tile-based CRM home, mirroring the Android CrmHomeScreen tile grid.
/// Removed: Settings, Templates, Emails (replaced by 10-tile module grid).
/// KINI is reachable as a sticky red circular FAB at the bottom-right —
/// the only entry point (no separate toolbar icon).
struct CRMHomeView: View {
    var onLogout: (() -> Void)? = nil
    /// Optional close callback. When provided (e.g. when CRMHomeView is hosted
    /// inside a fullScreenCover from SideMenuView), a Close button is rendered
    /// in the leading toolbar slot. Lets the caller dismiss without wrapping
    /// CRMHomeView in another NavigationStack — nested NavigationStacks hang
    /// iOS 26 SwiftUI.
    var onClose: (() -> Void)? = nil

    private let tiles: [CRMTile] = [
        .init(label: "Dashboard",  icon: "chart.bar.fill",                  color: Color(red: 0.12, green: 0.53, blue: 0.90), destination: .dashboard),
        .init(label: "Leads",      icon: "person.crop.circle.badge.plus",  color: Color(red: 0.90, green: 0.22, blue: 0.21), destination: .leads),
        .init(label: "Contacts",   icon: "person.2.fill",                  color: Color(red: 0.56, green: 0.14, blue: 0.67), destination: .contacts),
        .init(label: "Accounts",   icon: "building.2.fill",                color: Color(red: 0.00, green: 0.54, blue: 0.47), destination: .accounts),
        .init(label: "Deals",      icon: "indianrupeesign.circle.fill",    color: Color(red: 0.26, green: 0.63, blue: 0.28), destination: .deals),
        .init(label: "Pipeline",   icon: "square.stack.3d.up.fill",        color: Color(red: 0.98, green: 0.55, blue: 0.00), destination: .pipeline),
        .init(label: "Products",   icon: "shippingbox.fill",               color: Color(red: 0.42, green: 0.11, blue: 0.58), destination: .products),
        .init(label: "Activities", icon: "clock.arrow.circlepath",         color: Color(red: 0.43, green: 0.30, blue: 0.25), destination: .activities),
        .init(label: "Tasks",      icon: "checkmark.square.fill",          color: Color(red: 0.22, green: 0.29, blue: 0.67), destination: .tasks),
        .init(label: "Reports",    icon: "chart.pie.fill",                 color: Color(red: 0.37, green: 0.21, blue: 0.69), destination: .reports),
    ]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    // Single brand wordmark at the top — replaces the
                    // navigation bar's "CRM" title so reps don't see two
                    // headings stacked on the same screen.
                    HStack(spacing: 10) {
                        Image("KinematicMark")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 36, height: 36)
                        Text("Kinematic CRM")
                            .font(.title3.bold())
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 4)

                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(tiles) { tile in
                            NavigationLink(value: tile.destination) {
                                CRMTileCard(tile: tile)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(12)
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    if let onClose {
                        ToolbarItem(placement: .topBarLeading) {
                            Button(action: onClose) {
                                HStack(spacing: 4) { Image(systemName: "chevron.left"); Text("Close") }
                                    .foregroundColor(Brand.red)
                            }
                        }
                    }
                    // Chat icon sits adjacent to logout (top-right) so reps
                    // reach the inbox + team chats from one tap on Home.
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink(value: CRMDestination.messages) {
                            Image(systemName: "bubble.left.and.bubble.right")
                        }
                        .accessibilityLabel("Messages")
                    }
                    if let onLogout {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: onLogout) {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                            }
                            .accessibilityLabel("Sign out")
                        }
                    }
                }
                .navigationDestination(for: CRMDestination.self) { dest in
                    dest.view
                }
                // The local KINI FAB previously rendered here has been removed —
                // ContentView now overlays the global KiniFAB on every screen so
                // CRM matches the dashboard's KinematicAI pattern.
            }
        }
        .accentColor(Brand.red)
    }
}

private struct CRMTile: Identifiable {
    let label: String
    let icon: String
    let color: Color
    let destination: CRMDestination
    var id: String { label }
}

private enum CRMDestination: Hashable {
    case dashboard, leads, contacts, accounts, deals, pipeline, products, activities, tasks, reports, kini, messages

    @ViewBuilder
    var view: some View {
        switch self {
        case .dashboard:  CRMDashboardView()
        case .leads:      LeadsListView()
        case .contacts:   ContactsListView()
        case .accounts:   AccountsListView()
        case .deals:      DealsListView()
        case .pipeline:   DealKanbanView()
        case .products:   ProductsListView()
        case .activities: ActivitiesView()
        case .tasks:      TasksView()
        case .reports:    CRMReportsHubView()
        case .kini:       KiniChatView()
        // Inbox: DMs + team chats with scope-filtered user search.
        case .messages:   ChatListView()
        }
    }
}

private struct CRMTileCard: View {
    let tile: CRMTile

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Circle().fill(tile.color.opacity(0.18)).frame(width: 40, height: 40)
                Image(systemName: tile.icon).foregroundColor(tile.color).font(.system(size: 18, weight: .semibold))
            }
            Spacer()
            Text(tile.label).font(.system(size: 15, weight: .bold))
        }
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20).fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}
